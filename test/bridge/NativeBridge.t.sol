// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BaseSetup} from "./BaseSetup.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {NativeBridge} from "../../src/NativeBridge.sol";

/**
 * @title NativeBridgeTest
 * @notice Constructor and admin function tests for NativeBridge.
 */
contract NativeBridgeTest is BaseSetup {
    function setUp() public override {
        super.setUp();
    }

    // -------------------
    // Initial State Tests
    // -------------------

    /// @notice Native token is address(0), owner is set correctly, and initial reserve is funded.
    function test_Constructor() public view {
        assertEq(nativeBridge.token(), address(0));
        assertEq(nativeBridge.owner(), owner);
        assertFalse(nativeBridge.approvalRequired());
        assertEq(address(nativeBridge).balance, NATIVE_RESERVE);
    }

    // ----------------------------
    // Permissioned Functions Tests
    // ----------------------------

    /// @notice Owner can rescue ERC20 tokens accidentally sent to the bridge to a specified address.
    function test_RescueTokens() public {
        uint256 stuckAmount = 100 ether;
        vm.prank(user1);
        telcoinA.transfer(address(nativeBridge), stuckAmount);

        uint256 user2Before = telcoinA.balanceOf(user2);

        vm.prank(owner);
        nativeBridge.rescueTokens(address(telcoinA), stuckAmount, user2);

        assertEq(telcoinA.balanceOf(address(nativeBridge)), 0);
        assertEq(telcoinA.balanceOf(user2), user2Before + stuckAmount);
    }

    /// @notice rescueTokens reverts when called by a non-owner.
    function test_RescueTokens_RevertNotOwner() public {
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user1));
        nativeBridge.rescueTokens(address(telcoinA), 100, user2);
    }

    /// @notice rescueTokens reverts when _to is the zero address.
    function test_RescueTokens_RevertZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(NativeBridge.ZeroAddress.selector);
        nativeBridge.rescueTokens(address(telcoinA), 100, address(0));
    }

    /// @notice rescueTokens reverts when _amount is zero.
    function test_RescueTokens_RevertZeroAmount() public {
        vm.prank(owner);
        vm.expectRevert(NativeBridge.ZeroAmount.selector);
        nativeBridge.rescueTokens(address(telcoinA), 0, user2);
    }

    /// @notice Owner can pause the bridge.
    function test_Pause() public {
        vm.prank(owner);
        nativeBridge.pause();
        assertTrue(nativeBridge.paused());
    }

    /// @notice pause reverts when called by an address without PAUSER_ROLE.
    function test_Pause_RevertNotPauser() public {
        vm.prank(user1);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, user1, PAUSER_ROLE)
        );
        nativeBridge.pause();
    }

    /// @notice Owner can unpause the bridge after pausing.
    function test_Unpause() public {
        vm.startPrank(owner);
        nativeBridge.pause();
        nativeBridge.unpause();
        assertFalse(nativeBridge.paused());
        vm.stopPrank();
    }

    /// @notice unpause reverts when called by an address without UNPAUSER_ROLE.
    function test_Unpause_RevertNotUnpauser() public {
        vm.prank(owner);
        nativeBridge.pause();

        vm.prank(user1);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, user1, UNPAUSER_ROLE)
        );
        nativeBridge.unpause();
    }

    /// @notice A dedicated pauser can pause but not unpause; a dedicated unpauser can unpause but not pause.
    function test_PauseUnpause_roleSeparation() public {
        address pauserBot = makeAddr("pauserBot");
        address unpauserGov = makeAddr("unpauserGov");

        vm.startPrank(owner);
        nativeBridge.grantRole(PAUSER_ROLE, pauserBot);
        nativeBridge.grantRole(UNPAUSER_ROLE, unpauserGov);
        vm.stopPrank();

        vm.prank(pauserBot);
        nativeBridge.pause();
        assertTrue(nativeBridge.paused());

        vm.prank(pauserBot);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, pauserBot, UNPAUSER_ROLE)
        );
        nativeBridge.unpause();

        vm.prank(unpauserGov);
        nativeBridge.unpause();
        assertFalse(nativeBridge.paused());

        vm.prank(unpauserGov);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, unpauserGov, PAUSER_ROLE)
        );
        nativeBridge.pause();
    }

    /// @notice A role holder cannot renounce; admin cannot self-revoke its own admin role.
    function test_AccessControl_renounceAndSelfRevokeGuards() public {
        bytes32 adminRole = nativeBridge.DEFAULT_ADMIN_ROLE();

        vm.prank(owner);
        vm.expectRevert(NativeBridge.CannotRenounceRole.selector);
        nativeBridge.renounceRole(PAUSER_ROLE, owner);

        vm.prank(owner);
        vm.expectRevert(NativeBridge.CannotRenounceRole.selector);
        nativeBridge.revokeRole(adminRole, owner);
    }

    /// @notice The bridge accepts native ETH sent directly, increasing the reserve and emitting ReserveFunded.
    function test_Receive_DirectFunding() public {
        uint256 reserveBefore = address(nativeBridge).balance;
        uint256 fundAmount = 50 ether;

        vm.deal(user1, fundAmount);
        vm.expectEmit(true, false, false, true);
        emit NativeBridge.ReserveFunded(user1, fundAmount);

        vm.prank(user1);
        (bool success, ) = address(nativeBridge).call{value: fundAmount}("");

        assertTrue(success);
        assertEq(address(nativeBridge).balance, reserveBefore + fundAmount);
    }

    // ----------------------
    // Ownership Safety Tests
    // ----------------------

    /// @notice transferOwnership sets pendingOwner but does not change owner yet (two-step).
    function test_TransferOwnership_SetsPendingOwner() public {
        address newOwner = makeAddr("newOwner");
        vm.prank(owner);
        nativeBridge.transferOwnership(newOwner);

        assertEq(nativeBridge.pendingOwner(), newOwner);
        assertEq(nativeBridge.owner(), owner);
    }

    /// @notice Ownership transfer completes only after the pending owner calls acceptOwnership().
    function test_TransferOwnership_AcceptOwnership() public {
        address newOwner = makeAddr("newOwner");

        vm.prank(owner);
        nativeBridge.transferOwnership(newOwner);

        vm.prank(newOwner);
        nativeBridge.acceptOwnership();

        assertEq(nativeBridge.owner(), newOwner);
    }

    /// @notice renounceOwnership always reverts to prevent bricking bridge configuration.
    function test_RenounceOwnership_Reverts() public {
        vm.prank(owner);
        vm.expectRevert(NativeBridge.CannotRenounceOwnership.selector);
        nativeBridge.renounceOwnership();
    }

    /// @notice The initial owner holds DEFAULT_ADMIN_ROLE after construction.
    function test_OwnershipAdminBinding_initialOwnerIsAdmin() public view {
        assertTrue(nativeBridge.hasRole(nativeBridge.DEFAULT_ADMIN_ROLE(), owner));
    }

    /// @notice Accepting ownership grants DEFAULT_ADMIN_ROLE to the new owner and revokes it from
    ///         the old owner atomically, so the two authority systems cannot diverge.
    function test_OwnershipAdminBinding_followsAcceptedTransfer() public {
        address newOwner = makeAddr("newOwner");
        bytes32 adminRole = nativeBridge.DEFAULT_ADMIN_ROLE();

        vm.prank(owner);
        nativeBridge.transferOwnership(newOwner);

        // pending transfer must not move admin yet
        assertTrue(nativeBridge.hasRole(adminRole, owner));
        assertFalse(nativeBridge.hasRole(adminRole, newOwner));

        vm.prank(newOwner);
        nativeBridge.acceptOwnership();

        // admin now tracks ownership exactly
        assertTrue(nativeBridge.hasRole(adminRole, newOwner));
        assertFalse(nativeBridge.hasRole(adminRole, owner));
        assertEq(nativeBridge.getRoleMemberCount(adminRole), 1);
    }

    /// @notice After handover the old owner can no longer administer roles; the new owner can.
    function test_OwnershipAdminBinding_oldOwnerLosesRoleAdmin() public {
        address newOwner = makeAddr("newOwner");
        bytes32 adminRole = nativeBridge.DEFAULT_ADMIN_ROLE();

        vm.prank(owner);
        nativeBridge.transferOwnership(newOwner);
        vm.prank(newOwner);
        nativeBridge.acceptOwnership();

        address someBot = makeAddr("someBot");
        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, owner, adminRole)
        );
        nativeBridge.grantRole(PAUSER_ROLE, someBot);

        vm.prank(newOwner);
        nativeBridge.grantRole(PAUSER_ROLE, someBot);
        assertTrue(nativeBridge.hasRole(PAUSER_ROLE, someBot));
    }

    /// @notice The LayerZero endpoint delegate tracks ownership: it starts as the initial owner
    ///         and rotates to the new owner on acceptOwnership, so a former owner cannot retain
    ///         endpoint-configuration authority.
    function test_DelegateFollowsOwnership() public {
        address newOwner = makeAddr("newOwner");

        // baseline: delegate is the initial owner (set at construction)
        assertEq(endpointTN.delegates(address(nativeBridge)), owner);

        vm.prank(owner);
        nativeBridge.transferOwnership(newOwner);

        // pending transfer must not move the delegate yet
        assertEq(endpointTN.delegates(address(nativeBridge)), owner);

        vm.prank(newOwner);
        nativeBridge.acceptOwnership();

        // delegate now tracks the new owner; the former owner is no longer endpoint-authorized
        assertEq(endpointTN.delegates(address(nativeBridge)), newOwner);
    }
}