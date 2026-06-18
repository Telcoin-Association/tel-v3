// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {console} from "forge-std/console.sol";
import {VmSafe} from "forge-std/Vm.sol";
import {Safe} from "@safe-utils/Safe.sol";
import {DeployBase} from "forge-deploy-utils/DeployBase.sol";
import {SaltMath} from "forge-deploy-utils/libraries/SaltMath.sol";
import {ICreateX} from "forge-deploy-utils/interfaces/ICreateX.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {TelcoinV3} from "../../src/TelcoinV3.sol";
import {Roles} from "../../src/helpers/Roles.sol";

/// @title BaseDeployToken
/// @notice Deploys TelcoinV3 via CREATE3 and configures PAUSER/UNPAUSER roles.
///         All deploys and role grants for a single chain are batched into one MultiSend Safe transaction.
/// @dev    Step 0 in the deployment pipeline. Children populate configuration in setUp().
///
///         Per chain (single MultiSend):
///         1. Deploy TelcoinV3 (mints initialSupply to _admin)
///         2. Grant PAUSER_ROLE to _pauser
///         3. Grant UNPAUSER_ROLE to _unpauser
///         4. Save address to deployments JSON
abstract contract BaseDeployToken is DeployBase, Roles {
    using Safe for *;

    // -----
    // Roles
    // -----

    address internal _admin;
    address internal _pauser;
    address internal _unpauser;

    // ---------
    // Variables
    // ---------

    bytes32 internal _telcoinV3Salt;

    struct TokenChainConfig {
        string chainName;
        string rpcUrl;
        uint256 evmChainId;
        uint256 initialSupply;
    }

    TokenChainConfig[] internal allChains;

    // Batch accumulation
    address[] internal _batchTargets;
    bytes[] internal _batchDatas;

    // ------
    // Script
    // ------

    /// @dev Iterates all configured chains, fork-switches, and deploys TelcoinV3 + roles on each.
    function run() public {
        uint256 len = allChains.length;

        for (uint256 i; i < len; ++i) {
            vm.createSelectFork(allChains[i].rpcUrl);
            currentNonce = safe.getNonce();

            console.log("=== Deploy TelcoinV3 on %s ===", allChains[i].chainName);

            _deployAndConfigure(allChains[i]);
        }
    }

    // ------
    // Deploy
    // ------

    /// @dev Batches TelcoinV3 deploy + PAUSER/UNPAUSER grants into one MultiSend, then persists to JSON.
    function _deployAndConfigure(TokenChainConfig memory chain) internal {
        require(
            block.chainid == chain.evmChainId,
            string.concat(
                "Chain ID mismatch: expected ",
                vm.toString(chain.evmChainId),
                " but connected to ",
                vm.toString(block.chainid)
            )
        );

        // 1. Deploy TelcoinV3 (batched)
        address token = _addCreate3ToBatch(
            _telcoinV3Salt,
            bytes.concat(type(TelcoinV3).creationCode, abi.encode(chain.initialSupply, _admin)),
            "Deploy TelcoinV3"
        );

        // 2. Grant PAUSER_ROLE (batched)
        console.log("  [batch] Grant PAUSER_ROLE to pauser");
        _batchTargets.push(token);
        _batchDatas.push(abi.encodeCall(IAccessControl.grantRole, (PAUSER_ROLE, _pauser)));

        // 3. Grant UNPAUSER_ROLE (batched)
        console.log("  [batch] Grant UNPAUSER_ROLE to unpauser");
        _batchTargets.push(token);
        _batchDatas.push(abi.encodeCall(IAccessControl.grantRole, (UNPAUSER_ROLE, _unpauser)));

        // 4. Flush batch
        _flushBatch(string.concat("Deploy + configure TelcoinV3 on ", chain.chainName));

        // 5. Save address (only on broadcast to avoid polluting JSON during simulation)
        if (vm.isContext(VmSafe.ForgeContext.ScriptBroadcast)) {
            _saveDeploymentAddress(chain.chainName, "TelcoinV3", token);
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
