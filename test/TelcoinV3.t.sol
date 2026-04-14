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
    address internal user2 = makeAddr("user2");
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

    // ---------------------
    // Supply Cap Tests
    // ---------------------

    /// @dev Constructor succeeds when initialSupply_ is zero (no initial mint).
    function test_Constructor_ZeroSupply() public {
        TelcoinV3 t = new TelcoinV3(0, owner);
        assertEq(t.totalSupply(), 0);
    }

    /// @dev Constructor succeeds when initialSupply_ is exactly the cap.
    function test_Constructor_SupplyAtCap() public {
        TelcoinV3 t = new TelcoinV3(token.MIGRATION_SUPPLY_CAP(), owner);
        assertEq(t.totalSupply(), token.MIGRATION_SUPPLY_CAP());
    }

    /// @dev Constructor reverts when initialSupply_ exceeds the 100B cap.
    function test_RevertIf_Constructor_SupplyExceedsCap() public {
        // Cache the cap before arming vm.expectRevert — evaluating token.MIGRATION_SUPPLY_CAP()
        // inline would itself be the "next call" that Foundry intercepts, consuming the expectation
        // before the constructor is ever reached.
        uint256 cap = token.MIGRATION_SUPPLY_CAP();
        vm.expectRevert(TelcoinV3.SupplyCapExceeded.selector);
        new TelcoinV3(cap + 1, owner);
    }

    /// @dev mint() succeeds when the resulting total supply equals the cap exactly.
    function test_Mint_UpToSupplyCap() public {
        uint256 remaining = token.MIGRATION_SUPPLY_CAP() - token.totalSupply();

        vm.prank(bridge);
        token.mint(user, remaining);

        assertEq(token.totalSupply(), token.MIGRATION_SUPPLY_CAP());
    }

    /// @dev mint() reverts with SupplyCapExceeded when the resulting total supply would exceed the cap.
    function test_RevertIf_Mint_ExceedsSupplyCap() public {
        uint256 remaining = token.MIGRATION_SUPPLY_CAP() - token.totalSupply();

        vm.prank(bridge);
        vm.expectRevert(TelcoinV3.SupplyCapExceeded.selector);
        token.mint(user, remaining + 1);
    }

    /// @dev Verifies the bridge (given the minter role) can mint tokens
    function test_BridgeCanMint() public {
        uint256 preBalance = token.balanceOf(user);

        vm.prank(bridge);
        token.mint(user, MINT_AMOUNT);

        assertEq(token.balanceOf(user), preBalance + MINT_AMOUNT);
    }

    /// @dev Verifies an attacker (given no minter role) cannot mint tokens
    function test_RevertIf_NonBridgeMints() public {
        vm.prank(attacker);
        vm.expectRevert();
        token.mint(user, MINT_AMOUNT);
    }

    /// @dev Verifies the bride (given the burner role) can burn tokens
    function test_BridgeCanBurn() public {
        vm.prank(bridge);
        token.mint(user, MINT_AMOUNT);

        uint256 preBalance = token.balanceOf(user);

        vm.prank(bridge);
        token.burn(user, MINT_AMOUNT);

        assertEq(token.balanceOf(user), preBalance - MINT_AMOUNT);
    }

    /// @dev Verifies an attacker (given no burner role) cannot burn tokens
    function test_RevertIf_NonBridgeBurns() public {
        vm.prank(bridge);
        token.mint(user, MINT_AMOUNT);

        vm.prank(attacker);
        vm.expectRevert();
        token.burn(user, MINT_AMOUNT);
    }

    /// @dev Verifies owner can pause and unpause transfers
    function test_OwnerCanPauseAndUnpause() public {
        assertFalse(token.paused());

        vm.prank(owner);
        token.pause();
        assertTrue(token.paused());

        vm.prank(owner);
        token.unpause();
        assertFalse(token.paused());
    }

    /// @dev Verifies an attacker cannot pause token
    function test_RevertIf_NonOwnerPauses() public {
        vm.prank(attacker);
        vm.expectRevert(
            abi.encodeWithSignature("AccessControlUnauthorizedAccount(address,bytes32)", attacker, PAUSER_ROLE)
        );
        token.pause();
    }

    /// @dev Verifies a mint after a pause will revert
    function test_MintingWhilePaused() public {
        vm.prank(owner);
        token.pause();

        uint256 preBalance = token.balanceOf(user);

        vm.prank(bridge);
        token.mint(user, MINT_AMOUNT);

        assertEq(token.balanceOf(user), preBalance + MINT_AMOUNT);
    }

    /// @dev Verifies burning after a pause is successful
    function test_BurningWhilePaused() public {
        vm.prank(bridge);
        token.mint(user, MINT_AMOUNT);

        vm.prank(owner);
        token.pause();

        uint256 preBalance = token.balanceOf(user);

        vm.prank(bridge);
        token.burn(user, MINT_AMOUNT);

        assertEq(token.balanceOf(user), preBalance - MINT_AMOUNT);
    }

    // -------------------
    // rescueTokens Tests
    // -------------------

    /// @dev Admin can recover ERC20 tokens accidentally sent to the TelcoinV3 contract.
    function test_RescueTokens() public {
        uint256 stuckAmount = 100 ether;

        // Simulate tokens accidentally sent directly to the token contract
        vm.prank(bridge);
        token.mint(address(token), stuckAmount);

        uint256 adminBalanceBefore = token.balanceOf(owner);

        vm.prank(owner);
        token.rescueTokens(address(token), stuckAmount);

        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.balanceOf(owner), adminBalanceBefore + stuckAmount);
    }

    /// @dev rescueTokens reverts when called by an address without DEFAULT_ADMIN_ROLE.
    function test_RevertIf_NonAdminRescuesTokens() public {
        vm.prank(bridge);
        token.mint(address(token), 100 ether);

        vm.prank(attacker);
        vm.expectRevert(
            abi.encodeWithSignature("AccessControlUnauthorizedAccount(address,bytes32)", attacker, bytes32(0))
        );
        token.rescueTokens(address(token), 100 ether);
    }

    /// @dev Verifies transfers fail after contract is paused
    function test_RevertIf_TransferWhilePaused() public {
        vm.prank(bridge);
        token.mint(user, MINT_AMOUNT);

        vm.prank(owner);
        token.pause();

        vm.prank(user);
        vm.expectRevert();
        token.transfer(user2, MINT_AMOUNT);

        vm.prank(owner);
        token.unpause();

        uint256 preBalance = token.balanceOf(user2);

        vm.prank(user);
        token.transfer(user2, MINT_AMOUNT);

        assertEq(token.balanceOf(user2), preBalance + MINT_AMOUNT);
    }
}
