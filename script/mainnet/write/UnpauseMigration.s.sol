// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {console} from "forge-std/console.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {DeployBase} from "forge-deploy-utils/DeployBase.sol";
import {TokenMigration} from "../../../src/TokenMigration.sol";
import {Roles} from "../../../src/helpers/Roles.sol";
import "../utils/Constants.sol";

/// @title UnpauseMigration (Mainnet)
/// @notice Launches public TEL v2 -> TEL v3 migration as ONE MultiSend Safe transaction:
///         1. setMigrationExpiry(now + 365 days) — the expiry clock started at deploy, so
///            without this the public window would be deploy + 365d, not launch + 365d.
///            Extend-only and DEFAULT_ADMIN_ROLE-gated.
///         2. unpause()                          — UNPAUSER_ROLE-gated.
///
///         Run with DEPLOYER_SAFE_ADDRESS set to the admin Safe, which holds BOTH roles
///         (the dedicated unpauser Safe cannot extend the expiry). Both are checked
///         up front with clear errors.
///
/// ## How to Run
///
/// Simulation:
/// ```
/// forge script script/mainnet/write/UnpauseMigration.s.sol --rpc-url $RPC_URL --ffi -vvvv
/// ```
///
/// Broadcast (proposes to Safe TX Service):
/// ```
/// forge script script/mainnet/write/UnpauseMigration.s.sol --rpc-url $RPC_URL --broadcast --ffi -vvvv
/// ```
///
/// ## Queueing behind pending Safe txns
///
/// Proposal nonces derive from the on-chain Safe nonce, which only advances on
/// execution. If an earlier txn is proposed but not yet executed, set SAFE_NONCE_OFFSET
/// to the number of pending (unexecuted) proposals so this one queues behind them:
/// ```
/// SAFE_NONCE_OFFSET=1 forge script <this script> --rpc-url $RPC_URL --broadcast --ffi -vvvv
/// ```
contract UnpauseMigration is DeployBase, Roles {
    bytes32 internal constant DEFAULT_ADMIN_ROLE = 0x00;

    /// @notice Public migration window measured from launch (this proposal), not deploy.
    uint256 internal constant MIGRATION_WINDOW = 365 days;

    address[] internal _batchTargets;
    bytes[] internal _batchDatas;

    function setUp() public {
        _initializeSafeMultiSig();
    }

    function run() public {
        // SAFE_NONCE_OFFSET queues this proposal behind pending-but-unexecuted
        // Safe txns (on-chain nonce doesn't advance until execution).
        currentNonce = getSafeNonce() + vm.envOr("SAFE_NONCE_OFFSET", uint256(0));

        string memory chainAlias = _chainAlias();

        address migrator = _loadDeploymentAddress(chainAlias, "TokenMigration");
        require(migrator != address(0), "TokenMigration not deployed");

        TokenMigration migration = TokenMigration(migrator);
        IAccessControl access = IAccessControl(migrator);
        uint256 newExpiry = block.timestamp + MIGRATION_WINDOW;

        // Pre-flight checks
        require(migration.paused(), "TokenMigration is already unpaused");
        require(!migration.migrationClosed(), "Migration permanently closed");
        require(
            access.hasRole(UNPAUSER_ROLE, deployerSafeAddress),
            "Safe lacks UNPAUSER_ROLE (set DEPLOYER_SAFE_ADDRESS to the admin Safe)"
        );
        require(
            access.hasRole(DEFAULT_ADMIN_ROLE, deployerSafeAddress),
            "Safe lacks DEFAULT_ADMIN_ROLE to extend expiry (set DEPLOYER_SAFE_ADDRESS to the admin Safe)"
        );
        require(newExpiry > migration.migrationExpiry(), "New expiry does not extend the current one");

        console.log("=== Launch Migration: extend expiry + unpause (Safe) ===");
        console.log("Chain:", chainAlias);
        console.log("Safe:", deployerSafeAddress);
        console.log("TokenMigration:", migrator);
        console.log("Current expiry:", migration.migrationExpiry());
        console.log("New expiry (launch + 365d):", newExpiry);
        console.log("");

        // 1. Full 365-day public window measured from launch
        _batchTargets.push(migrator);
        _batchDatas.push(abi.encodeCall(TokenMigration.setMigrationExpiry, (newExpiry)));

        // 2. Open public migration
        _batchTargets.push(migrator);
        _batchDatas.push(abi.encodeCall(TokenMigration.unpause, ()));

        _proposeTransactions(
            _batchTargets, _batchDatas, string.concat("Launch migration on ", chainAlias)
        );

        // Simulation executes the batch on the fork — verify the end state
        if (isSimulation()) {
            require(!migration.paused(), "TokenMigration still paused after simulation");
            require(migration.migrationExpiry() == newExpiry, "Expiry not extended");
            console.log("Simulation OK: expiry extended, TokenMigration unpaused, migration is live.");
        } else {
            console.log("Launch batch proposed.");
        }
    }

    function _chainAlias() internal view returns (string memory) {
        if (block.chainid == ETH_MAINNET_CHAIN_ID) return "ethereum";
        if (block.chainid == BASE_MAINNET_CHAIN_ID) return "base";
        if (block.chainid == POLYGON_MAINNET_CHAIN_ID) return "polygon";
        revert("Unsupported chain");
    }
}
