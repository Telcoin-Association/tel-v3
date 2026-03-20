// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BaseSetup} from "./BaseSetup.sol";
import {Origin} from "@layerzerolabs/oapp-evm/contracts/oapp/OApp.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {TelcoinBridge} from "../../src/TelcoinBridge.sol";

/**
 * @title TelcoinBridgeLzReceiveTest
 * @notice This test file is meant to verify the basic functions of the TelcoinBridge::lzReceive function.
 */
contract TelcoinBridgeLzReceiveTest is BaseSetup {
    function setUp() public override {
        super.setUp();
    }

    // ---------------
    // LzReceive Tests
    // ---------------

    /// @dev Verifies proper state changes when TelcoinBridge::lzReceive is executed successfully.
    function test_LzReceive_MintsTokens() public {
        uint256 mintAmount = 2000 ether;
        uint256 preSupply = telcoinB.totalSupply();

        // Simulate receiving a cross-chain message
        Origin memory origin = Origin({
            srcEid: EID_A,
            sender: _addressToBytes32(address(bridgeA)),
            nonce: 1
        });

        bytes memory message = abi.encode(user1, mintAmount);
        bytes32 guid = keccak256("test-guid");

        // Call lzReceive from endpoint (simulated)
        vm.prank(address(endpointB));
        bridgeB.lzReceive(origin, guid, message, address(0), bytes(""));

        // Verify tokens were minted
        assertEq(telcoinB.balanceOf(user1), mintAmount);
        assertEq(telcoinB.totalSupply(), preSupply + mintAmount);
    }

    /// @dev Verifies the `BridgeReceived` event is emitted during a successful call to
    ///      TelcoinBridge::lzReceive.
    function test_LzReceive_EmitsEvent() public {
        uint256 mintAmount = 3000 ether;

        Origin memory origin = Origin({
            srcEid: EID_A,
            sender: _addressToBytes32(address(bridgeA)),
            nonce: 1
        });

        bytes memory message = abi.encode(user2, mintAmount);
        bytes32 guid = keccak256("test-guid-2");

        vm.expectEmit(true, true, true, true);
        emit BridgeReceived(guid, EID_A, user2, mintAmount);

        vm.prank(address(endpointB));
        bridgeB.lzReceive(origin, guid, message, address(0), bytes(""));
    }

    /// @dev Verifies TelcoinBridge::lzReceive can only be called by the lz endpoint.
    function test_LzReceive_RevertNotEndpoint() public {
        Origin memory origin = Origin({
            srcEid: EID_A,
            sender: _addressToBytes32(address(bridgeA)),
            nonce: 1
        });

        bytes memory message = abi.encode(user1, 1000);
        bytes32 guid = keccak256("test-guid");

        // Should revert when called by non-endpoint
        vm.prank(user1);
        vm.expectRevert();
        bridgeB.lzReceive(origin, guid, message, address(0), bytes(""));
    }

    /// @dev Verifies TelcoinBridge::lzReceive reverts when a sender is not connected to a peer.
    function test_LzReceive_RevertInvalidPeer() public {
        Origin memory origin = Origin({
            srcEid: EID_A,
            sender: _addressToBytes32(address(0x999)), // Wrong sender
            nonce: 1
        });

        bytes memory message = abi.encode(user1, 1000);
        bytes32 guid = keccak256("test-guid");

        vm.prank(address(endpointB));
        vm.expectRevert();
        bridgeB.lzReceive(origin, guid, message, address(0), bytes(""));
    }

    /// @dev Using fuzzing, verifies proper state changes when TelcoinBridge::lzReceive is
    ///      executed successfully.
    function testFuzz_LzReceive(address recipient, uint256 amount) public {
        vm.assume(recipient != address(0));
        vm.assume(amount > 0 && amount < type(uint128).max);

        uint256 preSupply = telcoinB.totalSupply();
        uint256 preBal = telcoinB.balanceOf(recipient);

        Origin memory origin = Origin({
            srcEid: EID_A,
            sender: _addressToBytes32(address(bridgeA)),
            nonce: 1
        });

        bytes memory message = abi.encode(recipient, amount);
        bytes32 guid = keccak256(abi.encodePacked(recipient, amount));

        vm.prank(address(endpointB));
        bridgeB.lzReceive(origin, guid, message, address(0), bytes(""));

        assertEq(telcoinB.balanceOf(recipient), preBal + amount);
        assertEq(telcoinB.totalSupply(), preSupply + amount);
    }

    /// @dev Verifies if contract is paused, a call to _lzReceive will revert.
    function test_LzReceive_RevertWhenPaused() public {
        uint256 mintAmount = 1 ether;

        // Simulate receiving a cross-chain message
        Origin memory origin = Origin({
            srcEid: EID_A,
            sender: _addressToBytes32(address(bridgeA)),
            nonce: 1
        });

        bytes memory message = abi.encode(user1, mintAmount);
        bytes32 guid = keccak256("test-guid");

        vm.prank(owner);
        bridgeB.pause();

        // Call lzReceive from endpoint (simulated)
        vm.prank(address(endpointB));
        vm.expectRevert(Pausable.EnforcedPause.selector);
        bridgeB.lzReceive(origin, guid, message, address(0), bytes(""));
    }
}
