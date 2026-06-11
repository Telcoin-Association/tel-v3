// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {console} from "forge-std/console.sol";
import {Safe} from "@safe-utils/Safe.sol";
import {DeployBase} from "forge-deploy-utils/DeployBase.sol";
import {ILayerZeroEndpointV2} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import {SetConfigParam} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/IMessageLibManager.sol";
import {UlnConfig} from "@layerzerolabs/lz-evm-messagelib-v2/contracts/uln/UlnBase.sol";
import {ExecutorConfig} from "@layerzerolabs/lz-evm-messagelib-v2/contracts/SendLibBase.sol";
import {IOAppOptionsType3, EnforcedOptionParam} from
    "@layerzerolabs/oapp-evm/contracts/oapp/interfaces/IOAppOptionsType3.sol";

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
    uint16 constant SEND = 1;

    // ---------
    // Variables
    // ---------

    uint32 internal _maxMessageSize;

    ChainConfig[] internal allChains;

    /// @notice Per-chain configuration for LayerZero DVN, executor, library, and enforced option settings.
    /// @dev Populated by child scripts in setUp(). One entry per chain in the OFT mesh.
    struct ChainConfig {
        /// @dev Name of chain used to locate the <chainName>.json for address tracking.
        string chainName;
        /// @dev RPC URL used to fork this chain.
        string rpcUrl;
        /// @dev Expected EVM chain ID for sanity-checking the fork.
        uint256 evmChainId;
        /// @dev LayerZero V2 endpoint ID for this chain.
        uint32 eid;
        /// @dev Local LayerZero V2 endpoint contract for this chain.
        address endpoint;
        /// @dev DVNs that must all verify every message on this chain.
        address[] requiredDVNs;
        /// @dev Additional DVNs from which a threshold subset must verify.
        address[] optionalDVNs;
        /// @dev Number of optional DVNs required to reach quorum.
        uint8 optionalDVNThreshold;
        /// @dev SendUln302 library address for outbound messages.
        address sendLib;
        /// @dev ReceiveUln302 library address for inbound messages.
        address receiveLib;
        /// @dev LayerZero executor responsible for delivering messages on this chain.
        address executor;
        /// @dev True if this is the native-TEL chain (NativeBridge); false for satellite chains (TelcoinBridge).
        bool mainChain;
        /// @dev Block confirmations required before DVNs attest a message from this chain.
        uint64 confirmations;
        /// @dev Minimum lzReceive gas enforced when this chain is the destination.
        uint128 minDstGas;
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
                require(
                    block.chainid == src.evmChainId,
                    string.concat("Chain ID mismatch on source: expected ", vm.toString(src.evmChainId), " but got ", vm.toString(block.chainid))
                );
                currentNonce = safe.getNonce();

                string memory srcBridgeKey = src.mainChain ? "NativeBridge" : "TelcoinBridge";
                address srcBridge = _loadDeploymentAddress(src.chainName, srcBridgeKey);
                require(srcBridge != address(0), string.concat("Bridge not deployed on ", src.chainName));

                console.log("  [Source:", src.chainName, "]");
                console.log("  Bridge:", srcBridge);

                _configureSendOnSource(src, dst, srcBridge);

                // (2) Configure RECEIVE on destination chain
                vm.createSelectFork(dst.rpcUrl);
                require(
                    block.chainid == dst.evmChainId,
                    string.concat("Chain ID mismatch on destination: expected ", vm.toString(dst.evmChainId), " but got ", vm.toString(block.chainid))
                );
                currentNonce = safe.getNonce();

                string memory dstBridgeKey = dst.mainChain ? "NativeBridge" : "TelcoinBridge";
                address dstBridge = _loadDeploymentAddress(dst.chainName, dstBridgeKey);
                require(dstBridge != address(0), string.concat("Bridge not deployed on ", dst.chainName));

                console.log("  [Destination:", dst.chainName, "]");
                console.log("  Bridge:", dstBridge);

                _configureReceiveOnDestination(src, dst, dstBridge);

                console.log("");
            }

            // (3) Configure enforced lzReceive gas options on this source bridge
            {
                ChainConfig memory srcChain = allChains[i];
                vm.createSelectFork(srcChain.rpcUrl);
                require(
                    block.chainid == srcChain.evmChainId,
                    string.concat("Chain ID mismatch: expected ", vm.toString(srcChain.evmChainId), " but got ", vm.toString(block.chainid))
                );
                currentNonce = safe.getNonce();

                string memory bridgeKey = srcChain.mainChain ? "NativeBridge" : "TelcoinBridge";
                address bridge = _loadDeploymentAddress(srcChain.chainName, bridgeKey);

                _configureEnforcedOptions(i, chainCount, bridge);
            }
        }

        console.log("=== Configuration Complete ===");
    }

    // -----------------
    // Enforced Options
    // -----------------

    /// @dev Builds and proposes enforced lzReceive gas options for all destination pathways from a single source bridge.
    ///      Skips pathways where the enforced option is already set. Batches all updates into one Safe tx.
    function _configureEnforcedOptions(uint256 srcIdx, uint256 chainCount, address bridge) internal {
        uint256 peerCount = chainCount - 1;
        EnforcedOptionParam[] memory params = new EnforcedOptionParam[](peerCount);
        uint256 updateCount;

        for (uint256 j; j < chainCount; ++j) {
            if (srcIdx == j) continue;

            ChainConfig memory dst = allChains[j];
            bytes memory desired = _buildLzReceiveOption(dst.minDstGas);
            bytes memory current = IOAppOptionsType3(bridge).combineOptions(dst.eid, SEND, bytes(""));

            if (keccak256(current) != keccak256(desired)) {
                params[updateCount] = EnforcedOptionParam({
                    eid: dst.eid,
                    msgType: SEND,
                    options: desired
                });
                updateCount++;
            }
        }

        if (updateCount == 0) {
            console.log("  Enforced options already set on", allChains[srcIdx].chainName, ", skipping");
            return;
        }

        // Trim array to actual update count
        EnforcedOptionParam[] memory trimmed = new EnforcedOptionParam[](updateCount);
        for (uint256 k; k < updateCount; ++k) {
            trimmed[k] = params[k];
        }

        console.log("  Setting enforced lzReceive gas options on", allChains[srcIdx].chainName);
        _proposeTransaction(
            bridge,
            abi.encodeCall(IOAppOptionsType3.setEnforcedOptions, (trimmed)),
            "Set enforced lzReceive gas options"
        );
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
            (address currentSendLib, bool isDefault) = _getSendLibrary(endpoint, srcBridge, dst.eid);
            needsLibUpdate = isDefault || currentSendLib != src.sendLib;
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

        bool needsLibUpdate;
        bool needsConfigUpdate;

        {
            (address currentRecvLib, bool isDefault) = _getReceiveLibrary(endpoint, dstBridge, src.eid);
            needsLibUpdate = isDefault || currentRecvLib != dst.receiveLib;
        }

        bytes memory ulnConfig = _buildUlnConfig(dst);

        {
            bytes memory currentUln = endpoint.getConfig(dstBridge, dst.receiveLib, src.eid, CONFIG_TYPE_ULN);
            needsConfigUpdate = keccak256(currentUln) != keccak256(ulnConfig);
        }

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
            datas[idx] = _encodeReceiveLibrary(endpoint, dstBridge, src.eid, dst.receiveLib);
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

    /// @dev Encodes setReceiveLibrary calldata. Extracted to avoid stack-too-deep.
    function _encodeReceiveLibrary(
        ILayerZeroEndpointV2 endpoint,
        address oapp,
        uint32 eid,
        address receiveLib
    ) internal pure returns (bytes memory) {
        return abi.encodeCall(endpoint.setReceiveLibrary, (oapp, eid, receiveLib, 0));
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
    function _buildUlnConfig(ChainConfig memory chain) internal pure returns (bytes memory) {
        UlnConfig memory config = UlnConfig({
            confirmations: chain.confirmations,
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

    /// @dev Encodes a Type 3 enforced option for lzReceive with the given gas limit.
    ///      Equivalent to OptionsBuilder.newOptions().addExecutorLzReceiveOption(gas, 0).
    function _buildLzReceiveOption(uint128 gas) internal pure returns (bytes memory) {
        return abi.encodePacked(
            uint16(3),  // TYPE_3
            uint8(1),   // WORKER_ID (executor)
            uint16(17), // option length: 16 bytes (uint128 gas) + 1 byte (option type)
            uint8(1),   // OPTION_TYPE_LZRECEIVE
            gas
        );
    }
}
