// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BaseSetup} from "./BaseSetup.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {Origin} from "@layerzerolabs/oapp-evm/contracts/oapp/OApp.sol";

contract TelcoinBridgeLzReceiveTest is BaseSetup {
    function setUp() public override {
        super.setUp();
    }

    // ---------------
    // LzReceive Tests
    // ---------------

    function test_LzReceive_MintsTokens() public {
        uint256 mintAmount = 2000 ether;
        uint256 preSupply = telcoinB.totalSupply();

        Origin memory origin = Origin({srcEid: EID_A, sender: _addressToBytes32(address(bridgeA)), nonce: 1});

        vm.prank(address(endpointB));
        bridgeB.lzReceive(origin, keccak256("test-guid"), _encodeOFTMessage(user1, mintAmount), address(0), bytes(""));

        assertEq(telcoinB.balanceOf(user1), mintAmount);
        assertEq(telcoinB.totalSupply(), preSupply + mintAmount);
    }

    function test_LzReceive_EmitsEvent() public {
        uint256 mintAmount = 3000 ether;
        bytes32 guid = keccak256("test-guid-2");

        Origin memory origin = Origin({srcEid: EID_A, sender: _addressToBytes32(address(bridgeA)), nonce: 1});

        // OFTReceived has 2 indexed params (guid, toAddress); srcEid is non-indexed data
        vm.expectEmit(true, true, false, true);
        emit OFTReceived(guid, EID_A, user2, mintAmount);

        vm.prank(address(endpointB));
        bridgeB.lzReceive(origin, guid, _encodeOFTMessage(user2, mintAmount), address(0), bytes(""));
    }

    function test_LzReceive_RevertNotEndpoint() public {
        Origin memory origin = Origin({srcEid: EID_A, sender: _addressToBytes32(address(bridgeA)), nonce: 1});

        vm.prank(user1);
        vm.expectRevert();
        bridgeB.lzReceive(origin, keccak256("test-guid"), _encodeOFTMessage(user1, 1000 ether), address(0), bytes(""));
    }

    function test_LzReceive_RevertInvalidPeer() public {
        Origin memory origin = Origin({srcEid: EID_A, sender: _addressToBytes32(address(0x999)), nonce: 1});

        vm.prank(address(endpointB));
        vm.expectRevert();
        bridgeB.lzReceive(origin, keccak256("test-guid"), _encodeOFTMessage(user1, 1000 ether), address(0), bytes(""));
    }

    function test_LzReceive_RevertWhenPaused() public {
        Origin memory origin = Origin({srcEid: EID_A, sender: _addressToBytes32(address(bridgeA)), nonce: 1});

        vm.prank(owner);
        bridgeB.pause();

        vm.prank(address(endpointB));
        vm.expectRevert(Pausable.EnforcedPause.selector);
        bridgeB.lzReceive(origin, keccak256("test-guid"), _encodeOFTMessage(user1, 1 ether), address(0), bytes(""));
    }

    function testFuzz_LzReceive(address recipient, uint64 amountSD) public {
        vm.assume(recipient != address(0));
        vm.assume(amountSD > 0);

        // amountLD is the local-decimal amount after SD → LD conversion
        uint256 amountLD = uint256(amountSD) * 1e12;

        uint256 preSupply = telcoinB.totalSupply();
        uint256 preBal = telcoinB.balanceOf(recipient);

        Origin memory origin = Origin({srcEid: EID_A, sender: _addressToBytes32(address(bridgeA)), nonce: 1});

        bytes memory message = abi.encodePacked(bytes32(uint256(uint160(recipient))), amountSD);

        vm.prank(address(endpointB));
        bridgeB.lzReceive(origin, keccak256(abi.encodePacked(recipient, amountSD)), message, address(0), bytes(""));

        assertEq(telcoinB.balanceOf(recipient), preBal + amountLD);
        assertEq(telcoinB.totalSupply(), preSupply + amountLD);
    }
}