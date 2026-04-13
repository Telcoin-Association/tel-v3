// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BaseSetup} from "./BaseSetup.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {NativeBridge} from "../../src/NativeBridge.sol";
import {SendParam, OFTReceipt} from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";
import {MessagingFee, MessagingReceipt} from "@layerzerolabs/oapp-evm/contracts/oapp/OApp.sol";

/**
 * @title NativeBridgeTest
 * @notice General state, full round-trip, and admin tests for NativeBridge.
 */
contract NativeBridgeTest is BaseSetup {
    function setUp() public override {
        super.setUp();
    }

    // -------------------
    // Initial State Tests
    // -------------------

    function test_Constructor() public view {
        assertEq(nativeBridge.token(), address(0));
        assertEq(nativeBridge.owner(), owner);
        assertFalse(nativeBridge.approvalRequired());
        assertEq(address(nativeBridge).balance, NATIVE_RESERVE);
    }

    // ----------------
    // Round Trip Tests
    // ----------------

    /// @dev Satellite A burns ERC20 TEL → NativeBridge credits native TEL to recipient.
    function test_FullRoundTrip_SatelliteToTN() public {
        uint256 bridgeAmount = 1000 ether;
        bytes memory options = _createBasicOptions();
        SendParam memory sendParam = _createSendParam(EID_TN, user1, bridgeAmount, options);

        uint256 user1ERC20Before = telcoinA.balanceOf(user1);
        uint256 user1NativeBefore = user1.balance;

        // Burn ERC20 on satellite A, pay LZ fee in native
        vm.startPrank(user1);
        MessagingFee memory fee = bridgeA.quoteSend(sendParam, false);
        (MessagingReceipt memory receipt, ) = bridgeA.send{value: fee.nativeFee}(sendParam, fee, user1);
        vm.stopPrank();

        assertEq(telcoinA.balanceOf(user1), user1ERC20Before - bridgeAmount);

        // Simulate delivery on TelcoinNetwork — NativeBridge transfers native TEL
        endpointTN.deliverPacket(
            EID_A,
            _addressToBytes32(address(bridgeA)),
            1,
            receipt.guid,
            _encodeOFTMessage(user1, bridgeAmount),
            address(nativeBridge)
        );

        assertEq(user1.balance, user1NativeBefore - fee.nativeFee + bridgeAmount);
        assertEq(address(nativeBridge).balance, NATIVE_RESERVE - bridgeAmount);
    }

    /// @dev NativeBridge locks native TEL → satellite A mints ERC20 TEL to recipient.
    function test_FullRoundTrip_TNToSatellite() public {
        uint256 bridgeAmount = 10 ether;
        bytes memory options = _createBasicOptions();
        SendParam memory sendParam = _createSendParam(EID_A, user1, bridgeAmount, options);

        uint256 user1ERC20Before = telcoinA.balanceOf(user1);

        // Lock native TEL in NativeBridge (msg.value = fee + amount)
        vm.startPrank(user1);
        MessagingFee memory fee = nativeBridge.quoteSend(sendParam, false);
        (MessagingReceipt memory receipt, ) = nativeBridge.send{value: fee.nativeFee + bridgeAmount}(sendParam, fee, user1);
        vm.stopPrank();

        assertEq(address(nativeBridge).balance, NATIVE_RESERVE + bridgeAmount);

        // Simulate delivery on satellite A — bridge mints ERC20
        endpointA.deliverPacket(
            EID_TN,
            _addressToBytes32(address(nativeBridge)),
            1,
            receipt.guid,
            _encodeOFTMessage(user1, bridgeAmount),
            address(bridgeA)
        );

        assertEq(telcoinA.balanceOf(user1), user1ERC20Before + bridgeAmount);
    }

    // -----------------
    // Precision Tests
    // -----------------

    /// @dev Fuzzes over shared-decimal amounts: native TEL locked → exact same ERC20 TEL minted on satellite.
    ///      Using uint64 amountSD guarantees no dust: amountLD = amountSD * 1e12 is always cleanly convertible.
    function testFuzz_Precision_TNToSatellite(uint64 amountSD) public {
        // Bound so amountLD fits within user1's 100 ether native budget (minus fee headroom)
        amountSD = uint64(bound(amountSD, 1, 50_000_000)); // max 50 TEL
        uint256 amountLD = uint256(amountSD) * 1e12;

        SendParam memory sendParam = _createSendParam(EID_A, user1, amountLD, _createBasicOptions());
        uint256 erc20Before = telcoinA.balanceOf(user1);

        vm.startPrank(user1);
        MessagingFee memory fee = nativeBridge.quoteSend(sendParam, false);
        (MessagingReceipt memory receipt, ) = nativeBridge.send{value: fee.nativeFee + amountLD}(sendParam, fee, user1);
        vm.stopPrank();

        endpointA.deliverPacket(EID_TN, _addressToBytes32(address(nativeBridge)), 1, receipt.guid, _encodeOFTMessage(user1, amountLD), address(bridgeA));

        assertEq(telcoinA.balanceOf(user1), erc20Before + amountLD);
    }

    /// @dev Fuzzes over shared-decimal amounts: ERC20 TEL burned on satellite → exact same native TEL credited on TN.
    function testFuzz_Precision_SatelliteToTN(uint64 amountSD) public {
        // Bound so amountLD fits within user1's ERC20 balance (USER_BALANCE = 1_000_000 ether)
        amountSD = uint64(bound(amountSD, 1, uint64(USER_BALANCE / 1e12)));
        uint256 amountLD = uint256(amountSD) * 1e12;

        SendParam memory sendParam = _createSendParam(EID_TN, user1, amountLD, _createBasicOptions());
        uint256 nativeBefore = user1.balance;

        vm.startPrank(user1);
        MessagingFee memory fee = bridgeA.quoteSend(sendParam, false);
        (MessagingReceipt memory receipt, ) = bridgeA.send{value: fee.nativeFee}(sendParam, fee, user1);
        vm.stopPrank();

        assertEq(telcoinA.balanceOf(user1), USER_BALANCE - amountLD);

        endpointTN.deliverPacket(EID_A, _addressToBytes32(address(bridgeA)), 1, receipt.guid, _encodeOFTMessage(user1, amountLD), address(nativeBridge));

        assertEq(user1.balance, nativeBefore - fee.nativeFee + amountLD);
    }

    /// @dev Full bi-directional cycle: satellite → TN → satellite, back to original state.
    function test_FullRoundTrip_Complete() public {
        uint256 bridgeAmount = 500 ether;
        uint256 erc20Before = telcoinA.balanceOf(user1);

        _stepSatelliteToTN(bridgeAmount);
        assertEq(telcoinA.balanceOf(user1), erc20Before - bridgeAmount);

        _stepTNToSatellite(bridgeAmount);
        assertEq(telcoinA.balanceOf(user1), erc20Before);
    }

    /// @dev Burns ERC20 TEL on satellite A and delivers the packet to NativeBridge on TelcoinNetwork.
    function _stepSatelliteToTN(uint256 bridgeAmount) internal {
        bytes memory options = _createBasicOptions();
        SendParam memory toTN = _createSendParam(EID_TN, user1, bridgeAmount, options);
        vm.startPrank(user1);
        MessagingFee memory fee = bridgeA.quoteSend(toTN, false);
        (MessagingReceipt memory receipt, ) = bridgeA.send{value: fee.nativeFee}(toTN, fee, user1);
        vm.stopPrank();
        endpointTN.deliverPacket(EID_A, _addressToBytes32(address(bridgeA)), 1, receipt.guid, _encodeOFTMessage(user1, bridgeAmount), address(nativeBridge));
    }

    /// @dev Locks native TEL in NativeBridge on TelcoinNetwork and delivers the packet to satellite A.
    function _stepTNToSatellite(uint256 bridgeAmount) internal {
        bytes memory options = _createBasicOptions();
        SendParam memory toA = _createSendParam(EID_A, user1, bridgeAmount, options);
        vm.startPrank(user1);
        MessagingFee memory fee = nativeBridge.quoteSend(toA, false);
        (MessagingReceipt memory receipt, ) = nativeBridge.send{value: fee.nativeFee + bridgeAmount}(toA, fee, user1);
        vm.stopPrank();
        endpointA.deliverPacket(EID_TN, _addressToBytes32(address(nativeBridge)), 1, receipt.guid, _encodeOFTMessage(user1, bridgeAmount), address(bridgeA));
    }

    // ----------------------------
    // Permissioned Functions Tests
    // ----------------------------

    function test_WithdrawNative() public {
        uint256 withdrawAmount = 100 ether;
        uint256 ownerBefore = owner.balance;

        vm.prank(owner);
        nativeBridge.withdrawNative(withdrawAmount);

        assertEq(address(nativeBridge).balance, NATIVE_RESERVE - withdrawAmount);
        assertEq(owner.balance, ownerBefore + withdrawAmount);
    }

    function test_WithdrawNative_RevertNotOwner() public {
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user1));
        nativeBridge.withdrawNative(1 ether);
    }

    function test_WithdrawNative_RevertInsufficientBalance() public {
        vm.prank(owner);
        vm.expectRevert(NativeBridge.WithdrawFailed.selector);
        nativeBridge.withdrawNative(NATIVE_RESERVE + 1);
    }

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

    function test_RescueTokens_RevertNotOwner() public {
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user1));
        nativeBridge.rescueTokens(address(telcoinA), 100);
    }

    function test_Pause() public {
        vm.prank(owner);
        nativeBridge.pause();
        assertTrue(nativeBridge.paused());
    }

    function test_Pause_RevertNotOwner() public {
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user1));
        nativeBridge.pause();
    }

    function test_Unpause() public {
        vm.startPrank(owner);
        nativeBridge.pause();
        nativeBridge.unpause();
        assertFalse(nativeBridge.paused());
        vm.stopPrank();
    }

    function test_Unpause_RevertNotOwner() public {
        vm.prank(owner);
        nativeBridge.pause();

        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user1));
        nativeBridge.unpause();
    }

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

    function test_TransferOwnership_SetsPendingOwner() public {
        address newOwner = makeAddr("newOwner");
        vm.prank(owner);
        nativeBridge.transferOwnership(newOwner);

        assertEq(nativeBridge.pendingOwner(), newOwner);
        assertEq(nativeBridge.owner(), owner);
    }

    function test_TransferOwnership_AcceptOwnership() public {
        address newOwner = makeAddr("newOwner");

        vm.prank(owner);
        nativeBridge.transferOwnership(newOwner);

        vm.prank(newOwner);
        nativeBridge.acceptOwnership();

        assertEq(nativeBridge.owner(), newOwner);
    }

    function test_RenounceOwnership_Reverts() public {
        vm.prank(owner);
        vm.expectRevert(NativeBridge.CannotRenounceOwnership.selector);
        nativeBridge.renounceOwnership();
    }
}