// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {TelcoinV3} from "../../src/TelcoinV3.sol";
import {TokenMigration} from "../../src/TokenMigration.sol";
import {Create3Utils} from "../utils/Create3Utils.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Roles} from "../../src/helpers/Roles.sol";

contract TokenMigrationTest is Test, Roles {
    // contracts
    IERC20 public oldToken;
    TelcoinV3 public telcoinV3;
    TokenMigration public migration;
    Create3Utils public create3;

    // addresses
    address public user1 = 0xf10a701111111111111111111111111111111111;
    address public user2 = 0x7e75333333333333333333333333333333333300;
    address public owner = 0xF262D0995Da87FFF7a1d20635eA440Fac96CC5C1;
    address public deployer = 0x369921b758B1228882EFbd997a67075211b93835;

    // constants
    address constant OLDTOKEN_ADDRESS = 0x467Bccd9d29f223BcE8043b84E8C8B282827790F; // ethereum
    uint256 constant OLDTOKEN_SUPPLY = 100_000_000_000 * 10 ** 2; // 100B with 2 decimals
    uint256 constant INITIAL_NEW_TOKEN_SUPPLY = 10_000_000_000 * 10 ** 18; // 10B with 18 decimals
    uint256 constant INITIAL_USER_BAL = 1_000_000 * 10 ** 2;

    // fork
    string ethereumRpcUrl = vm.envString("ETHEREUM_RPC_URL");
    uint256 ethereumFork;

    function setUp() public {
        // fork ethereum
        ethereumFork = vm.createFork(ethereumRpcUrl);
        vm.selectFork(ethereumFork);

        // existing token
        oldToken = IERC20(OLDTOKEN_ADDRESS);

        // verify oldToken has 2 decimals
        assertEq(IERC20Metadata(address(oldToken)).decimals(), 2, "OldToken should have 2 decimals");

        // deploy create3 util contract
        create3 = new Create3Utils();

        // give deployer some eth
        vm.deal(deployer, 1 ether);

        vm.startPrank(deployer);

        // deploy new token using create3 and mint to migration contract
        bytes32 tokenSalt = keccak256("NEW_TOKEN_SALT");
        bytes memory tokenArgs = abi.encodePacked(
            type(TelcoinV3).creationCode, abi.encode(INITIAL_NEW_TOKEN_SUPPLY, owner)
        );
        address deployment = create3.deploy(tokenSalt, tokenArgs);
        telcoinV3 = TelcoinV3(deployment);

        // verify TelcoinV3 has 18 decimals
        assertEq(IERC20Metadata(address(telcoinV3)).decimals(), 18, "Telcoin V3 should have 18 decimals");

        // deploy token migration contract
        bytes32 migrationSalt = keccak256("TOKEN_MIGRATION_SALT");
        bytes memory migrationArgs = abi.encodePacked(
            type(TokenMigration).creationCode, abi.encode(address(oldToken), address(telcoinV3), owner, 365 days)
        );
        address migrationAddress = create3.deploy(migrationSalt, migrationArgs);
        migration = TokenMigration(migrationAddress);

        vm.stopPrank();

        // set minter role on TelcoinV3
        vm.prank(owner);
        telcoinV3.grantRole(MINTER_ROLE, address(migration));

        // fund accounts
        deal(address(oldToken), user1, INITIAL_USER_BAL);
        deal(address(oldToken), user2, INITIAL_USER_BAL);
    }

    // -------------------
    // Initial State Tests
    // -------------------

    /// @dev Verifies constructor reverts when _oldToken and _telcoinV3 are the same address.
    function test_Constructor_RevertsWhenSameAddress() public {
        vm.expectRevert(TokenMigration.SameAddress.selector);
        new TokenMigration(address(telcoinV3), address(telcoinV3), owner, 365 days);
    }

    // ---------------
    // Migration Tests
    // ---------------

    /// @dev Verifies a full migration: balances, burn address, supply, and tracking state update correctly.
    function test_Migration() public {
        vm.startPrank(user1);

        // check initial balances
        assertEq(oldToken.balanceOf(user1), INITIAL_USER_BAL);
        assertEq(telcoinV3.balanceOf(user1), 0);
        uint256 preSupply = telcoinV3.totalSupply();

        // take current burn balance since this forks live
        uint256 currentBurnBalance = oldToken.balanceOf(migration.BURN_ADDRESS());
        uint256 quote = migration.getAmountOut(INITIAL_USER_BAL);

        // approve migration contract
        oldToken.approve(address(migration), INITIAL_USER_BAL);

        // perform migration
        uint256 amountNewTokens = migration.migrate();

        // check user's final balances
        assertEq(quote, amountNewTokens);
        assertEq(amountNewTokens, INITIAL_USER_BAL * migration.DECIMAL_MULTIPLIER());
        assertEq(oldToken.balanceOf(user1), 0);
        assertEq(telcoinV3.balanceOf(user1), amountNewTokens);
        assertEq(telcoinV3.totalSupply(), preSupply + amountNewTokens);
        // check tokens were burned
        uint256 expectedBurnBalance = currentBurnBalance + INITIAL_USER_BAL;
        assertEq(oldToken.balanceOf(migration.BURN_ADDRESS()), expectedBurnBalance);

        // check totalOldTokenBurned tracking
        assertEq(migration.totalOldTokenBurned(), INITIAL_USER_BAL);

        vm.stopPrank();
    }

    /// @dev Verifies migrate() reverts when the caller has a zero OldToken balance.
    function test_MigrateWithZeroAmount() public {
        address zeroBalance = address(400);
        // sanity check
        assertEq(oldToken.balanceOf(zeroBalance), 0);

        vm.prank(zeroBalance);
        vm.expectRevert(TokenMigration.InvalidAmount.selector);
        migration.migrate();
    }

    /// @dev Verifies migrate() reverts when the caller has not approved their full balance.
    function test_UserHasNotApprovedFullAmount() public {
        // check initial balances
        assertEq(oldToken.balanceOf(user1), INITIAL_USER_BAL);
        assertEq(telcoinV3.balanceOf(user1), 0);

        vm.startPrank(user1);
        // approve less than full balance for migration contract
        uint256 notEnough = INITIAL_USER_BAL - 1000;
        oldToken.approve(address(migration), notEnough);
        vm.expectRevert();
        migration.migrate();
        vm.stopPrank();
    }

    /// @dev Verifies migrate() uses the caller's actual balance even when approval exceeds it.
    function test_MaxBalance() public {
        vm.startPrank(user1);
        uint256 userBalance = oldToken.balanceOf(user1);
        uint256 tooMuch = userBalance + 1000;
        oldToken.approve(address(migration), tooMuch);
        migration.migrate();
        vm.stopPrank();

        // amount up to user's balance migrated
        uint256 expectedBalance = userBalance * migration.DECIMAL_MULTIPLIER();
        assertEq(telcoinV3.balanceOf(user1), expectedBalance);
    }

    // --------------
    // Tracking Tests
    // --------------

    /// @dev Verifies totalOldTokenBurned accumulates correctly across multiple users.
    function test_TotalOldTokenBurned_AccumulatesAcrossUsers() public {
        assertEq(migration.totalOldTokenBurned(), 0);

        vm.startPrank(user1);
        oldToken.approve(address(migration), INITIAL_USER_BAL);
        migration.migrate();
        vm.stopPrank();

        assertEq(migration.totalOldTokenBurned(), INITIAL_USER_BAL);

        vm.startPrank(user2);
        oldToken.approve(address(migration), INITIAL_USER_BAL);
        migration.migrate();
        vm.stopPrank();

        assertEq(migration.totalOldTokenBurned(), INITIAL_USER_BAL * 2);
        assertEq(migration.totalOldTokenBurned() * migration.DECIMAL_MULTIPLIER(), migration.totalMigrated());
    }

    // ----------------------
    // Migration Expiry Tests
    // ----------------------

    /// @dev Verifies migrationExpiry is set in the future at deployment.
    function test_Migrate_verifyFuture() public {
        assertGt(migration.migrationExpiry(), block.timestamp);
    }

    /// @dev Verifies migrate() reverts when called after migrationExpiry.
    function test_Migrate_revertsAfterExpiry() public {
        vm.warp(migration.migrationExpiry() + 1);

        vm.startPrank(user1);
        oldToken.approve(address(migration), INITIAL_USER_BAL);
        vm.expectRevert(TokenMigration.MigrationConcluded.selector);
        migration.migrate();
        vm.stopPrank();
    }

    /// @dev Verifies migrate() reverts at the exact expiry timestamp (boundary is exclusive).
    function test_Migrate_revertsAtExactExpiry() public {
        vm.warp(migration.migrationExpiry());

        vm.startPrank(user1);
        oldToken.approve(address(migration), INITIAL_USER_BAL);
        vm.expectRevert(TokenMigration.MigrationConcluded.selector);
        migration.migrate();
        vm.stopPrank();
    }

    /// @dev Verifies setMigrationExpiry emits the expected event and updates state.
    function test_SetMigrationExpiry_success() public {
        uint256 oldExpiry = migration.migrationExpiry();
        uint256 newExpiry = oldExpiry + 180 days;

        vm.expectEmit(true, true, true, true);
        emit TokenMigration.MigrationExpirySet(oldExpiry, newExpiry);

        vm.prank(owner);
        migration.setMigrationExpiry(newExpiry);

        assertEq(migration.migrationExpiry(), newExpiry);
    }

    /// @dev Verifies setMigrationExpiry reverts when newExpiry is zero.
    function test_SetMigrationExpiry_revertsIfZero() public {
        vm.prank(owner);
        vm.expectRevert(TokenMigration.InvalidExpiry.selector);
        migration.setMigrationExpiry(0);
    }

    /// @dev Verifies setMigrationExpiry reverts when newExpiry is less than the current expiry.
    function test_SetMigrationExpiry_revertsIfDecreased() public {
        uint256 currentExpiry = migration.migrationExpiry();

        vm.prank(owner);
        vm.expectRevert(TokenMigration.InvalidExpiry.selector);
        migration.setMigrationExpiry(currentExpiry - 1);
    }

    /// @dev Verifies setMigrationExpiry can only be called by the owner.
    function test_SetMigrationExpiry_revertsIfNonOwner() public {
        uint256 expiry = migration.migrationExpiry();
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user1));
        migration.setMigrationExpiry(expiry + 1 days);
    }

    /// @dev Verifies migrate() reverts after the updated expiry has passed.
    function test_SetMigrationExpiry_thenMigrateRevertsAfterNewExpiry() public {
        uint256 newExpiry = migration.migrationExpiry() + 90 days;
        vm.prank(owner);
        migration.setMigrationExpiry(newExpiry);

        vm.warp(newExpiry + 1);

        vm.startPrank(user1);
        oldToken.approve(address(migration), INITIAL_USER_BAL);
        vm.expectRevert(TokenMigration.MigrationConcluded.selector);
        migration.migrate();
        vm.stopPrank();
    }

    /// @dev Verifies migrate() succeeds before the updated expiry.
    function test_SetMigrationExpiry_thenMigrateSucceedsBeforeNewExpiry() public {
        uint256 newExpiry = migration.migrationExpiry() + 90 days;
        vm.prank(owner);
        migration.setMigrationExpiry(newExpiry);

        vm.warp(newExpiry - 1);

        vm.startPrank(user1);
        oldToken.approve(address(migration), INITIAL_USER_BAL);
        migration.migrate();
        vm.stopPrank();

        assertEq(telcoinV3.balanceOf(user1), migration.getAmountOut(INITIAL_USER_BAL));
    }

    // ----------------------
    // Ownership Safety Tests
    // ----------------------

    /// @dev transferOwnership sets pendingOwner but does NOT change owner yet (two-step).
    function test_TransferOwnership_SetsPendingOwner() public {
        address newOwner = makeAddr("newOwner");

        vm.prank(owner);
        migration.transferOwnership(newOwner);

        assertEq(migration.pendingOwner(), newOwner);
        assertEq(migration.owner(), owner); // owner unchanged until accepted
    }

    /// @dev Ownership transfer completes only after the pending owner calls acceptOwnership().
    function test_TransferOwnership_AcceptOwnership() public {
        address newOwner = makeAddr("newOwner");

        vm.prank(owner);
        migration.transferOwnership(newOwner);

        vm.prank(newOwner);
        migration.acceptOwnership();

        assertEq(migration.owner(), newOwner);
        assertEq(migration.pendingOwner(), address(0));
    }

    /// @dev A non-pending-owner cannot call acceptOwnership().
    function test_TransferOwnership_RevertNotPendingOwner() public {
        address newOwner = makeAddr("newOwner");

        vm.prank(owner);
        migration.transferOwnership(newOwner);

        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user1));
        migration.acceptOwnership();
    }

    /// @dev Only the current owner can initiate a transfer.
    function test_TransferOwnership_RevertNotOwner() public {
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user1));
        migration.transferOwnership(user1);
    }

    /// @dev renounceOwnership always reverts to prevent accidentally bricking the migration contract.
    function test_RenounceOwnership_Reverts() public {
        vm.prank(owner);
        vm.expectRevert(TokenMigration.CannotRenounceOwnership.selector);
        migration.renounceOwnership();
    }

    // ----------------------------
    // Permissioned Functions Tests
    // ----------------------------

    // ~ pause/unpause ~

    /// @dev Verifies pause blocks migrate() and unpause restores it.
    function test_PauseUnpause() public {
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

    /// @dev Verifies pause(), unpause(), and recoverERC20() revert for non-owners.
    function test_OnlyOwnerFunctions() public {
        vm.startPrank(user1);

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user1));
        migration.pause();

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user1));
        migration.unpause();

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user1));
        migration.recoverERC20(user1, OLDTOKEN_ADDRESS, INITIAL_USER_BAL);

        vm.stopPrank();
    }

    // ~ recoverERC20 ~

    /// @dev Verifies recoverERC20 returns the full stuck OldToken balance to the specified address.
    function test_RecoverStuckOldToken() public {
        address migrationContract = address(migration);
        // sanity check
        assertEq(oldToken.balanceOf(migrationContract), 0);

        // transfer old token instead of migrating
        vm.startPrank(user1);
        oldToken.approve(migrationContract, INITIAL_USER_BAL);
        require(oldToken.transfer(migrationContract, INITIAL_USER_BAL));
        vm.stopPrank();

        // check old tokens received
        assertEq(oldToken.balanceOf(migrationContract), INITIAL_USER_BAL);
        assertEq(oldToken.balanceOf(user1), 0);

        // recover old tokens (full balance)
        vm.prank(owner);
        migration.recoverERC20(user1, OLDTOKEN_ADDRESS, INITIAL_USER_BAL);
        assertEq(oldToken.balanceOf(user1), INITIAL_USER_BAL);
        assertEq(oldToken.balanceOf(migrationContract), 0);
    }

    /// @dev Verifies recoverERC20 can recover a partial amount, leaving the remainder in the contract.
    function test_RecoverERC20_partialAmount() public {
        address migrationContract = address(migration);
        uint256 partialAmount = INITIAL_USER_BAL / 4;

        // transfer old token to contract
        vm.startPrank(user1);
        oldToken.approve(migrationContract, INITIAL_USER_BAL);
        require(oldToken.transfer(migrationContract, INITIAL_USER_BAL));
        vm.stopPrank();

        uint256 preBalUser = oldToken.balanceOf(user2);
        uint256 preBalMigrationContract = oldToken.balanceOf(migrationContract);

        // recover only part of the balance
        vm.prank(owner);
        migration.recoverERC20(user2, OLDTOKEN_ADDRESS, partialAmount);
        assertEq(oldToken.balanceOf(user2), preBalUser + partialAmount);
        assertEq(oldToken.balanceOf(migrationContract), preBalMigrationContract - partialAmount);
    }

    /// @dev Verifies recoverERC20 reverts when amount is zero.
    function test_RecoverERC20_revertsOnZeroAmount() public {
        address migrationContract = address(migration);

        vm.startPrank(user1);
        oldToken.approve(migrationContract, INITIAL_USER_BAL);
        require(oldToken.transfer(migrationContract, INITIAL_USER_BAL));
        vm.stopPrank();

        vm.prank(owner);
        vm.expectRevert(TokenMigration.InvalidAmount.selector);
        migration.recoverERC20(user1, OLDTOKEN_ADDRESS, 0);
    }

    /// @dev Verifies recoverERC20 reverts when amount exceeds the contract balance.
    function test_RecoverERC20_revertsWhenAmountExceedsBalance() public {
        address migrationContract = address(migration);

        vm.startPrank(user1);
        oldToken.approve(migrationContract, INITIAL_USER_BAL);
        require(oldToken.transfer(migrationContract, INITIAL_USER_BAL));
        vm.stopPrank();

        vm.prank(owner);
        vm.expectRevert(TokenMigration.InvalidAmount.selector);
        migration.recoverERC20(user1, OLDTOKEN_ADDRESS, INITIAL_USER_BAL + 1);
    }

    /// @dev Verifies recoverERC20 reverts when the contract holds no balance of the token.
    function test_RecoverERC20_revertsWhenContractBalanceIsZero() public {
        // no tokens in contract
        assertEq(oldToken.balanceOf(address(migration)), 0);

        vm.prank(owner);
        vm.expectRevert(TokenMigration.InvalidAmount.selector);
        migration.recoverERC20(user1, OLDTOKEN_ADDRESS, 1);
    }

    /// @dev Verifies recoverERC20 reverts when destination is address(0).
    function test_RecoverERC20_revertsWhenDestinationIsAddressZero() public {
        vm.prank(owner);
        vm.expectRevert(TokenMigration.ZeroAddress.selector);
        migration.recoverERC20(address(0), OLDTOKEN_ADDRESS, 1);
    }

    /// @dev Verifies recoverERC20 reverts when destination is the burn address.
    function test_RecoverERC20_revertsWhenDestinationIsBurnAddress() public {
        address burnAddress = migration.BURN_ADDRESS();

        vm.prank(owner);
        vm.expectRevert(TokenMigration.ZeroAddress.selector);
        migration.recoverERC20(burnAddress, OLDTOKEN_ADDRESS, 1);
    }

    /// @dev Verifies recoverERC20 reverts when token address is address(0).
    function test_RecoverERC20_revertsWhenTokenIsAddressZero() public {
        vm.prank(owner);
        vm.expectRevert(TokenMigration.ZeroAddress.selector);
        migration.recoverERC20(user1, address(0), 1);
    }
}
