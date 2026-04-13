// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BaseSetup} from "./BaseSetup.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {IOAppCore} from "@layerzerolabs/oapp-evm/contracts/oapp/interfaces/IOAppCore.sol";
import {NativeBridge} from "../../src/NativeBridge.sol";
import {NativeOFTAdapter} from "@layerzerolabs/oft-evm/contracts/NativeOFTAdapter.sol";
import {SendParam, OFTReceipt} from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";
import {MessagingFee, MessagingReceipt} from "@layerzerolabs/oapp-evm/contracts/oapp/OApp.sol";

/**
 * @title NativeBridgeLzSendTest
 * @notice Tests for NativeBridge.send() — locking native TEL and dispatching to satellite chains.
 */
contract NativeBridgeLzSendTest is BaseSetup {
    function setUp() public override {
        super.setUp();
    }

    // ----------
    // Send Tests
    // ----------

    function test_NativeSend_Success() public {
        uint256 bridgeAmount = 10 ether;
        bytes memory options = _createBasicOptions();
        SendParam memory sendParam = _createSendParam(EID_A, user1, bridgeAmount, options);

        uint256 nativeBefore = address(nativeBridge).balance;

        vm.startPrank(user1);
        MessagingFee memory fee = nativeBridge.quoteSend(sendParam, false);
        (MessagingReceipt memory receipt, ) = nativeBridge.send{value: fee.nativeFee + bridgeAmount}(sendParam, fee, user1);
        vm.stopPrank();

        // NativeBridge locks the bridged amount (balance increases by bridgeAmount)
        assertEq(address(nativeBridge).balance, nativeBefore + bridgeAmount);
        assertTrue(receipt.guid != bytes32(0));
        assertEq(receipt.fee.nativeFee, fee.nativeFee);
    }

    function test_NativeSend_EmitsEvent() public {
        uint256 bridgeAmount = 10 ether;
        bytes memory options = _createBasicOptions();
        SendParam memory sendParam = _createSendParam(EID_A, user1, bridgeAmount, options);

        vm.startPrank(user1);
        MessagingFee memory fee = nativeBridge.quoteSend(sendParam, false);

        // OFTSent has 2 indexed params (guid, fromAddress); dstEid is non-indexed
        vm.expectEmit(false, true, false, true);
        emit OFTSent(bytes32(0), EID_A, user1, bridgeAmount, bridgeAmount);

        nativeBridge.send{value: fee.nativeFee + bridgeAmount}(sendParam, fee, user1);
        vm.stopPrank();
    }

    function test_NativeSend_RevertWhenPaused() public {
        uint256 bridgeAmount = 10 ether;
        bytes memory options = _createBasicOptions();
        SendParam memory sendParam = _createSendParam(EID_A, user1, bridgeAmount, options);

        vm.prank(owner);
        nativeBridge.pause();

        vm.startPrank(user1);
        MessagingFee memory fee = nativeBridge.quoteSend(sendParam, false);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        nativeBridge.send{value: fee.nativeFee + bridgeAmount}(sendParam, fee, user1);
        vm.stopPrank();
    }

    function test_NativeSend_RevertNoPeer() public {
        // Deploy a NativeBridge with no peer set for EID_A
        vm.startPrank(owner);
        NativeBridge bridgeNoPeer = new NativeBridge(address(endpointTN), owner);
        vm.stopPrank();
        vm.deal(address(bridgeNoPeer), NATIVE_RESERVE);

        SendParam memory sendParam = _createSendParam(EID_A, user1, 10 ether, _createBasicOptions());

        // Skip quoteSend — it also calls _getPeerOrRevert internally
        vm.startPrank(user1);
        vm.expectRevert(abi.encodeWithSelector(IOAppCore.NoPeer.selector, EID_A));
        bridgeNoPeer.send{value: 0.1 ether + 10 ether}(sendParam, MessagingFee(0.1 ether, 0), user1);
        vm.stopPrank();
    }

    function test_NativeSend_RevertIncorrectMsgValue() public {
        uint256 bridgeAmount = 10 ether;
        bytes memory options = _createBasicOptions();
        SendParam memory sendParam = _createSendParam(EID_A, user1, bridgeAmount, options);

        vm.startPrank(user1);
        MessagingFee memory fee = nativeBridge.quoteSend(sendParam, false);

        // Send only the fee, not fee + amount — NativeOFTAdapter enforces exact msg.value
        uint256 provided = fee.nativeFee;
        uint256 required = fee.nativeFee + bridgeAmount;
        vm.expectRevert(abi.encodeWithSelector(NativeOFTAdapter.IncorrectMessageValue.selector, provided, required));
        nativeBridge.send{value: provided}(sendParam, fee, user1);
        vm.stopPrank();
    }

    function test_NativeSend_ToBothSatellites() public {
        uint256 bridgeAmount = 5 ether;
        bytes memory options = _createBasicOptions();

        uint256 nativeBefore = address(nativeBridge).balance;

        // Send to satellite A
        SendParam memory sendParamA = _createSendParam(EID_A, user1, bridgeAmount, options);
        vm.startPrank(user1);
        MessagingFee memory feeA = nativeBridge.quoteSend(sendParamA, false);
        nativeBridge.send{value: feeA.nativeFee + bridgeAmount}(sendParamA, feeA, user1);
        vm.stopPrank();

        // Send to satellite B
        SendParam memory sendParamB = _createSendParam(EID_B, user2, bridgeAmount, options);
        vm.startPrank(user2);
        MessagingFee memory feeB = nativeBridge.quoteSend(sendParamB, false);
        nativeBridge.send{value: feeB.nativeFee + bridgeAmount}(sendParamB, feeB, user2);
        vm.stopPrank();

        assertEq(address(nativeBridge).balance, nativeBefore + bridgeAmount + bridgeAmount);
    }

    function testFuzz_NativeSend(uint256 amount) public {
        // Minimum 1e12 to avoid full dust removal; max 50 ether (user has 100 ether, need room for fee)
        amount = bound(amount, 1e12, 50 ether);

        bytes memory options = _createBasicOptions();
        SendParam memory sendParam = _createSendParam(EID_A, user1, amount, options);

        uint256 nativeBefore = address(nativeBridge).balance;

        // NativeOFTAdapter requires msg.value == fee + _removeDust(amount)
        uint256 amountDustRemoved = (amount / 1e12) * 1e12;

        vm.startPrank(user1);
        MessagingFee memory fee = nativeBridge.quoteSend(sendParam, false);
        nativeBridge.send{value: fee.nativeFee + amountDustRemoved}(sendParam, fee, user1);
        vm.stopPrank();

        assertEq(address(nativeBridge).balance, nativeBefore + amountDustRemoved);
    }
}