// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import {TelcoinV3} from "../src/TelcoinV3.sol";
import {RolesConstants} from "interchain-token-service/contracts/utils/RolesConstants.sol";

contract TelcoinV3Test is Test {
    TelcoinV3 internal token;

    address internal owner = makeAddr("owner");
    address internal minterAddr = makeAddr("minter");
    address internal user = makeAddr("user");
    address internal attacker = makeAddr("attacker");

    uint256 internal constant INITIAL_SUPPLY = 10_000_000_000 ether;
    uint256 internal constant MINT_AMOUNT = 500 ether;

    // Define custom errors defined in TelcoinV3 for expectRevert
    error NotMinter(address addr);

    function setUp() public {
        vm.prank(owner);
        token = new TelcoinV3(
            INITIAL_SUPPLY, // initialSupply_
            owner,          // owner_
            makeAddr("migration"), // migration_
            makeAddr("originTEL"), // originTEL_
            makeAddr("originLinker"), // originLinker_
            keccak256("salt"), // originSalt_
            "Ethereum",     // originChainName_
            makeAddr("its") // interchainTokenService_
        );

        vm.prank(owner);
        token.transferMintership(minterAddr);
    }

    function test_OwnerCanRemoveMinter() public {
        assertTrue(token.hasRole(minterAddr, uint8(RolesConstants.Roles.MINTER)));

        vm.prank(owner);
        token.removeMinter(minterAddr);

        assertFalse(token.hasRole(minterAddr, uint8(RolesConstants.Roles.MINTER)));
    }

    function test_RevertIf_NonOwnerRemovesMinter() public {
        vm.prank(attacker);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", attacker));
        token.removeMinter(minterAddr);
    }

    function test_RevertIf_RemovingNonMinter() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(NotMinter.selector, attacker));
        token.removeMinter(attacker);
    }

    function test_MinterCanMint() public {
        uint256 preBalance = token.balanceOf(user);

        vm.prank(minterAddr);
        token.mint(user, MINT_AMOUNT);

        assertEq(token.balanceOf(user), preBalance + MINT_AMOUNT);
    }

    function test_RevertIf_NonMinterMints() public {
        vm.prank(attacker);
        vm.expectRevert(abi.encodeWithSelector(NotMinter.selector, attacker));
        token.mint(user, MINT_AMOUNT);
    }

    function test_MinterCanBurn() public {
        vm.prank(minterAddr);
        token.mint(user, MINT_AMOUNT);

        uint256 preBalance = token.balanceOf(user);

        vm.prank(minterAddr);
        token.burn(user, MINT_AMOUNT);

        assertEq(token.balanceOf(user), preBalance - MINT_AMOUNT);
    }

    function test_RevertIf_NonMinterBurns() public {
        vm.prank(minterAddr);
        token.mint(user, MINT_AMOUNT);

        vm.prank(attacker);
        vm.expectRevert(abi.encodeWithSelector(NotMinter.selector, attacker));
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
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", attacker));
        token.pause();
    }

    function test_RevertIf_MintingWhilePaused() public {
        vm.prank(owner);
        token.pause();

        // Even an authorized minter cannot mint while paused
        vm.prank(minterAddr);
        vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
        token.mint(user, MINT_AMOUNT);
    }

    function test_RevertIf_BurningWhilePaused() public {
        vm.prank(minterAddr);
        token.mint(user, MINT_AMOUNT);

        vm.prank(owner);
        token.pause();

        // Even an authorized minter cannot burn while paused
        vm.prank(minterAddr);
        vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
        token.burn(user, MINT_AMOUNT);
    }
}