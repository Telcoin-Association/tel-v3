// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {console} from "forge-std/console.sol";
import {Safe} from "@safe-utils/Safe.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {DeployUtility} from "../utils/DeployUtility.sol";
import {TelcoinV3} from "../../src/TelcoinV3.sol";
import {TokenMigration} from "../../src/TokenMigration.sol";
import {MigrationVault} from "../../src/MigrationVault.sol";
import {Roles} from "../../src/helpers/Roles.sol";

/// @title BaseDeployMigrationInfra
/// @notice Deploys TokenMigration + MigrationVault and configures roles.
/// @dev    Step 3 in the deployment pipeline. Requires TelcoinV3 already deployed (loaded from JSON).
///         Only run on chains that have a legacy TEL token to migrate from.
///
///         Per chain:
///         1. (Optional) Deploy legacy Telcoin for testnet
///         2. Deploy TokenMigration
///         3. Deploy MigrationVault (implementation + proxy)
///         4. Grant MINTER_ROLE to TokenMigration on TelcoinV3
///         5. Grant TREASURY_ROLE to admin on MigrationVault
///         6. Save addresses to deployments JSON
abstract contract BaseDeployMigrationInfra is DeployUtility, Roles {
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
    ///      deploys TokenMigration + MigrationVault, grants MINTER and TREASURY roles.
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

        // 1. Resolve legacy token
        address legacyTelcoin = chain.legacyTel;
        if (legacyTelcoin == address(0) && chain.deployLegacyTel) {
            legacyTelcoin = _deployLegacyTelcoin();
            _saveDeploymentAddress(chain.chainName, "TelcoinLegacy", legacyTelcoin);
        }
        require(legacyTelcoin != address(0), string.concat("No legacy TEL for ", chain.chainName));

        // 2. Deploy TokenMigration
        address migrator = _deployTokenMigration(legacyTelcoin, token);

        // 3. Deploy MigrationVault
        address migrationVault = _deployMigrationVault(legacyTelcoin, token);

        // 4. Grant MINTER_ROLE to TokenMigration on TelcoinV3
        TelcoinV3 telcoinContract = TelcoinV3(token);
        if (!telcoinContract.hasRole(MINTER_ROLE, migrator)) {
            _proposeTransaction(
                token,
                abi.encodeCall(telcoinContract.grantRole, (MINTER_ROLE, migrator)),
                "Grant MINTER_ROLE to TokenMigration"
            );
        }

        // 5. Grant TREASURY_ROLE to treasury on MigrationVault
        MigrationVault vault = MigrationVault(migrationVault);
        bytes32 treasuryRole = vault.TREASURY_ROLE();
        if (!vault.hasRole(treasuryRole, _treasury)) {
            _proposeTransaction(
                migrationVault,
                abi.encodeCall(vault.grantRole, (treasuryRole, _treasury)),
                "Grant TREASURY_ROLE to treasury on MigrationVault"
            );
        }

        // 6. Save addresses
        _saveDeploymentAddress(chain.chainName, "TelcoinMigration", migrator);
        _saveDeploymentAddress(chain.chainName, "MigrationVault", migrationVault);
    }

    // -----------
    // Deployments
    // -----------

    /// @dev Deploys legacy Telcoin (^0.4.18) using deployCode. Testnet only.
    function _deployLegacyTelcoin() internal returns (address) {
        address legacyTelcoin = deployCode("Telcoin.sol:Telcoin", abi.encode(deployerSafeAddress));
        console.log("Legacy Telcoin deployed at:", legacyTelcoin);
        return legacyTelcoin;
    }

    /// @dev Deploys TokenMigration via CREATE3. Time-limited 1:1 swap with escrow. Idempotent.
    function _deployTokenMigration(address legacyToken, address telcoinV3) internal returns (address) {
        bytes memory params = abi.encode(legacyToken, telcoinV3, _admin, _migrationDuration, _withdrawalDelay);
        bytes memory bytecode = bytes.concat(type(TokenMigration).creationCode, params);
        (address addr, bool isNew) = _deployCreate3(_migrationSalt, bytecode, "Deploy TokenMigration");

        if (isNew) console.log("Deployed TokenMigration at:", addr);
        else console.log("TokenMigration already deployed at:", addr);

        return addr;
    }

    /// @dev Deploys MigrationVault impl + ERC1967Proxy via CREATE3. Proxy is initialized with
    ///      _admin as admin, pauser, and unpauser. Returns the proxy address. Idempotent.
    function _deployMigrationVault(address legacyToken, address telcoinV3) internal returns (address) {
        // Deploy implementation
        bytes memory implParams = abi.encode(legacyToken, telcoinV3);
        bytes memory implBytecode = bytes.concat(type(MigrationVault).creationCode, implParams);
        (address implAddr, bool implNew) = _deployCreate3(_migrationVaultImplSalt, implBytecode, "Deploy MigrationVault impl");

        if (implNew) console.log("Deployed MigrationVault impl at:", implAddr);
        else console.log("MigrationVault impl already deployed at:", implAddr);

        // Deploy proxy
        bytes memory initData = abi.encodeCall(MigrationVault.initialize, (_admin, _pauser, _unpauser));
        bytes memory proxyParams = abi.encode(implAddr, initData);
        bytes memory proxyBytecode = bytes.concat(type(ERC1967Proxy).creationCode, proxyParams);
        (address proxyAddr, bool proxyNew) = _deployCreate3(_migrationVaultProxySalt, proxyBytecode, "Deploy MigrationVault proxy");

        if (proxyNew) console.log("Deployed MigrationVault proxy at:", proxyAddr);
        else console.log("MigrationVault proxy already deployed at:", proxyAddr);

        return proxyAddr;
    }
}
