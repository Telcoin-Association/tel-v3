// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {console} from "forge-std/console.sol";
import {DeployUtility} from "../utils/DeployUtility.sol";
import {ILayerZeroEndpointV2} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import {SetConfigParam} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/IMessageLibManager.sol";
import {UlnConfig} from "@layerzerolabs/lz-evm-messagelib-v2/contracts/uln/UlnBase.sol";
import {ExecutorConfig} from "@layerzerolabs/lz-evm-messagelib-v2/contracts/SendLibBase.sol";
import "../utils/Constants.sol";

/**
 * @title ConfigureAllBridges
 * @author chasebrownn
 * @notice Script to configure DVN and Executor settings for TelcoinBridge across all supported chains.
 *
 * @dev This script configures LayerZero V2 OApp security settings (DVN and Executor) for each
 *      pathway between supported chains. For N chains, this configures N*(N-1) pathways.
 *
 *      For each pathway A → B:
 *      - On chain A: setSendLibrary + send ULN/Executor config (using A's sendLib with B's EID)
 *      - On chain B: setReceiveLibrary + receive ULN config (using B's receiveLib with A's EID)
 *
 *      Example with 3 chains (A, B, C):
 *      - Pathway A→B: send config on A, receive config on B
 *      - Pathway A→C: send config on A, receive config on C
 *      - Pathway B→A: send config on B, receive config on A
 *      - Pathway B→C: send config on B, receive config on C
 *      - Pathway C→A: send config on C, receive config on A
 *      - Pathway C→B: send config on C, receive config on B
 *
 * ## How to Run
 *
 * Dry run (simulation):
 * ```
 * forge script script/testnet/ConfigureAllBridges.s.sol --multi
 * ```
 *
 * Live execution:
 * ```
 * forge script script/testnet/ConfigureAllBridges.s.sol --multi --broadcast -vvvv
 * ```
 *
 * ## Configuration
 *
 * Each chain requires:
 * - LZ Endpoint address
 * - LZ Chain ID (EID)
 * - DVN address (LayerZero Labs DVN for testnets)
 * - SendLib302 address
 * - ReceiveLib302 address
 * - Executor address
 *
 * The script will query the bridge address from deployment JSON files.
 */
contract ConfigureAllBridges is DeployUtility {
    // ---------
    // Constants
    // ---------

    /// @dev Config type for Executor settings
    uint32 constant CONFIG_TYPE_EXECUTOR = 1;

    /// @dev Config type for ULN (DVN) settings
    uint32 constant CONFIG_TYPE_ULN = 2;

    /// @dev Block confirmations required for message verification
    uint64 constant CONFIRMATIONS = 1;

    /// @dev Maximum message size in bytes
    uint32 constant MAX_MESSAGE_SIZE = 10000;

    // ---------
    // Variables
    // ---------

    ChainConfig[] internal allChains;

    struct ChainConfig {
        string chainName;
        string rpcUrl;
        uint32 eid;              // LayerZero endpoint ID
        address endpoint;        // LZ EndpointV2 address
        address dvn;             // LayerZero Labs DVN address
        address sendLib;         // SendUln302 address
        address receiveLib;      // ReceiveUln302 address
        address executor;        // LZ Executor address
    }

    // -----
    // Setup
    // -----

    function setUp() public {
        _setup();

        // -----------------------------------------------------------------------------
        // CONFIGURE CHAINS HERE
        // -----------------------------------------------------------------------------
        //
        // To find addresses for a new chain:
        // 1. Go to https://docs.layerzero.network/v2/deployments/chains/<chain-name>
        // 2. Or check the chain's block explorer for the endpoint contract
        // 3. DVN addresses: https://docs.layerzero.network/v2/deployments/dvn-addresses
        //
        // For testnets, LayerZero Labs DVN is typically the only available DVN.
        // -----------------------------------------------------------------------------

        // Ethereum Sepolia
        allChains.push(ChainConfig({
            chainName: "eth-sepolia",
            rpcUrl: vm.envString("ETH_SEPOLIA_RPC_URL"),
            eid: ETH_SEPOLIA_LZ_CHAIN_ID_V2,
            endpoint: ETH_SEPOLIA_LZ_ENDPOINT_V2,
            dvn: ETH_SEPOLIA_LZ_DVN,
            sendLib: ETH_SEPOLIA_LZ_SEND_ULN_302,
            receiveLib: ETH_SEPOLIA_LZ_RECEIVE_ULN_302,
            executor: ETH_SEPOLIA_LZ_EXECUTOR
        }));

        // Base Sepolia
        allChains.push(ChainConfig({
            chainName: "base-sepolia",
            rpcUrl: vm.envString("BASE_SEPOLIA_RPC_URL"),
            eid: BASE_SEPOLIA_LZ_CHAIN_ID_V2,
            endpoint: BASE_SEPOLIA_LZ_ENDPOINT_V2,
            dvn: BASE_SEPOLIA_LZ_DVN,
            sendLib: BASE_SEPOLIA_LZ_SEND_ULN_302,
            receiveLib: BASE_SEPOLIA_LZ_RECEIVE_ULN_302,
            executor: BASE_SEPOLIA_LZ_EXECUTOR
        }));
    }

    // ------
    // Script
    // ------

    function run() public {
        uint256 chainCount = allChains.length;

        console.log("=== Configure All Bridges ===");
        console.log("Total chains:", chainCount);
        console.log("Total pathways to configure:", chainCount * (chainCount - 1));
        console.log("");

        // For each pathway src → dst
        for (uint256 i; i < chainCount; ++i) {
            for (uint256 j; j < chainCount; ++j) {
                if (i == j) continue;

                ChainConfig memory src = allChains[i];
                ChainConfig memory dst = allChains[j];

                console.log("----------------------------------------");
                console.log("Configuring pathway:", src.chainName, "->", dst.chainName);
                console.log("");

                // ====== (1) Configure SEND on source chain ======
                vm.createSelectFork(src.rpcUrl);
                address srcBridge = _loadDeploymentAddress(src.chainName, "TelcoinBridge");
                require(srcBridge != address(0), string.concat("TelcoinBridge not deployed on ", src.chainName));

                console.log("  [Source:", src.chainName, "]");
                console.log("  Bridge:", srcBridge);

                vm.startBroadcast(_pk);
                _configureSendOnSource(src, dst, srcBridge);
                vm.stopBroadcast();

                // ====== (2) Configure RECEIVE on destination chain ======
                vm.createSelectFork(dst.rpcUrl);
                address dstBridge = _loadDeploymentAddress(dst.chainName, "TelcoinBridge");
                require(dstBridge != address(0), string.concat("TelcoinBridge not deployed on ", dst.chainName));

                console.log("  [Destination:", dst.chainName, "]");
                console.log("  Bridge:", dstBridge);

                vm.startBroadcast(_pk);
                _configureReceiveOnDestination(src, dst, dstBridge);
                vm.stopBroadcast();

                console.log("");
            }
        }

        console.log("=== Configuration Complete ===");
    }

    // ----------------
    // Internal Helpers
    // ----------------

    /**
     * @dev Configure SEND settings on the source chain for pathway src → dst
     *      1. Sets the send library for this pathway
     *      2. Sets ULN (DVN) and Executor config using src's sendLib with dst's EID
     */
    function _configureSendOnSource(
        ChainConfig memory src,
        ChainConfig memory dst,
        address srcBridge
    ) internal {
        ILayerZeroEndpointV2 endpoint = ILayerZeroEndpointV2(src.endpoint);

        // 1. Set Send Library for this pathway (if not already set)
        (address currentSendLib,) = _getSendLibrary(endpoint, srcBridge, dst.eid);
        if (currentSendLib != src.sendLib) {
            endpoint.setSendLibrary(srcBridge, dst.eid, src.sendLib);
            console.log("  SendLibrary SET:", src.sendLib);
        } else {
            console.log("  SendLibrary already set, skipping");
        }

        // 2. Build configs using SOURCE chain's DVN and Executor
        bytes memory ulnConfig = _buildUlnConfig(src.dvn);
        bytes memory executorConfig = _buildExecutorConfig(src.executor);

        // Check current config on SOURCE using SOURCE's sendLib and dst.eid
        bytes memory currentUln = endpoint.getConfig(srcBridge, src.sendLib, dst.eid, CONFIG_TYPE_ULN);
        bytes memory currentExec = endpoint.getConfig(srcBridge, src.sendLib, dst.eid, CONFIG_TYPE_EXECUTOR);

        bool ulnMatch = keccak256(currentUln) == keccak256(ulnConfig);
        bool execMatch = keccak256(currentExec) == keccak256(executorConfig);

        if (!ulnMatch || !execMatch) {
            SetConfigParam[] memory params = new SetConfigParam[](2);

            params[0] = SetConfigParam({
                eid: dst.eid,
                configType: CONFIG_TYPE_ULN,
                config: ulnConfig
            });

            params[1] = SetConfigParam({
                eid: dst.eid,
                configType: CONFIG_TYPE_EXECUTOR,
                config: executorConfig
            });

            endpoint.setConfig(srcBridge, src.sendLib, params);
            console.log("  Send config SET (ULN + Executor)");
        } else {
            console.log("  Send config already set, skipping");
        }
    }

    /**
     * @dev Configure RECEIVE settings on the destination chain for pathway src → dst
     *      1. Sets the receive library for this pathway
     *      2. Sets ULN (DVN) config using dst's receiveLib with src's EID
     */
    function _configureReceiveOnDestination(
        ChainConfig memory src,
        ChainConfig memory dst,
        address dstBridge
    ) internal {
        ILayerZeroEndpointV2 endpoint = ILayerZeroEndpointV2(dst.endpoint);

        // 1. Set Receive Library for this pathway (if not already set)
        (address currentRecvLib,) = _getReceiveLibrary(endpoint, dstBridge, src.eid);
        if (currentRecvLib != dst.receiveLib) {
            endpoint.setReceiveLibrary(dstBridge, src.eid, dst.receiveLib, 0);
            console.log("  ReceiveLibrary SET:", dst.receiveLib);
        } else {
            console.log("  ReceiveLibrary already set, skipping");
        }

        // 2. Build ULN config using DESTINATION chain's DVN
        // (the DVN on the receiving chain verifies incoming messages)
        bytes memory ulnConfig = _buildUlnConfig(dst.dvn);

        // Check current config on DESTINATION using DEST's receiveLib and src.eid
        bytes memory currentUln = endpoint.getConfig(dstBridge, dst.receiveLib, src.eid, CONFIG_TYPE_ULN);

        bool ulnMatch = keccak256(currentUln) == keccak256(ulnConfig);

        if (!ulnMatch) {
            SetConfigParam[] memory params = new SetConfigParam[](1);

            params[0] = SetConfigParam({
                eid: src.eid,
                configType: CONFIG_TYPE_ULN,
                config: ulnConfig
            });

            endpoint.setConfig(dstBridge, dst.receiveLib, params);
            console.log("  Receive config SET (ULN)");
        } else {
            console.log("  Receive config already set, skipping");
        }
    }

    /**
     * @dev Get the current send library for an OApp
     */
    function _getSendLibrary(
        ILayerZeroEndpointV2 endpoint,
        address oapp,
        uint32 eid
    ) internal view returns (address lib, bool isDefault) {
        lib = endpoint.getSendLibrary(oapp, eid);
        isDefault = endpoint.isDefaultSendLibrary(oapp, eid);
    }

    /**
     * @dev Get the current receive library for an OApp
     */
    function _getReceiveLibrary(
        ILayerZeroEndpointV2 endpoint,
        address oapp,
        uint32 eid
    ) internal view returns (address lib, bool isDefault) {
        (lib, isDefault) = endpoint.getReceiveLibrary(oapp, eid);
    }

    /**
     * @dev Build ULN config bytes using the actual UlnConfig struct
     */
    function _buildUlnConfig(address dvn) internal pure returns (bytes memory) {
        address[] memory requiredDVNs = new address[](1);
        requiredDVNs[0] = dvn;
        address[] memory optionalDVNs = new address[](0);

        UlnConfig memory config = UlnConfig({
            confirmations: CONFIRMATIONS,
            requiredDVNCount: 1,
            optionalDVNCount: 0,
            optionalDVNThreshold: 0,
            requiredDVNs: requiredDVNs,
            optionalDVNs: optionalDVNs
        });

        return abi.encode(config);
    }

    /**
     * @dev Build Executor config bytes using the actual ExecutorConfig struct
     */
    function _buildExecutorConfig(address executor) internal pure returns (bytes memory) {
        ExecutorConfig memory config = ExecutorConfig({
            maxMessageSize: MAX_MESSAGE_SIZE,
            executor: executor
        });

        return abi.encode(config);
    }
}
