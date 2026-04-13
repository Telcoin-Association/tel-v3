// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BaseSetup} from "./BaseSetup.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {Origin} from "@layerzerolabs/oapp-evm/contracts/oapp/OApp.sol";
import {IOAppCore} from "@layerzerolabs/oapp-evm/contracts/oapp/interfaces/IOAppCore.sol";
import {OAppReceiver} from "@layerzerolabs/oapp-evm/contracts/oapp/OAppReceiver.sol";

/**
 * @title NativeBridgeLzReceiveTest
 * @notice Tests for NativeBridge lzReceive — crediting native TEL to recipients from satellite chains.
 */
contract NativeBridgeLzReceiveTest is BaseSetup {
    function setUp() public override {
        super.setUp();
    }

    // ---------------
    // LzReceive Tests
    // ---------------

    /// @notice lzReceive credits native TEL to the recipient and decreases the reserve.
    function test_NativeLzReceive_CreditsNativeTEL() public {
        uint256 receiveAmount = 2000 ether;

        uint256 recipientBefore = user1.balance;
        uint256 reserveBefore = address(nativeBridge).balance;

        Origin memory origin = Origin({srcEid: EID_A, sender: _addressToBytes32(address(bridgeA)), nonce: 1});

        vm.prank(address(endpointTN));
        nativeBridge.lzReceive(origin, keccak256("test-guid"), _encodeOFTMessage(user1, receiveAmount), address(0), bytes(""));

        assertEq(user1.balance, recipientBefore + receiveAmount);
        assertEq(address(nativeBridge).balance, reserveBefore - receiveAmount);
    }

    /// @notice lzReceive emits OFTReceived with the correct guid, srcEid, recipient, and amount.
    function test_NativeLzReceive_EmitsEvent() public {
        uint256 receiveAmount = 3000 ether;
        bytes32 guid = keccak256("test-guid-2");

        Origin memory origin = Origin({srcEid: EID_A, sender: _addressToBytes32(address(bridgeA)), nonce: 1});

        // OFTReceived has 2 indexed params (guid, toAddress); srcEid is non-indexed
        vm.expectEmit(true, true, false, true);
        emit OFTReceived(guid, EID_A, user2, receiveAmount);

        vm.prank(address(endpointTN));
        nativeBridge.lzReceive(origin, guid, _encodeOFTMessage(user2, receiveAmount), address(0), bytes(""));
    }

    /// @notice lzReceive credits native TEL when the origin is satellite chain B.
    function test_NativeLzReceive_FromSatelliteB() public {
        uint256 receiveAmount = 500 ether;

        uint256 recipientBefore = user2.balance;

        Origin memory origin = Origin({srcEid: EID_B, sender: _addressToBytes32(address(bridgeB)), nonce: 1});

        vm.prank(address(endpointTN));
        nativeBridge.lzReceive(origin, keccak256("test-guid-b"), _encodeOFTMessage(user2, receiveAmount), address(0), bytes(""));

        assertEq(user2.balance, recipientBefore + receiveAmount);
    }

    /// @notice lzReceive reverts with OnlyEndpoint when called by an address other than the LZ endpoint.
    function test_NativeLzReceive_RevertNotEndpoint() public {
        Origin memory origin = Origin({srcEid: EID_A, sender: _addressToBytes32(address(bridgeA)), nonce: 1});

        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(OAppReceiver.OnlyEndpoint.selector, user1));
        nativeBridge.lzReceive(origin, keccak256("test-guid"), _encodeOFTMessage(user1, 1000 ether), address(0), bytes(""));
    }

    /// @notice lzReceive reverts with OnlyPeer when the origin sender is not the registered peer.
    function test_NativeLzReceive_RevertInvalidPeer() public {
        bytes32 fakeSender = _addressToBytes32(address(0x999));
        Origin memory origin = Origin({srcEid: EID_A, sender: fakeSender, nonce: 1});

        vm.prank(address(endpointTN));
        vm.expectRevert(abi.encodeWithSelector(IOAppCore.OnlyPeer.selector, EID_A, fakeSender));
        nativeBridge.lzReceive(origin, keccak256("test-guid"), _encodeOFTMessage(user1, 1000 ether), address(0), bytes(""));
    }

    /// @notice lzReceive reverts with EnforcedPause when the bridge is paused.
    function test_NativeLzReceive_RevertWhenPaused() public {
        Origin memory origin = Origin({srcEid: EID_A, sender: _addressToBytes32(address(bridgeA)), nonce: 1});

        vm.prank(owner);
        nativeBridge.pause();

        vm.prank(address(endpointTN));
        vm.expectRevert(Pausable.EnforcedPause.selector);
        nativeBridge.lzReceive(origin, keccak256("test-guid"), _encodeOFTMessage(user1, 1 ether), address(0), bytes(""));
    }

    /// @notice lzReceive credits exactly the correct native TEL amount for any valid recipient and shared-decimal amount.
    function testFuzz_NativeLzReceive(address recipient, uint64 amountSD) public {
        vm.assume(recipient != address(0));
        vm.assume(amountSD > 0);

        uint256 amountLD = uint256(amountSD) * 1e12;

        // Ensure reserve can cover the credit
        vm.assume(amountLD <= address(nativeBridge).balance);

        uint256 reserveBefore = address(nativeBridge).balance;
        uint256 recipientBefore = recipient.balance;

        Origin memory origin = Origin({srcEid: EID_A, sender: _addressToBytes32(address(bridgeA)), nonce: 1});

        bytes memory message = abi.encodePacked(bytes32(uint256(uint160(recipient))), amountSD);

        vm.prank(address(endpointTN));
        nativeBridge.lzReceive(origin, keccak256(abi.encodePacked(recipient, amountSD)), message, address(0), bytes(""));

        assertEq(recipient.balance, recipientBefore + amountLD);
        assertEq(address(nativeBridge).balance, reserveBefore - amountLD);
    }
}