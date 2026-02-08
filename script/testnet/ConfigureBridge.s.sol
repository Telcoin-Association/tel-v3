// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {console} from "forge-std/console.sol";
import {DeployUtility} from "../utils/DeployUtility.sol";
import {ILayerZeroEndpointV2} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import {SetConfigParam} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/IMessageLibManager.sol";
import "../utils/Constants.sol";

/**
 * @title ConfigureBridge
 * @author chasebrownn
 * @notice Script to configure TelcoinBridge DVN settings for LayerZero V2.
 *
 * @dev The delegate (TESTNET_ADMIN) must call this script to configure the bridge's
 *      DVN and Executor settings on the LayerZero endpoint.
 *
 * ## How to Run
 *
 * Dry run (Sepolia - configures for sending to Base Sepolia):
 * ```
 * forge script script/testnet/ConfigureBridge.s.sol --fork-url $ETH_SEPOLIA_RPC_URL
 * ```
 *
 * Live execution (Sepolia):
 * ```
 * forge script script/testnet/ConfigureBridge.s.sol --fork-url $ETH_SEPOLIA_RPC_URL --broadcast -vvvv
 * ```
 *
 * NOTE: You must also run an equivalent script on Base Sepolia to configure the
 * bridge for receiving from Sepolia.
 */
contract ConfigureBridge is DeployUtility {
    // ---------
    // Constants
    // ---------

    /// @dev LayerZero Labs DVN on Sepolia (from trace)
    address constant SEPOLIA_LZ_DVN = 0x8eebf8b423B73bFCa51a1Db4B7354AA0bFCA9193;

    /// @dev SendLib302 on Sepolia (from trace)
    address constant SEPOLIA_SEND_LIB = 0xcc1ae8Cf5D3904Cef3360A9532B477529b177cCE;

    /// @dev ReceiveLib302 on Sepolia
    address constant SEPOLIA_RECEIVE_LIB = 0xdAf00F5eE2158dD58E0d3857851c432E34A3A851;

    /// @dev Executor on Sepolia (from trace)
    address constant SEPOLIA_EXECUTOR = 0x718B92b5CB0a5552039B593faF724D182A881eDA;

    /// @dev Config type for Executor
    uint32 constant CONFIG_TYPE_EXECUTOR = 1;

    /// @dev Config type for ULN (DVN settings)
    uint32 constant CONFIG_TYPE_ULN = 2;

    /// @dev Chain alias for this script
    string internal constant CHAIN_ALIAS = "eth-sepolia";

    // ------
    // Script
    // ------

    function run() public {
        _setup();

        // Load deployed contract addresses
        address bridgeContract = _loadDeploymentAddress(CHAIN_ALIAS, "TelcoinBridge");
        require(bridgeContract != address(0), "TelcoinBridge not deployed");

        console.log("=== Configure Bridge Script ===");
        console.log("Chain:", CHAIN_ALIAS);
        console.log("Bridge:", bridgeContract);
        console.log("Destination EID:", BASE_SEPOLIA_LZ_CHAIN_ID_V2);
        console.log("");

        ILayerZeroEndpointV2 endpoint = ILayerZeroEndpointV2(ETH_SEPOLIA_LZ_ENDPOINT_V2);

        // Build ULN config for DVN
        // UlnConfig struct:
        //   uint64 confirmations
        //   uint8 requiredDVNCount
        //   uint8 optionalDVNCount
        //   uint8 optionalDVNThreshold
        //   address[] requiredDVNs
        //   address[] optionalDVNs
        address[] memory requiredDVNs = new address[](1);
        requiredDVNs[0] = SEPOLIA_LZ_DVN;
        address[] memory optionalDVNs = new address[](0);

        bytes memory ulnConfig = abi.encode(
            uint64(1),           // confirmations (1 block)
            uint8(1),            // requiredDVNCount
            uint8(0),            // optionalDVNCount
            uint8(0),            // optionalDVNThreshold
            requiredDVNs,        // requiredDVNs
            optionalDVNs         // optionalDVNs
        );

        // Build Executor config
        // ExecutorConfig struct:
        //   uint32 maxMessageSize
        //   address executor
        bytes memory executorConfig = abi.encode(
            uint32(10000),       // maxMessageSize (10KB should be plenty)
            SEPOLIA_EXECUTOR     // executor address
        );

        console.log("=== Current Config ===");

        // Check current config
        bytes memory currentSendUln = endpoint.getConfig(bridgeContract, SEPOLIA_SEND_LIB, BASE_SEPOLIA_LZ_CHAIN_ID_V2, CONFIG_TYPE_ULN);
        bytes memory currentSendExec = endpoint.getConfig(bridgeContract, SEPOLIA_SEND_LIB, BASE_SEPOLIA_LZ_CHAIN_ID_V2, CONFIG_TYPE_EXECUTOR);

        console.log("Current Send ULN config length:", currentSendUln.length);
        console.log("Current Send Executor config length:", currentSendExec.length);
        console.log("");

        console.log("=== Setting Send Config ===");

        vm.startBroadcast(_pk);

        // Set Send library config - ULN (DVN) and Executor
        SetConfigParam[] memory sendParams = new SetConfigParam[](2);

        sendParams[0] = SetConfigParam({
            eid: BASE_SEPOLIA_LZ_CHAIN_ID_V2,
            configType: CONFIG_TYPE_ULN,
            config: ulnConfig
        });

        sendParams[1] = SetConfigParam({
            eid: BASE_SEPOLIA_LZ_CHAIN_ID_V2,
            configType: CONFIG_TYPE_EXECUTOR,
            config: executorConfig
        });

        endpoint.setConfig(bridgeContract, SEPOLIA_SEND_LIB, sendParams);
        console.log("Send config set successfully");

        // Set Receive library config - ULN (DVN)
        SetConfigParam[] memory receiveParams = new SetConfigParam[](1);

        receiveParams[0] = SetConfigParam({
            eid: BASE_SEPOLIA_LZ_CHAIN_ID_V2,
            configType: CONFIG_TYPE_ULN,
            config: ulnConfig
        });

        endpoint.setConfig(bridgeContract, SEPOLIA_RECEIVE_LIB, receiveParams);
        console.log("Receive config set successfully");

        vm.stopBroadcast();

        console.log("");
        console.log("Bridge configuration complete for eth-sepolia -> base-sepolia!");
        console.log("");
        console.log("NEXT STEPS:");
        console.log("1. Run ConfigureBridgeBaseSepolia.s.sol on Base Sepolia");
        console.log("2. Then retry BridgeTokens.s.sol");
    }
}
