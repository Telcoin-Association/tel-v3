// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {console} from "forge-std/console.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {DeployUtility} from "../utils/DeployUtility.sol";
import {TokenMigration} from "../../src/TokenMigration.sol";

/**
 * @title MigrateTokens
 * @author chasebrownn
 * @notice Script to migrate legacy TEL tokens to TelcoinV3 via TokenMigration contract.
 *
 * ## How to Run
 *
 * Dry run (Sepolia):
 * ```
 * forge script script/testnet/MigrateTokens.s.sol --fork-url $ETH_SEPOLIA_RPC_URL
 * ```
 *
 * Live execution (Sepolia):
 * ```
 * forge script script/testnet/MigrateTokens.s.sol --fork-url $ETH_SEPOLIA_RPC_URL --broadcast -vvvv
 * ```
 *
 * For Base Sepolia, use $BASE_SEPOLIA_RPC_URL instead.
 */
contract MigrateTokens is DeployUtility {
    // ---------
    // Variables
    // ---------

    /// @dev Chain alias for loading deployment addresses
    string internal constant CHAIN_ALIAS = "eth-sepolia";

    // ------
    // Script
    // ------

    function run() public {
        _setup();

        // Load deployed contract addresses
        address legacyTelcoin = _loadDeploymentAddress(CHAIN_ALIAS, "TelcoinLegacy");
        address telcoinV3 = _loadDeploymentAddress(CHAIN_ALIAS, "TelcoinV3");
        address migrationContract = _loadDeploymentAddress(CHAIN_ALIAS, "TelcoinMigration");

        require(legacyTelcoin != address(0), "Legacy Telcoin not deployed");
        require(telcoinV3 != address(0), "TelcoinV3 not deployed");
        require(migrationContract != address(0), "TokenMigration not deployed");

        console.log("=== Migration Script ===");
        console.log("Chain:", CHAIN_ALIAS);
        console.log("Migrator:", _deployer);
        console.log("");
        console.log("Legacy TEL:", legacyTelcoin);
        console.log("TelcoinV3:", telcoinV3);
        console.log("Migration Contract:", migrationContract);
        console.log("");

        IERC20 legacyToken = IERC20(legacyTelcoin);
        IERC20 newToken = IERC20(telcoinV3);
        TokenMigration migration = TokenMigration(migrationContract);

        // --- PRE-MIGRATION CHECKS ---
        console.log("=== Pre-Migration State ===");

        uint256 legacyBalanceBefore = legacyToken.balanceOf(_deployer);
        uint256 newBalanceBefore = newToken.balanceOf(_deployer);

        console.log("Deployer Legacy TEL Balance:", legacyBalanceBefore);
        console.log("Deployer TelcoinV3 Balance:", newBalanceBefore);
        console.log("");

        // Calculate expected new tokens (legacy has 2 decimals, new has 18)
        uint256 decimalMultiplier = migration.DECIMAL_MULTIPLIER();
        uint256 expectedNewTokens = legacyBalanceBefore * decimalMultiplier;
        console.log("Expected TelcoinV3 to receive:", expectedNewTokens);
        console.log("");

        // --- EXECUTE MIGRATION ---
        console.log("=== Executing Migration ===");

        vm.startBroadcast(_pk);

        // Step 1: Approve migration contract to spend legacy tokens
        console.log("Step 1: Approving migration contract...");
        legacyToken.approve(migrationContract, legacyBalanceBefore);

        // Step 2: Execute migration
        console.log("Step 2: Calling migrate()...");
        migration.migrate();

        vm.stopBroadcast();

        // --- POST-MIGRATION CHECKS ---
        console.log("");
        console.log("=== Post-Migration State ===");

        uint256 legacyBalanceAfter = legacyToken.balanceOf(_deployer);
        uint256 newBalanceAfter = newToken.balanceOf(_deployer);
        uint256 burnAddressBalance = legacyToken.balanceOf(migration.BURN_ADDRESS());

        console.log("Deployer Legacy TEL Balance:", legacyBalanceAfter);
        console.log("Deployer TelcoinV3 Balance:", newBalanceAfter);
        console.log("Burn Address Legacy TEL Balance:", burnAddressBalance);
        console.log("");

        // Verify state changes
        console.log("=== Verification ===");

        bool legacyBurned = legacyBalanceAfter == 0;
        bool newReceived = (newBalanceAfter - newBalanceBefore) == expectedNewTokens;

        console.log("Legacy tokens burned correctly:", legacyBurned ? "PASS" : "FAIL");
        console.log("New tokens received correctly:", newReceived ? "PASS" : "FAIL");

        if (legacyBurned && newReceived) {
            console.log("");
            console.log("Migration successful!");
        } else {
            console.log("");
            console.log("Migration verification failed!");
        }
    }
}
