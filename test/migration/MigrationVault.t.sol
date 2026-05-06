// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {MigrationVault} from "../../src/MigrationVault.sol";
import {MockERC20} from "../mocks/MockERC20.sol";

contract MigrationVaultTest is Test {
    MigrationVault internal vault;
    MigrationVault internal implementation;
    MockERC20 internal oldToken;
    MockERC20 internal newToken;

    address internal admin = makeAddr("admin");
    address internal pauser = makeAddr("pauser");
    address internal unpauser = makeAddr("unpauser");
    address internal treasuryAddr = makeAddr("treasury");
    address internal user = makeAddr("user");
    address internal user2 = makeAddr("user2");
    address internal attacker = makeAddr("attacker");

    uint8 internal constant OLD_DECIMALS = 2;
    uint8 internal constant NEW_DECIMALS = 18;
    uint256 internal constant VAULT_RESERVE = 1_000_000_000 ether; // 1B NEW tokens
    uint256 internal constant USER_BALANCE = 1_000_000 * 10 ** OLD_DECIMALS; // 1M OLD tokens

    // Cached role hashes (avoids vm.prank being consumed by view calls)
    bytes32 internal defaultAdminRole;
    bytes32 internal treasuryRole;
    bytes32 internal pauserRole;
    bytes32 internal unpauserRole;

    function setUp() public {
        // Deploy mock tokens
        oldToken = new MockERC20("TEL v2", "TELv2", OLD_DECIMALS);
        newToken = new MockERC20("TEL v3", "TELv3", NEW_DECIMALS);

        // Deploy implementation and proxy
        implementation = new MigrationVault();
        bytes memory initData = abi.encodeCall(
            MigrationVault.initialize,
            (address(oldToken), address(newToken), admin, pauser, unpauser)
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        vault = MigrationVault(address(proxy));

        // Cache role hashes
        defaultAdminRole = vault.DEFAULT_ADMIN_ROLE();
        treasuryRole = vault.TREASURY_ROLE();
        pauserRole = vault.PAUSER_ROLE();
        unpauserRole = vault.UNPAUSER_ROLE();

        // Grant treasury role
        vm.prank(admin);
        vault.grantRole(treasuryRole, treasuryAddr);

        // Fund vault with NEW tokens
        newToken.mint(address(vault), VAULT_RESERVE);

        // Fund users with OLD tokens
        oldToken.mint(user, USER_BALANCE);
        oldToken.mint(user2, USER_BALANCE);

        // Approve vault
        vm.prank(user);
        oldToken.approve(address(vault), type(uint256).max);
        vm.prank(user2);
        oldToken.approve(address(vault), type(uint256).max);
    }

    // ====================
    // Initialization Tests
    // ====================

    function test_initialize_setsState() public view {
        assertEq(address(vault.OLD_TOKEN()), address(oldToken));
        assertEq(address(vault.NEW_TOKEN()), address(newToken));
        assertEq(vault.oldToWad(), 10 ** (18 - OLD_DECIMALS));
        assertEq(vault.newToWad(), 10 ** (18 - NEW_DECIMALS));
    }

    function test_initialize_grantsRoles() public view {
        assertTrue(vault.hasRole(defaultAdminRole, admin));
        assertTrue(vault.hasRole(pauserRole, pauser));
        assertTrue(vault.hasRole(unpauserRole, unpauser));
        assertTrue(vault.hasRole(treasuryRole, treasuryAddr));
    }

    function test_initialize_cannotReinitialize() public {
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        vault.initialize(address(oldToken), address(newToken), admin, pauser, unpauser);
    }

    function test_initialize_revertsZeroOldToken() public {
        MigrationVault impl = new MigrationVault();
        vm.expectRevert(MigrationVault.ZeroAddress.selector);
        new ERC1967Proxy(
            address(impl),
            abi.encodeCall(MigrationVault.initialize, (address(0), address(newToken), admin, pauser, unpauser))
        );
    }

    function test_initialize_revertsZeroNewToken() public {
        MigrationVault impl = new MigrationVault();
        vm.expectRevert(MigrationVault.ZeroAddress.selector);
        new ERC1967Proxy(
            address(impl),
            abi.encodeCall(MigrationVault.initialize, (address(oldToken), address(0), admin, pauser, unpauser))
        );
    }

    function test_initialize_revertsZeroAdmin() public {
        MigrationVault impl = new MigrationVault();
        vm.expectRevert(MigrationVault.ZeroAddress.selector);
        new ERC1967Proxy(
            address(impl),
            abi.encodeCall(MigrationVault.initialize, (address(oldToken), address(newToken), address(0), pauser, unpauser))
        );
    }

    function test_initialize_revertsZeroPauser() public {
        MigrationVault impl = new MigrationVault();
        vm.expectRevert(MigrationVault.ZeroAddress.selector);
        new ERC1967Proxy(
            address(impl),
            abi.encodeCall(MigrationVault.initialize, (address(oldToken), address(newToken), admin, address(0), unpauser))
        );
    }

    function test_initialize_revertsZeroUnpauser() public {
        MigrationVault impl = new MigrationVault();
        vm.expectRevert(MigrationVault.ZeroAddress.selector);
        new ERC1967Proxy(
            address(impl),
            abi.encodeCall(MigrationVault.initialize, (address(oldToken), address(newToken), admin, pauser, address(0)))
        );
    }

    function test_initialize_revertsDecimalsExceedMax() public {
        MockERC20 badToken = new MockERC20("Bad", "BAD", 19);
        MigrationVault impl = new MigrationVault();
        vm.expectRevert(MigrationVault.DecimalsExceedMax.selector);
        new ERC1967Proxy(
            address(impl),
            abi.encodeCall(MigrationVault.initialize, (address(badToken), address(newToken), admin, pauser, unpauser))
        );
    }

    function test_implementation_cannotBeInitialized() public {
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        implementation.initialize(address(oldToken), address(newToken), admin, pauser, unpauser);
    }

    // ===============
    // Migration Tests
    // ===============

    function test_migrate_basic() public {
        uint256 amountIn = 100 * 10 ** OLD_DECIMALS; // 100 OLD tokens
        uint256 expectedOut = 100 ether; // 100 NEW tokens (18 decimals)

        vm.prank(user);
        uint256 amountOut = vault.migrate(user, amountIn);

        assertEq(amountOut, expectedOut);
        assertEq(oldToken.balanceOf(user), USER_BALANCE - amountIn);
        assertEq(newToken.balanceOf(user), expectedOut);
        assertEq(oldToken.balanceOf(address(vault)), amountIn);
        assertEq(newToken.balanceOf(address(vault)), VAULT_RESERVE - expectedOut);
    }

    function test_migrate_toDifferentRecipient() public {
        uint256 amountIn = 50 * 10 ** OLD_DECIMALS;
        uint256 expectedOut = 50 ether;

        vm.prank(user);
        uint256 amountOut = vault.migrate(user2, amountIn);

        assertEq(amountOut, expectedOut);
        assertEq(oldToken.balanceOf(user), USER_BALANCE - amountIn);
        assertEq(newToken.balanceOf(user), 0);
        assertEq(newToken.balanceOf(user2), expectedOut);
    }

    function test_migrate_emitsEvent() public {
        uint256 amountIn = 100 * 10 ** OLD_DECIMALS;
        uint256 expectedOut = 100 ether;

        vm.expectEmit(true, true, true, true);
        emit MigrationVault.Migrated(user, user, amountIn, expectedOut);

        vm.prank(user);
        vault.migrate(user, amountIn);
    }

    function test_migrate_entireBalance() public {
        vm.prank(user);
        uint256 amountOut = vault.migrate(user, USER_BALANCE);

        uint256 expectedOut = 1_000_000 ether;
        assertEq(amountOut, expectedOut);
        assertEq(oldToken.balanceOf(user), 0);
        assertEq(newToken.balanceOf(user), expectedOut);
    }

    function test_migrate_multipleUsers() public {
        uint256 amountIn = 100 * 10 ** OLD_DECIMALS;
        uint256 expectedOut = 100 ether;

        vm.prank(user);
        vault.migrate(user, amountIn);

        vm.prank(user2);
        vault.migrate(user2, amountIn);

        assertEq(newToken.balanceOf(user), expectedOut);
        assertEq(newToken.balanceOf(user2), expectedOut);
        assertEq(oldToken.balanceOf(address(vault)), amountIn * 2);
        assertEq(newToken.balanceOf(address(vault)), VAULT_RESERVE - expectedOut * 2);
    }

    function test_migrate_revertsZeroAddress() public {
        vm.prank(user);
        vm.expectRevert(MigrationVault.ZeroAddress.selector);
        vault.migrate(address(0), 100);
    }

    function test_migrate_revertsZeroAmount() public {
        vm.prank(user);
        vm.expectRevert(MigrationVault.ZeroAmount.selector);
        vault.migrate(user, 0);
    }

    function test_migrate_revertsInsufficientReserves() public {
        // Drain the vault first
        vm.prank(admin);
        vault.grantRole(treasuryRole, admin);
        vm.prank(admin);
        vault.withdraw(address(newToken), admin, VAULT_RESERVE);

        vm.prank(user);
        vm.expectRevert(MigrationVault.InsufficientReserves.selector);
        vault.migrate(user, 100 * 10 ** OLD_DECIMALS);
    }

    function test_migrate_revertsWhenPaused() public {
        vm.prank(pauser);
        vault.pause();

        vm.prank(user);
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        vault.migrate(user, 100 * 10 ** OLD_DECIMALS);
    }

    // ====================
    // Preview Migrate Tests
    // ====================

    function test_previewMigrate_matchesActual() public {
        uint256 amountIn = 500 * 10 ** OLD_DECIMALS;
        uint256 preview = vault.previewMigrate(amountIn);

        vm.prank(user);
        uint256 actual = vault.migrate(user, amountIn);

        assertEq(preview, actual);
    }

    function test_previewMigrate_decimalConversion() public view {
        // 1 OLD token (2 decimals) = 1 NEW token (18 decimals)
        uint256 oneOld = 1 * 10 ** OLD_DECIMALS; // 100
        uint256 expected = 1 ether; // 1e18
        assertEq(vault.previewMigrate(oneOld), expected);

        // Smallest unit: 1 unit of OLD (0.01) = 1e16 NEW
        assertEq(vault.previewMigrate(1), 10 ** (NEW_DECIMALS - OLD_DECIMALS));
    }

    // ====================
    // Same Decimals Tests
    // ====================

    function test_migrate_sameDecimals() public {
        // Deploy with both tokens at 18 decimals
        MockERC20 old18 = new MockERC20("Old18", "O18", 18);
        MockERC20 new18 = new MockERC20("New18", "N18", 18);

        MigrationVault impl = new MigrationVault();
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(impl),
            abi.encodeCall(MigrationVault.initialize, (address(old18), address(new18), admin, pauser, unpauser))
        );
        MigrationVault sameDecVault = MigrationVault(address(proxy));

        uint256 amount = 1000 ether;
        old18.mint(user, amount);
        new18.mint(address(sameDecVault), amount);

        vm.prank(user);
        old18.approve(address(sameDecVault), type(uint256).max);

        vm.prank(user);
        uint256 amountOut = sameDecVault.migrate(user, amount);

        assertEq(amountOut, amount);
    }

    // ==================
    // Pause/Unpause Tests
    // ==================

    function test_pause_byPauser() public {
        vm.prank(pauser);
        vault.pause();
        assertTrue(vault.paused());
    }

    function test_pause_revertsNonPauser() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                attacker,
                pauserRole
            )
        );
        vm.prank(attacker);
        vault.pause();
    }

    function test_unpause_byUnpauser() public {
        vm.prank(pauser);
        vault.pause();

        vm.prank(unpauser);
        vault.unpause();
        assertFalse(vault.paused());
    }

    function test_unpause_revertsNonUnpauser() public {
        vm.prank(pauser);
        vault.pause();

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                attacker,
                unpauserRole
            )
        );
        vm.prank(attacker);
        vault.unpause();
    }

    function test_migrateAfterUnpause() public {
        vm.prank(pauser);
        vault.pause();

        vm.prank(unpauser);
        vault.unpause();

        vm.prank(user);
        uint256 amountOut = vault.migrate(user, 100 * 10 ** OLD_DECIMALS);
        assertEq(amountOut, 100 ether);
    }

    // ===============
    // Withdraw Tests
    // ===============

    function test_withdraw_oldTokens() public {
        // First migrate some tokens so vault has OLD tokens
        vm.prank(user);
        vault.migrate(user, USER_BALANCE);

        uint256 withdrawAmount = USER_BALANCE;
        vm.prank(treasuryAddr);
        vault.withdraw(address(oldToken), treasuryAddr, withdrawAmount);

        assertEq(oldToken.balanceOf(treasuryAddr), withdrawAmount);
        assertEq(oldToken.balanceOf(address(vault)), 0);
    }

    function test_withdraw_newTokens() public {
        uint256 withdrawAmount = 1000 ether;

        vm.prank(treasuryAddr);
        vault.withdraw(address(newToken), treasuryAddr, withdrawAmount);

        assertEq(newToken.balanceOf(treasuryAddr), withdrawAmount);
        assertEq(newToken.balanceOf(address(vault)), VAULT_RESERVE - withdrawAmount);
    }

    function test_withdraw_emitsEvent() public {
        uint256 withdrawAmount = 1000 ether;

        vm.expectEmit(true, true, true, true);
        emit MigrationVault.Withdrawn(address(newToken), treasuryAddr, withdrawAmount);

        vm.prank(treasuryAddr);
        vault.withdraw(address(newToken), treasuryAddr, withdrawAmount);
    }

    function test_withdraw_revertsNonTreasury() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                attacker,
                treasuryRole
            )
        );
        vm.prank(attacker);
        vault.withdraw(address(newToken), attacker, 100);
    }

    function test_withdraw_revertsZeroTokenAddress() public {
        vm.prank(treasuryAddr);
        vm.expectRevert(MigrationVault.ZeroAddress.selector);
        vault.withdraw(address(0), treasuryAddr, 100);
    }

    function test_withdraw_revertsZeroToAddress() public {
        vm.prank(treasuryAddr);
        vm.expectRevert(MigrationVault.ZeroAddress.selector);
        vault.withdraw(address(newToken), address(0), 100);
    }

    function test_withdraw_revertsZeroAmount() public {
        vm.prank(treasuryAddr);
        vm.expectRevert(MigrationVault.ZeroAmount.selector);
        vault.withdraw(address(newToken), treasuryAddr, 0);
    }

    // ==========
    // View Tests
    // ==========

    function test_getReserves() public {
        // Before any migration
        (uint256 oldReserve, uint256 newReserve) = vault.getReserves();
        assertEq(oldReserve, 0);
        assertEq(newReserve, VAULT_RESERVE);

        // After a migration
        uint256 amountIn = 100 * 10 ** OLD_DECIMALS;
        vm.prank(user);
        vault.migrate(user, amountIn);

        (oldReserve, newReserve) = vault.getReserves();
        assertEq(oldReserve, amountIn);
        assertEq(newReserve, VAULT_RESERVE - 100 ether);
    }

    function test_getDecimals() public view {
        (uint8 oldDec, uint8 newDec) = vault.getDecimals();
        assertEq(oldDec, OLD_DECIMALS);
        assertEq(newDec, NEW_DECIMALS);
    }

    // =============
    // Upgrade Tests
    // =============

    function test_upgrade_byAdmin() public {
        MigrationVault newImpl = new MigrationVault();

        vm.prank(admin);
        vault.upgradeToAndCall(address(newImpl), "");

        // Verify state preserved
        assertEq(address(vault.OLD_TOKEN()), address(oldToken));
        assertEq(address(vault.NEW_TOKEN()), address(newToken));
    }

    function test_upgrade_revertsNonAdmin() public {
        MigrationVault newImpl = new MigrationVault();

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                attacker,
                defaultAdminRole
            )
        );
        vm.prank(attacker);
        vault.upgradeToAndCall(address(newImpl), "");
    }

    // ==========
    // Fuzz Tests
    // ==========

    function testFuzz_migrate(uint256 amountIn) public {
        // Bound to valid range: at least 1 unit, at most user balance
        amountIn = bound(amountIn, 1, USER_BALANCE);

        uint256 expectedOut = amountIn * (10 ** (NEW_DECIMALS - OLD_DECIMALS));

        // Ensure vault has enough reserves
        if (expectedOut > VAULT_RESERVE) return;

        vm.prank(user);
        uint256 amountOut = vault.migrate(user, amountIn);

        assertEq(amountOut, expectedOut);
        assertEq(oldToken.balanceOf(user), USER_BALANCE - amountIn);
        assertEq(newToken.balanceOf(user), expectedOut);
    }

    function testFuzz_previewMatchesMigrate(uint256 amountIn) public {
        amountIn = bound(amountIn, 1, USER_BALANCE);

        uint256 preview = vault.previewMigrate(amountIn);

        if (preview > VAULT_RESERVE || preview == 0) return;

        vm.prank(user);
        uint256 actual = vault.migrate(user, amountIn);

        assertEq(preview, actual);
    }

    function testFuzz_migrate_conservesValue(uint256 amountIn) public view {
        amountIn = bound(amountIn, 1, USER_BALANCE);

        uint256 amountOut = vault.previewMigrate(amountIn);

        // Value in WAD should be equal (1:1 conversion)
        uint256 valueInWad = amountIn * vault.oldToWad();
        uint256 valueOutWad = amountOut * vault.newToWad();
        assertEq(valueInWad, valueOutWad);
    }

    // ========================
    // Access Control Edge Cases
    // ========================

    function test_adminCanGrantTreasuryRole() public {
        address newTreasury = makeAddr("newTreasury");

        vm.prank(admin);
        vault.grantRole(treasuryRole, newTreasury);

        assertTrue(vault.hasRole(treasuryRole, newTreasury));
    }

    function test_nonAdminCannotGrantRoles() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                attacker,
                defaultAdminRole
            )
        );
        vm.prank(attacker);
        vault.grantRole(treasuryRole, attacker);
    }

    // ==================
    // Constants Tests
    // ==================

    function test_constants() public view {
        assertEq(vault.WAD(), 1e18);
        assertEq(vault.MAX_DECIMALS(), 18);
        assertEq(vault.TREASURY_ROLE(), keccak256("TREASURY_ROLE"));
        assertEq(vault.PAUSER_ROLE(), keccak256("PAUSER_ROLE"));
        assertEq(vault.UNPAUSER_ROLE(), keccak256("UNPAUSER_ROLE"));
    }
}
