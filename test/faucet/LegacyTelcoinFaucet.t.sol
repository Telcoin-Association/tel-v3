// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {LegacyTelcoinFaucet} from "../../src/faucet/LegacyTelcoinFaucet.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract LegacyTelcoinFaucetTest is Test {
    MockERC20 internal legacyTel;
    LegacyTelcoinFaucet internal faucet;

    address internal admin = makeAddr("admin");
    address internal user = makeAddr("user");
    address internal user2 = makeAddr("user2");

    // Legacy TEL has 2 decimals
    uint256 internal constant DRIP_AMOUNT = 1_000 * 1e2;
    uint256 internal constant COOLDOWN = 1 days;
    uint256 internal constant FUND_AMOUNT = 1_000_000 * 1e2;

    function setUp() public {
        legacyTel = new MockERC20("Telcoin", "TEL", 2);
        faucet = new LegacyTelcoinFaucet(address(legacyTel), DRIP_AMOUNT, COOLDOWN, admin);

        // Pre-fund the faucet
        legacyTel.mint(address(faucet), FUND_AMOUNT);
    }

    // ----------
    // Drip tests
    // ----------

    function test_drip_transfersTokensToMsgSender() public {
        vm.prank(user);
        faucet.drip();

        assertEq(legacyTel.balanceOf(user), DRIP_AMOUNT);
        assertEq(legacyTel.balanceOf(address(faucet)), FUND_AMOUNT - DRIP_AMOUNT);
    }

    function test_drip_transfersTokensToSpecifiedAddress() public {
        vm.prank(user);
        faucet.drip(user2);

        assertEq(legacyTel.balanceOf(user2), DRIP_AMOUNT);
    }

    function test_drip_emitsDrippedEvent() public {
        vm.prank(user);
        vm.expectEmit(true, false, false, true);
        emit LegacyTelcoinFaucet.Dripped(user, DRIP_AMOUNT);
        faucet.drip();
    }

    function test_drip_revertsIfCooldownNotElapsed() public {
        vm.prank(user);
        faucet.drip();

        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(LegacyTelcoinFaucet.CooldownNotElapsed.selector, block.timestamp + COOLDOWN)
        );
        faucet.drip();
    }

    function test_drip_succeedsAfterCooldownElapsed() public {
        vm.prank(user);
        faucet.drip();

        vm.warp(block.timestamp + COOLDOWN);

        vm.prank(user);
        faucet.drip();

        assertEq(legacyTel.balanceOf(user), DRIP_AMOUNT * 2);
    }

    function test_drip_revertsIfFaucetEmpty() public {
        // Drain most of the faucet
        vm.prank(admin);
        faucet.withdraw(admin, FUND_AMOUNT);

        vm.prank(user);
        vm.expectRevert(LegacyTelcoinFaucet.InsufficientFaucetBalance.selector);
        faucet.drip();
    }

    function test_drip_separateCooldownsPerRecipient() public {
        vm.prank(user);
        faucet.drip(user2);

        vm.prank(user);
        faucet.drip();

        assertEq(legacyTel.balanceOf(user), DRIP_AMOUNT);
        assertEq(legacyTel.balanceOf(user2), DRIP_AMOUNT);
    }

    // -----------
    // Admin tests
    // -----------

    function test_setDripAmount() public {
        uint256 newAmount = 5_000 * 1e2;

        vm.prank(admin);
        faucet.setDripAmount(newAmount);

        assertEq(faucet.dripAmount(), newAmount);

        vm.prank(user);
        faucet.drip();
        assertEq(legacyTel.balanceOf(user), newAmount);
    }

    function test_setCooldown() public {
        uint256 newCooldown = 1 hours;

        vm.prank(admin);
        faucet.setCooldown(newCooldown);

        assertEq(faucet.cooldown(), newCooldown);
    }

    function test_withdraw() public {
        uint256 withdrawAmount = 500 * 1e2;

        vm.prank(admin);
        faucet.withdraw(admin, withdrawAmount);

        assertEq(legacyTel.balanceOf(admin), withdrawAmount);
        assertEq(legacyTel.balanceOf(address(faucet)), FUND_AMOUNT - withdrawAmount);
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

    function test_withdraw_revertsForNonOwner() public {
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user));
        faucet.withdraw(user, 1);
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

        vm.prank(user);
        faucet.drip();

        assertEq(legacyTel.balanceOf(user), DRIP_AMOUNT * 2);
    }

    function test_transferWhitelisted_transfersArbitraryAmount() public {
        vm.prank(admin);
        faucet.setWhitelist(user, true);

        uint256 bigAmount = 100_000 * 1e2;

        vm.prank(user);
        faucet.transferWhitelisted(user2, bigAmount);

        assertEq(legacyTel.balanceOf(user2), bigAmount);
    }

    function test_transferWhitelisted_revertsForNonWhitelisted() public {
        vm.prank(user);
        vm.expectRevert(LegacyTelcoinFaucet.NotWhitelisted.selector);
        faucet.transferWhitelisted(user, 1);
    }

    function test_transferWhitelisted_revertsIfInsufficientBalance() public {
        vm.prank(admin);
        faucet.setWhitelist(user, true);

        vm.prank(user);
        vm.expectRevert(LegacyTelcoinFaucet.InsufficientFaucetBalance.selector);
        faucet.transferWhitelisted(user, FUND_AMOUNT + 1);
    }

    function test_setWhitelist_removeFromWhitelist() public {
        vm.startPrank(admin);
        faucet.setWhitelist(user, true);
        faucet.setWhitelist(user, false);
        vm.stopPrank();

        assertFalse(faucet.whitelisted(user));

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
            assertEq(legacyTel.balanceOf(user), DRIP_AMOUNT * 2);
        }
    }
}
