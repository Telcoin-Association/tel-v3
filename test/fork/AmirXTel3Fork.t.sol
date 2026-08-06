// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {ICreateX} from "forge-deploy-utils/interfaces/ICreateX.sol";
import {SaltMath} from "forge-deploy-utils/libraries/SaltMath.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {TelcoinV3} from "../../src/TelcoinV3.sol";
import {AmirX} from "./amirx/AmirX.sol";
import {StablecoinHandler} from "./amirx/StablecoinHandler.sol";
import {SimplePlugin} from "./amirx/plugin/SimplePlugin.sol";
import {ISimplePlugin} from "./amirx/interfaces/ISimplePlugin.sol";
import {IProxyAdmin} from "./amirx/interfaces/IProxyAdmin.sol";
import {IUniswapV2Router02} from "./interfaces/IUniswapV2Router02.sol";
import {TestWallet} from "./mocks/TestWallet.sol";
import {TestPlugin} from "./mocks/TestPlugin.sol";

/// @title AmirXTel3ForkTest
/// @notice Polygon mainnet fork test: deploy TelcoinV3, upgrade the live AmirX
///         proxy to an implementation whose TELCOIN constant points at TEL v3,
///         and validate all functional paths against the new token.
/// @dev Requirements: TEL3 liquidity pools being available
contract AmirXTel3ForkTest is Test {

    // ------------------
    // Live Polygon state
    // ------------------

    /// @dev AmirX TransparentUpgradeableProxy (live)
    address internal constant AMIRX_PROXY = 0x4eB4A35257458C1a87A4124CE02B3329Ed6b8D5a;
    /// @dev OZ v5 ProxyAdmin of the AmirX proxy
    address internal constant AMIRX_PROXY_ADMIN = 0xB454c0C350F61346B9862e786deFC32EF8c10Ea9;
    /// @dev Legacy TEL (2 decimals)
    address internal constant LEGACY_TEL = 0xdF7837DE1F2Fa4631D716CF2502f8b230F1dcc32;
    /// @dev CreateX factory (same address on all EVM chains)
    address internal constant CREATEX = 0xba5Ed099633D3B313e4D5F7bdc1305d3c28ba5Ed;
    /// @dev QuickSwap V2 router (dominant V2-style DEX on Polygon by TVL)
    address internal constant QUICKSWAP_V2_ROUTER = 0xa5E0829CaCEd8fFDD4De3c43696c57F7D7A678ff;
    /// @dev Wrapped POL
    address internal constant WPOL = 0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270;
    /// @dev Native USDC — the dominant production feeToken (46 of last 100 swaps)
    address internal constant USDC = 0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359;
    /// @dev Live SWAPPER_ROLE EOA (55 of last 100 swaps)
    address internal constant LIVE_SWAPPER = 0x0082CaF47363bD42917947d81f4d4E0395257267;
    /// @dev Live legacy-TEL referral SimplePlugin (tel/staking immutable — cannot be reused for TEL3)
    address internal constant LIVE_PLUGIN = 0xDb0e60A38Bf7d04c8ae0B396A65E5aa550f9885A;
    /// @dev Live StakingModule the referral plugin claims through
    address internal constant STAKING_MODULE = 0x92e43Aec69207755CB1E6A8Dc589aAE630476330;
    /// @dev Live registered eXYZ stablecoins seen in recent prod traffic
    address internal constant EGBP = 0x660674AB7E524AEf817B6761fE48702F06D8510a;
    address internal constant EXOF = 0x5370B325aef39E987406EB0aB1B86Bf04152778c;
    /// @dev Second live SWAPPER_ROLE EOA
    address internal constant LIVE_SWAPPER_2 = 0xA64B745351EC40bdb3147FF99db2ae21cf93E6E3;
    /// @dev Safe holding DEFAULT_ADMIN + SUPPORT_ROLE on AmirX (also owns the live plugin)
    address internal constant AMIRX_ADMIN_SAFE = 0xBF58e5b1Ed34031579341C79913CDcB81f76415C;
    /// @dev EIP-1967 implementation slot
    bytes32 internal constant IMPL_SLOT =
        0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    // ---------------
    // Fork deployment
    // ---------------

    /// @dev Deterministic CREATE3 address TelcoinV3 is deployed at in setUp.
    address internal constant TEL3 =
        0x940C74Faa99beFD6745A7B54346A22076E376E62;
    bytes32 internal constant TEL3_RAW_SALT = keccak256("AMIRX_FORK_TEL3_V1");

    TelcoinV3 internal tel3;
    AmirX internal amirx;
    AmirX internal newImplementation;
    address internal proxyAdminOwner;
    address internal tel3Deployer;
    address internal governance;

    /// @dev Live AmirX state captured immediately before the upgrade
    struct PreUpgradeState {
        bool paused;
        bool egbpValid;
        bool exofValid;
        uint256 egbpMax;
        uint256 egbpMin;
        uint256 exofMax;
        uint256 exofMin;
        bool swapper1;
        bool swapper2;
        bool adminSafe;
        bool supportSafe;
    }

    PreUpgradeState internal pre;

    function setUp() public {
        vm.createSelectFork(vm.envString("POLYGON_RPC_URL"), 91493697);

        tel3Deployer = makeAddr("tel3Deployer");
        governance = makeAddr("governance");

        // 1. Deploy TelcoinV3 at its deterministic CREATE3 address via CreateX,
        //    mirroring the production deploy pipeline (DeployBase/SaltMath).
        bytes32 guardedSalt = SaltMath.guardSalt(tel3Deployer, TEL3_RAW_SALT);
        vm.prank(tel3Deployer);
        address deployed = ICreateX(CREATEX).deployCreate3(
            guardedSalt,
            abi.encodePacked(
                type(TelcoinV3).creationCode,
                abi.encode(governance)
            )
        );
        require(
            deployed == TEL3,
            "TEL3 address mismatch: update TEL3 + AmirX.TELCOIN constants"
        );
        tel3 = TelcoinV3(deployed);

        // 2. Snapshot live AmirX state pre-upgrade for the preservation test.
        AmirX live = AmirX(payable(AMIRX_PROXY));
        pre = PreUpgradeState({
            paused: live.paused(),
            egbpValid: live.isXYZ(EGBP),
            exofValid: live.isXYZ(EXOF),
            egbpMax: live.getMaxLimit(EGBP),
            egbpMin: live.getMinLimit(EGBP),
            exofMax: live.getMaxLimit(EXOF),
            exofMin: live.getMinLimit(EXOF),
            swapper1: live.hasRole(live.SWAPPER_ROLE(), LIVE_SWAPPER),
            swapper2: live.hasRole(live.SWAPPER_ROLE(), LIVE_SWAPPER_2),
            adminSafe: live.hasRole(live.DEFAULT_ADMIN_ROLE(), AMIRX_ADMIN_SAFE),
            supportSafe: live.hasRole(live.SUPPORT_ROLE(), AMIRX_ADMIN_SAFE)
        });

        // 3. Upgrade the live AmirX proxy to the implementation whose TELCOIN
        //    constant points at TEL v3. Storage is untouched (constant-only diff).
        newImplementation = new AmirX();
        proxyAdminOwner = IProxyAdmin(AMIRX_PROXY_ADMIN).owner();
        vm.prank(proxyAdminOwner);
        IProxyAdmin(AMIRX_PROXY_ADMIN).upgradeAndCall(
            AMIRX_PROXY,
            address(newImplementation),
            ""
        );
        require(
            address(
                uint160(uint256(vm.load(AMIRX_PROXY, IMPL_SLOT)))
            ) == address(newImplementation),
            "AmirX upgrade failed"
        );

        amirx = AmirX(payable(AMIRX_PROXY));

        vm.label(AMIRX_PROXY, "AmirXProxy");
        vm.label(AMIRX_PROXY_ADMIN, "AmirXProxyAdmin");
        vm.label(LEGACY_TEL, "LegacyTEL");
        vm.label(address(tel3), "TelcoinV3");
        vm.label(QUICKSWAP_V2_ROUTER, "QuickSwapV2Router");
    }

    // -------
    // Utility
    // -------

    /// @dev Mints TEL3 to `to` (governance self-grants MINTER_ROLE; idempotent).
    function _mintTel3(address to, uint256 amount) internal {
        vm.startPrank(governance);
        tel3.grantRole(tel3.MINTER_ROLE(), governance);
        tel3.mint(to, amount);
        vm.stopPrank();
    }

    /// @dev Mints TEL3 and seeds a QuickSwap V2 TEL3/<counter> pool so buyback
    ///      routes have real liquidity.
    function _seedTel3Pool(
        address counter,
        uint256 counterAmount,
        uint256 telAmount
    ) internal {
        deal(counter, governance, counterAmount);
        _mintTel3(governance, telAmount);
        vm.startPrank(governance);
        tel3.approve(QUICKSWAP_V2_ROUTER, telAmount);
        IERC20(counter).approve(QUICKSWAP_V2_ROUTER, counterAmount);
        IUniswapV2Router02(QUICKSWAP_V2_ROUTER).addLiquidity(
            address(tel3),
            counter,
            telAmount,
            counterAmount,
            0,
            0,
            governance,
            block.timestamp
        );
        vm.stopPrank();
    }

    function _seedTel3UsdcPool(uint256 telAmount, uint256 usdcAmount) internal {
        _seedTel3Pool(USDC, usdcAmount, telAmount);
    }

    // ----------
    // Unit Tests
    // ----------

    /// @notice Post-upgrade, the proxy's TELCOIN constant points at the freshly
    ///         deployed TelcoinV3; POL is unchanged.
    function test_upgrade_telcoinConstantRepointed() public view {
        assertEq(address(amirx.TELCOIN()), address(tel3));
        assertNotEq(address(amirx.TELCOIN()), LEGACY_TEL);
        assertEq(amirx.POL(), 0x0000000000000000000000000000000000001010);
    }

    /// @notice The end-state modal case: fees collected directly in TEL3 match
    ///         the TELCOIN constant, skip buyback, and sweep to defiSafe.
    function test_defiSwap_feeTokenTel3_sweepsToDefiSafe() public {
        uint256 feeAmount = 500e18;
        address defiSafe = makeAddr("defiSafe");
        TestWallet wallet = new TestWallet();
        _mintTel3(address(wallet), feeAmount);

        AmirX.DefiSwap memory defi;
        defi.defiSafe = defiSafe;
        defi.feeToken = ERC20(address(tel3));
        defi.walletData = abi.encodeCall(
            TestWallet.transferToken,
            (IERC20(address(tel3)), AMIRX_PROXY, feeAmount)
        );

        vm.prank(LIVE_SWAPPER);
        amirx.defiSwap(address(wallet), defi);

        assertEq(tel3.balanceOf(defiSafe), feeAmount);
        assertEq(tel3.balanceOf(AMIRX_PROXY), 0);
    }

    /// @notice The constant-only upgrade must not disturb storage: pause state,
    ///         eXYZ registry (eGBP/eXOF), and role assignments all match the
    ///         values captured from the live contract just before the upgrade.
    function test_upgrade_preservesStorage() public view {
        assertEq(amirx.paused(), pre.paused);
        assertEq(amirx.isXYZ(EGBP), pre.egbpValid);
        assertEq(amirx.isXYZ(EXOF), pre.exofValid);
        assertEq(amirx.getMaxLimit(EGBP), pre.egbpMax);
        assertEq(amirx.getMinLimit(EGBP), pre.egbpMin);
        assertEq(amirx.getMaxLimit(EXOF), pre.exofMax);
        assertEq(amirx.getMinLimit(EXOF), pre.exofMin);
        assertEq(amirx.hasRole(amirx.SWAPPER_ROLE(), LIVE_SWAPPER), pre.swapper1);
        assertEq(
            amirx.hasRole(amirx.SWAPPER_ROLE(), LIVE_SWAPPER_2),
            pre.swapper2
        );
        assertEq(
            amirx.hasRole(amirx.DEFAULT_ADMIN_ROLE(), AMIRX_ADMIN_SAFE),
            pre.adminSafe
        );
        assertEq(
            amirx.hasRole(amirx.SUPPORT_ROLE(), AMIRX_ADMIN_SAFE),
            pre.supportSafe
        );
        // the registry entries are live ones, not empty defaults
        assertTrue(pre.egbpValid);
        assertTrue(pre.exofValid);
        assertTrue(pre.swapper1 && pre.swapper2);
    }

    /// @notice eXYZ legs are untouched by the upgrade: full round trip on the
    ///         chained entry points prod uses — cash-in (defiToStablecoinSwap:
    ///         wallet acquires USDC via walletData, balance-delta oAmount, eGBP
    ///         minted) then cash-out (stablecoinToDefiSwap: eGBP burned, USDC
    ///         paid from the liquidity safe).
    function test_stablecoinSwap_regression() public {
        TestWallet wallet = new TestWallet();
        address funder = makeAddr("funder");
        address liquiditySafe = makeAddr("liquiditySafe");
        uint256 usdcIn = 250e6;
        uint256 egbpOut = 180e6; // eGBP is 6 decimals
        uint256 egbpSupplyBefore = IERC20(EGBP).totalSupply();

        // wallet "acquires" USDC during the defi leg by pulling from funder
        deal(USDC, funder, usdcIn);
        vm.prank(funder);
        IERC20(USDC).approve(address(wallet), usdcIn);
        // wallet pre-approves AmirX for both legs
        wallet.execute(
            USDC,
            abi.encodeCall(IERC20.approve, (AMIRX_PROXY, type(uint256).max))
        );
        wallet.execute(
            EGBP,
            abi.encodeCall(IERC20.approve, (AMIRX_PROXY, type(uint256).max))
        );

        // --- cash-in: defi swap feeds stablecoin swap (USDC -> eGBP mint) ---
        AmirX.StablecoinSwap memory ss;
        ss.liquiditySafe = liquiditySafe;
        ss.destination = address(wallet);
        ss.origin = USDC;
        ss.oAmount = 1; // overwritten by balance delta
        ss.target = EGBP;
        ss.tAmount = egbpOut;

        AmirX.DefiSwap memory defi;
        defi.defiSafe = makeAddr("defiSafe");
        defi.walletData = abi.encodeCall(
            TestWallet.execute,
            (
                USDC,
                abi.encodeCall(
                    IERC20.transferFrom,
                    (funder, address(wallet), usdcIn)
                )
            )
        );

        vm.prank(LIVE_SWAPPER);
        amirx.defiToStablecoinSwap(address(wallet), ss, defi);

        assertEq(IERC20(EGBP).balanceOf(address(wallet)), egbpOut);
        assertEq(IERC20(USDC).balanceOf(liquiditySafe), usdcIn);
        assertEq(IERC20(EGBP).totalSupply(), egbpSupplyBefore + egbpOut);

        // --- cash-out: stablecoin swap feeds defi swap (eGBP burn -> USDC) ---
        uint256 usdcOut = 240e6;
        vm.prank(liquiditySafe);
        IERC20(USDC).approve(AMIRX_PROXY, usdcOut);

        AmirX.StablecoinSwap memory ss2;
        ss2.liquiditySafe = liquiditySafe;
        ss2.destination = address(wallet);
        ss2.origin = EGBP;
        ss2.oAmount = egbpOut;
        ss2.target = USDC;
        ss2.tAmount = usdcOut;

        AmirX.DefiSwap memory defi2;
        defi2.defiSafe = makeAddr("defiSafe");
        // empty walletData: the wallet call hits TestWallet's receive()

        vm.prank(LIVE_SWAPPER);
        amirx.stablecoinToDefiSwap(address(wallet), ss2, defi2);

        assertEq(IERC20(EGBP).balanceOf(address(wallet)), 0);
        assertEq(IERC20(EGBP).totalSupply(), egbpSupplyBefore);
        assertEq(IERC20(USDC).balanceOf(address(wallet)), usdcOut);
    }

    /// @notice defiSwap with a USDC fee, buyback into TEL, and a referral payout —
    ///         run post-upgrade against TEL v3. Buyback routes through a seeded
    ///         TEL3/USDC QuickSwap V2 pool, the referral fee is paid to a
    ///         TEL3-aware plugin in 18 decimals, the remainder is swept to
    ///         defiSafe, and the tx is sent by the live SWAPPER_ROLE EOA.
    function test_defiSwap_feeTokenUsdc_buybackAndReferral() public {
        uint256 feeAmount = 100e6; // 100 USDC
        uint256 referralFee = 1_000e18; // 1,000 TEL3
        address defiSafe = makeAddr("defiSafe");
        address referrer = makeAddr("referrer");

        _seedTel3UsdcPool(10_000_000e18, 100_000e6);

        TestWallet wallet = new TestWallet();
        deal(USDC, address(wallet), feeAmount);
        TestPlugin plugin = new TestPlugin(IERC20(address(tel3)));

        address[] memory path = new address[](2);
        path[0] = USDC; // in token
        path[1] = address(tel3); // out token

        AmirX.DefiSwap memory defi = AmirX.DefiSwap({
            defiSafe: defiSafe,
            // Target router for swaps and buybacks
            aggregator: QUICKSWAP_V2_ROUTER,
            // If referrer exists, pass the SimplePlugin to increase rewards
            plugin: ISimplePlugin(address(plugin)),
            // the token being used to pay the fee amount which is then used to buyback TEL
            feeToken: ERC20(USDC),
            // if the wallet was referred by a 'referrer', the referrer gets a fee form the swap
            referrer: referrer,
            // amount fee to grant to referrer as a reward through the SimplePlugin
            referralFee: referralFee,
            // wallet executable - wallet sends this fee amount
            walletData: abi.encodeCall(
                TestWallet.transferToken,
                (IERC20(USDC), AMIRX_PROXY, feeAmount)
            ),
            // wallet executable - swaps usdc to tel3 in this case
            swapData: abi.encodeCall(
                IUniswapV2Router02.swapExactTokensForTokens,
                (feeAmount, 0, path, AMIRX_PROXY, block.timestamp)
            )
        });

        // live storage survived the upgrade: the production swapper still has the role
        assertTrue(amirx.hasRole(amirx.SWAPPER_ROLE(), LIVE_SWAPPER));

        vm.prank(LIVE_SWAPPER);
        amirx.defiSwap(address(wallet), defi);

        // wallet paid the fee, AmirX retained nothing
        assertEq(IERC20(USDC).balanceOf(address(wallet)), 0);
        assertEq(IERC20(USDC).balanceOf(AMIRX_PROXY), 0);
        assertEq(tel3.balanceOf(AMIRX_PROXY), 0);
        // referral credited and funded in 18-decimal TEL3
        assertEq(plugin.claimable(referrer), referralFee);
        assertEq(tel3.balanceOf(address(plugin)), referralFee);
        // buyback remainder swept to defiSafe
        assertGt(tel3.balanceOf(defiSafe), 0);
    }

    /// @notice THE day-one breaking change (17% of prod traffic): today's exact
    ///         params — feeToken = legacy TEL with no aggregator/swapData — pass
    ///         today because legacy TEL == TELCOIN, but revert post-upgrade at
    ///         _verifyDefiSwap. Documents why the BE flip must be atomic.
    function test_defiSwap_legacyTelFeeNoSwapData_reverts() public {
        uint256 feeAmount = 10_000e2; // legacy TEL is 2 decimals
        TestWallet wallet = new TestWallet();
        deal(LEGACY_TEL, address(wallet), feeAmount);

        AmirX.DefiSwap memory defi;
        defi.defiSafe = makeAddr("defiSafe");
        defi.feeToken = ERC20(LEGACY_TEL);
        defi.walletData = abi.encodeCall(
            TestWallet.transferToken,
            (IERC20(LEGACY_TEL), AMIRX_PROXY, feeAmount)
        );

        vm.prank(LIVE_SWAPPER);
        vm.expectRevert(
            abi.encodeWithSelector(
                StablecoinHandler.ZeroValueInput.selector,
                "BUYBACK"
            )
        );
        amirx.defiSwap(address(wallet), defi);
    }

    /// @notice The transition path for fees still collected in v2: legacy TEL
    ///         plus aggregator + swapData routes through _buyBack over a seeded
    ///         legacy->TEL3 pool, ending as TEL3 in the defiSafe.
    function test_defiSwap_feeTokenLegacyTel_takesBuybackBranch() public {
        // ~1:1 value pool: 1M legacy TEL (2 dec) vs 1M TEL3 (18 dec)
        _seedTel3Pool(LEGACY_TEL, 1_000_000e2, 1_000_000e18);

        uint256 feeAmount = 10_000e2;
        address defiSafe = makeAddr("defiSafe");
        TestWallet wallet = new TestWallet();
        deal(LEGACY_TEL, address(wallet), feeAmount);

        address[] memory path = new address[](2);
        path[0] = LEGACY_TEL;
        path[1] = address(tel3);

        AmirX.DefiSwap memory defi;
        defi.defiSafe = defiSafe;
        defi.aggregator = QUICKSWAP_V2_ROUTER;
        defi.feeToken = ERC20(LEGACY_TEL);
        defi.walletData = abi.encodeCall(
            TestWallet.transferToken,
            (IERC20(LEGACY_TEL), AMIRX_PROXY, feeAmount)
        );
        defi.swapData = abi.encodeCall(
            IUniswapV2Router02.swapExactTokensForTokens,
            (feeAmount, 0, path, AMIRX_PROXY, block.timestamp)
        );

        vm.prank(LIVE_SWAPPER);
        amirx.defiSwap(address(wallet), defi);

        assertGt(tel3.balanceOf(defiSafe), 0);
        assertEq(IERC20(LEGACY_TEL).balanceOf(AMIRX_PROXY), 0);
        assertEq(tel3.balanceOf(AMIRX_PROXY), 0);
    }

    /// @notice Cutover requirement: a referral pointed at the LIVE legacy plugin
    ///         reverts post-upgrade — AmirX approves the plugin in TEL3 but the
    ///         plugin pulls legacy TEL. A v3 SimplePlugin must exist (and the BE
    ///         must reference it) before referrals resume.
    function test_defiSwap_livePluginPostUpgrade_reverts() public {
        uint256 feeAmount = 1_000e18;
        TestWallet wallet = new TestWallet();
        _mintTel3(address(wallet), feeAmount);

        AmirX.DefiSwap memory defi;
        defi.defiSafe = makeAddr("defiSafe");
        defi.feeToken = ERC20(address(tel3));
        defi.plugin = ISimplePlugin(LIVE_PLUGIN);
        defi.referrer = makeAddr("referrer");
        defi.referralFee = 500e18;
        defi.walletData = abi.encodeCall(
            TestWallet.transferToken,
            (IERC20(address(tel3)), AMIRX_PROXY, feeAmount)
        );

        vm.prank(LIVE_SWAPPER);
        vm.expectRevert(); // legacy plugin pulls legacy TEL AmirX never approved
        amirx.defiSwap(address(wallet), defi);
    }

    /// @notice The actual cutover deployment: the REAL SimplePlugin (verified
    ///         prod source) constructed with (STAKING_MODULE, TEL3) and
    ///         setIncreaser(AmirX). Runs the modal swap against it, then claims
    ///         the referral end-to-end (claim pranked as the staking module —
    ///         plugin registration in the module is a separate governance step).
    function test_defiSwap_realSimplePluginV3_claimThroughStaking() public {
        uint256 feeAmount = 100e6;
        uint256 referralFee = 1_000e18;
        address defiSafe = makeAddr("defiSafe");
        address referrer = makeAddr("referrer");

        _seedTel3UsdcPool(10_000_000e18, 100_000e6);

        SimplePlugin plugin = new SimplePlugin(
            STAKING_MODULE,
            IERC20(address(tel3))
        );
        plugin.setIncreaser(AMIRX_PROXY);

        TestWallet wallet = new TestWallet();
        deal(USDC, address(wallet), feeAmount);

        address[] memory path = new address[](2);
        path[0] = USDC;
        path[1] = address(tel3);

        AmirX.DefiSwap memory defi;
        defi.defiSafe = defiSafe;
        defi.aggregator = QUICKSWAP_V2_ROUTER;
        defi.plugin = ISimplePlugin(address(plugin));
        defi.feeToken = ERC20(USDC);
        defi.referrer = referrer;
        defi.referralFee = referralFee;
        defi.walletData = abi.encodeCall(
            TestWallet.transferToken,
            (IERC20(USDC), AMIRX_PROXY, feeAmount)
        );
        defi.swapData = abi.encodeCall(
            IUniswapV2Router02.swapExactTokensForTokens,
            (feeAmount, 0, path, AMIRX_PROXY, block.timestamp)
        );

        vm.prank(LIVE_SWAPPER);
        amirx.defiSwap(address(wallet), defi);

        assertEq(plugin.claimable(referrer, ""), referralFee);
        assertEq(tel3.balanceOf(address(plugin)), referralFee);

        // claim end-to-end: plugin.claim is onlyStaking
        vm.prank(STAKING_MODULE);
        plugin.claim(referrer, referrer, "");
        assertEq(tel3.balanceOf(referrer), referralFee);
        assertEq(plugin.claimable(referrer, ""), 0);
    }

    /// @notice Transition mode (29% of prod traffic today): feeToken/aggregator/
    ///         swapData all zero passes verification and disperses nothing; the
    ///         collected fee accumulates in AmirX for a later flush.
    function test_defiSwap_feeTokenZero_skipsBuyback() public {
        uint256 feeAmount = 100e6;
        address defiSafe = makeAddr("defiSafe");
        TestWallet wallet = new TestWallet();
        deal(USDC, address(wallet), feeAmount);

        AmirX.DefiSwap memory defi;
        defi.defiSafe = defiSafe;
        defi.walletData = abi.encodeCall(
            TestWallet.transferToken,
            (IERC20(USDC), AMIRX_PROXY, feeAmount)
        );

        vm.prank(LIVE_SWAPPER);
        amirx.defiSwap(address(wallet), defi);

        // fee accumulated in AmirX, nothing dispersed
        assertEq(IERC20(USDC).balanceOf(AMIRX_PROXY), feeAmount);
        assertEq(tel3.balanceOf(defiSafe), 0);
        assertEq(IERC20(USDC).balanceOf(defiSafe), 0);
    }

    /// @notice Transition-mode gotcha: with buyback off and no TEL3 held by
    ///         AmirX, a nonzero referrer reverts in the plugin pull. Documents
    ///         why the BE must zero the referrer while buyback is disabled.
    function test_defiSwap_referralWithoutTelBalance_reverts() public {
        TestPlugin plugin = new TestPlugin(IERC20(address(tel3)));
        address userWallet = makeAddr("userWallet"); // codeless: empty call succeeds

        AmirX.DefiSwap memory defi;
        defi.defiSafe = makeAddr("defiSafe");
        defi.plugin = ISimplePlugin(address(plugin));
        defi.referrer = makeAddr("referrer");
        defi.referralFee = 500e18;

        vm.prank(LIVE_SWAPPER);
        vm.expectRevert(); // TEL3 transferFrom exceeds AmirX's zero balance
        amirx.defiSwap(userWallet, defi);
    }

    /// @notice Once a pool exists, fees accumulated during the buyback-off
    ///         window are flushed in a single defiSwap with empty walletData.
    function test_defiSwap_feeFlush_emptyWalletData() public {
        _seedTel3UsdcPool(10_000_000e18, 100_000e6);

        uint256 accumulated = 5_000e6;
        deal(USDC, AMIRX_PROXY, accumulated); // fees from the disabled window
        address defiSafe = makeAddr("defiSafe");
        address userWallet = makeAddr("flushWallet"); // codeless: empty call succeeds

        address[] memory path = new address[](2);
        path[0] = USDC;
        path[1] = address(tel3);

        AmirX.DefiSwap memory defi;
        defi.defiSafe = defiSafe;
        defi.aggregator = QUICKSWAP_V2_ROUTER;
        defi.feeToken = ERC20(USDC);
        defi.swapData = abi.encodeCall(
            IUniswapV2Router02.swapExactTokensForTokens,
            (accumulated, 0, path, AMIRX_PROXY, block.timestamp)
        );

        vm.prank(LIVE_SWAPPER);
        amirx.defiSwap(userWallet, defi);

        assertEq(IERC20(USDC).balanceOf(AMIRX_PROXY), 0);
        assertEq(tel3.balanceOf(AMIRX_PROXY), 0);
        assertGt(tel3.balanceOf(defiSafe), 0);
    }

    /// @notice POL fee branch (4.5% of prod traffic): AmirX sends its entire
    ///         native balance to the aggregator; bought TEL3 sweeps to defiSafe.
    function test_defiSwap_feeTokenPol_path() public {
        _seedTel3Pool(WPOL, 1_000_000e18, 10_000_000e18);

        uint256 accumulatedPol = 2_000e18;
        vm.deal(AMIRX_PROXY, accumulatedPol);
        address defiSafe = makeAddr("defiSafe");
        address userWallet = makeAddr("polWallet");

        address[] memory path = new address[](2);
        path[0] = WPOL;
        path[1] = address(tel3);

        AmirX.DefiSwap memory defi;
        defi.defiSafe = defiSafe;
        defi.aggregator = QUICKSWAP_V2_ROUTER;
        defi.feeToken = ERC20(amirx.POL());
        defi.swapData = abi.encodeCall(
            IUniswapV2Router02.swapExactETHForTokens,
            (0, path, AMIRX_PROXY, block.timestamp)
        );

        vm.prank(LIVE_SWAPPER);
        amirx.defiSwap(userWallet, defi);

        assertEq(AMIRX_PROXY.balance, 0);
        assertEq(tel3.balanceOf(AMIRX_PROXY), 0);
        assertGt(tel3.balanceOf(defiSafe), 0);
    }

    /// @notice New operational coupling: pausing TEL3 bricks _feeDispersal (the
    ///         sweep transfer reverts), and unpausing restores it.
    function test_tel3Paused_blocksFeeDispersal() public {
        uint256 pending = 100e18;
        _mintTel3(AMIRX_PROXY, pending); // TEL3 awaiting sweep
        address defiSafe = makeAddr("defiSafe");
        address userWallet = makeAddr("pausedWallet");

        vm.startPrank(governance);
        tel3.grantRole(tel3.PAUSER_ROLE(), governance);
        tel3.grantRole(tel3.UNPAUSER_ROLE(), governance);
        tel3.pause();
        vm.stopPrank();

        AmirX.DefiSwap memory defi;
        defi.defiSafe = defiSafe;
        defi.feeToken = ERC20(address(tel3));

        vm.prank(LIVE_SWAPPER);
        vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
        amirx.defiSwap(userWallet, defi);

        vm.prank(governance);
        tel3.unpause();

        vm.prank(LIVE_SWAPPER);
        amirx.defiSwap(userWallet, defi);
        assertEq(tel3.balanceOf(defiSafe), pending);
    }

    /// @notice SUPPORT_ROLE rescue post-upgrade — including legacy TEL stranded
    ///         in AmirX at the flip (no longer swept once TELCOIN is TEL3) and
    ///         native POL.
    function test_rescueCrypto() public {
        uint256 strandedLegacy = 50_000e2;
        uint256 strandedPol = 5e18;
        deal(LEGACY_TEL, AMIRX_PROXY, strandedLegacy);
        vm.deal(AMIRX_PROXY, strandedPol);

        uint256 legacyBefore = IERC20(LEGACY_TEL).balanceOf(AMIRX_ADMIN_SAFE);
        uint256 polBefore = AMIRX_ADMIN_SAFE.balance;

        vm.startPrank(AMIRX_ADMIN_SAFE); // holds SUPPORT_ROLE (verified live)
        amirx.rescueCrypto(ERC20(LEGACY_TEL), strandedLegacy);
        amirx.rescueCrypto(ERC20(amirx.POL()), strandedPol);
        vm.stopPrank();

        assertEq(
            IERC20(LEGACY_TEL).balanceOf(AMIRX_ADMIN_SAFE),
            legacyBefore + strandedLegacy
        );
        assertEq(AMIRX_ADMIN_SAFE.balance, polBefore + strandedPol);
        assertEq(IERC20(LEGACY_TEL).balanceOf(AMIRX_PROXY), 0);
        assertEq(AMIRX_PROXY.balance, 0);
    }

    // TODO: test_prodBytecodeParity — vm.etch the Hardhat-compiled (OZ 5.0.1)
    //       implementation from telcoin-contracts over newImplementation and re-run
    //       the critical paths; final gate before the real upgrade
}
