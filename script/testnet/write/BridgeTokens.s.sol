// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {console} from "forge-std/console.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {DeployUtility} from "../../utils/DeployUtility.sol";
import {TelcoinBridge} from "../../../src/TelcoinBridge.sol";
import {MessagingFee, MessagingReceipt} from "@layerzerolabs/oapp-evm/contracts/oapp/OApp.sol";
import {SendParam, OFTReceipt} from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";
import "../utils/Constants.sol";

/// @title BridgeTokens
/// @notice Script to bridge TelcoinV3 tokens across chains via TelcoinBridge (LayerZero V2)
///         using a Gnosis Safe.
///
/// @dev Configure the `pathway` array in setUp():
///      - pathway[0] = source chain (where tokens are burned)
///      - pathway[1] = destination chain (where tokens are minted)
///
/// ## How to Run
///
/// Simulation:
/// ```
/// forge script script/testnet/BridgeTokens.s.sol --rpc-url <SOURCE_CHAIN_RPC> --ffi -vvvv
/// ```
///
/// Broadcast (proposes to Safe TX Service):
/// ```
/// forge script script/testnet/BridgeTokens.s.sol --rpc-url <SOURCE_CHAIN_RPC> --broadcast --ffi -vvvv
/// ```
contract BridgeTokens is DeployUtility {
    // ---------
    // Constants
    // ---------

    uint256 internal constant BRIDGE_AMOUNT = 1_000_000 ether;
    uint128 internal constant DST_GAS_LIMIT = 200_000;

    // ---------
    // Variables
    // ---------

    ChainConfig[2] internal pathway;

    struct ChainConfig {
        string chainName;
        string rpcUrl;
        uint32 eid;
    }

    // -----
    // Setup
    // -----

    function setUp() public {
        _initializeSafe();

        // pathway[0] = SOURCE chain (tokens burned here)
        // pathway[1] = DESTINATION chain (tokens minted here)

        pathway[0] = ChainConfig({
            chainName: "base-sepolia",
            rpcUrl: vm.envString("BASE_SEPOLIA_RPC_URL"),
            eid: BASE_SEPOLIA_LZ_CHAIN_ID_V2
        });

        pathway[1] = ChainConfig({
            chainName: "eth-sepolia",
            rpcUrl: vm.envString("ETH_SEPOLIA_RPC_URL"),
            eid: ETH_SEPOLIA_LZ_CHAIN_ID_V2
        });
    }

    // ------
    // Script
    // ------

    function run() public {
        ChainConfig memory src = pathway[0];
        ChainConfig memory dst = pathway[1];

        address telcoinV3 = _loadDeploymentAddress(src.chainName, "TelcoinV3");
        address bridgeContract = _loadDeploymentAddress(src.chainName, "TelcoinBridge");

        require(telcoinV3 != address(0), "TelcoinV3 not deployed on source chain");
        require(bridgeContract != address(0), "TelcoinBridge not deployed on source chain");

        console.log("=== Bridge Script (Safe) ===");
        console.log("Source Chain:", src.chainName);
        console.log("Destination Chain:", dst.chainName);
        console.log("Safe:", deployerSafeAddress);
        console.log("TelcoinV3:", telcoinV3);
        console.log("TelcoinBridge:", bridgeContract);
        console.log("");

        IERC20 token = IERC20(telcoinV3);
        TelcoinBridge bridge = TelcoinBridge(bridgeContract);

        uint256 balanceBefore = token.balanceOf(deployerSafeAddress);
        console.log("Safe TelcoinV3 Balance:", balanceBefore);
        console.log("Amount to Bridge:", BRIDGE_AMOUNT);
        require(balanceBefore >= BRIDGE_AMOUNT, "Insufficient TelcoinV3 balance");

        // Approve MintBurnWrapper to burn tokens
        address minterBurner = address(bridge.minterBurner());
        _proposeTransaction(
            telcoinV3,
            abi.encodeCall(token.approve, (minterBurner, BRIDGE_AMOUNT)),
            "Approve MintBurnWrapper for bridge"
        );

        // Build LZ V2 TYPE_3 options
        bytes memory options = abi.encodePacked(
            uint16(3), uint8(1), uint16(17), uint8(1), DST_GAS_LIMIT
        );

        SendParam memory sendParam = SendParam({
            dstEid: dst.eid,
            to: bytes32(uint256(uint160(deployerSafeAddress))),
            amountLD: BRIDGE_AMOUNT,
            minAmountLD: 0,
            extraOptions: options,
            composeMsg: bytes(""),
            oftCmd: bytes("")
        });
        MessagingFee memory fee = bridge.quoteSend(sendParam, false);

        console.log("LayerZero Fee (native):", fee.nativeFee);

        // Execute bridge via Safe (send with value for LZ fee)
        _proposeTransaction(
            bridgeContract,
            abi.encodeCall(bridge.send, (sendParam, fee, deployerSafeAddress)),
            "Bridge TelcoinV3 tokens"
        );

        console.log("Bridge transactions proposed.");
    }
}
