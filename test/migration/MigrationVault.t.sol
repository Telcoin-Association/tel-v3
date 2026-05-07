// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {MigrationVault} from "../../src/MigrationVault.sol";
import {TelcoinV3} from "../../src/TelcoinV3.sol";
import {Roles} from "../../src/helpers/Roles.sol";
import {MockERC20} from "../mocks/MockERC20.sol";

/**
 * @title MigrationVaultTest
 * @dev Full test suite for the MigrationVault contract (Phase 2 token migration).
 *      Tests run against an Ethereum mainnet fork using the real TEL v2 contract
 *      and a freshly deployed TelcoinV3 instance. Covers initialization, one-way
 *      migration (TEL v2 -> TEL v3), decimal conversion, pause/unpause, treasury
 *      withdrawals, UUPS upgrades, access control, and fuzz-based invariants.
 */
contract MigrationVaultTest is Test, Roles {
    MigrationVault internal vault;
    MigrationVault internal implementation;
    IERC20 internal oldToken;
    TelcoinV3 internal newToken;

    address internal admin = makeAddr("admin");
    address internal pauser = makeAddr("pauser");
    address internal unpauser = makeAddr("unpauser");
    address internal treasuryAddr = makeAddr("treasury");
    address internal user = makeAddr("user");
    address internal user2 = makeAddr("user2");
    address internal attacker = makeAddr("attacker");

    uint8 internal constant OLD_DECIMALS = 2;
    uint8 internal constant NEW_DECIMALS = 18;
    uint256 internal constant VAULT_RESERVE = 1_000_000_000 ether; // 1B NEW tokens
    uint256 internal constant USER_BALANCE = 1_000_000 * 10 ** OLD_DECIMALS; // 1M OLD tokens
    uint256 internal constant INITIAL_V3_SUPPLY = 10_000_000_000 ether; // 10B

    address constant TELV2_ADDRESS = 0x467Bccd9d29f223BcE8043b84E8C8B282827790F;

    // Cached role hashes (avoids vm.prank being consumed by view calls)
    bytes32 internal defaultAdminRole;
    bytes32 internal treasuryRole;
    bytes32 internal pauserRole;
    bytes32 internal unpauserRole;

    // Fork
    string ethereumRpcUrl = vm.envString("ETHEREUM_RPC_URL");
    uint256 ethereumFork;

    function setUp() public {
        // Fork ethereum mainnet
        ethereumFork = vm.createFork(ethereumRpcUrl);
        vm.selectFork(ethereumFork);

        // Use real TEL v2 on mainnet
        oldToken = IERC20(TELV2_ADDRESS);
        assertEq(IERC20Metadata(address(oldToken)).decimals(), OLD_DECIMALS);

        // Deploy TelcoinV3
        vm.prank(admin);
        newToken = new TelcoinV3(INITIAL_V3_SUPPLY, admin);
        assertEq(newToken.decimals(), NEW_DECIMALS);

        // Deploy MigrationVault implementation and proxy
        implementation = new MigrationVault();
        bytes memory initData = abi.encodeCall(
            MigrationVault.initialize,
            (address(oldToken), address(newToken), admin, pauser, unpauser)
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        vault = MigrationVault(address(proxy));

        // Cache role hashes
        defaultAdminRole = vault.DEFAULT_ADMIN_ROLE();
        treasuryRole = vault.TREASURY_ROLE();
        pauserRole = vault.PAUSER_ROLE();
        unpauserRole = vault.UNPAUSER_ROLE();

        // Grant treasury role on vault
        vm.prank(admin);
        vault.grantRole(treasuryRole, treasuryAddr);

        // Mint TEL v3 to vault as reserves (grant MINTER_ROLE, mint, then revoke)
        vm.startPrank(admin);
        newToken.grantRole(MINTER_ROLE, admin);
        newToken.mint(address(vault), VAULT_RESERVE);
        newToken.revokeRole(MINTER_ROLE, admin);
        vm.stopPrank();

        // Fund users with TEL v2 via deal
        deal(address(oldToken), user, USER_BALANCE);
        deal(address(oldToken), user2, USER_BALANCE);

        // Approve vault
        vm.prank(user);
        oldToken.approve(address(vault), type(uint256).max);
        vm.prank(user2);
        oldToken.approve(address(vault), type(uint256).max);
    }

    // --------------------
    // Initialization Tests
    // --------------------

    /// @dev Verifies token addresses and WAD conversion factors are set correctly after initialization.
    function test_initialize_setsState() public view {
        assertEq(address(vault.OLD_TOKEN()), address(oldToken));
        assertEq(address(vault.NEW_TOKEN()), address(newToken));
        assertEq(vault.oldToWad(), 10 ** (18 - OLD_DECIMALS));
        assertEq(vault.newToWad(), 10 ** (18 - NEW_DECIMALS));
    }

    /// @dev Verifies all four roles are granted to the correct addresses during initialization.
    function test_initialize_grantsRoles() public view {
        assertTrue(vault.hasRole(defaultAdminRole, admin));
        assertTrue(vault.hasRole(pauserRole, pauser));
        assertTrue(vault.hasRole(unpauserRole, unpauser));
        assertTrue(vault.hasRole(treasuryRole, treasuryAddr));
    }

    /// @dev Verifies the proxy cannot be reinitialized after the first initialization.
    function test_initialize_cannotReinitialize() public {
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        vault.initialize(address(oldToken), address(newToken), admin, pauser, unpauser);
    }

    /// @dev Verifies initialization reverts when _oldToken is the zero address.
    function test_initialize_revertsZeroOldToken() public {
        MigrationVault impl = new MigrationVault();
        vm.expectRevert(MigrationVault.ZeroAddress.selector);
        new ERC1967Proxy(
            address(impl),
            abi.encodeCall(MigrationVault.initialize, (address(0), address(newToken), admin, pauser, unpauser))
        );
    }

    /// @dev Verifies initialization reverts when _newToken is the zero address.
    function test_initialize_revertsZeroNewToken() public {
        MigrationVault impl = new MigrationVault();
        vm.expectRevert(MigrationVault.ZeroAddress.selector);
        new ERC1967Proxy(
            address(impl),
            abi.encodeCall(MigrationVault.initialize, (address(oldToken), address(0), admin, pauser, unpauser))
        );
    }

    /// @dev Verifies initialization reverts when _admin is the zero address.
    function test_initialize_revertsZeroAdmin() public {
        MigrationVault impl = new MigrationVault();
        vm.expectRevert(MigrationVault.ZeroAddress.selector);
        new ERC1967Proxy(
            address(impl),
            abi.encodeCall(MigrationVault.initialize, (address(oldToken), address(newToken), address(0), pauser, unpauser))
        );
    }

    /// @dev Verifies initialization reverts when _pauser is the zero address.
    function test_initialize_revertsZeroPauser() public {
        MigrationVault impl = new MigrationVault();
        vm.expectRevert(MigrationVault.ZeroAddress.selector);
        new ERC1967Proxy(
            address(impl),
            abi.encodeCall(MigrationVault.initialize, (address(oldToken), address(newToken), admin, address(0), unpauser))
        );
    }

    /// @dev Verifies initialization reverts when _unpauser is the zero address.
    function test_initialize_revertsZeroUnpauser() public {
        MigrationVault impl = new MigrationVault();
        vm.expectRevert(MigrationVault.ZeroAddress.selector);
        new ERC1967Proxy(
            address(impl),
            abi.encodeCall(MigrationVault.initialize, (address(oldToken), address(newToken), admin, pauser, address(0)))
        );
    }

    /// @dev Verifies initialization reverts when a token has more than 18 decimals.
    function test_initialize_revertsDecimalsExceedMax() public {
        MockERC20 badToken = new MockERC20("Bad", "BAD", 19);
        MigrationVault impl = new MigrationVault();
        vm.expectRevert(MigrationVault.DecimalsExceedMax.selector);
        new ERC1967Proxy(
            address(impl),
            abi.encodeCall(MigrationVault.initialize, (address(badToken), address(newToken), admin, pauser, unpauser))
        );
    }

    /// @dev Verifies the bare implementation contract cannot be initialized directly.
    function test_implementation_cannotBeInitialized() public {
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        implementation.initialize(address(oldToken), address(newToken), admin, pauser, unpauser);
    }

    // ---------------
    // Migration Tests
    // ---------------

    /// @dev Verifies a basic migration transfers correct amounts and updates all balances.
    function test_migrate_basic() public {
        uint256 amountIn = 100 * 10 ** OLD_DECIMALS; // 100 TEL v2
        uint256 expectedOut = 100 ether; // 100 TEL v3

        vm.prank(user);
        uint256 amountOut = vault.migrate(user, amountIn);

        assertEq(amountOut, expectedOut);
        assertEq(oldToken.balanceOf(user), USER_BALANCE - amountIn);
        assertEq(newToken.balanceOf(user), expectedOut);
        assertEq(oldToken.balanceOf(address(vault)), amountIn);
        assertEq(newToken.balanceOf(address(vault)), VAULT_RESERVE - expectedOut);
    }

    /// @dev Verifies a user can migrate tokens to a different recipient address.
    function test_migrate_toDifferentRecipient() public {
        uint256 amountIn = 50 * 10 ** OLD_DECIMALS;
        uint256 expectedOut = 50 ether;

        vm.prank(user);
        uint256 amountOut = vault.migrate(user2, amountIn);

        assertEq(amountOut, expectedOut);
        assertEq(oldToken.balanceOf(user), USER_BALANCE - amountIn);
        assertEq(newToken.balanceOf(user), 0);
        assertEq(newToken.balanceOf(user2), expectedOut);
    }

    /// @dev Verifies the Migrated event is emitted with correct parameters.
    function test_migrate_emitsEvent() public {
        uint256 amountIn = 100 * 10 ** OLD_DECIMALS;
        uint256 expectedOut = 100 ether;

        vm.expectEmit(true, true, true, true);
        emit MigrationVault.Migrated(user, user, amountIn, expectedOut);

        vm.prank(user);
        vault.migrate(user, amountIn);
    }

    /// @dev Verifies a user can migrate their entire TEL v2 balance in a single call.
    function test_migrate_entireBalance() public {
        vm.prank(user);
        uint256 amountOut = vault.migrate(user, USER_BALANCE);

        uint256 expectedOut = 1_000_000 ether;
        assertEq(amountOut, expectedOut);
        assertEq(oldToken.balanceOf(user), 0);
        assertEq(newToken.balanceOf(user), expectedOut);
    }

    /// @dev Verifies multiple users can migrate sequentially with correct accounting.
    function test_migrate_multipleUsers() public {
        uint256 amountIn = 100 * 10 ** OLD_DECIMALS;
        uint256 expectedOut = 100 ether;

        vm.prank(user);
        vault.migrate(user, amountIn);

        vm.prank(user2);
        vault.migrate(user2, amountIn);

        assertEq(newToken.balanceOf(user), expectedOut);
        assertEq(newToken.balanceOf(user2), expectedOut);
        assertEq(oldToken.balanceOf(address(vault)), amountIn * 2);
        assertEq(newToken.balanceOf(address(vault)), VAULT_RESERVE - expectedOut * 2);
    }

    /// @dev Verifies migrate reverts when recipient is the zero address.
    function test_migrate_revertsZeroAddress() public {
        vm.prank(user);
        vm.expectRevert(MigrationVault.ZeroAddress.selector);
        vault.migrate(address(0), 100);
    }

    /// @dev Verifies migrate reverts when amountIn is zero.
    function test_migrate_revertsZeroAmount() public {
        vm.prank(user);
        vm.expectRevert(MigrationVault.ZeroAmount.selector);
        vault.migrate(user, 0);
    }

    /// @dev Verifies migrate reverts when the vault has insufficient NEW token reserves.
    function test_migrate_revertsInsufficientReserves() public {
        // Drain the vault first
        vm.prank(admin);
        vault.grantRole(treasuryRole, admin);
        vm.prank(admin);
        vault.withdraw(address(newToken), admin, VAULT_RESERVE);

        vm.prank(user);
        vm.expectRevert(MigrationVault.InsufficientReserves.selector);
        vault.migrate(user, 100 * 10 ** OLD_DECIMALS);
    }

    /// @dev Verifies migrate reverts when decimal conversion truncates amountOut to zero.
    function test_migrate_revertsZeroAmountOut() public {
        // Deploy a vault where OLD has more decimals than NEW so conversion truncates to 0
        MockERC20 old18 = new MockERC20("Old18", "O18", 18);
        MockERC20 new6 = new MockERC20("New6", "N6", 6);

        MigrationVault impl = new MigrationVault();
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(impl),
            abi.encodeCall(MigrationVault.initialize, (address(old18), address(new6), admin, pauser, unpauser))
        );
        MigrationVault truncVault = MigrationVault(address(proxy));

        new6.mint(address(truncVault), 1_000_000 * 1e6);

        // amountIn < 1e12 will truncate to 0 when converting 18-dec to 6-dec
        uint256 tinyAmount = 1e11; // less than 1e12
        old18.mint(user, tinyAmount);
        vm.prank(user);
        old18.approve(address(truncVault), tinyAmount);

        vm.prank(user);
        vm.expectRevert(MigrationVault.ZeroAmount.selector);
        truncVault.migrate(user, tinyAmount);
    }

    /// @dev Verifies migrate reverts when the contract is paused.
    function test_migrate_revertsWhenPaused() public {
        vm.prank(pauser);
        vault.pause();

        vm.prank(user);
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        vault.migrate(user, 100 * 10 ** OLD_DECIMALS);
    }

    // ---------------------
    // Preview Migrate Tests
    // ---------------------

    /// @dev Verifies previewMigrate returns the exact same amount as an actual migrate call.
    function test_previewMigrate_matchesActual() public {
        uint256 amountIn = 500 * 10 ** OLD_DECIMALS;
        uint256 preview = vault.previewMigrate(amountIn);

        vm.prank(user);
        uint256 actual = vault.migrate(user, amountIn);

        assertEq(preview, actual);
    }

    /// @dev Verifies the 2-decimal to 18-decimal conversion produces correct output values.
    function test_previewMigrate_decimalConversion() public view {
        // 1 TEL v2 (2 decimals) = 1 TEL v3 (18 decimals)
        uint256 oneOld = 1 * 10 ** OLD_DECIMALS; // 100
        uint256 expected = 1 ether; // 1e18
        assertEq(vault.previewMigrate(oneOld), expected);

        // Smallest unit: 1 unit of TEL v2 (0.01) = 1e16 TEL v3
        assertEq(vault.previewMigrate(1), 10 ** (NEW_DECIMALS - OLD_DECIMALS));
    }

    // -------------------
    // Pause/Unpause Tests
    // -------------------

    /// @dev Verifies the PAUSER_ROLE can successfully pause the contract.
    function test_pause_byPauser() public {
        vm.prank(pauser);
        vault.pause();
        assertTrue(vault.paused());
    }

    /// @dev Verifies pause reverts when called by an account without PAUSER_ROLE.
    function test_pause_revertsNonPauser() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                attacker,
                pauserRole
            )
        );
        vm.prank(attacker);
        vault.pause();
    }

    /// @dev Verifies the UNPAUSER_ROLE can successfully unpause the contract.
    function test_unpause_byUnpauser() public {
        vm.prank(pauser);
        vault.pause();

        vm.prank(unpauser);
        vault.unpause();
        assertFalse(vault.paused());
    }

    /// @dev Verifies unpause reverts when called by an account without UNPAUSER_ROLE.
    function test_unpause_revertsNonUnpauser() public {
        vm.prank(pauser);
        vault.pause();

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                attacker,
                unpauserRole
            )
        );
        vm.prank(attacker);
        vault.unpause();
    }

    /// @dev Verifies migration resumes correctly after a pause-unpause cycle.
    function test_migrateAfterUnpause() public {
        vm.prank(pauser);
        vault.pause();

        vm.prank(unpauser);
        vault.unpause();

        vm.prank(user);
        uint256 amountOut = vault.migrate(user, 100 * 10 ** OLD_DECIMALS);
        assertEq(amountOut, 100 ether);
    }

    // --------------
    // Withdraw Tests
    // --------------

    /// @dev Verifies TREASURY_ROLE can withdraw accumulated OLD tokens after migrations.
    function test_withdraw_oldTokens() public {
        // First migrate some tokens so vault has OLD tokens
        vm.prank(user);
        vault.migrate(user, USER_BALANCE);

        uint256 withdrawAmount = USER_BALANCE;
        vm.prank(treasuryAddr);
        vault.withdraw(address(oldToken), treasuryAddr, withdrawAmount);

        assertEq(oldToken.balanceOf(treasuryAddr), withdrawAmount);
        assertEq(oldToken.balanceOf(address(vault)), 0);
    }

    /// @dev Verifies TREASURY_ROLE can withdraw NEW token reserves from the vault.
    function test_withdraw_newTokens() public {
        uint256 withdrawAmount = 1000 ether;

        vm.prank(treasuryAddr);
        vault.withdraw(address(newToken), treasuryAddr, withdrawAmount);

        assertEq(newToken.balanceOf(treasuryAddr), withdrawAmount);
        assertEq(newToken.balanceOf(address(vault)), VAULT_RESERVE - withdrawAmount);
    }

    /// @dev Verifies the Withdrawn event is emitted with correct parameters.
    function test_withdraw_emitsEvent() public {
        uint256 withdrawAmount = 1000 ether;

        vm.expectEmit(true, true, true, true);
        emit MigrationVault.Withdrawn(address(newToken), treasuryAddr, withdrawAmount);

        vm.prank(treasuryAddr);
        vault.withdraw(address(newToken), treasuryAddr, withdrawAmount);
    }

    /// @dev Verifies withdraw reverts when called by an account without TREASURY_ROLE.
    function test_withdraw_revertsNonTreasury() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                attacker,
                treasuryRole
            )
        );
        vm.prank(attacker);
        vault.withdraw(address(newToken), attacker, 100);
    }

    /// @dev Verifies withdraw reverts when the token address is zero.
    function test_withdraw_revertsZeroTokenAddress() public {
        vm.prank(treasuryAddr);
        vm.expectRevert(MigrationVault.ZeroAddress.selector);
        vault.withdraw(address(0), treasuryAddr, 100);
    }

    /// @dev Verifies withdraw reverts when the recipient address is zero.
    function test_withdraw_revertsZeroToAddress() public {
        vm.prank(treasuryAddr);
        vm.expectRevert(MigrationVault.ZeroAddress.selector);
        vault.withdraw(address(newToken), address(0), 100);
    }

    /// @dev Verifies withdraw reverts when the amount is zero.
    function test_withdraw_revertsZeroAmount() public {
        vm.prank(treasuryAddr);
        vm.expectRevert(MigrationVault.ZeroAmount.selector);
        vault.withdraw(address(newToken), treasuryAddr, 0);
    }

    // ----------
    // View Tests
    // ----------

    /// @dev Verifies getReserves returns correct balances before and after a migration.
    function test_getReserves() public {
        // Before any migration
        (uint256 oldReserve, uint256 newReserve) = vault.getReserves();
        assertEq(oldReserve, 0);
        assertEq(newReserve, VAULT_RESERVE);

        // After a migration
        uint256 amountIn = 100 * 10 ** OLD_DECIMALS;
        vm.prank(user);
        vault.migrate(user, amountIn);

        (oldReserve, newReserve) = vault.getReserves();
        assertEq(oldReserve, amountIn);
        assertEq(newReserve, VAULT_RESERVE - 100 ether);
    }

    /// @dev Verifies getDecimals returns the correct decimals for both tokens.
    function test_getDecimals() public view {
        (uint8 oldDec, uint8 newDec) = vault.getDecimals();
        assertEq(oldDec, OLD_DECIMALS);
        assertEq(newDec, NEW_DECIMALS);
    }

    // -------------
    // Upgrade Tests
    // -------------

    /// @dev Verifies DEFAULT_ADMIN_ROLE can upgrade the implementation and state is preserved.
    function test_upgrade_byAdmin() public {
        MigrationVault newImpl = new MigrationVault();

        vm.prank(admin);
        vault.upgradeToAndCall(address(newImpl), "");

        // Verify state preserved
        assertEq(address(vault.OLD_TOKEN()), address(oldToken));
        assertEq(address(vault.NEW_TOKEN()), address(newToken));
    }

    /// @dev Verifies upgrade reverts when called by an account without DEFAULT_ADMIN_ROLE.
    function test_upgrade_revertsNonAdmin() public {
        MigrationVault newImpl = new MigrationVault();

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                attacker,
                defaultAdminRole
            )
        );
        vm.prank(attacker);
        vault.upgradeToAndCall(address(newImpl), "");
    }

    // ----------
    // Fuzz Tests
    // ----------

    /// @dev Fuzz: verifies migration produces correct output and balance changes for arbitrary amounts.
    function testFuzz_migrate(uint256 amountIn) public {
        amountIn = bound(amountIn, 1, USER_BALANCE);

        uint256 expectedOut = amountIn * (10 ** (NEW_DECIMALS - OLD_DECIMALS));

        if (expectedOut > VAULT_RESERVE) return;

        vm.prank(user);
        uint256 amountOut = vault.migrate(user, amountIn);

        assertEq(amountOut, expectedOut);
        assertEq(oldToken.balanceOf(user), USER_BALANCE - amountIn);
        assertEq(newToken.balanceOf(user), expectedOut);
    }

    /// @dev Fuzz: verifies previewMigrate always matches the actual migrate output.
    function testFuzz_previewMatchesMigrate(uint256 amountIn) public {
        amountIn = bound(amountIn, 1, USER_BALANCE);

        uint256 preview = vault.previewMigrate(amountIn);

        if (preview > VAULT_RESERVE || preview == 0) return;

        vm.prank(user);
        uint256 actual = vault.migrate(user, amountIn);

        assertEq(preview, actual);
    }

    /// @dev Fuzz: verifies the 1:1 value invariant holds — WAD-normalized input equals WAD-normalized output.
    function testFuzz_migrate_conservesValue(uint256 amountIn) public view {
        amountIn = bound(amountIn, 1, USER_BALANCE);

        uint256 amountOut = vault.previewMigrate(amountIn);

        // Value in WAD should be equal (1:1 conversion)
        uint256 valueInWad = amountIn * vault.oldToWad();
        uint256 valueOutWad = amountOut * vault.newToWad();
        assertEq(valueInWad, valueOutWad);
    }

    // -------------------------
    // Access Control Edge Cases
    // -------------------------

    /// @dev Verifies the admin can grant TREASURY_ROLE to a new address.
    function test_adminCanGrantTreasuryRole() public {
        address newTreasury = makeAddr("newTreasury");

        vm.prank(admin);
        vault.grantRole(treasuryRole, newTreasury);

        assertTrue(vault.hasRole(treasuryRole, newTreasury));
    }

    /// @dev Verifies a non-admin cannot grant roles.
    function test_nonAdminCannotGrantRoles() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                attacker,
                defaultAdminRole
            )
        );
        vm.prank(attacker);
        vault.grantRole(treasuryRole, attacker);
    }

    // ---------------
    // Constants Tests
    // ---------------

    /// @dev Verifies all public constants match their expected values.
    function test_constants() public view {
        assertEq(vault.WAD(), 1e18);
        assertEq(vault.MAX_DECIMALS(), 18);
        assertEq(vault.TREASURY_ROLE(), keccak256("TREASURY_ROLE"));
        assertEq(vault.PAUSER_ROLE(), keccak256("PAUSER_ROLE"));
        assertEq(vault.UNPAUSER_ROLE(), keccak256("UNPAUSER_ROLE"));
    }
}
