// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {MigrationVault} from "../../src/MigrationVault.sol";
import {TelcoinV3} from "../../src/TelcoinV3.sol";
import {Roles} from "../../src/helpers/Roles.sol";

/**
 * @title MigrationVaultFuzzTest
 * @dev Fuzz test suite stress-testing the MigrationVault.migrate() function.
 *      Runs against an Ethereum mainnet fork with real TEL v2 and a fresh TelcoinV3.
 *      Covers single-user migration, concurrent multi-user migrations, reserve
 *      depletion, pause/unpause during migration, decimal boundary cases,
 *      and supply conservation invariants.
 */
contract MigrationVaultFuzzTest is Test, Roles {
    MigrationVault internal vault;
    IERC20 internal oldToken;
    TelcoinV3 internal newToken;

    address internal admin = makeAddr("admin");
    address internal pauser = makeAddr("pauser");
    address internal unpauser = makeAddr("unpauser");

    address constant TELV2_ADDRESS = 0x467Bccd9d29f223BcE8043b84E8C8B282827790F;
    uint8 internal constant OLD_DECIMALS = 2;
    uint8 internal constant NEW_DECIMALS = 18;
    uint256 internal constant DECIMAL_MULTIPLIER = 10 ** (NEW_DECIMALS - OLD_DECIMALS);
    // Largest holder is Polygon bridge ~35B, so bound to 50B
    uint256 internal constant MAX_OLD_TOKEN_AMOUNT = 50_000_000_000 * 10 ** OLD_DECIMALS;
    uint256 internal constant VAULT_RESERVE = 90_000_000_000 ether; // 90B TEL v3

    // Fork
    string ethereumRpcUrl = vm.envString("ETHEREUM_RPC_URL");
    uint256 ethereumFork;

    function setUp() public {
        // Fork ethereum mainnet
        ethereumFork = vm.createFork(ethereumRpcUrl);
        vm.selectFork(ethereumFork);

        // Use real TEL v2 on mainnet
        oldToken = IERC20(TELV2_ADDRESS);

        // Deploy TelcoinV3 with no initial supply (all minted to vault)
        vm.prank(admin);
        newToken = new TelcoinV3(0, admin);

        // Deploy MigrationVault behind UUPS proxy
        MigrationVault implementation = new MigrationVault(address(oldToken), address(newToken));
        bytes memory initData = abi.encodeCall(
            MigrationVault.initialize,
            (admin, pauser, unpauser)
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        vault = MigrationVault(address(proxy));

        // Mint TEL v3 reserves to vault
        vm.startPrank(admin);
        newToken.grantRole(MINTER_ROLE, admin);
        newToken.mint(address(vault), VAULT_RESERVE);
        newToken.revokeRole(MINTER_ROLE, admin);
        vm.stopPrank();
    }

    // -----------------------------
    // Single User Migration Fuzzing
    // -----------------------------

    /// @dev Fuzz: verifies a single migration with arbitrary amount produces correct balances and output.
    function testFuzz_singleUserMigration(uint256 amount) public {
        amount = bound(amount, 1, MAX_OLD_TOKEN_AMOUNT);

        address user = address(uint160(uint256(keccak256("fuzz_user"))));
        deal(address(oldToken), user, amount);

        uint256 preVaultOld = oldToken.balanceOf(address(vault));
        uint256 preVaultNew = newToken.balanceOf(address(vault));
        uint256 expectedOut = amount * DECIMAL_MULTIPLIER;
        uint256 quote = vault.previewMigrate(amount);

        vm.startPrank(user);
        oldToken.approve(address(vault), amount);
        uint256 amountOut = vault.migrate(user, amount);
        vm.stopPrank();

        // Output correctness
        assertEq(amountOut, expectedOut, "Returned amount mismatch");
        assertEq(amountOut, quote, "Quote mismatch");

        // User balances
        assertEq(oldToken.balanceOf(user), 0, "User should have no old tokens");
        assertEq(newToken.balanceOf(user), expectedOut, "Incorrect new token balance");

        // Vault balances
        assertEq(oldToken.balanceOf(address(vault)), preVaultOld + amount, "Vault old token balance mismatch");
        assertEq(newToken.balanceOf(address(vault)), preVaultNew - expectedOut, "Vault new token balance mismatch");
    }

    // --------------------------------
    // Concurrent Multi-User Migrations
    // --------------------------------

    /// @dev Fuzz: verifies multiple users migrating sequentially maintains correct per-user and global accounting.
    function testFuzz_concurrentMigrations(uint256 numUsers, uint256 seed) public {
        numUsers = bound(numUsers, 2, 20);
        vm.assume(seed != 0);

        address[] memory users = new address[](numUsers);
        uint256[] memory balances = new uint256[](numUsers);
        uint256 totalOldMigrated;
        uint256 totalNewDistributed;

        uint256 preVaultOld = oldToken.balanceOf(address(vault));
        uint256 preVaultNew = newToken.balanceOf(address(vault));

        for (uint256 i; i < numUsers; i++) {
            users[i] = address(uint160(uint256(keccak256(abi.encode(seed, i)))));
            balances[i] = (uint256(keccak256(abi.encode(seed, i, "amount"))) % (MAX_OLD_TOKEN_AMOUNT / numUsers)) + 1;

            vm.deal(users[i], 0);
            deal(address(oldToken), users[i], balances[i]);

            vm.prank(users[i]);
            oldToken.approve(address(vault), balances[i]);
        }

        for (uint256 i; i < numUsers; i++) {
            uint256 expectedNew = balances[i] * DECIMAL_MULTIPLIER;
            uint256 preStepVaultOld = oldToken.balanceOf(address(vault));

            vm.prank(users[i]);
            vault.migrate(users[i], balances[i]);

            totalOldMigrated += balances[i];
            totalNewDistributed += expectedNew;

            // Per-migration invariants
            assertEq(oldToken.balanceOf(address(vault)), preStepVaultOld + balances[i], "Per-step vault old mismatch");
            assertEq(newToken.balanceOf(users[i]), expectedNew, "User new token balance mismatch");
            assertEq(oldToken.balanceOf(users[i]), 0, "User still holds old tokens");
        }

        // Global invariants
        assertEq(oldToken.balanceOf(address(vault)), preVaultOld + totalOldMigrated, "Total vault old mismatch");
        assertEq(newToken.balanceOf(address(vault)), preVaultNew - totalNewDistributed, "Total vault new mismatch");
    }

    // --------------------------------------------
    // Reserve Depletion — Migrate Until Exhaustion
    // --------------------------------------------

    /// @dev Fuzz: verifies migrations succeed until reserves are depleted, then correctly revert.
    function testFuzz_reserveDepletion(uint256 seed) public {
        vm.assume(seed != 0);

        // Use a smaller vault so we can deplete it
        MigrationVault implementation = new MigrationVault(address(oldToken), address(newToken));
        MigrationVault smallVault;
        {
            uint256 smallReserve = 1_000 ether; // 1,000 TEL v3
            vm.startPrank(admin);
            newToken.grantRole(MINTER_ROLE, admin);

            bytes memory initData = abi.encodeCall(
                MigrationVault.initialize,
                (admin, pauser, unpauser)
            );
            ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
            smallVault = MigrationVault(address(proxy));

            newToken.mint(address(smallVault), smallReserve);
            newToken.revokeRole(MINTER_ROLE, admin);
            vm.stopPrank();
        }

        // Migrate in random chunks until reserves run out
        uint256 totalMigrated;
        uint256 reserve = 1_000 ether;

        for (uint256 i; i < 50; i++) {
            uint256 chunkOld = (uint256(keccak256(abi.encode(seed, i))) % 500 + 1) * 10 ** OLD_DECIMALS;
            uint256 chunkNew = chunkOld * DECIMAL_MULTIPLIER;

            address migrator = address(uint160(uint256(keccak256(abi.encode(seed, i, "addr")))));
            vm.deal(migrator, 0);
            deal(address(oldToken), migrator, chunkOld);

            vm.prank(migrator);
            oldToken.approve(address(smallVault), chunkOld);

            if (chunkNew > reserve) {
                // Should revert — insufficient reserves
                vm.prank(migrator);
                vm.expectRevert(MigrationVault.InsufficientReserves.selector);
                smallVault.migrate(migrator, chunkOld);
                break;
            }

            vm.prank(migrator);
            smallVault.migrate(migrator, chunkOld);

            totalMigrated += chunkNew;
            reserve -= chunkNew;

            assertEq(newToken.balanceOf(migrator), chunkNew, "Migrator balance mismatch");
        }

        // Vault new token balance matches remaining reserve
        assertEq(newToken.balanceOf(address(smallVault)), reserve, "Final reserve mismatch");
    }

    // ---------------------------------------
    // Pause/Unpause During Migration Attempts
    // ---------------------------------------

    /// @dev Fuzz: verifies migrate reverts while paused and succeeds after unpausing, across random attempts.
    function testFuzz_pauseDuringMigrations(uint256 numAttempts, uint256 seed) public {
        numAttempts = bound(numAttempts, 1, 10);

        uint256 totalExpectedNew;

        for (uint256 i; i < numAttempts; i++) {
            address user = address(uint160(uint256(keccak256(abi.encode(seed, i)))));
            uint256 amount = ((uint256(keccak256(abi.encode(seed, i, "amt"))) % 1000) + 1) * 10 ** OLD_DECIMALS;

            vm.deal(user, 0);
            deal(address(oldToken), user, amount);

            bool shouldPause = uint256(keccak256(abi.encode(seed, i, "pause"))) % 2 == 0;

            if (shouldPause) {
                vm.prank(pauser);
                vault.pause();

                vm.startPrank(user);
                oldToken.approve(address(vault), amount);
                vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
                vault.migrate(user, amount);
                vm.stopPrank();

                vm.prank(unpauser);
                vault.unpause();
            }

            vm.startPrank(user);
            oldToken.approve(address(vault), amount);
            vault.migrate(user, amount);
            vm.stopPrank();

            uint256 expectedNew = amount * DECIMAL_MULTIPLIER;
            totalExpectedNew += expectedNew;

            assertEq(oldToken.balanceOf(user), 0, "User still holds old tokens");
            assertEq(newToken.balanceOf(user), expectedNew, "User new token balance mismatch");
        }

        // All successful migrations should be reflected in vault reserves
        assertEq(newToken.balanceOf(address(vault)), VAULT_RESERVE - totalExpectedNew, "Vault reserve mismatch");
    }

    // ---------------------------------
    // Decimal Conversion Boundary Cases
    // ---------------------------------

    /// @dev Verifies correct conversion for edge-case amounts including the smallest unit and precision boundaries.
    function testFuzz_decimalConversionEdgeCases() public {
        uint256 totalExpectedNew;

        // Test 1: Smallest possible amount (1 unit of TEL v2 = 0.01 TEL)
        address user1 = address(0x1);
        deal(address(oldToken), user1, 1);

        vm.startPrank(user1);
        oldToken.approve(address(vault), 1);
        vault.migrate(user1, 1);
        vm.stopPrank();

        assertEq(newToken.balanceOf(user1), DECIMAL_MULTIPLIER, "Smallest amount: balance mismatch");
        totalExpectedNew += DECIMAL_MULTIPLIER;

        // Test 2: Amounts that might cause precision issues
        uint256[5] memory testAmounts = [
            uint256(99), // 0.99 TEL v2
            uint256(100), // 1.00 TEL v2
            uint256(101), // 1.01 TEL v2
            uint256(1234567), // 12,345.67 TEL v2
            uint256(999999999) // 9,999,999.99 TEL v2
        ];

        for (uint256 i; i < testAmounts.length; i++) {
            address user = address(uint160(i + 2));
            uint256 oldAmount = testAmounts[i];

            deal(address(oldToken), user, oldAmount);

            vm.startPrank(user);
            oldToken.approve(address(vault), oldAmount);
            vault.migrate(user, oldAmount);
            vm.stopPrank();

            uint256 expectedNew = oldAmount * DECIMAL_MULTIPLIER;
            assertEq(newToken.balanceOf(user), expectedNew, "Decimal conversion precision error");

            // Reverse calculation should match (no rounding with whole multiplier)
            assertEq(expectedNew / DECIMAL_MULTIPLIER, oldAmount, "Reverse calculation mismatch");

            totalExpectedNew += expectedNew;
        }

        assertEq(newToken.balanceOf(address(vault)), VAULT_RESERVE - totalExpectedNew, "Vault reserve mismatch");
    }

    // -----------------------------
    // Supply Conservation Invariant
    // -----------------------------

    /// @dev Fuzz: verifies vault accounting is conserved across many migrations — old tokens in + new tokens out = constant.
    function testFuzz_supplyConservation(uint256[] memory userAmounts) public {
        vm.assume(userAmounts.length > 0 && userAmounts.length <= 100);

        uint256 preVaultOld = oldToken.balanceOf(address(vault));
        uint256 preVaultNew = newToken.balanceOf(address(vault));

        uint256 totalMigratedOld;

        for (uint256 i; i < userAmounts.length; i++) {
            userAmounts[i] = bound(userAmounts[i], 0, MAX_OLD_TOKEN_AMOUNT / userAmounts.length);
            if (userAmounts[i] == 0) continue;

            uint256 expectedNew = userAmounts[i] * DECIMAL_MULTIPLIER;
            // Stop if vault would be depleted
            if (expectedNew > newToken.balanceOf(address(vault))) break;

            address user = address(uint160(i + 1));
            deal(address(oldToken), user, userAmounts[i]);

            vm.startPrank(user);
            oldToken.approve(address(vault), userAmounts[i]);
            vault.migrate(user, userAmounts[i]);
            vm.stopPrank();

            totalMigratedOld += userAmounts[i];
        }

        uint256 totalNewDistributed = totalMigratedOld * DECIMAL_MULTIPLIER;

        // Invariant 1: Vault received all old tokens
        assertEq(oldToken.balanceOf(address(vault)), preVaultOld + totalMigratedOld, "Vault old balance mismatch");

        // Invariant 2: Vault disbursed correct amount of new tokens
        assertEq(newToken.balanceOf(address(vault)), preVaultNew - totalNewDistributed, "Vault new balance mismatch");

        // Invariant 3: 1:1 value conservation (WAD-normalized)
        uint256 oldValueWad = totalMigratedOld * vault.OLD_TO_WAD();
        uint256 newValueWad = totalNewDistributed * vault.NEW_TO_WAD();
        assertEq(oldValueWad, newValueWad, "WAD value conservation violated");
    }

    // -------------------------
    // Partial Balance Migration
    // -------------------------

    /// @dev Fuzz: verifies a user can migrate in multiple partial chunks with correct cumulative accounting.
    function testFuzz_partialMigrations(uint256 totalAmount, uint256 numChunks) public {
        totalAmount = bound(totalAmount, 10, MAX_OLD_TOKEN_AMOUNT);
        numChunks = bound(numChunks, 2, 20);

        address user = address(uint160(uint256(keccak256("partial_user"))));
        deal(address(oldToken), user, totalAmount);

        vm.prank(user);
        oldToken.approve(address(vault), totalAmount);

        uint256 totalMigrated;
        uint256 totalReceived;
        uint256 remaining = totalAmount;

        for (uint256 i; i < numChunks && remaining > 0; i++) {
            uint256 chunk;
            if (i == numChunks - 1) {
                chunk = remaining;
            } else {
                chunk = remaining / (numChunks - i);
                if (chunk == 0) chunk = 1;
            }

            vm.prank(user);
            uint256 amountOut = vault.migrate(user, chunk);

            totalMigrated += chunk;
            totalReceived += amountOut;
            remaining -= chunk;

            assertEq(amountOut, chunk * DECIMAL_MULTIPLIER, "Chunk output mismatch");
        }

        // User should have migrated everything
        assertEq(oldToken.balanceOf(user), totalAmount - totalMigrated, "User old token remainder mismatch");
        assertEq(newToken.balanceOf(user), totalReceived, "User new token total mismatch");
        assertEq(totalReceived, totalMigrated * DECIMAL_MULTIPLIER, "Total conversion mismatch");
    }

    // ------------------------
    // Maximum Migration Amount
    // ------------------------

    /// @dev Verifies migration works at the maximum realistic amount without overflow.
    function testFuzz_maximumMigrationAmount() public {
        // Maximum old tokens that won't overflow when converted
        uint256 maxSafe = type(uint256).max / DECIMAL_MULTIPLIER;
        uint256 testAmount = maxSafe > MAX_OLD_TOKEN_AMOUNT ? MAX_OLD_TOKEN_AMOUNT : maxSafe;

        address whale = address(uint160(uint256(keccak256("whale"))));
        deal(address(oldToken), whale, testAmount);

        uint256 expectedNew = testAmount * DECIMAL_MULTIPLIER;

        vm.startPrank(whale);
        oldToken.approve(address(vault), testAmount);
        uint256 amountOut = vault.migrate(whale, testAmount);
        vm.stopPrank();

        assertEq(amountOut, expectedNew, "Whale output mismatch");
        assertEq(newToken.balanceOf(whale), expectedNew, "Whale new token balance mismatch");
        assertEq(oldToken.balanceOf(whale), 0, "Whale still holds old tokens");
    }
}
