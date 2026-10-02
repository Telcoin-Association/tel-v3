// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {console} from "forge-std/console.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {DeployBase} from "forge-deploy-utils/DeployBase.sol";
import {TelcoinBridge} from "../../../src/TelcoinBridge.sol";
import {MessagingFee} from "@layerzerolabs/oapp-evm/contracts/oapp/OApp.sol";
import {SendParam} from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";
import "../utils/Constants.sol";

/// @title BridgeTokensFromEOA (Mainnet)
/// @notice Bridges TelcoinV3 across mainnet chains via TelcoinBridge (LayerZero V2) from a
///         plain EOA instead of the Safe — for quick end-to-end bridge testing. The EOA pays
///         the LayerZero native fee directly as msg.value, which the Safe propose flow cannot.
///
///         The amount is the BRIDGE_AMOUNT constant below. The source chain is whatever
///         --rpc-url points at; the destination comes from env:
///           DST_CHAIN          "ethereum" | "base" | "polygon" (must differ from source)
///           BRIDGE_RECIPIENT   optional destination recipient (defaults to the sending EOA)
///
///         The EOA needs TEL v3 on the source chain plus native gas for the LZ fee.
///
/// ## How to Run
///
/// Simulation (pass --sender so balance checks run against the right EOA):
/// ```
/// DST_CHAIN=base forge script script/mainnet/write/BridgeTokensFromEOA.s.sol \
///     --rpc-url $ETHEREUM_RPC_URL --sender $EOA -vvvv
/// ```
///
/// Broadcast (private key, or swap in --trezor / --ledger / --account). The -g 200 gas
/// multiplier is REQUIRED: foundry's fork simulation undercharges cold state access, so its
/// gas estimate for send() lands ~40% below real execution (verified on Polygon: forge
/// measured ~410k vs 671k actual; a real node's eth_estimateGas gets it right). Without it
/// the send runs out of gas in the DVN fee loop:
/// ```
/// DST_CHAIN=base forge script script/mainnet/write/BridgeTokensFromEOA.s.sol \
///     --rpc-url $ETHEREUM_RPC_URL --broadcast --private-key $EOA_PRIVATE_KEY -g 200 -vvvv
/// ```
contract BridgeTokensFromEOA is DeployBase {
    /// @notice Amount of TEL v3 to bridge (18 decimals). Must be a multiple of 1e12 wei:
    ///         OFT shared decimals are 6, so anything below that is truncated as dust and
    ///         would trip the exact-amount slippage check. Whole-TEL amounts are always safe.
    uint256 internal constant BRIDGE_AMOUNT = 10 ether;
    uint128 internal constant DST_GAS_LIMIT = 200_000;

    struct BridgeConfig {
        string srcChain;
        string dstChain;
        uint32 dstEid;
        uint256 amount;
        address telcoinV3;
        address bridge;
    }

    function run() public {
        BridgeConfig memory cfg = _loadConfig();

        vm.startBroadcast();
        _bridge(cfg, msg.sender);
        vm.stopBroadcast();

        console.log("Bridge send submitted: %s -> %s", cfg.srcChain, cfg.dstChain);
        console.log("Track delivery: https://layerzeroscan.com/");
    }

    function _loadConfig() internal view returns (BridgeConfig memory cfg) {
        (cfg.srcChain,) = _chainByChainId(block.chainid);
        (cfg.dstChain, cfg.dstEid) = _chainByName(vm.envString("DST_CHAIN"));
        require(
            keccak256(bytes(cfg.srcChain)) != keccak256(bytes(cfg.dstChain)),
            "DST_CHAIN must differ from the source chain"
        );

        cfg.amount = BRIDGE_AMOUNT;
        require(cfg.amount > 0, "BRIDGE_AMOUNT is zero");
        require(cfg.amount % 1e12 == 0, "BRIDGE_AMOUNT has OFT dust (not a multiple of 1e12)");

        cfg.telcoinV3 = _loadDeploymentAddress(cfg.srcChain, "TelcoinV3");
        cfg.bridge = _loadDeploymentAddress(cfg.srcChain, "TelcoinBridge");
        require(cfg.telcoinV3 != address(0), "TelcoinV3 not deployed on source chain");
        require(cfg.bridge != address(0), "TelcoinBridge not deployed on source chain");
    }

    function _bridge(BridgeConfig memory cfg, address eoa) internal {
        address recipient = vm.envOr("BRIDGE_RECIPIENT", eoa);

        console.log("=== Bridge TelcoinV3 (EOA) ===");
        console.log("Source Chain:", cfg.srcChain);
        console.log("Destination Chain:", cfg.dstChain);
        console.log("EOA:", eoa);
        console.log("Recipient on destination:", recipient);
        console.log("Amount (18 dec):", cfg.amount);
        console.log("EOA TelcoinV3 balance:", IERC20(cfg.telcoinV3).balanceOf(eoa));
        require(IERC20(cfg.telcoinV3).balanceOf(eoa) >= cfg.amount, "Insufficient TelcoinV3 balance");

        // TelcoinV3.burn is allowance-gated, so the wrapper (not the bridge) needs approval
        IERC20(cfg.telcoinV3).approve(address(TelcoinBridge(cfg.bridge).minterBurner()), cfg.amount);

        SendParam memory sendParam = SendParam({
            dstEid: cfg.dstEid,
            to: bytes32(uint256(uint160(recipient))),
            amountLD: cfg.amount,
            minAmountLD: cfg.amount, // burn adapter delivers exactly; whole-TEL amounts have no dust
            // LZ V2 TYPE_3 options: lzReceive gas on the destination
            extraOptions: abi.encodePacked(uint16(3), uint8(1), uint16(17), uint8(1), DST_GAS_LIMIT),
            composeMsg: bytes(""),
            oftCmd: bytes("")
        });

        MessagingFee memory fee = TelcoinBridge(cfg.bridge).quoteSend(sendParam, false);
        console.log("LayerZero fee quoted (native wei):", fee.nativeFee);

        // DVN/executor fees float with gas-price feeds between quote and inclusion (especially
        // on Polygon). Pay a 20% buffer; the endpoint refunds the excess to the refund address.
        fee.nativeFee = (fee.nativeFee * 120) / 100;
        console.log("LayerZero fee with buffer:", fee.nativeFee);
        require(eoa.balance >= fee.nativeFee, "Insufficient native balance for LZ fee");

        TelcoinBridge(cfg.bridge).send{value: fee.nativeFee}(sendParam, fee, eoa);
    }

    function _chainByChainId(uint256 chainId) internal pure returns (string memory, uint32) {
        if (chainId == ETH_MAINNET_CHAIN_ID) return ("ethereum", ETH_MAINNET_LZ_CHAIN_ID_V2);
        if (chainId == BASE_MAINNET_CHAIN_ID) return ("base", BASE_MAINNET_LZ_CHAIN_ID_V2);
        if (chainId == POLYGON_MAINNET_CHAIN_ID) return ("polygon", POLYGON_MAINNET_LZ_CHAIN_ID_V2);
        revert("Unsupported source chain");
    }

    function _chainByName(string memory name) internal pure returns (string memory, uint32) {
        bytes32 h = keccak256(bytes(name));
        if (h == keccak256("ethereum")) return ("ethereum", ETH_MAINNET_LZ_CHAIN_ID_V2);
        if (h == keccak256("base")) return ("base", BASE_MAINNET_LZ_CHAIN_ID_V2);
        if (h == keccak256("polygon")) return ("polygon", POLYGON_MAINNET_LZ_CHAIN_ID_V2);
        revert("DST_CHAIN must be ethereum, base, or polygon");
    }
}
