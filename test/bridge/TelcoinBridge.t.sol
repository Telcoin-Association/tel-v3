// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BaseSetup} from "./BaseSetup.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Origin, MessagingFee, MessagingReceipt} from "@layerzerolabs/oapp-evm/contracts/oapp/OApp.sol";
import {TelcoinBridge} from "../../src/TelcoinBridge.sol";
import {ITelcoinBridge} from "../../src/interfaces/ITelcoinBridge.sol";

/**
 * @title TelcoinBridgeTest
 * @notice This test file is meant to verify the basic functions of the TelcoinBridge contract.
 */
contract TelcoinBridgeTest is BaseSetup {
    function setUp() public override {
        super.setUp();
    }

    // -------------------
    // Initial State Tests
    // -------------------

    /// @dev Verifies initial state of the TelcoinBridge contract.
    function test_Constructor() public view {
        assertEq(address(bridgeA.telcoin()), address(telcoinA));
        assertEq(bridgeA.owner(), owner);
        assertEq(bridgeA.dstGasLimit(), 200_000);
    }

    // ----------------
    // Round Trip Tests
    // ----------------

    /// @dev Verifies a round trip bridging of tokens from chain A to chain B and back to chain A.
    function test_FullRoundTrip() public {
        uint256 bridgeAmount = 5000 ether;
        bytes memory options = _createBasicOptions();

        // STEP 1: Bridge from A to B
        vm.startPrank(user1);
        MessagingFee memory feeAtoB = bridgeA.quote(EID_B, user1, bridgeAmount, options);
        MessagingReceipt memory receiptAtoB = bridgeA.bridge{value: feeAtoB.nativeFee}(
            EID_B,
            user1,
            bridgeAmount,
            options
        );
        vm.stopPrank();

        // Verify burn on chain A
        assertEq(telcoinA.balanceOf(user1), USER_BALANCE - bridgeAmount);

        // Simulate delivery on chain B using mock endpoint
        endpointB.deliverPacket(
            EID_A,
            _addressToBytes32(address(bridgeA)),
            1, // nonce
            receiptAtoB.guid,
            abi.encode(user1, bridgeAmount),
            address(bridgeB)
        );

        // Verify mint on chain B
        assertEq(telcoinB.balanceOf(user1), bridgeAmount);

        // STEP 2: Bridge back from B to A
        vm.startPrank(user1);
        MessagingFee memory feeBtoA = bridgeB.quote(EID_A, user1, bridgeAmount, options);
        MessagingReceipt memory receiptBtoA = bridgeB.bridge{value: feeBtoA.nativeFee}(
            EID_A,
            user1,
            bridgeAmount,
            options
        );
        vm.stopPrank();

        // Verify burn on chain B
        assertEq(telcoinB.balanceOf(user1), 0);

        // Simulate delivery on chain A
        endpointA.deliverPacket(
            EID_B,
            _addressToBytes32(address(bridgeB)),
            1, // nonce
            receiptBtoA.guid,
            abi.encode(user1, bridgeAmount),
            address(bridgeA)
        );

        // Verify mint on chain A - back to original balance
        assertEq(telcoinA.balanceOf(user1), USER_BALANCE);
    }

    // -----------
    // Quote Tests
    // -----------

    /// @dev Verifies the quote method returns the intended values.
    function test_Quote() public view {
        bytes memory options = _createBasicOptions();

        MessagingFee memory fee = bridgeA.quote(EID_B, user1, 1000, options);

        // Fee should be non-zero (mock returns 0.001 ether)
        assertEq(fee.nativeFee, 0.001 ether);
        assertEq(fee.lzTokenFee, 0);
    }

    /// @dev Verifies the quote method returns the intended fees with different amounts.
    function test_Quote_DifferentAmountsSameFee() public view {
        bytes memory options = _createBasicOptions();

        // Quote for different amounts - fee should be the same since payload size is same
        MessagingFee memory fee1 = bridgeA.quote(EID_B, user1, 1000, options);
        MessagingFee memory fee2 = bridgeA.quote(EID_B, user1, 1_000_000, options);

        // Fees should be equal (same payload structure)
        assertEq(fee1.nativeFee, fee2.nativeFee);
    }

    // ----------------------------
    // Permissioned Functions Tests
    // ----------------------------

    // ~ setDstGasLimit ~

    /// @dev Verifies TelcoinBridge::setDstGasLimit results in the expected state changes.
    function test_SetDstGasLimit() public {
        uint128 newGasLimit = 300_000;

        vm.prank(owner);
        bridgeA.setDstGasLimit(newGasLimit);

        assertEq(bridgeA.dstGasLimit(), newGasLimit);
    }

    /// @dev Verifies TelcoinBridge::setDstGasLimit emits the `DstGasLimitSet` event.
    function test_SetDstGasLimit_EmitsEvent() public {
        uint128 newGasLimit = 400_000;

        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit DstGasLimitSet(newGasLimit);

        bridgeA.setDstGasLimit(newGasLimit);
    }

    /// @dev Verifies TelcoinBridge::setDstGasLimit can only be called by the owner.
    function test_SetDstGasLimit_RevertNotOwner() public {
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user1));
        bridgeA.setDstGasLimit(300_000);
    }

    // ~ pause/unpause ~

    /// @dev Verifies TelcoinBridge::pause results in the expected state changes.
    function test_Pause() public {
        vm.prank(owner);
        bridgeA.pause();

        assertTrue(bridgeA.paused());
    }

    /// @dev Verifies TelcoinBridge::pause can only be called by the owner.
    function test_Pause_RevertNotOwner() public {
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user1));
        bridgeA.pause();
    }

    /// @dev Verifies TelcoinBridge::unpause results in the expected state changes.
    function test_Unpause() public {
        vm.startPrank(owner);
        bridgeA.pause();
        assertTrue(bridgeA.paused());

        bridgeA.unpause();
        assertFalse(bridgeA.paused());
        vm.stopPrank();
    }

    /// @dev Verifies TelcoinBridge::unpause can only be called by the owner.
    function test_Unpause_RevertNotOwner() public {
        vm.prank(owner);
        bridgeA.pause();

        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user1));
        bridgeA.unpause();
    }

    // ~ rescueTokens ~

    /// @dev Verifies TelcoinBridge::rescueTokens results in the expected state changes.
    function test_RescueTokens() public {
        // Send some tokens to the bridge accidentally
        uint256 stuckAmount = 100 ether;
        vm.prank(user1);
        telcoinA.transfer(address(bridgeA), stuckAmount);

        uint256 bridgeBalanceBefore = telcoinA.balanceOf(address(bridgeA));
        uint256 ownerBalanceBefore = telcoinA.balanceOf(owner);

        assertEq(bridgeBalanceBefore, stuckAmount);

        // Rescue tokens
        vm.prank(owner);
        bridgeA.rescueTokens(address(telcoinA), stuckAmount);

        assertEq(telcoinA.balanceOf(address(bridgeA)), 0);
        assertEq(telcoinA.balanceOf(owner), ownerBalanceBefore + stuckAmount);
    }

    /// @dev Verifies TelcoinBridge::rescueTokens can only be called by the owner.
    function test_RescueTokens_RevertNotOwner() public {
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user1));
        bridgeA.rescueTokens(address(telcoinA), 100);
    }

    /// @dev Verifies TelcoinBridge::rescueTokens reverts if amount == 0.
    function test_RescueTokens_RevertZeroAmount() public {
        vm.prank(owner);
        vm.expectRevert(ITelcoinBridge.ZeroAmount.selector);
        bridgeA.rescueTokens(address(telcoinA), 0);
    }

    /// @dev Verifies TelcoinBridge::rescueTokens reverts if token == address(0).
    function test_RescueTokens_RevertZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(ITelcoinBridge.ZeroAddress.selector);
        bridgeA.rescueTokens(address(0), 100);
    } 
}
