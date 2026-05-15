// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BaseDeployMigrationInfra} from "../base/BaseDeployMigrationInfra.s.sol";
import "./utils/Constants.sol";

/// @title DeployMigrationInfra (Mainnet)
/// @notice Deploys TokenMigration + MigrationVault to mainnet chains via Gnosis Safe.
///         Only run on chains that have a legacy TEL token to migrate from.
///
/// ## How to Run
///
/// Simulation:
/// ```
/// forge script script/mainnet/3_DeployMigrationInfra.s.sol --rpc-url $RPC_URL --ffi -vvvv
/// ```
///
/// Broadcast:
/// ```
/// forge script script/mainnet/3_DeployMigrationInfra.s.sol --rpc-url $RPC_URL --broadcast --ffi -vvvv
/// ```
contract DeployMigrationInfra is BaseDeployMigrationInfra {
    function setUp() public {
        _initializeSafe();

        _admin = deployerSafeAddress;
        _migrationSalt = keccak256("RAW_TELCOIN_MIGRATION_SALT_MAINNET");
        _migrationVaultImplSalt = keccak256("RAW_MIGRATION_VAULT_IMPL_SALT_MAINNET");
        _migrationVaultProxySalt = keccak256("RAW_MIGRATION_VAULT_PROXY_SALT_MAINNET");

        _migrationDuration = 365 days;
        _withdrawalDelay = 90 days;

        // Only chains with legacy TEL tokens
        // Ethereum Mainnet — TEL v2 at 0x467Bccd9d29f223BcE8043b84E8C8B282827790F
        allChains.push(MigrationChainConfig({
            chainName: "ethereum",
            rpcUrl: vm.envString("ETHEREUM_RPC_URL"),
            evmChainId: ETH_MAINNET_CHAIN_ID,
            legacyTel: _loadDeploymentAddress("ethereum", "TelcoinLegacy"),
            deployLegacyTel: false
        }));

        // Add more chains here as needed (e.g. Polygon if legacy TEL exists there)
    }
}
