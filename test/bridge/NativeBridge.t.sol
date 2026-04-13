// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BaseSetup} from "./BaseSetup.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
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

    /// @notice Owner can withdraw native TEL from the reserve.
    function test_WithdrawNative() public {
        uint256 withdrawAmount = 100 ether;
        uint256 ownerBefore = owner.balance;

        vm.prank(owner);
        nativeBridge.withdrawNative(withdrawAmount);

        assertEq(address(nativeBridge).balance, NATIVE_RESERVE - withdrawAmount);
        assertEq(owner.balance, ownerBefore + withdrawAmount);
    }

    /// @notice withdrawNative reverts when called by a non-owner.
    function test_WithdrawNative_RevertNotOwner() public {
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user1));
        nativeBridge.withdrawNative(1 ether);
    }

    /// @notice withdrawNative reverts when the requested amount exceeds the reserve balance.
    function test_WithdrawNative_RevertInsufficientBalance() public {
        vm.prank(owner);
        vm.expectRevert(NativeBridge.WithdrawFailed.selector);
        nativeBridge.withdrawNative(NATIVE_RESERVE + 1);
    }

    /// @notice Owner can rescue ERC20 tokens accidentally sent to the bridge.
    function test_RescueTokens() public {
        uint256 stuckAmount = 100 ether;
        vm.prank(user1);
        telcoinA.transfer(address(nativeBridge), stuckAmount);

        uint256 ownerBefore = telcoinA.balanceOf(owner);

        vm.prank(owner);
        nativeBridge.rescueTokens(address(telcoinA), stuckAmount);

        assertEq(telcoinA.balanceOf(address(nativeBridge)), 0);
        assertEq(telcoinA.balanceOf(owner), ownerBefore + stuckAmount);
    }

    /// @notice rescueTokens reverts when called by a non-owner.
    function test_RescueTokens_RevertNotOwner() public {
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user1));
        nativeBridge.rescueTokens(address(telcoinA), 100);
    }

    /// @notice Owner can pause the bridge.
    function test_Pause() public {
        vm.prank(owner);
        nativeBridge.pause();
        assertTrue(nativeBridge.paused());
    }

    /// @notice pause reverts when called by a non-owner.
    function test_Pause_RevertNotOwner() public {
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user1));
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

    /// @notice unpause reverts when called by a non-owner.
    function test_Unpause_RevertNotOwner() public {
        vm.prank(owner);
        nativeBridge.pause();

        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user1));
        nativeBridge.unpause();
    }

    /// @notice The bridge accept native ETH sent directly, increasing the reserve.
    function test_Receive_DirectFunding() public {
        uint256 reserveBefore = address(nativeBridge).balance;
        uint256 fundAmount = 50 ether;

        vm.deal(user1, fundAmount);
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
}