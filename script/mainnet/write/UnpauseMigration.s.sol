// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {console} from "forge-std/console.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {DeployBase} from "forge-deploy-utils/DeployBase.sol";
import {TokenMigration} from "../../../src/TokenMigration.sol";
import {Roles} from "../../../src/helpers/Roles.sol";
import "../utils/Constants.sol";

/// @title UnpauseMigration (Mainnet)
/// @notice Unpauses TokenMigration at launch, opening TEL v2 -> TEL v3 migration to the public.
///
///         unpause() is gated by UNPAUSER_ROLE, which is held by the dedicated unpauser
///         (not the admin Safe) — run with DEPLOYER_SAFE_ADDRESS set to the Safe that
///         holds UNPAUSER_ROLE on TokenMigration.
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

        // Pre-flight checks
        require(migration.paused(), "TokenMigration is already unpaused");
        require(
            IAccessControl(migrator).hasRole(UNPAUSER_ROLE, deployerSafeAddress),
            "Safe lacks UNPAUSER_ROLE (set DEPLOYER_SAFE_ADDRESS to the unpauser Safe)"
        );
        require(!migration.migrationClosed(), "Migration permanently closed");
        require(block.timestamp < migration.migrationExpiry(), "Migration expired");

        console.log("=== Unpause Migration for Launch (Safe) ===");
        console.log("Chain:", chainAlias);
        console.log("Safe:", deployerSafeAddress);
        console.log("TokenMigration:", migrator);
        console.log("Migration expiry:", migration.migrationExpiry());
        console.log("");

        _proposeTransaction(
            migrator,
            abi.encodeCall(TokenMigration.unpause, ()),
            "Unpause TokenMigration for launch"
        );

        if (isSimulation()) {
            require(!migration.paused(), "TokenMigration still paused after simulation");
            console.log("Simulation OK: TokenMigration unpaused, migration is live.");
        } else {
            console.log("Unpause transaction proposed.");
        }
    }

    function _chainAlias() internal view returns (string memory) {
        if (block.chainid == ETH_MAINNET_CHAIN_ID) return "ethereum";
        if (block.chainid == BASE_MAINNET_CHAIN_ID) return "base";
        if (block.chainid == POLYGON_MAINNET_CHAIN_ID) return "polygon";
        revert("Unsupported chain");
    }
}
