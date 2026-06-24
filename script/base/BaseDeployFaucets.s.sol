// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {console} from "forge-std/console.sol";
import {VmSafe} from "forge-std/Vm.sol";
import {Safe} from "@safe-utils/Safe.sol";
import {DeployBase} from "forge-deploy-utils/DeployBase.sol";
import {SaltMath} from "forge-deploy-utils/libraries/SaltMath.sol";
import {ICreateX} from "forge-deploy-utils/interfaces/ICreateX.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {TelcoinV3Faucet} from "../../src/faucet/TelcoinV3Faucet.sol";
import {LegacyTelcoinFaucet} from "../../src/faucet/LegacyTelcoinFaucet.sol";
import {Roles} from "../../src/helpers/Roles.sol";

/// @title BaseDeployFaucets
/// @notice Deploys TelcoinV3Faucet + LegacyTelcoinFaucet via CREATE3 and configures roles.
///         All deploys and role grants for a single chain are batched into one MultiSend Safe transaction.
/// @dev    Testnet only. Requires TelcoinV3 and TelcoinLegacy already deployed (loaded from JSON).
///
///         Per chain (single MultiSend):
///         1. Deploy TelcoinV3Faucet
///         2. Deploy LegacyTelcoinFaucet
///         3. Grant MINTER_ROLE to TelcoinV3Faucet on TelcoinV3
///         4. Fund LegacyTelcoinFaucet with legacy TEL
///         5. Save addresses to deployments JSON
abstract contract BaseDeployFaucets is DeployBase, Roles {
    using Safe for *;

    // ---------
    // Variables
    // ---------

    address internal _admin;

    uint256 internal _dripAmount;
    uint256 internal _legacyDripAmount;
    uint256 internal _cooldown;

    bytes32 internal _v3FaucetSalt;
    bytes32 internal _legacyFaucetSalt;

    struct FaucetChainConfig {
        string chainName;
        string rpcUrl;
        uint256 evmChainId;
    }

    FaucetChainConfig[] internal allChains;

    // Batch accumulation
    address[] internal _batchTargets;
    bytes[] internal _batchDatas;

    // ------
    // Script
    // ------

    /// @dev Iterates configured chains and deploys faucets on each.
    function run() public {
        uint256 len = allChains.length;

        for (uint256 i; i < len; ++i) {
            vm.createSelectFork(allChains[i].rpcUrl);
            currentNonce = safe.getNonce();

            console.log("=== Deploy Faucets on %s ===", allChains[i].chainName);

            _deployAndConfigure(allChains[i]);
        }
    }

    // ------
    // Deploy
    // ------

    /// @dev Loads TelcoinV3 and TelcoinLegacy from JSON, batches faucet deploys + role grants
    ///      into one MultiSend.
    function _deployAndConfigure(FaucetChainConfig memory chain) internal {
        require(
            block.chainid == chain.evmChainId,
            string.concat(
                "Chain ID mismatch: expected ",
                vm.toString(chain.evmChainId),
                " but connected to ",
                vm.toString(block.chainid)
            )
        );

        address telcoinV3 = _loadDeploymentAddress(chain.chainName, "TelcoinV3");
        require(telcoinV3 != address(0), string.concat("TelcoinV3 not deployed on ", chain.chainName));

        address legacyTel = _loadDeploymentAddress(chain.chainName, "TelcoinLegacy");
        require(legacyTel != address(0), string.concat("TelcoinLegacy not deployed on ", chain.chainName));

        // 1. Deploy TelcoinV3Faucet (batched)
        address v3Faucet = _addCreate3ToBatch(
            _v3FaucetSalt,
            bytes.concat(
                type(TelcoinV3Faucet).creationCode,
                abi.encode(telcoinV3, _dripAmount, _cooldown, _admin)
            ),
            "Deploy TelcoinV3Faucet"
        );

        // 2. Deploy LegacyTelcoinFaucet (batched)
        address legacyFaucet = _addCreate3ToBatch(
            _legacyFaucetSalt,
            bytes.concat(
                type(LegacyTelcoinFaucet).creationCode,
                abi.encode(legacyTel, _legacyDripAmount, _cooldown, _admin)
            ),
            "Deploy LegacyTelcoinFaucet"
        );

        // 3. Grant MINTER_ROLE to TelcoinV3Faucet on TelcoinV3 (batched)
        console.log("  [batch] Grant MINTER_ROLE to TelcoinV3Faucet");
        _batchTargets.push(telcoinV3);
        _batchDatas.push(abi.encodeCall(IAccessControl.grantRole, (MINTER_ROLE, v3Faucet)));

        // 4. Flush batch
        _flushBatch(string.concat("Deploy + configure faucets on ", chain.chainName));

        // 6. Save addresses (only on broadcast to avoid polluting JSON during simulation)
        if (vm.isContext(VmSafe.ForgeContext.ScriptBroadcast)) {
            _saveDeploymentAddress(chain.chainName, "TelcoinV3Faucet", v3Faucet);
            _saveDeploymentAddress(chain.chainName, "LegacyTelcoinFaucet", legacyFaucet);
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
