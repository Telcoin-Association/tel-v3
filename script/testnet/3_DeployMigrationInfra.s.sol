// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BaseDeployMigrationInfra} from "../base/BaseDeployMigrationInfra.s.sol";
import "./utils/Constants.sol";

/// @title DeployMigrationInfra (Testnet)
/// @notice Deploys TokenMigration + MigrationVault to testnet chains via Gnosis Safe.
///
/// ## How to Run
///
/// Simulation:
/// ```
/// forge script script/testnet/3_DeployMigrationInfra.s.sol --rpc-url $RPC_URL --ffi -vvvv
/// ```
///
/// Broadcast:
/// ```
/// forge script script/testnet/3_DeployMigrationInfra.s.sol --rpc-url $RPC_URL --broadcast --ffi -vvvv
/// ```
contract DeployMigrationInfra is BaseDeployMigrationInfra {
    function setUp() public {
        _initializeSafe();

        _admin = deployerSafeAddress;
        _migrationSalt = keccak256("RAW_TELCOIN_MIGRATION_SALT_V2");
        _migrationVaultImplSalt = keccak256("RAW_MIGRATION_VAULT_IMPL_SALT_V2");
        _migrationVaultProxySalt = keccak256("RAW_MIGRATION_VAULT_PROXY_SALT_V2");

        _migrationDuration = 365 days;
        _withdrawalDelay = 90 days;

        allChains.push(MigrationChainConfig({
            chainName: "eth-sepolia",
            rpcUrl: vm.envString("ETH_SEPOLIA_RPC_URL"),
            evmChainId: ETH_SEPOLIA_CHAIN_ID,
            legacyTel: _loadDeploymentAddress("eth-sepolia", "TelcoinLegacy"),
            deployLegacyTel: true
        }));

        allChains.push(MigrationChainConfig({
            chainName: "base-sepolia",
            rpcUrl: vm.envString("BASE_SEPOLIA_RPC_URL"),
            evmChainId: BASE_SEPOLIA_CHAIN_ID,
            legacyTel: _loadDeploymentAddress("base-sepolia", "TelcoinLegacy"),
            deployLegacyTel: true
        }));
    }
}
