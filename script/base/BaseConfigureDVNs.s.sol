// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {console} from "forge-std/console.sol";
import {Safe} from "@safe-utils/Safe.sol";
import {DeployBase} from "forge-deploy-utils/DeployBase.sol";
import {ILayerZeroEndpointV2} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import {SetConfigParam} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/IMessageLibManager.sol";
import {UlnConfig} from "@layerzerolabs/lz-evm-messagelib-v2/contracts/uln/UlnBase.sol";
import {ExecutorConfig} from "@layerzerolabs/lz-evm-messagelib-v2/contracts/SendLibBase.sol";

/// @title BaseConfigureDVNs
/// @notice Abstract base script to configure DVN and Executor settings via Gnosis Safe.
///         All endpoint configuration calls are proposed as Safe transactions (simulation or broadcast).
/// @dev    Children populate configuration in setUp() and call _initializeSafe()
///         or _initializeSafeMultiSig().
abstract contract BaseConfigureDVNs is DeployBase {
    using Safe for *;

    // ---------
    // Constants
    // ---------

    uint32 constant CONFIG_TYPE_EXECUTOR = 1;
    uint32 constant CONFIG_TYPE_ULN = 2;

    // ---------
    // Variables
    // ---------

    uint64 internal _confirmations;
    uint32 internal _maxMessageSize;

    ChainConfig[] internal allChains;

    struct ChainConfig {
        string chainName;
        string rpcUrl;
        uint32 eid;
        address endpoint;
        address[] requiredDVNs;
        address[] optionalDVNs;
        uint8 optionalDVNThreshold;
        address sendLib;
        address receiveLib;
        address executor;
        bool mainChain;
    }

    // ------
    // Script
    // ------

    /// @dev Iterates every src→dst pathway, fork-switches per side, and proposes DVN/Executor config.
    function run() public {
        uint256 chainCount = allChains.length;

        console.log("=== Configure All DVNs (Safe) ===");
        console.log("Total chains:", chainCount);
        console.log("Total pathways to configure:", chainCount * (chainCount - 1));
        console.log("");

        for (uint256 i; i < chainCount; ++i) {
            for (uint256 j; j < chainCount; ++j) {
                if (i == j) continue;

                ChainConfig memory src = allChains[i];
                ChainConfig memory dst = allChains[j];

                console.log("----------------------------------------");
                console.log("Configuring pathway:", src.chainName, "->", dst.chainName);
                console.log("");

                // (1) Configure SEND on source chain
                vm.createSelectFork(src.rpcUrl);
                currentNonce = safe.getNonce();

                string memory srcBridgeKey = src.mainChain ? "NativeBridge" : "TelcoinBridge";
                address srcBridge = _loadDeploymentAddress(src.chainName, srcBridgeKey);
                require(srcBridge != address(0), string.concat("Bridge not deployed on ", src.chainName));

                console.log("  [Source:", src.chainName, "]");
                console.log("  Bridge:", srcBridge);

                _configureSendOnSource(src, dst, srcBridge);

                // (2) Configure RECEIVE on destination chain
                vm.createSelectFork(dst.rpcUrl);
                currentNonce = safe.getNonce();

                string memory dstBridgeKey = dst.mainChain ? "NativeBridge" : "TelcoinBridge";
                address dstBridge = _loadDeploymentAddress(dst.chainName, dstBridgeKey);
                require(dstBridge != address(0), string.concat("Bridge not deployed on ", dst.chainName));

                console.log("  [Destination:", dst.chainName, "]");
                console.log("  Bridge:", dstBridge);

                _configureReceiveOnDestination(src, dst, dstBridge);

                console.log("");
            }
        }

        console.log("=== Configuration Complete ===");
    }

    // ----------------
    // Internal Helpers
    // ----------------

    /// @dev Sets send library + ULN/Executor config on the source chain for a given pathway.
    ///      Batches setSendLibrary + setConfig into a single Safe tx when both need updating.
    function _configureSendOnSource(
        ChainConfig memory src,
        ChainConfig memory dst,
        address srcBridge
    ) internal {
        ILayerZeroEndpointV2 endpoint = ILayerZeroEndpointV2(src.endpoint);

        bool needsLibUpdate;
        bool needsConfigUpdate;

        {
            (address currentSendLib,) = _getSendLibrary(endpoint, srcBridge, dst.eid);
            needsLibUpdate = currentSendLib != src.sendLib;
        }

        bytes memory ulnConfig = _buildUlnConfig(src);
        bytes memory executorConfig = _buildExecutorConfig(src.executor);

        {
            bytes memory currentUln = endpoint.getConfig(srcBridge, src.sendLib, dst.eid, CONFIG_TYPE_ULN);
            bytes memory currentExec = endpoint.getConfig(srcBridge, src.sendLib, dst.eid, CONFIG_TYPE_EXECUTOR);
            needsConfigUpdate = keccak256(currentUln) != keccak256(ulnConfig)
                || keccak256(currentExec) != keccak256(executorConfig);
        }

        if (!needsLibUpdate && !needsConfigUpdate) {
            console.log("  Send config already set, skipping");
            return;
        }

        // Batch into one Safe tx
        uint256 txCount = (needsLibUpdate ? 1 : 0) + (needsConfigUpdate ? 1 : 0);
        address[] memory targets = new address[](txCount);
        bytes[] memory datas = new bytes[](txCount);
        uint256 idx;

        if (needsLibUpdate) {
            targets[idx] = src.endpoint;
            datas[idx] = _encodeSendLibrary(endpoint, srcBridge, dst.eid, src.sendLib);
            idx++;
            console.log("  SendLibrary will be SET:", src.sendLib);
        }

        if (needsConfigUpdate) {
            targets[idx] = src.endpoint;
            datas[idx] = _encodeSendConfig(endpoint, srcBridge, src.sendLib, dst.eid, ulnConfig, executorConfig);
            idx++;
            console.log("  Send config will be SET (ULN + Executor)");
        }

        _proposeTransactions(targets, datas, "Configure send pathway");
    }

    /// @dev Encodes setSendLibrary calldata. Extracted to avoid stack-too-deep.
    function _encodeSendLibrary(
        ILayerZeroEndpointV2 endpoint,
        address oapp,
        uint32 eid,
        address sendLib
    ) internal pure returns (bytes memory) {
        return abi.encodeCall(endpoint.setSendLibrary, (oapp, eid, sendLib));
    }

    /// @dev Encodes setConfig calldata for ULN + Executor params. Extracted to avoid stack-too-deep.
    function _encodeSendConfig(
        ILayerZeroEndpointV2 endpoint,
        address oapp,
        address sendLib,
        uint32 eid,
        bytes memory ulnConfig,
        bytes memory executorConfig
    ) internal pure returns (bytes memory) {
        SetConfigParam[] memory params = new SetConfigParam[](2);
        params[0] = SetConfigParam({eid: eid, configType: CONFIG_TYPE_ULN, config: ulnConfig});
        params[1] = SetConfigParam({eid: eid, configType: CONFIG_TYPE_EXECUTOR, config: executorConfig});
        return abi.encodeCall(endpoint.setConfig, (oapp, sendLib, params));
    }

    /// @dev Sets receive library + ULN config on the destination chain for a given pathway.
    ///      Batches setReceiveLibrary + setConfig into a single Safe tx when both need updating.
    function _configureReceiveOnDestination(
        ChainConfig memory src,
        ChainConfig memory dst,
        address dstBridge
    ) internal {
        ILayerZeroEndpointV2 endpoint = ILayerZeroEndpointV2(dst.endpoint);

        // 1. Set Receive Library
        (address currentRecvLib,) = _getReceiveLibrary(endpoint, dstBridge, src.eid);

        bool needsLibUpdate = currentRecvLib != dst.receiveLib;
        bool needsConfigUpdate;

        // 2. Build ULN config
        bytes memory ulnConfig = _buildUlnConfig(dst);
        bytes memory currentUln = endpoint.getConfig(dstBridge, dst.receiveLib, src.eid, CONFIG_TYPE_ULN);

        needsConfigUpdate = keccak256(currentUln) != keccak256(ulnConfig);

        if (!needsLibUpdate && !needsConfigUpdate) {
            console.log("  Receive config already set, skipping");
            return;
        }

        // Batch: setReceiveLibrary + setConfig into one Safe tx
        uint256 txCount = (needsLibUpdate ? 1 : 0) + (needsConfigUpdate ? 1 : 0);
        address[] memory targets = new address[](txCount);
        bytes[] memory datas = new bytes[](txCount);
        uint256 idx;

        if (needsLibUpdate) {
            targets[idx] = dst.endpoint;
            datas[idx] = abi.encodeCall(endpoint.setReceiveLibrary, (dstBridge, src.eid, dst.receiveLib, 0));
            idx++;
            console.log("  ReceiveLibrary will be SET:", dst.receiveLib);
        }

        if (needsConfigUpdate) {
            SetConfigParam[] memory params = new SetConfigParam[](1);
            params[0] = SetConfigParam({eid: src.eid, configType: CONFIG_TYPE_ULN, config: ulnConfig});

            targets[idx] = dst.endpoint;
            datas[idx] = abi.encodeCall(endpoint.setConfig, (dstBridge, dst.receiveLib, params));
            idx++;
            console.log("  Receive config will be SET (ULN)");
        }

        _proposeTransactions(targets, datas, "Configure receive pathway");
    }

    /// @dev Reads the current send library for an OApp on a given pathway.
    function _getSendLibrary(
        ILayerZeroEndpointV2 endpoint,
        address oapp,
        uint32 eid
    ) internal view returns (address lib, bool isDefault) {
        lib = endpoint.getSendLibrary(oapp, eid);
        isDefault = endpoint.isDefaultSendLibrary(oapp, eid);
    }

    /// @dev Reads the current receive library for an OApp on a given pathway.
    function _getReceiveLibrary(
        ILayerZeroEndpointV2 endpoint,
        address oapp,
        uint32 eid
    ) internal view returns (address lib, bool isDefault) {
        (lib, isDefault) = endpoint.getReceiveLibrary(oapp, eid);
    }

    /// @dev Encodes a UlnConfig struct from a chain's DVN arrays and threshold.
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

    /// @dev Encodes an ExecutorConfig struct with _maxMessageSize and the given executor.
    function _buildExecutorConfig(address executor) internal view returns (bytes memory) {
        ExecutorConfig memory config = ExecutorConfig({
            maxMessageSize: _maxMessageSize,
            executor: executor
        });

        return abi.encode(config);
    }
}
