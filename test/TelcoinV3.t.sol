// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import {TelcoinV3} from "../src/TelcoinV3.sol";
import {Roles} from "../src/helpers/Roles.sol";

contract TelcoinV3Test is Test, Roles {
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
            owner // owner_
        );

        vm.startPrank(owner);
        token.grantRole(MINTER_ROLE, address(bridge));
        token.grantRole(BURNER_ROLE, address(bridge));
        token.grantRole(PAUSER_ROLE, address(owner));
        token.grantRole(UNPAUSER_ROLE, address(owner));
        vm.stopPrank();
    }

    function test_BridgeCanMint() public {
        uint256 preBalance = token.balanceOf(user);

        vm.prank(bridge);
        token.mint(user, MINT_AMOUNT);

        assertEq(token.balanceOf(user), preBalance + MINT_AMOUNT);
    }

    function test_RevertIf_NonBridgeMints() public {
        vm.prank(attacker);
        vm.expectRevert();
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
        vm.expectRevert();
        token.burn(user, MINT_AMOUNT);
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
        vm.expectRevert(
            abi.encodeWithSignature("AccessControlUnauthorizedAccount(address,bytes32)", attacker, PAUSER_ROLE)
        );
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
