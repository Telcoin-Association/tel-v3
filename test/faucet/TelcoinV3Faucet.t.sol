// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import {TelcoinV3} from "../../src/TelcoinV3.sol";
import {TelcoinV3Faucet} from "../../src/faucet/TelcoinV3Faucet.sol";
import {Roles} from "../../src/helpers/Roles.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract TelcoinV3FaucetTest is Test, Roles {
    TelcoinV3 internal token;
    TelcoinV3Faucet internal faucet;

    address internal admin = makeAddr("admin");
    address internal user = makeAddr("user");
    address internal user2 = makeAddr("user2");

    uint256 internal constant DRIP_AMOUNT = 1_000 ether;
    uint256 internal constant COOLDOWN = 1 days;

    function setUp() public {
        vm.prank(admin);
        token = new TelcoinV3(admin);

        faucet = new TelcoinV3Faucet(address(token), DRIP_AMOUNT, COOLDOWN, admin);

        // Grant MINTER_ROLE to faucet
        vm.prank(admin);
        token.grantRole(MINTER_ROLE, address(faucet));
    }

    // ----------
    // Drip tests
    // ----------

    function test_drip_mintsTokensToMsgSender() public {
        vm.prank(user);
        faucet.drip();

        assertEq(token.balanceOf(user), DRIP_AMOUNT);
    }

    function test_drip_mintsTokensToSpecifiedAddress() public {
        vm.prank(user);
        faucet.drip(user2);

        assertEq(token.balanceOf(user2), DRIP_AMOUNT);
    }

    function test_drip_emitsDrippedEvent() public {
        vm.prank(user);
        vm.expectEmit(true, false, false, true);
        emit TelcoinV3Faucet.Dripped(user, DRIP_AMOUNT);
        faucet.drip();
    }

    function test_drip_revertsIfCooldownNotElapsed() public {
        vm.prank(user);
        faucet.drip();

        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(TelcoinV3Faucet.CooldownNotElapsed.selector, block.timestamp + COOLDOWN)
        );
        faucet.drip();
    }

    function test_drip_succeedsAfterCooldownElapsed() public {
        vm.prank(user);
        faucet.drip();

        vm.warp(block.timestamp + COOLDOWN);

        vm.prank(user);
        faucet.drip();

        assertEq(token.balanceOf(user), DRIP_AMOUNT * 2);
    }

    function test_drip_separateCooldownsPerRecipient() public {
        // drip(user2) tracks cooldown on user2, not msg.sender
        vm.prank(user);
        faucet.drip(user2);

        // user can still drip to themselves
        vm.prank(user);
        faucet.drip();

        assertEq(token.balanceOf(user), DRIP_AMOUNT);
        assertEq(token.balanceOf(user2), DRIP_AMOUNT);
    }

    // -----------
    // Admin tests
    // -----------

    function test_setDripAmount() public {
        uint256 newAmount = 5_000 ether;

        vm.prank(admin);
        faucet.setDripAmount(newAmount);

        assertEq(faucet.dripAmount(), newAmount);

        vm.prank(user);
        faucet.drip();
        assertEq(token.balanceOf(user), newAmount);
    }

    function test_setCooldown() public {
        uint256 newCooldown = 1 hours;

        vm.prank(admin);
        faucet.setCooldown(newCooldown);

        assertEq(faucet.cooldown(), newCooldown);
    }

    function test_setDripAmount_revertsForNonOwner() public {
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user));
        faucet.setDripAmount(1);
    }

    function test_setCooldown_revertsForNonOwner() public {
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user));
        faucet.setCooldown(1);
    }

    // ---------------
    // Whitelist tests
    // ---------------

    function test_setWhitelist() public {
        vm.prank(admin);
        faucet.setWhitelist(user, true);

        assertTrue(faucet.whitelisted(user));
    }

    function test_setWhitelist_revertsForNonOwner() public {
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user));
        faucet.setWhitelist(user, true);
    }

    function test_drip_whitelistedBypassesCooldown() public {
        vm.prank(admin);
        faucet.setWhitelist(user, true);

        vm.prank(user);
        faucet.drip();

        // No cooldown wait — drip again immediately
        vm.prank(user);
        faucet.drip();

        assertEq(token.balanceOf(user), DRIP_AMOUNT * 2);
    }

    function test_mintWhitelisted_mintsArbitraryAmount() public {
        vm.prank(admin);
        faucet.setWhitelist(user, true);

        uint256 bigAmount = 1_000_000 ether;

        vm.prank(user);
        faucet.mintWhitelisted(user2, bigAmount);

        assertEq(token.balanceOf(user2), bigAmount);
    }

    function test_mintWhitelisted_revertsForNonWhitelisted() public {
        vm.prank(user);
        vm.expectRevert(TelcoinV3Faucet.NotWhitelisted.selector);
        faucet.mintWhitelisted(user, 1 ether);
    }

    function test_setWhitelist_removeFromWhitelist() public {
        vm.startPrank(admin);
        faucet.setWhitelist(user, true);
        faucet.setWhitelist(user, false);
        vm.stopPrank();

        assertFalse(faucet.whitelisted(user));

        // Should be subject to cooldown again
        vm.prank(user);
        faucet.drip();

        vm.prank(user);
        vm.expectRevert();
        faucet.drip();
    }

    // ----------
    // Fuzz tests
    // ----------

    function testFuzz_drip_respectsCooldown(uint256 elapsed) public {
        elapsed = bound(elapsed, 0, 365 days);

        vm.prank(user);
        faucet.drip();

        vm.warp(block.timestamp + elapsed);

        if (elapsed < COOLDOWN) {
            vm.prank(user);
            vm.expectRevert();
            faucet.drip();
        } else {
            vm.prank(user);
            faucet.drip();
            assertEq(token.balanceOf(user), DRIP_AMOUNT * 2);
        }
    }
}
