// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {TelcoinV3} from "../../src/TelcoinV3.sol";
import {TokenMigration} from "../../src/TokenMigration.sol";
import {Create3Utils} from "../utils/Create3Utils.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
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
    uint256 constant MIGRATION_DURATION = 365 days;
    uint256 constant WITHDRAWAL_DELAY = 90 days;

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
            type(TokenMigration).creationCode, abi.encode(address(oldToken), address(telcoinV3), owner, MIGRATION_DURATION, WITHDRAWAL_DELAY)
        );
        address migrationAddress = create3.deploy(migrationSalt, migrationArgs);
        migration = TokenMigration(migrationAddress);

        vm.stopPrank();

        // set minter role on TelcoinV3
        vm.prank(owner);
        telcoinV3.grantRole(MINTER_ROLE, address(migration));

        // grant pause roles post-deploy (mirrors the deployment configuration step)
        vm.startPrank(owner);
        migration.grantRole(PAUSER_ROLE, owner);
        migration.grantRole(UNPAUSER_ROLE, owner);
        vm.stopPrank();

        // fund accounts
        deal(address(oldToken), user1, INITIAL_USER_BAL);
        deal(address(oldToken), user2, INITIAL_USER_BAL);
    }

    // -------------------
    // Initial State Tests
    // -------------------

    /// @dev Verifies constructor reverts when _oldToken is the zero address.
    function test_Constructor_RevertsWhenOldTokenZero() public {
        vm.expectRevert(TokenMigration.ZeroAddress.selector);
        new TokenMigration(address(0), address(telcoinV3), owner, MIGRATION_DURATION, WITHDRAWAL_DELAY);
    }

    /// @dev Verifies constructor reverts when _telcoinV3 is the zero address.
    function test_Constructor_RevertsWhenNewTokenZero() public {
        vm.expectRevert(TokenMigration.ZeroAddress.selector);
        new TokenMigration(address(oldToken), address(0), owner, MIGRATION_DURATION, WITHDRAWAL_DELAY);
    }

    /// @dev Verifies constructor reverts when _admin is the zero address.
    function test_Constructor_RevertsWhenAdminZero() public {
        vm.expectRevert(TokenMigration.ZeroAddress.selector);
        new TokenMigration(address(oldToken), address(telcoinV3), address(0), MIGRATION_DURATION, WITHDRAWAL_DELAY);
    }

    /// @dev Verifies constructor reverts when _oldToken and _telcoinV3 are the same address.
    function test_Constructor_RevertsWhenSameAddress() public {
        vm.expectRevert(TokenMigration.SameAddress.selector);
        new TokenMigration(address(telcoinV3), address(telcoinV3), owner, MIGRATION_DURATION, WITHDRAWAL_DELAY);
    }

    /// @dev Verifies constructor reverts when _migrationDuration is zero.
    function test_Constructor_RevertsWhenDurationZero() public {
        vm.expectRevert(TokenMigration.InvalidExpiry.selector);
        new TokenMigration(address(oldToken), address(telcoinV3), owner, 0, WITHDRAWAL_DELAY);
    }

    // ---------------
    // Migration Tests
    // ---------------

    /// @dev Verifies a full migration: balances, escrow, supply, and tracking state update correctly.
    function test_Migration() public {
        vm.startPrank(user1);

        // check initial balances
        assertEq(oldToken.balanceOf(user1), INITIAL_USER_BAL);
        assertEq(telcoinV3.balanceOf(user1), 0);
        uint256 preSupply = telcoinV3.totalSupply();

        // take current escrow balance since this forks live
        uint256 currentEscrowBalance = oldToken.balanceOf(address(migration));
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
        // check tokens were escrowed
        uint256 expectedEscrowBalance = currentEscrowBalance + INITIAL_USER_BAL;
        assertEq(oldToken.balanceOf(address(migration)), expectedEscrowBalance);

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

    /// @dev Verifies setMigrationExpiry can only be called by the admin.
    function test_SetMigrationExpiry_revertsIfNonAdmin() public {
        uint256 expiry = migration.migrationExpiry();
        bytes32 adminRole = migration.DEFAULT_ADMIN_ROLE();

        vm.prank(user1);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, user1, adminRole)
        );
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

    // --------------------------
    // Access Control Safety Tests
    // --------------------------

    /// @dev Constructor grants only DEFAULT_ADMIN_ROLE; pause roles are granted post-deploy.
    function test_AccessControl_initialRoles() public {
        TokenMigration fresh =
            new TokenMigration(address(oldToken), address(telcoinV3), owner, MIGRATION_DURATION, WITHDRAWAL_DELAY);

        assertTrue(fresh.hasRole(fresh.DEFAULT_ADMIN_ROLE(), owner));
        assertFalse(fresh.hasRole(PAUSER_ROLE, owner));
        assertFalse(fresh.hasRole(UNPAUSER_ROLE, owner));

        // admin grants the pause roles as a configuration step
        vm.startPrank(owner);
        fresh.grantRole(PAUSER_ROLE, owner);
        fresh.grantRole(UNPAUSER_ROLE, owner);
        vm.stopPrank();

        assertTrue(fresh.hasRole(PAUSER_ROLE, owner));
        assertTrue(fresh.hasRole(UNPAUSER_ROLE, owner));
    }

    /// @dev renounceRole always reverts to prevent accidentally bricking the migration contract.
    function test_RenounceRole_Reverts() public {
        bytes32 adminRole = migration.DEFAULT_ADMIN_ROLE();
        vm.prank(owner);
        vm.expectRevert(TokenMigration.CannotRenounceRole.selector);
        migration.renounceRole(adminRole, owner);
    }

    /// @dev An admin cannot bypass the renounce ban by revoking its own DEFAULT_ADMIN_ROLE.
    function test_RevokeRole_revertsAdminSelfRevoke() public {
        bytes32 adminRole = migration.DEFAULT_ADMIN_ROLE();
        vm.prank(owner);
        vm.expectRevert(TokenMigration.CannotRenounceRole.selector);
        migration.revokeRole(adminRole, owner);
    }

    /// @dev Admin handover: grant the new admin, then the new admin revokes the old one.
    function test_AdminHandover() public {
        address newAdmin = makeAddr("newAdmin");
        bytes32 adminRole = migration.DEFAULT_ADMIN_ROLE();

        vm.prank(owner);
        migration.grantRole(adminRole, newAdmin);

        vm.prank(newAdmin);
        migration.revokeRole(adminRole, owner);

        assertFalse(migration.hasRole(adminRole, owner));
        assertTrue(migration.hasRole(adminRole, newAdmin));

        // new admin controls admin-gated functions
        uint256 newExpiry = migration.migrationExpiry() + 30 days;
        vm.prank(newAdmin);
        migration.setMigrationExpiry(newExpiry);
        assertEq(migration.migrationExpiry(), newExpiry);
    }

    /// @dev A dedicated pauser can pause but not unpause, and holds no admin authority.
    function test_PauseUnpause_roleSeparation() public {
        address pauserBot = makeAddr("pauserBot");
        address unpauserGov = makeAddr("unpauserGov");
        bytes32 adminRole = migration.DEFAULT_ADMIN_ROLE();

        vm.startPrank(owner);
        migration.grantRole(PAUSER_ROLE, pauserBot);
        migration.grantRole(UNPAUSER_ROLE, unpauserGov);
        vm.stopPrank();

        vm.prank(pauserBot);
        migration.pause();
        assertTrue(migration.paused());

        // pauser cannot unpause
        vm.prank(pauserBot);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, pauserBot, UNPAUSER_ROLE)
        );
        migration.unpause();

        // pauser holds no admin authority
        vm.prank(pauserBot);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, pauserBot, adminRole)
        );
        migration.withdrawOldTokens(pauserBot);

        vm.prank(unpauserGov);
        migration.unpause();
        assertFalse(migration.paused());
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

    /// @dev Verifies pause(), unpause(), and recoverERC20() revert for unauthorized callers.
    function test_PermissionedFunctions_revertUnauthorized() public {
        bytes32 adminRole = migration.DEFAULT_ADMIN_ROLE();
        bytes32 pauserRole = migration.PAUSER_ROLE();
        bytes32 unpauserRole = migration.UNPAUSER_ROLE();

        vm.startPrank(user1);

        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, user1, pauserRole)
        );
        migration.pause();

        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, user1, unpauserRole)
        );
        migration.unpause();

        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, user1, adminRole)
        );
        migration.recoverERC20(user1, OLDTOKEN_ADDRESS, INITIAL_USER_BAL);

        vm.stopPrank();
    }

    // ~ recoverERC20 ~

    /// @dev Verifies recoverERC20 reverts when attempting to recover escrowed old tokens.
    function test_RecoverERC20_revertsForOldToken() public {
        vm.prank(owner);
        vm.expectRevert(TokenMigration.CannotRecoverOldToken.selector);
        migration.recoverERC20(user1, OLDTOKEN_ADDRESS, 1);
    }

    /// @dev Verifies recoverERC20 reverts when destination is address(0).
    function test_RecoverERC20_revertsWhenDestinationIsAddressZero() public {
        vm.prank(owner);
        vm.expectRevert(TokenMigration.ZeroAddress.selector);
        migration.recoverERC20(address(0), address(telcoinV3), 1);
    }

    /// @dev Verifies recoverERC20 reverts when token address is address(0).
    function test_RecoverERC20_revertsWhenTokenIsAddressZero() public {
        vm.prank(owner);
        vm.expectRevert(TokenMigration.ZeroAddress.selector);
        migration.recoverERC20(user1, address(0), 1);
    }

    /// @dev Verifies recoverERC20 reverts when the contract holds no balance of the token.
    function test_RecoverERC20_revertsWhenContractBalanceIsZero() public {
        assertEq(telcoinV3.balanceOf(address(migration)), 0);

        vm.prank(owner);
        vm.expectRevert(TokenMigration.InvalidAmount.selector);
        migration.recoverERC20(user1, address(telcoinV3), 1);
    }

    /// @dev Verifies recoverERC20 reverts when amount is zero.
    function test_RecoverERC20_revertsOnZeroAmount() public {
        // send some telcoinV3 to migration contract
        vm.prank(owner);
        telcoinV3.transfer(address(migration), 1000);

        vm.prank(owner);
        vm.expectRevert(TokenMigration.InvalidAmount.selector);
        migration.recoverERC20(user1, address(telcoinV3), 0);
    }

    /// @dev Verifies recoverERC20 reverts when amount exceeds the contract balance.
    function test_RecoverERC20_revertsWhenAmountExceedsBalance() public {
        uint256 sendAmount = 1000;

        // send some telcoinV3 to migration contract
        vm.prank(owner);
        telcoinV3.transfer(address(migration), sendAmount);

        vm.prank(owner);
        vm.expectRevert(TokenMigration.InvalidAmount.selector);
        migration.recoverERC20(user1, address(telcoinV3), sendAmount + 1);
    }

    // ~ withdrawOldTokens ~

    /// @dev Verifies withdrawOldTokens succeeds after migrationExpiry + withdrawalDelay.
    function test_WithdrawOldTokens_success() public {
        // migrate first to escrow tokens
        vm.startPrank(user1);
        oldToken.approve(address(migration), INITIAL_USER_BAL);
        migration.migrate();
        vm.stopPrank();

        uint256 escrowedBalance = oldToken.balanceOf(address(migration));
        assertEq(escrowedBalance, INITIAL_USER_BAL);

        // warp past migrationExpiry + withdrawalDelay
        vm.warp(migration.migrationExpiry() + migration.withdrawalDelay());

        uint256 user2BalBefore = oldToken.balanceOf(user2);

        vm.prank(owner);
        migration.withdrawOldTokens(user2);

        assertEq(oldToken.balanceOf(address(migration)), 0);
        assertEq(oldToken.balanceOf(user2), user2BalBefore + INITIAL_USER_BAL);
    }

    /// @dev Verifies withdrawOldTokens reverts before the withdrawal delay has passed.
    function test_WithdrawOldTokens_revertsBeforeDelay() public {
        // migrate first
        vm.startPrank(user1);
        oldToken.approve(address(migration), INITIAL_USER_BAL);
        migration.migrate();
        vm.stopPrank();

        // warp to just before unlock
        vm.warp(migration.migrationExpiry() + migration.withdrawalDelay() - 1);

        vm.prank(owner);
        vm.expectRevert(TokenMigration.WithdrawalLocked.selector);
        migration.withdrawOldTokens(user2);
    }

    /// @dev Verifies withdrawOldTokens reverts when no tokens are escrowed.
    function test_WithdrawOldTokens_revertsWhenEmpty() public {
        vm.warp(migration.migrationExpiry() + migration.withdrawalDelay());

        vm.prank(owner);
        vm.expectRevert(TokenMigration.InvalidAmount.selector);
        migration.withdrawOldTokens(user2);
    }

    /// @dev Verifies withdrawOldTokens reverts when called by non-admin.
    function test_WithdrawOldTokens_revertsIfNonAdmin() public {
        vm.warp(migration.migrationExpiry() + migration.withdrawalDelay());
        bytes32 adminRole = migration.DEFAULT_ADMIN_ROLE();

        vm.prank(user1);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, user1, adminRole)
        );
        migration.withdrawOldTokens(user2);
    }

    /// @dev Verifies withdrawOldTokens reverts when destination is address(0).
    function test_WithdrawOldTokens_revertsWhenDestinationZero() public {
        vm.warp(migration.migrationExpiry() + migration.withdrawalDelay());

        vm.prank(owner);
        vm.expectRevert(TokenMigration.ZeroAddress.selector);
        migration.withdrawOldTokens(address(0));
    }

    // -----------------------
    // Migration Closure Tests
    // -----------------------

    /// @dev Migration is not closed at deployment.
    function test_MigrationClosed_initiallyFalse() public view {
        assertFalse(migration.migrationClosed());
    }

    /// @dev Withdrawing escrowed old tokens permanently closes migration and emits MigrationClosed.
    function test_WithdrawOldTokens_closesMigration() public {
        vm.startPrank(user1);
        oldToken.approve(address(migration), INITIAL_USER_BAL);
        migration.migrate();
        vm.stopPrank();

        vm.warp(migration.migrationExpiry() + migration.withdrawalDelay());

        vm.expectEmit(true, true, true, true);
        emit TokenMigration.MigrationClosed();

        vm.prank(owner);
        migration.withdrawOldTokens(user2);

        assertTrue(migration.migrationClosed());
    }

    /// @dev Once closed, the expiry can never be moved into the future to reopen migration.
    function test_SetMigrationExpiry_revertsWhenClosed() public {
        vm.startPrank(user1);
        oldToken.approve(address(migration), INITIAL_USER_BAL);
        migration.migrate();
        vm.stopPrank();

        vm.warp(migration.migrationExpiry() + migration.withdrawalDelay());
        vm.prank(owner);
        migration.withdrawOldTokens(owner);

        vm.prank(owner);
        vm.expectRevert(TokenMigration.MigrationConcluded.selector);
        migration.setMigrationExpiry(block.timestamp + 365 days);
    }

    /// @dev Once closed, migrate() reverts regardless of timing.
    function test_Migrate_revertsWhenClosed() public {
        vm.startPrank(user1);
        oldToken.approve(address(migration), INITIAL_USER_BAL);
        migration.migrate();
        vm.stopPrank();

        vm.warp(migration.migrationExpiry() + migration.withdrawalDelay());
        vm.prank(owner);
        migration.withdrawOldTokens(owner);

        vm.startPrank(user2);
        oldToken.approve(address(migration), INITIAL_USER_BAL);
        vm.expectRevert(TokenMigration.MigrationConcluded.selector);
        migration.migrate();
        vm.stopPrank();
    }

    /// @dev Full recycle-attack scenario (Spearbit finding): owner withdraws escrowed old tokens
    ///      after expiry + delay, then attempts to extend the expiry and re-migrate the withdrawn
    ///      tokens to mint additional new tokens. Both steps must revert.
    function test_RecycleAttack_prevented() public {
        // user1 migrates; old tokens are escrowed and new tokens minted 1:1
        vm.startPrank(user1);
        oldToken.approve(address(migration), INITIAL_USER_BAL);
        migration.migrate();
        vm.stopPrank();

        uint256 supplyAfterMigration = telcoinV3.totalSupply();

        // conclusion: expiry + delay pass, owner withdraws the escrow to itself
        vm.warp(migration.migrationExpiry() + migration.withdrawalDelay());
        vm.prank(owner);
        migration.withdrawOldTokens(owner);
        assertEq(oldToken.balanceOf(owner), INITIAL_USER_BAL);

        // attack step 1: reopen migration by extending expiry — must revert
        vm.prank(owner);
        vm.expectRevert(TokenMigration.MigrationConcluded.selector);
        migration.setMigrationExpiry(block.timestamp + 365 days);

        // attack step 2: re-migrate the withdrawn old tokens — must revert
        vm.startPrank(owner);
        oldToken.approve(address(migration), INITIAL_USER_BAL);
        vm.expectRevert(TokenMigration.MigrationConcluded.selector);
        migration.migrate();
        vm.stopPrank();

        // no additional new tokens were minted
        assertEq(telcoinV3.totalSupply(), supplyAfterMigration);
    }

    /// @dev Old tokens sent directly to the contract after closure can still be withdrawn,
    ///      and MigrationClosed is not emitted a second time.
    function test_WithdrawOldTokens_afterClosureWithdrawsDonations() public {
        vm.startPrank(user1);
        oldToken.approve(address(migration), INITIAL_USER_BAL);
        migration.migrate();
        vm.stopPrank();

        vm.warp(migration.migrationExpiry() + migration.withdrawalDelay());
        vm.prank(owner);
        migration.withdrawOldTokens(owner);
        assertTrue(migration.migrationClosed());

        // user2 sends old tokens directly to the contract after closure
        vm.prank(user2);
        oldToken.transfer(address(migration), INITIAL_USER_BAL);

        vm.recordLogs();
        vm.prank(owner);
        migration.withdrawOldTokens(owner);

        // withdrawal succeeded and migration remains closed
        assertEq(oldToken.balanceOf(address(migration)), 0);
        assertTrue(migration.migrationClosed());

        // MigrationClosed must not be re-emitted on subsequent withdrawals
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i = 0; i < logs.length; i++) {
            assertTrue(logs[i].topics[0] != TokenMigration.MigrationClosed.selector);
        }
    }
}
