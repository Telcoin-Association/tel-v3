// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {console} from "forge-std/console.sol";
import {DeployUtility} from "../utils/DeployUtility.sol";
import {ILayerZeroEndpointV2} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import {SetConfigParam} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/IMessageLibManager.sol";
import {UlnConfig} from "@layerzerolabs/lz-evm-messagelib-v2/contracts/uln/UlnBase.sol";
import {ExecutorConfig} from "@layerzerolabs/lz-evm-messagelib-v2/contracts/SendLibBase.sol";

/**
 * @title BaseConfigureDVNs
 * @author chasebrownn
 * @notice Abstract base script to configure DVN and Executor settings for TelcoinBridge / NativeBridge
 *         across all supported chains.
 *
 * @dev Children inherit this and populate configuration in setUp():
 *      - `allChains` array with per-chain ChainConfig
 *      - `_confirmations` for block confirmation requirements
 *      - `_maxMessageSize` for executor max message size
 *
 *      For each pathway A -> B:
 *      - On chain A: setSendLibrary + send ULN/Executor config (using A's sendLib with B's EID)
 *      - On chain B: setReceiveLibrary + receive ULN config (using B's receiveLib with A's EID)
 */
abstract contract BaseConfigureDVNs is DeployUtility {
    // ---------
    // Constants
    // ---------

    /// @dev Config type for Executor settings
    uint32 constant CONFIG_TYPE_EXECUTOR = 1;

    /// @dev Config type for ULN (DVN) settings
    uint32 constant CONFIG_TYPE_ULN = 2;

    // ---------
    // Variables
    // ---------

    /// @dev Children MUST set these in setUp()
    uint64 internal _confirmations;
    uint32 internal _maxMessageSize;

    ChainConfig[] internal allChains;

    struct ChainConfig {
        string chainName;
        string rpcUrl;
        uint32 eid;                    // LayerZero endpoint ID
        address endpoint;              // LZ EndpointV2 address
        address[] requiredDVNs;        // DVNs that MUST all verify (e.g. LZ Labs, Google Cloud)
        address[] optionalDVNs;        // DVNs in the optional quorum pool
        uint8 optionalDVNThreshold;    // How many optional DVNs must verify (e.g. 2-of-3)
        address sendLib;               // SendUln302 address
        address receiveLib;            // ReceiveUln302 address
        address executor;              // LZ Executor address
        bool mainChain;                // true = NativeBridge, false = TelcoinBridge
    }

    // ------
    // Script
    // ------

    function run() public {
        uint256 chainCount = allChains.length;

        console.log("=== Configure All DVNs ===");
        console.log("Total chains:", chainCount);
        console.log("Total pathways to configure:", chainCount * (chainCount - 1));
        console.log("");

        // For each pathway src -> dst
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
                string memory srcBridgeKey = src.mainChain ? "NativeBridge" : "TelcoinBridge";
                address srcBridge = _loadDeploymentAddress(src.chainName, srcBridgeKey);
                require(srcBridge != address(0), string.concat("Bridge not deployed on ", src.chainName));

                console.log("  [Source:", src.chainName, "]");
                console.log("  Bridge:", srcBridge);

                vm.startBroadcast(_pk);
                _configureSendOnSource(src, dst, srcBridge);
                vm.stopBroadcast();

                // ====== (2) Configure RECEIVE on destination chain ======
                vm.createSelectFork(dst.rpcUrl);
                string memory dstBridgeKey = dst.mainChain ? "NativeBridge" : "TelcoinBridge";
                address dstBridge = _loadDeploymentAddress(dst.chainName, dstBridgeKey);
                require(dstBridge != address(0), string.concat("Bridge not deployed on ", dst.chainName));

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
     * @dev Configure SEND settings on the source chain for pathway src -> dst
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

        // 2. Build configs using SOURCE chain's DVNs and Executor
        bytes memory ulnConfig = _buildUlnConfig(src);
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
     * @dev Configure RECEIVE settings on the destination chain for pathway src -> dst
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

        // 2. Build ULN config using DESTINATION chain's DVNs
        bytes memory ulnConfig = _buildUlnConfig(dst);

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
     * @dev Build ULN config bytes from a ChainConfig's DVN arrays and threshold
     */
    function _buildUlnConfig(ChainConfig memory chain) internal view returns (bytes memory) {
        UlnConfig memory config = UlnConfig({
            confirmations: _confirmations,
            requiredDVNCount: uint8(chain.requiredDVNs.length),
            optionalDVNCount: uint8(chain.optionalDVNs.length),
            optionalDVNThreshold: chain.optionalDVNThreshold,
            requiredDVNs: chain.requiredDVNs,
            optionalDVNs: chain.optionalDVNs
        });

        return abi.encode(config);
    }

    /**
     * @dev Build Executor config bytes using the actual ExecutorConfig struct
     */
    function _buildExecutorConfig(address executor) internal view returns (bytes memory) {
        ExecutorConfig memory config = ExecutorConfig({
            maxMessageSize: _maxMessageSize,
            executor: executor
        });

        return abi.encode(config);
    }
}
