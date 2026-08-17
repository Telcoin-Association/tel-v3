// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BaseDeployMigrationInfra} from "../base/BaseDeployMigrationInfra.s.sol";
import "./utils/Constants.sol";
import "./utils/Roles.sol";
import "./utils/Salts.sol";

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
/// ## Queueing behind pending Safe txns
///
/// Proposal nonces derive from the on-chain Safe nonce, which only advances on
/// execution. If an earlier step is proposed but not yet executed, broadcasting
/// this step would collide at the same nonce. Set SAFE_NONCE_OFFSET to the
/// number of pending (unexecuted) proposals so this one queues behind them:
/// ```
/// SAFE_NONCE_OFFSET=1 SAFE_BROADCAST=true forge script <this script> --rpc-url $RPC_URL --broadcast --ffi -vvvv
/// ```
contract DeployMigrationInfra is BaseDeployMigrationInfra {
    function setUp() public {
        _initializeSafeMultiSig();

        _admin = ADMIN;
        _pauser = PAUSER;
        _unpauser = UNPAUSER;
        _treasury = TREASURY;
        _migrationSalt = TELCOIN_MIGRATION_SALT;
        _migrationVaultImplSalt = MIGRATION_VAULT_IMPL_SALT;
        _migrationVaultProxySalt = MIGRATION_VAULT_PROXY_SALT;

        _migrationDuration = 365 days;
        _withdrawalDelay = 90 days;

        // Only chains with legacy TEL tokens
        allChains.push(MigrationChainConfig({
            chainName: "ethereum",
            rpcUrl: vm.envString("ETHEREUM_RPC_URL"),
            evmChainId: ETH_MAINNET_CHAIN_ID,
            legacyTel: LEGACY_TELCOIN_ETHEREUM,
            deployLegacyTel: false
        }));

        // Add more chains here as needed (e.g. Polygon if legacy TEL exists there)
    }
}
