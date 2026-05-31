// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {console} from "forge-std/console.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {DeployBase} from "forge-deploy-utils/DeployBase.sol";
import {TokenMigration} from "../../../src/TokenMigration.sol";

/// @title MigrateTokens
/// @notice Script to migrate legacy TEL tokens to TelcoinV3 via TokenMigration contract
///         using a Gnosis Safe.
///
/// ## How to Run
///
/// Simulation:
/// ```
/// forge script script/testnet/MigrateTokens.s.sol --fork-url $ETH_SEPOLIA_RPC_URL --ffi -vvvv
/// ```
///
/// Broadcast (proposes to Safe TX Service):
/// ```
/// forge script script/testnet/MigrateTokens.s.sol --fork-url $ETH_SEPOLIA_RPC_URL --broadcast --ffi -vvvv
/// ```
contract MigrateTokens is DeployBase {
    // ---------
    // Variables
    // ---------

    string internal constant CHAIN_ALIAS = "eth-sepolia";

    // ------
    // Script
    // ------

    function setUp() public {
        _initializeSafe();
    }

    function run() public {
        address legacyTelcoin = _loadDeploymentAddress(CHAIN_ALIAS, "TelcoinLegacy");
        address telcoinV3 = _loadDeploymentAddress(CHAIN_ALIAS, "TelcoinV3");
        address migrationContract = _loadDeploymentAddress(CHAIN_ALIAS, "TelcoinMigration");

        require(legacyTelcoin != address(0), "Legacy Telcoin not deployed");
        require(telcoinV3 != address(0), "TelcoinV3 not deployed");
        require(migrationContract != address(0), "TokenMigration not deployed");

        console.log("=== Migration Script (Safe) ===");
        console.log("Chain:", CHAIN_ALIAS);
        console.log("Safe:", deployerSafeAddress);
        console.log("Legacy TEL:", legacyTelcoin);
        console.log("TelcoinV3:", telcoinV3);
        console.log("Migration Contract:", migrationContract);
        console.log("");

        IERC20 legacyToken = IERC20(legacyTelcoin);

        uint256 legacyBalance = legacyToken.balanceOf(deployerSafeAddress);
        console.log("Safe Legacy TEL Balance:", legacyBalance);

        // Step 1: Approve migration contract to spend legacy tokens
        _proposeTransaction(
            legacyTelcoin,
            abi.encodeCall(legacyToken.approve, (migrationContract, legacyBalance)),
            "Approve TokenMigration for legacy TEL"
        );

        // Step 2: Execute migration
        _proposeTransaction(
            migrationContract,
            abi.encodeCall(TokenMigration.migrate, ()),
            "Migrate legacy TEL to TelcoinV3"
        );

        console.log("Migration transactions proposed.");
    }
}
