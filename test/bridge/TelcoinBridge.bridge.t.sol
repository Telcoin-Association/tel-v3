// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BaseSetup} from "./BaseSetup.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {MessagingFee, MessagingReceipt} from "@layerzerolabs/oapp-evm/contracts/oapp/OApp.sol";
import {IOAppCore} from "@layerzerolabs/oapp-evm/contracts/oapp/interfaces/IOAppCore.sol";
import {TelcoinBridge} from "../../src/TelcoinBridge.sol";
import {ITelcoinBridge} from "../../src/interfaces/ITelcoinBridge.sol";

/**
 * @title TelcoinBridgeBridgeTest
 * @notice This test file is meant to verify the basic functions of the TelcoinBridge::bridge function.
 */
contract TelcoinBridgeBridgeTest is BaseSetup {
    function setUp() public override {
        super.setUp();
    }

    // ------------
    // Bridge Tests
    // ------------

    /// @dev Verifies successful call to TelcoinBridge::bridge with no expectation of txn landing.
    function test_Bridge_Success() public {
        uint256 bridgeAmount = 1000 ether;
        bytes memory options = _createBasicOptions();
        uint256 preSupply = telcoinA.totalSupply();

        // Get quote
        MessagingFee memory fee = bridgeA.quote(EID_B, user2, bridgeAmount, options);

        // Check balances before
        uint256 user1BalanceBefore = telcoinA.balanceOf(user1);

        // Bridge tokens
        vm.prank(user1);
        MessagingReceipt memory receipt = bridgeA.bridge{value: fee.nativeFee}(
            EID_B,
            user2,
            bridgeAmount,
            options
        );

        // Verify tokens were burned on chain A
        assertEq(telcoinA.balanceOf(user1), user1BalanceBefore - bridgeAmount);
        assertEq(telcoinA.totalSupply(), preSupply - bridgeAmount);

        // Verify receipt
        assertTrue(receipt.guid != bytes32(0));
        assertEq(receipt.fee.nativeFee, fee.nativeFee);
    }

    /// @dev Verifies a successful call to bridge emits the intended `BridgeSent` event.
    function test_Bridge_EmitsEvent() public {
        uint256 bridgeAmount = 1000 ether;
        bytes memory options = _createBasicOptions();

        vm.startPrank(user1);
        MessagingFee memory fee = bridgeA.quote(EID_B, user1, bridgeAmount, options);

        // Check event (guid is unpredictable, so we use false for first indexed param)
        vm.expectEmit(false, true, true, true);
        emit BridgeSent(bytes32(0), EID_B, user1, user1, bridgeAmount);

        bridgeA.bridge{value: fee.nativeFee}(EID_B, user1, bridgeAmount, options);
        vm.stopPrank();
    }

    /// @dev Verifies if amount == 0, contract reverts with the `ZeroAmount` error.
    function test_Bridge_RevertZeroAmount() public {
        bytes memory options = _createBasicOptions();

        vm.startPrank(user1);
        vm.expectRevert(ITelcoinBridge.ZeroAmount.selector);
        bridgeA.bridge{value: 0.1 ether}(EID_B, user1, 0, options);
        vm.stopPrank();
    }

    /// @dev Verifies if recipient == address(0), contract reverts with the `ZeroAddress` error.
    function test_Bridge_RevertZeroRecipient() public {
        bytes memory options = _createBasicOptions();

        vm.startPrank(user1);
        vm.expectRevert(ITelcoinBridge.ZeroAddress.selector);
        bridgeA.bridge{value: 0.1 ether}(EID_B, address(0), 1000, options);
        vm.stopPrank();
    }

    /// @dev Verifies if contract is paused, a call to bridge will revert.
    function test_Bridge_RevertWhenPaused() public {
        bytes memory options = _createBasicOptions();

        vm.prank(owner);
        bridgeA.pause();

        vm.startPrank(user1);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        bridgeA.bridge{value: 0.1 ether}(EID_B, user1, 1000, options);
        vm.stopPrank();
    }

    /// @dev Verifies if contract is bridged to a chain with no peer, contract reverts.
    function test_Bridge_RevertNoPeer() public {
        // Deploy a new bridge without setting peer
        TelcoinBridge bridgeNoPeer = new TelcoinBridge(
            address(telcoinA),
            address(endpointA),
            owner
        );

        // Set bridgeNoPeer as the bridge so it can burn
        vm.prank(owner);
        telcoinA.setBridge(address(bridgeNoPeer));

        bytes memory options = _createBasicOptions();

        vm.startPrank(user1);
        vm.expectRevert(abi.encodeWithSelector(IOAppCore.NoPeer.selector, EID_B));
        bridgeNoPeer.bridge{value: 0.1 ether}(EID_B, user1, 1000, options);
        vm.stopPrank();
    }

    /// @dev Uses fuzzing to verify successful call to TelcoinBridge::bridge with no expectation of
    ///      txn landing.
    function testFuzz_Bridge(uint256 amount) public {
        // Bound amount to valid range
        amount = bound(amount, 1, USER_BALANCE);

        bytes memory options = _createBasicOptions();
        uint256 balanceBefore = telcoinA.balanceOf(user1);
        uint256 preSupply = telcoinA.totalSupply();

        vm.startPrank(user1);
        MessagingFee memory fee = bridgeA.quote(EID_B, user1, amount, options);
        bridgeA.bridge{value: fee.nativeFee}(EID_B, user1, amount, options);
        vm.stopPrank();

        // Verify burn on source chain
        assertEq(telcoinA.balanceOf(user1), balanceBefore - amount);
        assertEq(telcoinA.totalSupply(), preSupply - amount);
    }
}
