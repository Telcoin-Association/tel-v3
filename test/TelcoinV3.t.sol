// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import {TelcoinV3} from "../src/TelcoinV3.sol";

contract TelcoinV3Test is Test {
    TelcoinV3 internal token;

    address internal owner = makeAddr("owner");
    address internal bridge = makeAddr("bridge");
    address internal user = makeAddr("user");
    address internal attacker = makeAddr("attacker");

    uint256 internal constant INITIAL_SUPPLY = 10_000_000_000 ether;
    uint256 internal constant MINT_AMOUNT = 500 ether;

    function setUp() public {
        vm.prank(owner);
        token = new TelcoinV3(
            INITIAL_SUPPLY, // initialSupply_
            owner, // owner_
            makeAddr("migration") // migration_
        );

        vm.prank(owner);
        token.setBridge(bridge);
    }

    function test_BridgeCanMint() public {
        uint256 preBalance = token.balanceOf(user);

        vm.prank(bridge);
        token.mint(user, MINT_AMOUNT);

        assertEq(token.balanceOf(user), preBalance + MINT_AMOUNT);
    }

    function test_RevertIf_NonBridgeMints() public {
        vm.prank(attacker);
        vm.expectRevert(TelcoinV3.NotBridge.selector);
        token.mint(user, MINT_AMOUNT);
    }

    function test_BridgeCanBurn() public {
        vm.prank(bridge);
        token.mint(user, MINT_AMOUNT);

        uint256 preBalance = token.balanceOf(user);

        vm.prank(bridge);
        token.burn(user, MINT_AMOUNT);

        assertEq(token.balanceOf(user), preBalance - MINT_AMOUNT);
    }

    function test_RevertIf_NonBridgeBurns() public {
        vm.prank(bridge);
        token.mint(user, MINT_AMOUNT);

        vm.prank(attacker);
        vm.expectRevert(TelcoinV3.NotBridge.selector);
        token.burn(user, MINT_AMOUNT);
    }

    function test_OwnerCanSetBridge() public {
        address newBridge = makeAddr("newBridge");

        vm.prank(owner);
        token.setBridge(newBridge);

        assertEq(token.bridge(), newBridge);
    }

    function test_RevertIf_NonOwnerSetsBridge() public {
        vm.prank(attacker);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", attacker));
        token.setBridge(attacker);
    }

    function test_RevertIf_SetBridgeToZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(TelcoinV3.ZeroAddress.selector);
        token.setBridge(address(0));
    }

    function test_SetBridge_EmitsEvent() public {
        address newBridge = makeAddr("newBridge");

        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit TelcoinV3.BridgeSet(newBridge);
        token.setBridge(newBridge);
    }

    function test_OwnerCanPauseAndUnpause() public {
        assertFalse(token.paused());

        vm.prank(owner);
        token.pause();
        assertTrue(token.paused());

        vm.prank(owner);
        token.unpause();
        assertFalse(token.paused());
    }

    function test_RevertIf_NonOwnerPauses() public {
        vm.prank(attacker);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", attacker));
        token.pause();
    }

    function test_RevertIf_MintingWhilePaused() public {
        vm.prank(owner);
        token.pause();

        vm.prank(bridge);
        vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
        token.mint(user, MINT_AMOUNT);
    }

    function test_RevertIf_BurningWhilePaused() public {
        vm.prank(bridge);
        token.mint(user, MINT_AMOUNT);

        vm.prank(owner);
        token.pause();

        vm.prank(bridge);
        vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
        token.burn(user, MINT_AMOUNT);
    }
}
