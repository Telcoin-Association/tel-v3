// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {console} from "forge-std/console.sol";
import {VmSafe} from "forge-std/Vm.sol";
import {Safe} from "@safe-utils/Safe.sol";
import {IOAppCore} from "@layerzerolabs/oapp-evm/contracts/oapp/interfaces/IOAppCore.sol";
import {IMintableBurnable} from "@layerzerolabs/oft-evm/contracts/interfaces/IMintableBurnable.sol";
import {DeployBase} from "forge-deploy-utils/DeployBase.sol";
import {SaltMath} from "forge-deploy-utils/libraries/SaltMath.sol";
import {ICreateX} from "forge-deploy-utils/interfaces/ICreateX.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {TelcoinV3} from "../../src/TelcoinV3.sol";
import {TelcoinBridge} from "../../src/TelcoinBridge.sol";
import {NativeBridge} from "../../src/NativeBridge.sol";
import {MintBurnWrapper} from "../../src/MintBurnWrapper.sol";
import {Roles} from "../../src/helpers/Roles.sol";

/// @title BaseDeployBridges
/// @notice Deploys bridge infrastructure and configures peers across all chains.
///         Each chain gets TWO MultiSend proposals at consecutive nonces: the initcode-heavy
///         deploy calls alone exceed hardware-wallet signing memory when combined with the
///         config calls, so deploys and configuration are split.
/// @dev    Step 1 in the deployment pipeline. Requires TelcoinV3 already deployed (loaded from JSON).
///
///         Per chain:
///         - Proposal 1 (deploys): NativeBridge on mainChain; MintBurnWrapper + TelcoinBridge on satellites
///         - Proposal 2 (config): pause-role grants, MINTER/BURNER grants, bridge authorization, peers
abstract contract BaseDeployBridges is DeployBase, Roles {
    using Safe for *;

    // ---------
    // Variables
    // ---------

    address internal _admin;
    address internal _pauser;
    address internal _unpauser;

    bytes32 internal _mintBurnWrapperSalt;
    bytes32 internal _bridgeSalt;
    bytes32 internal _nativeBridgeSalt;

    struct BridgeChainConfig {
        string chainName;
        string rpcUrl;
        address lzEndpoint;
        uint32 lzChainId;
        uint256 evmChainId;
        bool mainChain;
    }

    struct RuntimeData {
        uint256 forkId;
        address bridgeAddress;
        bool deployProposed;
        address[] batchTargets;
        bytes[] batchDatas;
    }

    BridgeChainConfig[] internal allChains;
    mapping(string rpc => RuntimeData) internal getRuntimeData;

    // Batch accumulation
    address[] internal _batchTargets;
    bytes[] internal _batchDatas;

    // ------
    // Script
    // ------

    /// @dev Iterates all chains: proposes the deploy batch and stashes the config batch per
    ///      chain in the first pass, then adds peers and proposes the config batch in the second.
    function run() public {
        uint256 len = allChains.length;

        // First pass: propose each chain's deploy-only batch, then stash the accumulated
        // config txns — the shared batch arrays must not leak across chains.
        for (uint256 i; i < len; ++i) {
            uint256 forkId = vm.createSelectFork(allChains[i].rpcUrl);
            // SAFE_NONCE_OFFSET queues this proposal behind pending-but-unexecuted
            // Safe txns (on-chain nonce doesn't advance until execution).
            currentNonce = safe.getNonce() + vm.envOr("SAFE_NONCE_OFFSET", uint256(0));

            console.log("=== Deploy Bridges on %s ===", allChains[i].chainName);

            RuntimeData storage runtimeData = getRuntimeData[allChains[i].rpcUrl];
            runtimeData.forkId = forkId;
            runtimeData.bridgeAddress = _collectDeploys(allChains[i], runtimeData);
            runtimeData.batchTargets = _batchTargets;
            runtimeData.batchDatas = _batchDatas;
            delete _batchTargets;
            delete _batchDatas;
        }

        // Second pass: restore the chain's config batch, add peer config, and propose it
        // queued directly behind that chain's deploy proposal (if one was made).
        for (uint256 i; i < len; ++i) {
            RuntimeData storage runtimeData = getRuntimeData[allChains[i].rpcUrl];
            vm.selectFork(runtimeData.forkId);
            currentNonce = safe.getNonce() + vm.envOr("SAFE_NONCE_OFFSET", uint256(0))
                + (runtimeData.deployProposed ? 1 : 0);

            _batchTargets = runtimeData.batchTargets;
            _batchDatas = runtimeData.batchDatas;

            _collectPeers(i, len);

            _flushBatch(string.concat("Configure bridges on ", allChains[i].chainName));
        }
    }

    // ------
    // Deploy
    // ------

    /// @dev Loads TelcoinV3 from JSON. Batches the CREATE3 deploys (NativeBridge on mainChain;
    ///      MintBurnWrapper + TelcoinBridge on satellites) and flushes them as their own
    ///      proposal — the initcode payloads must not share a MultiSend with the config calls
    ///      or the combined payload exceeds hardware-wallet signing memory. The config txns
    ///      (role grants, bridge authorization) are left accumulated in the batch arrays;
    ///      the caller stashes them and flushes after peers are added.
    function _collectDeploys(BridgeChainConfig memory chain, RuntimeData storage runtimeData)
        internal
        returns (address bridge)
    {
        require(
            block.chainid == chain.evmChainId,
            string.concat(
                "Chain ID mismatch: expected ",
                vm.toString(chain.evmChainId),
                " but connected to ",
                vm.toString(block.chainid)
            )
        );

        address token = _loadDeploymentAddress(chain.chainName, "TelcoinV3");
        require(token != address(0), string.concat("TelcoinV3 not deployed on ", chain.chainName));

        if (chain.mainChain) {
            bridge = _addCreate3ToBatch(
                _nativeBridgeSalt,
                bytes.concat(type(NativeBridge).creationCode, abi.encode(chain.lzEndpoint, _admin)),
                "Deploy NativeBridge"
            );

            runtimeData.deployProposed = _flushBatch(string.concat("Deploy bridges on ", chain.chainName));

            _collectPauseRoleGrants(bridge);

            if (vm.isContext(VmSafe.ForgeContext.ScriptBroadcast)) {
                _saveDeploymentAddress(chain.chainName, "NativeBridge", bridge);
            }
        } else {
            address wrapper = _addCreate3ToBatch(
                _mintBurnWrapperSalt,
                bytes.concat(type(MintBurnWrapper).creationCode, abi.encode(token, _admin)),
                "Deploy MintBurnWrapper"
            );

            bridge = _addCreate3ToBatch(
                _bridgeSalt,
                bytes.concat(
                    type(TelcoinBridge).creationCode,
                    abi.encode(token, IMintableBurnable(wrapper), chain.lzEndpoint, _admin)
                ),
                "Deploy TelcoinBridge"
            );

            runtimeData.deployProposed = _flushBatch(string.concat("Deploy bridges on ", chain.chainName));

            _collectPauseRoleGrants(bridge);

            // Grant MINTER/BURNER roles to wrapper on TelcoinV3 (idempotent on-chain)
            TelcoinV3 telcoinContract = TelcoinV3(token);
            if (!telcoinContract.hasRole(MINTER_ROLE, wrapper)) {
                console.log("  [batch] Grant MINTER_ROLE to MintBurnWrapper");
                _batchTargets.push(token);
                _batchDatas.push(abi.encodeCall(IAccessControl.grantRole, (MINTER_ROLE, wrapper)));
            }

            if (!telcoinContract.hasRole(BURNER_ROLE, wrapper)) {
                console.log("  [batch] Grant BURNER_ROLE to MintBurnWrapper");
                _batchTargets.push(token);
                _batchDatas.push(abi.encodeCall(IAccessControl.grantRole, (BURNER_ROLE, wrapper)));
            }

            // Authorize bridge on wrapper (reverts if already set).
            // A freshly batched wrapper has no code yet — skip the staticcall and always authorize.
            MintBurnWrapper wrapperContract = MintBurnWrapper(wrapper);
            if (wrapper.code.length == 0 || wrapperContract.bridge() != bridge) {
                console.log("  [batch] Authorize bridge on MintBurnWrapper");
                _batchTargets.push(wrapper);
                _batchDatas.push(abi.encodeCall(MintBurnWrapper.authorizeBridge, (bridge)));
            }

            if (vm.isContext(VmSafe.ForgeContext.ScriptBroadcast)) {
                _saveDeploymentAddress(chain.chainName, "MintBurnWrapper", wrapper);
                _saveDeploymentAddress(chain.chainName, "TelcoinBridge", bridge);
            }
        }
    }

    /// @dev Batches PAUSER_ROLE/UNPAUSER_ROLE grants on a freshly deployed bridge.
    ///      Roles are granted post-deploy by the admin Safe rather than in the constructor.
    function _collectPauseRoleGrants(address bridge) internal {
        require(_pauser != address(0), "Pauser not configured");
        require(_unpauser != address(0), "Unpauser not configured");

        console.log("  [batch] Grant PAUSER_ROLE / UNPAUSER_ROLE on bridge");
        _batchTargets.push(bridge);
        _batchDatas.push(abi.encodeCall(IAccessControl.grantRole, (PAUSER_ROLE, _pauser)));
        _batchTargets.push(bridge);
        _batchDatas.push(abi.encodeCall(IAccessControl.grantRole, (UNPAUSER_ROLE, _unpauser)));
    }

    // -----
    // Peers
    // -----

    /// @dev Adds all setPeer calls for a single chain to the batch.
    function _collectPeers(uint256 chainIdx, uint256 chainCount) internal {
        address bridgeAddr = getRuntimeData[allChains[chainIdx].rpcUrl].bridgeAddress;

        for (uint256 j; j < chainCount; ++j) {
            if (chainIdx == j) continue;
            bytes32 peerAddress = bytes32(uint256(uint160(getRuntimeData[allChains[j].rpcUrl].bridgeAddress)));
            uint32 peerEid = allChains[j].lzChainId;

            // Only check current peers when the bridge already has code (simulation against a
            // live bridge); a freshly batched bridge has none and the staticcall would revert.
            if (bridgeAddr.code.length == 0 || !_isSimulation || IOAppCore(bridgeAddr).peers(peerEid) != peerAddress) {
                console.log("  [batch] setPeer(%d, %s)", peerEid, allChains[j].chainName);
                _batchTargets.push(bridgeAddr);
                _batchDatas.push(abi.encodeCall(IOAppCore.setPeer, (peerEid, peerAddress)));
            }
        }
    }

    // -------
    // Helpers
    // -------

    /// @dev Computes CREATE3 address and adds the deploy tx to the batch. Idempotent.
    function _addCreate3ToBatch(bytes32 rawSalt, bytes memory initCode, string memory label)
        internal
        returns (address)
    {
        bytes32 guardedSalt = SaltMath.guardSalt(deployerSafeAddress, rawSalt);
        require(SaltMath.extractGuard(guardedSalt) == deployerSafeAddress, "guarded salt incorrect");
        address expectedAddress = _computeCreate3Address(guardedSalt);

        if (expectedAddress.code.length > 0) {
            console.log("  [batch] %s already deployed at %s, skipping", label, expectedAddress);
            return expectedAddress;
        }

        console.log("  [batch] %s (expected: %s)", label, expectedAddress);
        _batchTargets.push(CREATEX);
        _batchDatas.push(abi.encodeCall(ICreateX.deployCreate3, (guardedSalt, initCode)));
        return expectedAddress;
    }

    /// @dev Flushes accumulated batch txns as one MultiSend proposal. Returns true if a
    ///      proposal was made (callers use this to queue follow-up proposals at nonce + 1).
    function _flushBatch(string memory description) internal returns (bool) {
        uint256 len = _batchTargets.length;
        if (len == 0) {
            console.log("  No changes needed, skipping");
            return false;
        }

        address[] memory targets = new address[](len);
        bytes[] memory datas = new bytes[](len);
        for (uint256 i; i < len; ++i) {
            targets[i] = _batchTargets[i];
            datas[i] = _batchDatas[i];
        }

        console.log("  Proposing %d txns as single MultiSend", len);
        _proposeTransactions(targets, datas, description);

        delete _batchTargets;
        delete _batchDatas;
        return true;
    }
}
