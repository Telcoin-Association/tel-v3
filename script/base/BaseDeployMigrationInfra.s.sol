// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {console} from "forge-std/console.sol";
import {VmSafe} from "forge-std/Vm.sol";
import {Safe} from "@safe-utils/Safe.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {DeployBase} from "forge-deploy-utils/DeployBase.sol";
import {SaltMath} from "forge-deploy-utils/libraries/SaltMath.sol";
import {ICreateX} from "forge-deploy-utils/interfaces/ICreateX.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {TelcoinV3} from "../../src/TelcoinV3.sol";
import {TokenMigration} from "../../src/TokenMigration.sol";
import {MigrationVault} from "../../src/MigrationVault.sol";
import {Roles} from "../../src/helpers/Roles.sol";

/// @title BaseDeployMigrationInfra
/// @notice Deploys TokenMigration + MigrationVault and configures roles.
///         All deploys and role grants for a single chain are batched into one MultiSend Safe transaction.
/// @dev    Step 3 in the deployment pipeline. Requires TelcoinV3 already deployed (loaded from JSON).
///         Only run on chains that have a legacy TEL token to migrate from.
///
///         Per chain (single MultiSend):
///         1. (Optional) Deploy legacy Telcoin for testnet
///         2. Deploy TokenMigration
///         3. Deploy MigrationVault (implementation + proxy)
///         4. Grant MINTER_ROLE to TokenMigration on TelcoinV3
///         5. Grant TREASURY_ROLE to admin on MigrationVault
///         6. Save addresses to deployments JSON
abstract contract BaseDeployMigrationInfra is DeployBase, Roles {
    using Safe for *;

    // ---------
    // Variables
    // ---------

    address internal _admin;
    address internal _pauser;
    address internal _unpauser;
    address internal _treasury;
    uint256 internal _migrationDuration;
    uint256 internal _withdrawalDelay;

    bytes32 internal _migrationSalt;
    bytes32 internal _migrationVaultImplSalt;
    bytes32 internal _migrationVaultProxySalt;

    struct MigrationChainConfig {
        string chainName;
        string rpcUrl;
        uint256 evmChainId;
        address legacyTel;
        bool deployLegacyTel;
    }

    MigrationChainConfig[] internal allChains;

    // Batch accumulation
    address[] internal _batchTargets;
    bytes[] internal _batchDatas;

    // ------
    // Script
    // ------

    /// @dev Iterates configured chains and deploys migration infrastructure on each.
    function run() public {
        uint256 len = allChains.length;

        for (uint256 i; i < len; ++i) {
            vm.createSelectFork(allChains[i].rpcUrl);
            currentNonce = safe.getNonce();

            console.log("=== Deploy Migration Infra on %s ===", allChains[i].chainName);

            _deployAndConfigure(allChains[i]);
        }
    }

    // ------
    // Deploy
    // ------

    /// @dev Loads TelcoinV3 from JSON. Resolves legacy token (optionally deploying on testnet),
    ///      batches TokenMigration + MigrationVault deploys and role grants into one MultiSend.
    function _deployAndConfigure(MigrationChainConfig memory chain) internal {
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

        // 1. Resolve legacy token (not batched — uses deployCode cheatcode)
        address legacyTelcoin = chain.legacyTel;
        if (legacyTelcoin == address(0) && chain.deployLegacyTel) {
            legacyTelcoin = _deployLegacyTelcoin();
            if (vm.isContext(VmSafe.ForgeContext.ScriptBroadcast)) {
                _saveDeploymentAddress(chain.chainName, "TelcoinLegacy", legacyTelcoin);
            }
        }
        require(legacyTelcoin != address(0), string.concat("No legacy TEL for ", chain.chainName));

        // 2. Deploy TokenMigration (batched)
        address migrator = _addCreate3ToBatch(
            _migrationSalt,
            bytes.concat(
                type(TokenMigration).creationCode,
                abi.encode(legacyTelcoin, token, _admin, _migrationDuration, _withdrawalDelay)
            ),
            "Deploy TokenMigration"
        );

        // 2b. Grant PAUSER_ROLE/UNPAUSER_ROLE on TokenMigration (batched, post-deploy)
        require(_pauser != address(0), "Pauser not configured");
        require(_unpauser != address(0), "Unpauser not configured");
        console.log("  [batch] Grant PAUSER_ROLE / UNPAUSER_ROLE on TokenMigration");
        _batchTargets.push(migrator);
        _batchDatas.push(abi.encodeCall(IAccessControl.grantRole, (PAUSER_ROLE, _pauser)));
        _batchTargets.push(migrator);
        _batchDatas.push(abi.encodeCall(IAccessControl.grantRole, (UNPAUSER_ROLE, _unpauser)));

        // 3. Deploy MigrationVault impl (batched)
        address implAddr = _addCreate3ToBatch(
            _migrationVaultImplSalt,
            bytes.concat(type(MigrationVault).creationCode, abi.encode(legacyTelcoin, token)),
            "Deploy MigrationVault impl"
        );

        // 4. Deploy MigrationVault proxy (batched)
        bytes memory initData = abi.encodeCall(MigrationVault.initialize, (_admin, _pauser, _unpauser));
        address proxyAddr = _addCreate3ToBatch(
            _migrationVaultProxySalt,
            bytes.concat(type(ERC1967Proxy).creationCode, abi.encode(implAddr, initData)),
            "Deploy MigrationVault proxy"
        );

        // 5. Grant MINTER_ROLE to TokenMigration on TelcoinV3 (batched)
        console.log("  [batch] Grant MINTER_ROLE to TokenMigration");
        _batchTargets.push(token);
        _batchDatas.push(abi.encodeCall(IAccessControl.grantRole, (MINTER_ROLE, migrator)));

        // 6. Grant TREASURY_ROLE to treasury on MigrationVault (batched)
        console.log("  [batch] Grant TREASURY_ROLE to treasury");
        bytes32 treasuryRole = keccak256("TREASURY_ROLE");
        _batchTargets.push(proxyAddr);
        _batchDatas.push(abi.encodeCall(IAccessControl.grantRole, (treasuryRole, _treasury)));

        // 7. Flush batch
        _flushBatch(string.concat("Deploy migration infra on ", chain.chainName));

        // 8. Save addresses (only on broadcast to avoid polluting JSON during simulation)
        if (vm.isContext(VmSafe.ForgeContext.ScriptBroadcast)) {
            _saveDeploymentAddress(chain.chainName, "TelcoinMigration", migrator);
            _saveDeploymentAddress(chain.chainName, "MigrationVault", proxyAddr);
        }
    }

    // -------
    // Helpers
    // -------

    /// @dev Deploys legacy Telcoin (^0.4.18) using deployCode. Testnet only. Not batched.
    function _deployLegacyTelcoin() internal returns (address) {
        address legacyTelcoin = deployCode("Telcoin.sol:Telcoin", abi.encode(deployerSafeAddress));
        console.log("Legacy Telcoin deployed at:", legacyTelcoin);
        return legacyTelcoin;
    }

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
