// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {TelcoinV3} from "../src/TelcoinV3.sol";
import {TelcoinV3BaseSetup} from "./BaseSetup.sol";

/**
 * @title TelcoinV3Test
 * @notice Core TelcoinV3 test suite covering supply caps, minting, burning, pausability,
 *         access control, role management, and token rescue functionality.
 */
contract TelcoinV3Test is TelcoinV3BaseSetup {
    // ---------------------
    // Supply Cap Tests
    // ---------------------

    /// @dev Constructor succeeds when initialSupply_ is zero (no initial mint).
    function test_Constructor_ZeroSupply() public {
        TelcoinV3 t = new TelcoinV3(0, owner);
        assertEq(t.totalSupply(), 0);
    }

    /// @dev Constructor succeeds when initialSupply_ is exactly the cap.
    function test_Constructor_SupplyAtCap() public {
        TelcoinV3 t = new TelcoinV3(token.MIGRATION_SUPPLY_CAP(), owner);
        assertEq(t.totalSupply(), token.MIGRATION_SUPPLY_CAP());
    }

    /// @dev Constructor reverts when initialSupply_ exceeds the 100B cap.
    function test_RevertIf_Constructor_SupplyExceedsCap() public {
        // Cache the cap before arming vm.expectRevert — evaluating token.MIGRATION_SUPPLY_CAP()
        // inline would itself be the "next call" that Foundry intercepts, consuming the expectation
        // before the constructor is ever reached.
        uint256 cap = token.MIGRATION_SUPPLY_CAP();
        vm.expectRevert(TelcoinV3.SupplyCapExceeded.selector);
        new TelcoinV3(cap + 1, owner);
    }

    /// @dev mint() succeeds when the resulting total supply equals the cap exactly.
    function test_Mint_UpToSupplyCap() public {
        uint256 remaining = token.MIGRATION_SUPPLY_CAP() - token.totalSupply();

        vm.prank(bridge);
        token.mint(user, remaining);

        assertEq(token.totalSupply(), token.MIGRATION_SUPPLY_CAP());
    }

    /// @dev mint() reverts with SupplyCapExceeded when the resulting total supply would exceed the cap.
    function test_RevertIf_Mint_ExceedsSupplyCap() public {
        uint256 remaining = token.MIGRATION_SUPPLY_CAP() - token.totalSupply();

        vm.prank(bridge);
        vm.expectRevert(TelcoinV3.SupplyCapExceeded.selector);
        token.mint(user, remaining + 1);
    }

    /// @dev Verifies the bridge (given the minter role) can mint tokens
    function test_BridgeCanMint() public {
        uint256 preBalance = token.balanceOf(user);

        vm.prank(bridge);
        token.mint(user, MINT_AMOUNT);

        assertEq(token.balanceOf(user), preBalance + MINT_AMOUNT);
    }

    /// @dev Verifies an attacker (given no minter role) cannot mint tokens
    function test_RevertIf_NonBridgeMints() public {
        vm.prank(attacker);
        vm.expectRevert();
        token.mint(user, MINT_AMOUNT);
    }

    /// @dev Verifies the bride (given the burner role) can burn tokens
    function test_BridgeCanBurn() public {
        vm.prank(bridge);
        token.mint(user, MINT_AMOUNT);

        uint256 preBalance = token.balanceOf(user);

        vm.prank(user);
        token.approve(bridge, MINT_AMOUNT);

        vm.prank(bridge);
        token.burn(user, MINT_AMOUNT);

        assertEq(token.balanceOf(user), preBalance - MINT_AMOUNT);
    }

    /// @dev Verifies an attacker (given no burner role) cannot burn tokens
    function test_RevertIf_NonBridgeBurns() public {
        vm.prank(bridge);
        token.mint(user, MINT_AMOUNT);

        vm.prank(attacker);
        vm.expectRevert();
        token.burn(user, MINT_AMOUNT);
    }

    /// @dev Verifies owner can pause and unpause transfers
    function test_OwnerCanPauseAndUnpause() public {
        assertFalse(token.paused());

        vm.prank(owner);
        token.pause();
        assertTrue(token.paused());

        vm.prank(owner);
        token.unpause();
        assertFalse(token.paused());
    }

    /// @dev Verifies an attacker cannot pause token
    function test_RevertIf_NonOwnerPauses() public {
        vm.prank(attacker);
        vm.expectRevert(
            abi.encodeWithSignature("AccessControlUnauthorizedAccount(address,bytes32)", attacker, PAUSER_ROLE)
        );
        token.pause();
    }

    /// @dev Verifies a mint after a pause will revert
    function test_MintingWhilePaused() public {
        vm.prank(owner);
        token.pause();

        uint256 preBalance = token.balanceOf(user);

        vm.prank(bridge);
        token.mint(user, MINT_AMOUNT);

        assertEq(token.balanceOf(user), preBalance + MINT_AMOUNT);
    }

    /// @dev Verifies burning after a pause is successful
    function test_BurningWhilePaused() public {
        vm.prank(bridge);
        token.mint(user, MINT_AMOUNT);

        vm.prank(user);
        token.approve(bridge, MINT_AMOUNT);

        vm.prank(owner);
        token.pause();

        uint256 preBalance = token.balanceOf(user);

        vm.prank(bridge);
        token.burn(user, MINT_AMOUNT);

        assertEq(token.balanceOf(user), preBalance - MINT_AMOUNT);
    }

    /// @notice burn reverts when the caller has no allowance from the token holder.
    function test_RevertIf_BurnWithoutApproval() public {
        vm.prank(bridge);
        token.mint(user, MINT_AMOUNT);

        vm.prank(bridge);
        vm.expectRevert();
        token.burn(user, MINT_AMOUNT);
    }

    // ----------------
    // rescueBurn Tests
    // ----------------

    /// @notice Admin can burn from any wallet without approval.
    function test_RescueBurn() public {
        vm.prank(bridge);
        token.mint(user, MINT_AMOUNT);

        uint256 preSupply = token.totalSupply();

        vm.prank(owner);
        token.rescueBurn(user, MINT_AMOUNT);

        assertEq(token.balanceOf(user), 0);
        assertEq(token.totalSupply(), preSupply - MINT_AMOUNT);
    }

    /// @notice rescueBurn reverts when called by a BURNER_ROLE holder (not admin).
    function test_RevertIf_BurnerCannotRescueBurn() public {
        vm.prank(bridge);
        token.mint(user, MINT_AMOUNT);

        vm.prank(bridge);
        vm.expectRevert();
        token.rescueBurn(user, MINT_AMOUNT);
    }

    /// @notice rescueBurn reverts when called by an unpermissioned address.
    function test_RevertIf_NonAdminCannotRescueBurn() public {
        vm.prank(bridge);
        token.mint(user, MINT_AMOUNT);

        vm.prank(attacker);
        vm.expectRevert();
        token.rescueBurn(user, MINT_AMOUNT);
    }

    // -------------------
    // rescueTokens Tests
    // -------------------

    /// @dev Admin can recover ERC20 tokens accidentally sent to the TelcoinV3 contract to a specified address.
    function test_RescueTokens() public {
        uint256 stuckAmount = 100 ether;

        // Simulate tokens accidentally sent directly to the token contract
        vm.prank(bridge);
        token.mint(address(token), stuckAmount);

        uint256 user2Before = token.balanceOf(user2);

        vm.prank(owner);
        token.rescueTokens(address(token), stuckAmount, user2);

        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.balanceOf(user2), user2Before + stuckAmount);
    }

    /// @dev rescueTokens reverts when _to is the zero address.
    function test_RevertIf_RescueTokens_ZeroAddress() public {
        vm.prank(bridge);
        token.mint(address(token), 100 ether);

        vm.prank(owner);
        vm.expectRevert(TelcoinV3.ZeroAddress.selector);
        token.rescueTokens(address(token), 100 ether, address(0));
    }

    /// @dev rescueTokens reverts when _amount is zero.
    function test_RevertIf_RescueTokens_ZeroAmount() public {
        vm.prank(owner);
        vm.expectRevert(TelcoinV3.ZeroAmount.selector);
        token.rescueTokens(address(token), 0, user2);
    }

    /// @dev rescueTokens reverts when called by an address without DEFAULT_ADMIN_ROLE.
    function test_RevertIf_NonAdminRescuesTokens() public {
        vm.prank(bridge);
        token.mint(address(token), 100 ether);

        vm.prank(attacker);
        vm.expectRevert(
            abi.encodeWithSignature("AccessControlUnauthorizedAccount(address,bytes32)", attacker, bytes32(0))
        );
        token.rescueTokens(address(token), 100 ether, user2);
    }

    /// @dev Verifies transfers fail after contract is paused
    function test_RevertIf_TransferWhilePaused() public {
        vm.prank(bridge);
        token.mint(user, MINT_AMOUNT);

        vm.prank(owner);
        token.pause();

        vm.prank(user);
        vm.expectRevert();
        token.transfer(user2, MINT_AMOUNT);

        vm.prank(owner);
        token.unpause();

        uint256 preBalance = token.balanceOf(user2);

        vm.prank(user);
        token.transfer(user2, MINT_AMOUNT);

        assertEq(token.balanceOf(user2), preBalance + MINT_AMOUNT);
    }

    /// @notice Admin can revoke a permissioned role from a holder; revoked address loses access.
    function test_AdminCanRevokeRole() public {
        vm.prank(owner);
        token.revokeRole(MINTER_ROLE, bridge);

        assertFalse(token.hasRole(MINTER_ROLE, bridge));

        vm.prank(bridge);
        vm.expectRevert();
        token.mint(user, MINT_AMOUNT);
    }

    /// @notice Admin can grant DEFAULT_ADMIN_ROLE to another address.
    function test_AdminCanGrantAdminRole() public {
        address newAdmin = makeAddr("newAdmin");
        bytes32 adminRole = token.DEFAULT_ADMIN_ROLE();

        vm.prank(owner);
        token.grantRole(adminRole, newAdmin);

        assertTrue(token.hasRole(adminRole, newAdmin));

        // New admin can grant roles too
        vm.prank(newAdmin);
        token.grantRole(MINTER_ROLE, user);
        assertTrue(token.hasRole(MINTER_ROLE, user));
    }

    /// @notice A role holder cannot renounce their own role.
    function test_RevertIf_RenounceRole() public {
        vm.prank(bridge);
        vm.expectRevert(TelcoinV3.CannotRenounceRole.selector);
        token.renounceRole(MINTER_ROLE, bridge);
    }

    /// @notice The DEFAULT_ADMIN_ROLE holder cannot renounce either.
    function test_RevertIf_AdminCannotRenounceRole() public {
        bytes32 adminRole = token.DEFAULT_ADMIN_ROLE();
        vm.prank(owner);
        vm.expectRevert(TelcoinV3.CannotRenounceRole.selector);
        token.renounceRole(adminRole, owner);
    }

    /// @notice An admin cannot bypass the renounce ban by revoking its own DEFAULT_ADMIN_ROLE.
    function test_RevertIf_AdminSelfRevokesAdminRole() public {
        bytes32 adminRole = token.DEFAULT_ADMIN_ROLE();
        vm.prank(owner);
        vm.expectRevert(TelcoinV3.CannotRenounceRole.selector);
        token.revokeRole(adminRole, owner);
    }

    /// @notice An admin may still revoke its own non-admin roles (recoverable via re-grant).
    function test_AdminCanSelfRevokeNonAdminRole() public {
        vm.startPrank(owner);
        token.grantRole(MINTER_ROLE, owner);
        assertTrue(token.hasRole(MINTER_ROLE, owner));

        token.revokeRole(MINTER_ROLE, owner);
        assertFalse(token.hasRole(MINTER_ROLE, owner));
        vm.stopPrank();
    }

    /// @notice Admin handover: grant the new admin, then the new admin revokes the old one.
    function test_AdminHandover() public {
        address newAdmin = makeAddr("newAdmin");
        bytes32 adminRole = token.DEFAULT_ADMIN_ROLE();

        vm.prank(owner);
        token.grantRole(adminRole, newAdmin);

        // new admin revokes the old admin (revoker != target, so the guard permits it)
        vm.prank(newAdmin);
        token.revokeRole(adminRole, owner);

        assertFalse(token.hasRole(adminRole, owner));
        assertTrue(token.hasRole(adminRole, newAdmin));

        // new admin retains full role administration
        vm.prank(newAdmin);
        token.grantRole(MINTER_ROLE, user);
        assertTrue(token.hasRole(MINTER_ROLE, user));
    }
}
