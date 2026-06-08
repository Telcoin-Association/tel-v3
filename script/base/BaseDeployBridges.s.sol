// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {console} from "forge-std/console.sol";
import {VmSafe} from "forge-std/Vm.sol";
import {Safe} from "@safe-utils/Safe.sol";
import {IOAppCore} from "@layerzerolabs/oapp-evm/contracts/oapp/interfaces/IOAppCore.sol";
import {IMintableBurnable} from "@layerzerolabs/oft-evm/contracts/interfaces/IMintableBurnable.sol";
import {DeployBase} from "forge-deploy-utils/DeployBase.sol";
import {TelcoinV3} from "../../src/TelcoinV3.sol";
import {TelcoinBridge} from "../../src/TelcoinBridge.sol";
import {NativeBridge} from "../../src/NativeBridge.sol";
import {MintBurnWrapper} from "../../src/MintBurnWrapper.sol";
import {Roles} from "../../src/helpers/Roles.sol";

/// @title BaseDeployBridges
/// @notice Deploys bridge infrastructure and configures peers across all chains.
/// @dev    Step 1 in the deployment pipeline. Requires TelcoinV3 already deployed (loaded from JSON).
///
///         Per chain:
///         - mainChain: Deploy NativeBridge
///         - satellite: Deploy MintBurnWrapper + TelcoinBridge, grant MINTER/BURNER, authorize bridge
///
///         After all chains: Configure LayerZero peers between all bridges.
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

    // ------
    // Script
    // ------

    /// @dev Iterates all chains: deploys bridges, then configures LZ peers in a second pass.
    function run() public {
        uint256 len = allChains.length;

        // Deploy bridges
        for (uint256 i; i < len; ++i) {
            uint256 forkId = vm.createSelectFork(allChains[i].rpcUrl);
            currentNonce = safe.getNonce();

            console.log("=== Deploy Bridges on %s ===", allChains[i].chainName);

            address bridgeAddress = _deployAndConfigure(allChains[i]);

            getRuntimeData[allChains[i].rpcUrl] = RuntimeData({
                forkId: forkId,
                bridgeAddress: bridgeAddress
            });
        }

        // Configure peers
        for (uint256 i; i < len; ++i) {
            string memory rpcUrl = allChains[i].rpcUrl;
            vm.selectFork(getRuntimeData[rpcUrl].forkId);
            currentNonce = safe.getNonce();

            _configurePeers(i, len);
        }
    }

    // ------
    // Deploy
    // ------

    /// @dev Loads TelcoinV3 from JSON. For mainChain deploys NativeBridge; for satellites deploys
    ///      MintBurnWrapper + TelcoinBridge, grants MINTER/BURNER roles, and authorizes the bridge.
    function _deployAndConfigure(BridgeChainConfig memory chain) internal returns (address bridge) {
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
            bridge = _deployNativeBridge(chain.lzEndpoint);
            if (vm.isContext(VmSafe.ForgeContext.ScriptBroadcast)) {
                _saveDeploymentAddress(chain.chainName, "NativeBridge", bridge);
            }
        } else {
            address wrapper = _deployMintBurnWrapper(token);
            bridge = _deployTelcoinBridge(token, wrapper, chain.lzEndpoint);

            // Grant MINTER/BURNER roles to wrapper on TelcoinV3
            TelcoinV3 telcoinContract = TelcoinV3(token);

            if (!telcoinContract.hasRole(MINTER_ROLE, wrapper)) {
                _proposeTransaction(
                    token,
                    abi.encodeCall(telcoinContract.grantRole, (MINTER_ROLE, wrapper)),
                    "Grant MINTER_ROLE to MintBurnWrapper"
                );
            }
            if (!telcoinContract.hasRole(BURNER_ROLE, wrapper)) {
                _proposeTransaction(
                    token,
                    abi.encodeCall(telcoinContract.grantRole, (BURNER_ROLE, wrapper)),
                    "Grant BURNER_ROLE to MintBurnWrapper"
                );
            }

            // Authorize bridge on wrapper
            MintBurnWrapper wrapperContract = MintBurnWrapper(wrapper);
            if (wrapperContract.bridge() != bridge) {
                _proposeTransaction(
                    wrapper,
                    abi.encodeCall(wrapperContract.authorizeBridge, (bridge)),
                    "Authorize bridge on MintBurnWrapper"
                );
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

    /// @dev Batches all setPeer calls for a single chain into one Safe transaction.
    ///      Two-pass approach: first counts needed updates, then builds the batch.
    function _configurePeers(uint256 chainIdx, uint256 chainCount) internal {
        address bridgeAddr = getRuntimeData[allChains[chainIdx].rpcUrl].bridgeAddress;
        IOAppCore bridge = IOAppCore(bridgeAddr);

        uint256 count;
        for (uint256 j; j < chainCount; ++j) {
            if (chainIdx == j) continue;
            bytes32 peerAddress = bytes32(uint256(uint160(getRuntimeData[allChains[j].rpcUrl].bridgeAddress)));
            uint32 peerEid = allChains[j].lzChainId;
            if (bridge.peers(peerEid) != peerAddress) count++;
        }

        if (count == 0) return;

        address[] memory targets = new address[](count);
        bytes[] memory datas = new bytes[](count);
        uint256 idx;

        for (uint256 j; j < chainCount; ++j) {
            if (chainIdx == j) continue;
            bytes32 peerAddress = bytes32(uint256(uint160(getRuntimeData[allChains[j].rpcUrl].bridgeAddress)));
            uint32 peerEid = allChains[j].lzChainId;
            if (bridge.peers(peerEid) != peerAddress) {
                targets[idx] = bridgeAddr;
                datas[idx] = abi.encodeCall(IOAppCore.setPeer, (peerEid, peerAddress));
                idx++;
            }
        }

        _proposeTransactions(targets, datas, "Configure LZ peers");
    }

    // -----------
    // Deployments
    // -----------

    /// @dev Deploys MintBurnWrapper via CREATE3. Owner set to _admin. Idempotent.
    function _deployMintBurnWrapper(address telcoinV3) internal returns (address) {
        bytes memory params = abi.encode(telcoinV3, _admin);
        bytes memory bytecode = bytes.concat(type(MintBurnWrapper).creationCode, params);
        (address addr, bool isNew) = _deployCreate3(_mintBurnWrapperSalt, bytecode, "Deploy MintBurnWrapper");

        if (isNew) console.log("Deployed MintBurnWrapper at:", addr);
        else console.log("MintBurnWrapper already deployed at:", addr);

        return addr;
    }

    /// @dev Deploys TelcoinBridge (MintBurnOFTAdapter) via CREATE3. Satellite chains only. Idempotent.
    function _deployTelcoinBridge(address telcoinV3, address wrapper, address endpoint) internal returns (address) {
        bytes memory params = abi.encode(telcoinV3, IMintableBurnable(wrapper), endpoint, _admin);
        bytes memory bytecode = bytes.concat(type(TelcoinBridge).creationCode, params);
        (address addr, bool isNew) = _deployCreate3(_bridgeSalt, bytecode, "Deploy TelcoinBridge");

        if (isNew) console.log("Deployed TelcoinBridge at:", addr);
        else console.log("TelcoinBridge already deployed at:", addr);

        return addr;
    }

    /// @dev Deploys NativeBridge (NativeOFTAdapter) via CREATE3. Main chain only. Idempotent.
    function _deployNativeBridge(address endpoint) internal returns (address) {
        bytes memory params = abi.encode(endpoint, _admin);
        bytes memory bytecode = bytes.concat(type(NativeBridge).creationCode, params);
        (address addr, bool isNew) = _deployCreate3(_nativeBridgeSalt, bytecode, "Deploy NativeBridge");

        if (isNew) console.log("Deployed NativeBridge at:", addr);
        else console.log("NativeBridge already deployed at:", addr);

        return addr;
    }
}
