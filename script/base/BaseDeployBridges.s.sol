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
///         All deploys, role grants, and peer config for a single chain are batched into one MultiSend.
/// @dev    Step 1 in the deployment pipeline. Requires TelcoinV3 already deployed (loaded from JSON).
///
///         Per chain (single MultiSend):
///         - mainChain: Deploy NativeBridge + configure peers
///         - satellite: Deploy MintBurnWrapper + TelcoinBridge, grant MINTER/BURNER, authorize bridge, configure peers
abstract contract BaseDeployBridges is DeployBase, Roles {
    using Safe for *;

    // ---------
    // Variables
    // ---------

    address internal _admin;

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
    }

    BridgeChainConfig[] internal allChains;
    mapping(string rpc => RuntimeData) internal getRuntimeData;

    // Batch accumulation
    address[] internal _batchTargets;
    bytes[] internal _batchDatas;

    // ------
    // Script
    // ------

    /// @dev Iterates all chains: deploys bridges + configures peers, all batched per chain.
    function run() public {
        uint256 len = allChains.length;

        // First pass: deploy bridges and collect addresses
        for (uint256 i; i < len; ++i) {
            uint256 forkId = vm.createSelectFork(allChains[i].rpcUrl);
            currentNonce = safe.getNonce();

            console.log("=== Deploy Bridges on %s ===", allChains[i].chainName);

            address bridgeAddress = _collectDeploys(allChains[i]);

            getRuntimeData[allChains[i].rpcUrl] = RuntimeData({
                forkId: forkId,
                bridgeAddress: bridgeAddress
            });
        }

        // Second pass: add peer config to batch and flush everything per chain
        for (uint256 i; i < len; ++i) {
            string memory rpcUrl = allChains[i].rpcUrl;
            vm.selectFork(getRuntimeData[rpcUrl].forkId);
            currentNonce = safe.getNonce();

            _collectPeers(i, len);

            _flushBatch(string.concat("Deploy + configure bridges on ", allChains[i].chainName));
        }
    }

    // ------
    // Deploy
    // ------

    /// @dev Loads TelcoinV3 from JSON. For mainChain batches NativeBridge deploy; for satellites batches
    ///      MintBurnWrapper + TelcoinBridge deploys, MINTER/BURNER grants, and bridge authorization.
    ///      Does NOT flush — caller is responsible for flushing after peers are added.
    function _collectDeploys(BridgeChainConfig memory chain) internal returns (address bridge) {
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

            // Authorize bridge on wrapper (reverts if already set)
            MintBurnWrapper wrapperContract = MintBurnWrapper(wrapper);
            if (wrapperContract.bridge() != bridge) {
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

            // In simulation we can check current peers; in broadcast the bridge may not exist yet
            if (!_isSimulation || IOAppCore(bridgeAddr).peers(peerEid) != peerAddress) {
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

    function _flushBatch(string memory description) internal {
        uint256 len = _batchTargets.length;
        if (len == 0) {
            console.log("  No changes needed, skipping");
            return;
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
    }
}
