// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import "../src/nGMUNY.sol";
import "../src/TokenMigration.sol";
import "../deployments/Create3Utils.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract TokenMigrationFuzzTest is Test {
    // contracts
    IERC20 public oldToken;
    nGMUNY public newToken;
    TokenMigration public migration;
    Create3Impl public create3;

    // addresses
    address public owner = 0xF262D0995Da87FFF7a1d20635eA440Fac96CC5C1;
    address public deployer = 0x369921b758B1228882EFbd997a67075211b93835;

    // constants
    address constant GMUNY_ADDRESS = 0x467Bccd9d29f223BcE8043b84E8C8B282827790F;
    uint256 constant INITIAL_NGMUNY_SUPPLY = 99_000_000_000 * 10 ** 18; // 99B
    // largest holder is Polygon bridge ~35B so set bound to 50B
    uint256 constant MAX_OLDTOKEN_AMOUNT = 50_000_000_000 * 10 ** 2; // 50B with 2 decimals
    uint256 constant MAX_UINT256 = type(uint256).max;

    // fork
    string ETHEREUM_RPC_URI = vm.envString("ETHEREUM_RPC_URI");
    uint256 ethereum_fork;

    function setUp() public {
        // fork ethereum
        ethereum_fork = vm.createFork(ETHEREUM_RPC_URI);
        vm.selectFork(ethereum_fork);

        // existing token
        oldToken = IERC20(GMUNY_ADDRESS);

        // deploy create3 util contract
        create3 = new Create3Impl();

        vm.deal(deployer, 1 ether);
        vm.startPrank(deployer);

        // predict create3 address for token migration contract
        bytes32 migrationSalt = keccak256("TOKEN_MIGRATION_SALT");
        address expectedMigrationAddress = create3.addressOf(migrationSalt);

        // deploy new token using create3
        bytes32 tokenSalt = keccak256("NEW_TOKEN_SALT");
        bytes memory tokenArgs = abi.encodePacked(
            type(nGMUNY).creationCode,
            abi.encode(INITIAL_NGMUNY_SUPPLY, owner, expectedMigrationAddress)
        );
        address deployment = create3.deploy(tokenSalt, tokenArgs);
        newToken = nGMUNY(deployment);

        // deploy token migration contract
        bytes memory migrationArgs = abi.encodePacked(
            type(TokenMigration).creationCode,
            abi.encode(address(oldToken), address(newToken), owner)
        );
        address migrationAddress = create3.deploy(migrationSalt, migrationArgs);
        migration = TokenMigration(migrationAddress);

        vm.stopPrank();
    }

    /**
     * Fuzz test: Single user migration with various amounts
     */
    function testFuzz_SingleUserMigration(uint256 amount) public {
        // Bound the amount to reasonable values (non-zero and within supply)
        amount = bound(amount, 1, MAX_OLDTOKEN_AMOUNT);

        address user = address(uint160(uint256(keccak256("user"))));

        // Fund user with old tokens
        deal(address(oldToken), user, amount);

        // Record initial state
        uint256 initialBurnBalance = oldToken.balanceOf(
            migration.BURN_ADDRESS()
        );
        uint256 initialMigrationBalance = newToken.balanceOf(
            address(migration)
        );

        vm.startPrank(user);

        // Approve and migrate
        oldToken.approve(address(migration), amount);
        migration.migrate();

        vm.stopPrank();

        // Verify invariants
        uint256 expectedNewAmount = amount * migration.DECIMAL_MULTIPLIER();

        // User should have no old tokens (entire balance migrated)
        assertEq(oldToken.balanceOf(user), 0, "User should have no old tokens");

        // User should have correct new token amount
        assertEq(
            newToken.balanceOf(user),
            expectedNewAmount,
            "Incorrect new token balance"
        );

        // Old tokens should be burned
        assertEq(
            oldToken.balanceOf(migration.BURN_ADDRESS()),
            initialBurnBalance + amount,
            "Incorrect burn amount"
        );

        // Migration contract balance should decrease correctly
        assertEq(
            newToken.balanceOf(address(migration)),
            initialMigrationBalance - expectedNewAmount,
            "Migration balance mismatch"
        );
    }

    /**
     * Fuzz test: Concurrent migrations with race conditions
     */
    function testFuzz_ConcurrentMigrations(
        uint256 numUsers,
        uint256 seed
    ) public {
        numUsers = bound(numUsers, 2, 20);

        // skip if seed would cause issues
        vm.assume(seed != 0);
        vm.assume(seed < type(uint256).max / numUsers);

        address[] memory users = new address[](numUsers);
        uint256[] memory balances = new uint256[](numUsers);
        uint256 totalOldTokens = 0;

        // Setup users with random balances
        for (uint256 i = 0; i < numUsers; i++) {
            users[i] = address(
                uint160(uint256(keccak256(abi.encode(seed, i))))
            );
            balances[i] =
                (uint256(keccak256(abi.encode(seed, i, "amount"))) %
                    (MAX_OLDTOKEN_AMOUNT / numUsers)) +
                1;

            deal(address(oldToken), users[i], balances[i]);
            totalOldTokens += balances[i];

            // All users approve upfront
            vm.prank(users[i]);
            oldToken.approve(address(migration), balances[i]);
        }

        // Calculate if all can migrate
        uint256 availableNewTokens = newToken.balanceOf(address(migration));

        // Record initial state
        uint256 initialBurnBalance = oldToken.balanceOf(
            migration.BURN_ADDRESS()
        );

        // Interleaved migrations
        uint256 successfulMigrations = 0;
        uint256 totalMigratedOld = 0;
        uint256 totalMigratedNew = 0;

        // Simulate random order migrations
        for (uint256 round = 0; round < numUsers; round++) {
            uint256 userIndex = uint256(keccak256(abi.encode(seed, round))) %
                numUsers;

            if (balances[userIndex] == 0) continue; // Already migrated

            uint256 requiredNew = balances[userIndex] *
                migration.DECIMAL_MULTIPLIER();

            if (requiredNew <= newToken.balanceOf(address(migration))) {
                vm.prank(users[userIndex]);
                migration.migrate();

                successfulMigrations++;
                totalMigratedOld += balances[userIndex];
                totalMigratedNew += requiredNew;

                // Verify user got their tokens
                assertEq(newToken.balanceOf(users[userIndex]), requiredNew);
                assertEq(oldToken.balanceOf(users[userIndex]), 0);

                balances[userIndex] = 0; // Mark as migrated
            } else {
                // Migration should fail due to insufficient balance
                vm.prank(users[userIndex]);
                vm.expectRevert();
                migration.migrate();
            }
        }

        // Verify global invariants
        assertEq(
            oldToken.balanceOf(migration.BURN_ADDRESS()),
            initialBurnBalance + totalMigratedOld,
            "Total burned mismatch"
        );
        assertEq(
            availableNewTokens - newToken.balanceOf(address(migration)),
            totalMigratedNew,
            "Total migrated new tokens mismatch"
        );
    }

    /**
     * Edge case: Testing maximum possible migration (near overflow)
     */
    function testFuzz_MaximumMigrationAmount() public {
        // Maximum old tokens that won't overflow when converted
        uint256 maxSafeOldTokens = MAX_UINT256 / migration.DECIMAL_MULTIPLIER();

        // Ensure we don't exceed actual supply
        uint256 testAmount = maxSafeOldTokens > MAX_OLDTOKEN_AMOUNT
            ? MAX_OLDTOKEN_AMOUNT
            : maxSafeOldTokens;

        address whale = address(uint160(uint256(keccak256("whale"))));
        deal(address(oldToken), whale, testAmount);

        // Ensure migration contract has enough new tokens
        uint256 requiredNewTokens = testAmount * migration.DECIMAL_MULTIPLIER();
        vm.prank(owner);
        deal(address(newToken), address(migration), requiredNewTokens);

        vm.startPrank(whale);
        oldToken.approve(address(migration), testAmount);
        migration.migrate();
        vm.stopPrank();

        assertEq(newToken.balanceOf(whale), requiredNewTokens);
        assertEq(oldToken.balanceOf(whale), 0);
    }

    /**
     * Edge case: Migration with exactly matching contract balance
     */
    function testFuzz_ExactBalanceMatch(uint256 amount) public {
        amount = bound(
            amount,
            1,
            INITIAL_NGMUNY_SUPPLY / migration.DECIMAL_MULTIPLIER()
        );

        address user = address(uint160(uint256(keccak256("exact_user"))));

        // Set migration contract to have exactly what's needed
        uint256 exactNewTokens = amount * migration.DECIMAL_MULTIPLIER();
        vm.prank(owner);

        // First withdraw all tokens
        migration.withdrawRemainingNewToken(owner);

        // Then send back exactly what's needed
        vm.prank(owner);
        newToken.transfer(address(migration), exactNewTokens);

        // Fund user and migrate
        deal(address(oldToken), user, amount);

        vm.startPrank(user);
        oldToken.approve(address(migration), amount);
        migration.migrate();
        vm.stopPrank();

        // Contract should have exactly 0 new tokens left
        assertEq(newToken.balanceOf(address(migration)), 0);
        assertEq(newToken.balanceOf(user), exactNewTokens);
    }

    /**
     * Edge case: Migration fails when contract is 1 wei short
     */
    function testFuzz_InsufficientByOneWei(uint256 amount) public {
        amount = bound(amount, 2, MAX_OLDTOKEN_AMOUNT);

        address user = address(uint160(uint256(keccak256("onewei_user"))));
        uint256 requiredNewTokens = amount * migration.DECIMAL_MULTIPLIER();

        // Set migration contract to be 1 wei short
        vm.startPrank(owner);
        migration.withdrawRemainingNewToken(owner);
        newToken.transfer(address(migration), requiredNewTokens - 1);
        vm.stopPrank();

        // Fund user
        deal(address(oldToken), user, amount);

        vm.startPrank(user);
        oldToken.approve(address(migration), amount);

        // Should revert with insufficient balance
        vm.expectRevert(
            abi.encodeWithSelector(
                TokenMigration.InsufficientContractBalance.selector,
                requiredNewTokens,
                requiredNewTokens - 1
            )
        );
        migration.migrate();
        vm.stopPrank();
    }

    /**
     * Fuzz test: Pause/unpause during migration attempts
     */
    function testFuzz_PauseDuringMigrations(
        uint256 numAttempts,
        uint256 seed
    ) public {
        numAttempts = bound(numAttempts, 1, 10);

        for (uint256 i = 0; i < numAttempts; i++) {
            address user = address(
                uint160(uint256(keccak256(abi.encode(seed, i))))
            );
            uint256 amount = ((uint256(keccak256(abi.encode(seed, i, "amt"))) %
                1000) + 1) * 10 ** 2;

            deal(address(oldToken), user, amount);

            // Randomly pause/unpause
            bool shouldPause = uint256(
                keccak256(abi.encode(seed, i, "pause"))
            ) %
                2 ==
                0;

            if (shouldPause) {
                vm.prank(owner);
                migration.pause();

                vm.startPrank(user);
                oldToken.approve(address(migration), amount);
                vm.expectRevert();
                migration.migrate();
                vm.stopPrank();

                vm.prank(owner);
                migration.unpause();
            }

            // Now should work
            vm.startPrank(user);
            oldToken.approve(address(migration), amount);
            migration.migrate();
            vm.stopPrank();

            assertEq(oldToken.balanceOf(user), 0);
            assertEq(
                newToken.balanceOf(user),
                amount * migration.DECIMAL_MULTIPLIER()
            );
        }
    }

    /**
     * Edge case: Decimal conversion boundary tests
     */
    function testFuzz_DecimalConversionEdgeCases() public {
        // Test 1: Smallest possible amount (1 unit of old token = 0.01)
        address user1 = address(0x1);
        deal(address(oldToken), user1, 1);

        vm.startPrank(user1);
        oldToken.approve(address(migration), 1);
        migration.migrate();
        vm.stopPrank();

        // Should receive 10^16 new tokens (0.01 * 10^18 = 10^16)
        assertEq(newToken.balanceOf(user1), 10 ** 16);

        // Test 2: Amounts that might cause precision issues in other implementations
        uint256[5] memory testAmounts = [
            uint256(99), // 0.99 old tokens
            uint256(100), // 1.00 old tokens
            uint256(101), // 1.01 old tokens
            uint256(1234567), // 12,345.67 old tokens
            uint256(999999999) // 9,999,999.99 old tokens
        ];

        for (uint256 i = 0; i < testAmounts.length; i++) {
            address user = address(uint160(i + 2));
            uint256 oldAmount = testAmounts[i];

            deal(address(oldToken), user, oldAmount);

            vm.startPrank(user);
            oldToken.approve(address(migration), oldAmount);
            migration.migrate();
            vm.stopPrank();

            uint256 expectedNewAmount = oldAmount * 10 ** 16;
            assertEq(
                newToken.balanceOf(user),
                expectedNewAmount,
                "Decimal conversion precision error"
            );

            // Verify no rounding issues - reverse calculation should match
            assertEq(
                expectedNewAmount / 10 ** 16,
                oldAmount,
                "Reverse calculation mismatch"
            );
        }
    }

    /**
     * Fuzz test: Recovery of various random ERC20 tokens with different decimals
     */
    function testFuzz_RecoverVariousTokens(
        uint8 decimals,
        uint256 amount,
        uint256 seed
    ) public {
        // Test various decimal places
        decimals = uint8(bound(decimals, 0, 36));

        // prevent overflow based on decimals
        uint256 maxAmount = decimals > 30 ? 10 ** 10 : 10 ** (30 - decimals);
        amount = bound(amount, 1, maxAmount);

        // Create tokens with different properties
        MockERC20 randomToken = new MockERC20(
            string(abi.encodePacked("Token", decimals)),
            string(abi.encodePacked("TKN", decimals)),
            decimals
        );

        // Send tokens to migration contract
        randomToken.mint(address(migration), amount);

        // Generate random recipient
        address recipient = address(uint160(seed));
        vm.assume(recipient != address(0));
        vm.assume(recipient != address(migration));

        // Verify cannot recover newToken
        vm.prank(owner);
        vm.expectRevert(TokenMigration.CannotRecoverProtectedToken.selector);
        migration.recoverERC20(recipient, address(newToken), 1);

        // Should successfully recover random token
        vm.prank(owner);
        migration.recoverERC20(recipient, address(randomToken), amount);

        assertEq(randomToken.balanceOf(recipient), amount);
        assertEq(randomToken.balanceOf(address(migration)), 0);
    }

    /**
     * Invariant test: Total supply conservation
     */
    function testFuzz_TotalSupplyConservation(
        uint256[] memory userAmounts
    ) public {
        vm.assume(userAmounts.length > 0 && userAmounts.length <= 100);

        uint256 initialTotalSupply = oldToken.totalSupply();
        uint256 initialNewSupply = newToken.totalSupply();
        uint256 initialBurnBalance = oldToken.balanceOf(
            migration.BURN_ADDRESS()
        );

        uint256 totalMigrated = 0;

        for (uint256 i = 0; i < userAmounts.length; i++) {
            userAmounts[i] = bound(
                userAmounts[i],
                0,
                MAX_OLDTOKEN_AMOUNT / userAmounts.length
            );

            if (userAmounts[i] == 0) continue;

            address user = address(uint160(i + 1));
            uint256 newTokensRequired = userAmounts[i] *
                migration.DECIMAL_MULTIPLIER();

            // Skip if would exceed available
            if (newTokensRequired > newToken.balanceOf(address(migration))) {
                continue;
            }

            deal(address(oldToken), user, userAmounts[i]);

            vm.startPrank(user);
            oldToken.approve(address(migration), userAmounts[i]);
            migration.migrate();
            vm.stopPrank();

            totalMigrated += userAmounts[i];
        }

        // Invariant 1: Old token total supply unchanged (tokens moved to burn address)
        assertEq(oldToken.totalSupply(), initialTotalSupply);

        // Invariant 2: New token total supply unchanged (only transferred, not minted)
        assertEq(newToken.totalSupply(), initialNewSupply);

        // Invariant 3: Burn address received all migrated old tokens
        assertEq(
            oldToken.balanceOf(migration.BURN_ADDRESS()),
            initialBurnBalance + totalMigrated
        );

        // Invariant 4: For every old token burned, exactly DECIMAL_MULTIPLIER new tokens distributed
        uint256 totalNewDistributed = totalMigrated *
            migration.DECIMAL_MULTIPLIER();
        assertEq(
            INITIAL_NGMUNY_SUPPLY - newToken.balanceOf(address(migration)),
            totalNewDistributed
        );
    }

    /**
     * Edge case: Attempting double migration
     */
    function testFuzz_DoubleMigrationPrevented(uint256 amount) public {
        amount = bound(amount, 1, MAX_OLDTOKEN_AMOUNT);

        address user = address(uint160(uint256(keccak256("double_user"))));
        deal(address(oldToken), user, amount);

        vm.startPrank(user);

        // First migration
        oldToken.approve(address(migration), amount);
        migration.migrate();

        // User has no more old tokens
        assertEq(oldToken.balanceOf(user), 0);

        // Attempt second migration should fail
        vm.expectRevert(TokenMigration.InvalidAmount.selector);
        migration.migrate();

        vm.stopPrank();
    }
}

// Mock ERC20 for testing token recovery
contract MockERC20 is ERC20 {
    uint8 private _decimals;

    constructor(
        string memory name,
        string memory symbol,
        uint8 decimals_
    ) ERC20(name, symbol) {
        _decimals = decimals_;
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }
}
