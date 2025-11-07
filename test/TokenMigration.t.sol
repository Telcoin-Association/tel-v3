// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import "../src/NewToken.sol";
import "../src/TokenMigration.sol";
import "../deployments/Create3Utils.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

contract TokenMigrationTest is Test {
    // contracts
    IERC20 public oldToken;
    NewToken public newToken;
    TokenMigration public migration;
    Create3Impl public create3;

    // addresses
    address public user1 = 0xf10a701111111111111111111111111111111111;
    address public user2 = 0x7e75333333333333333333333333333333333300;
    address public owner = 0xF262D0995Da87FFF7a1d20635eA440Fac96CC5C1;
    address public deployer = 0x369921b758B1228882EFbd997a67075211b93835;

    // constants
    address constant OLDTOKEN_ADDRESS =
        0x467Bccd9d29f223BcE8043b84E8C8B282827790F; // ethereum
    uint256 constant OldToken_SUPPLY = 100_000_000_000 * 10 ** 2; // 100B with 2 decimals
    uint256 constant INITIAL_NEW_TOKEN_SUPPLY = 10_000_000_000 * 10 ** 18; // 10B with 18 decimals
    uint256 constant INITIAL_USER_BAL = 1_000_000 * 10 ** 2;

    // fork
    string ETHEREUM_RPC_URI = vm.envString("ETHEREUM_RPC_URI");
    uint256 ethereum_fork;

    function setUp() public {
        // fork ethereum
        ethereum_fork = vm.createFork(ETHEREUM_RPC_URI);
        vm.selectFork(ethereum_fork);

        // existing token
        oldToken = IERC20(OLDTOKEN_ADDRESS);

        // verify oldToken has 2 decimals
        assertEq(
            IERC20Metadata(address(oldToken)).decimals(),
            2,
            "OldToken should have 2 decimals"
        );

        // deploy create3 util contract
        create3 = new Create3Impl();

        // give deployer some eth
        vm.deal(deployer, 1 ether);

        vm.startPrank(deployer);

        // predict create3 address for token migration contract
        bytes32 migrationSalt = keccak256("TOKEN_MIGRATION_SALT");
        address expectedMigrationAddress = create3.addressOf(migrationSalt);

        // deploy new token using create3 and mint to migration contract
        bytes32 tokenSalt = keccak256("NEW_TOKEN_SALT");
        bytes memory tokenArgs = abi.encodePacked(
            type(NewToken).creationCode,
            abi.encode(
                INITIAL_NEW_TOKEN_SUPPLY,
                owner,
                expectedMigrationAddress
            )
        );
        address deployment = create3.deploy(tokenSalt, tokenArgs);
        newToken = NewToken(deployment);

        // deploy token migration contract
        bytes memory migrationArgs = abi.encodePacked(
            type(TokenMigration).creationCode,
            abi.encode(address(oldToken), address(newToken), owner)
        );
        address migrationAddress = create3.deploy(migrationSalt, migrationArgs);
        assertEq(expectedMigrationAddress, migrationAddress);
        migration = TokenMigration(migrationAddress);

        vm.stopPrank();

        // fund accounts
        deal(address(oldToken), user1, INITIAL_USER_BAL);
        deal(address(oldToken), user2, INITIAL_USER_BAL);
    }

    function testMigration() public {
        vm.startPrank(user1);

        // check initial balances
        assertEq(oldToken.balanceOf(user1), INITIAL_USER_BAL);
        assertEq(newToken.balanceOf(user1), 0);
        assertEq(
            newToken.balanceOf(address(migration)),
            INITIAL_NEW_TOKEN_SUPPLY
        );

        // take current burn balance since this forks live
        uint256 currentBurnBalance = oldToken.balanceOf(
            migration.BURN_ADDRESS()
        );

        // approve migration contract
        oldToken.approve(address(migration), INITIAL_USER_BAL);

        // perform migration
        migration.migrate();

        // check user's final balances
        assertEq(oldToken.balanceOf(user1), 0);
        assertEq(
            newToken.balanceOf(user1),
            INITIAL_USER_BAL * migration.DECIMAL_MULTIPLIER()
        );
        // check tokens were burned
        uint256 expectedBurnBalance = currentBurnBalance + INITIAL_USER_BAL;
        assertEq(
            oldToken.balanceOf(migration.BURN_ADDRESS()),
            expectedBurnBalance
        );

        vm.stopPrank();
    }

    function testPauseUnpause() public {
        vm.prank(owner);
        migration.pause();

        vm.startPrank(user1);
        oldToken.approve(address(migration), INITIAL_USER_BAL);

        vm.expectRevert(Pausable.EnforcedPause.selector);
        migration.migrate();
        vm.stopPrank();

        vm.prank(owner);
        migration.unpause();

        vm.prank(user1);
        migration.migrate();
    }

    function testUserHasNotApprovedFullAmount() public {
        // check initial balances
        assertEq(oldToken.balanceOf(user1), INITIAL_USER_BAL);
        assertEq(newToken.balanceOf(user1), 0);

        vm.startPrank(user1);
        // approve less than full balance for migration contract
        uint256 notEnough = INITIAL_USER_BAL - 1000;
        oldToken.approve(address(migration), notEnough);
        vm.expectRevert(
            abi.encodeWithSelector(
                TokenMigration.InsufficientAllowance.selector,
                INITIAL_USER_BAL,
                notEnough
            )
        );
        migration.migrate();
        vm.stopPrank();
    }

    function testWithdrawRemainingNewToken() public {
        // First do a migration
        vm.startPrank(user1);
        oldToken.approve(address(migration), INITIAL_USER_BAL);
        migration.migrate();
        vm.stopPrank();

        // Owner withdraws remaining
        uint256 remainingBalance = newToken.balanceOf(address(migration));

        vm.prank(owner);
        migration.withdrawRemainingNewToken(owner);

        assertEq(newToken.balanceOf(owner), remainingBalance);
        assertEq(newToken.balanceOf(address(migration)), 0);
    }

    function testRecoverStuckOldToken() public {
        address migrationContract = address(migration);
        // sanity check
        assertEq(oldToken.balanceOf(migrationContract), 0);

        // transfer old token instead of migrating
        vm.startPrank(user1);
        oldToken.approve(migrationContract, INITIAL_USER_BAL);
        oldToken.transfer(migrationContract, INITIAL_USER_BAL);
        vm.stopPrank();

        // check old tokens received
        assertEq(oldToken.balanceOf(migrationContract), INITIAL_USER_BAL);
        assertEq(oldToken.balanceOf(user1), 0);

        // recover old tokens
        vm.prank(owner);
        migration.recoverERC20(user1, OLDTOKEN_ADDRESS, INITIAL_USER_BAL);
        assertEq(oldToken.balanceOf(user1), INITIAL_USER_BAL);
        assertEq(oldToken.balanceOf(migrationContract), 0);
    }

    function testOnlyOwnerFunctions() public {
        vm.startPrank(user1);

        vm.expectRevert(
            abi.encodeWithSelector(
                Ownable.OwnableUnauthorizedAccount.selector,
                user1
            )
        );
        migration.pause();

        vm.expectRevert(
            abi.encodeWithSelector(
                Ownable.OwnableUnauthorizedAccount.selector,
                user1
            )
        );
        migration.unpause();

        vm.expectRevert(
            abi.encodeWithSelector(
                Ownable.OwnableUnauthorizedAccount.selector,
                user1
            )
        );
        migration.withdrawRemainingNewToken(user1);

        vm.expectRevert(
            abi.encodeWithSelector(
                Ownable.OwnableUnauthorizedAccount.selector,
                user1
            )
        );

        migration.recoverERC20(user1, OLDTOKEN_ADDRESS, 10);

        vm.stopPrank();
    }

    function testMigrateWithZeroAmount() public {
        address zeroBalance = address(400);
        // sanity check
        assertEq(oldToken.balanceOf(zeroBalance), 0);

        vm.prank(zeroBalance);
        vm.expectRevert(TokenMigration.InvalidAmount.selector);
        migration.migrate();
    }

    function testMaxBalance() public {
        vm.startPrank(user1);
        uint256 userBalance = oldToken.balanceOf(user1);
        uint256 tooMuch = userBalance + 1000;
        oldToken.approve(address(migration), tooMuch);
        migration.migrate();
        vm.stopPrank();

        // amount up to user's balance migrated
        uint256 expectedBalance = userBalance * migration.DECIMAL_MULTIPLIER();
        assertEq(newToken.balanceOf(user1), expectedBalance);
    }

    function testRecoverNewTokenFails() public {
        address migrationContract = address(migration);
        // sanity check
        assert(newToken.balanceOf(migrationContract) > INITIAL_USER_BAL);

        // owner tries to recover new token
        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(
                TokenMigration.CannotRecoverProtectedToken.selector
            )
        );
        migration.recoverERC20(user1, address(newToken), INITIAL_USER_BAL);
    }
}
