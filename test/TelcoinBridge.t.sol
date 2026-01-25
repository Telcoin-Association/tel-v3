// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Origin, MessagingFee, MessagingReceipt} from "@layerzerolabs/oapp-evm/contracts/oapp/OApp.sol";
import {IOAppCore} from "@layerzerolabs/oapp-evm/contracts/oapp/interfaces/IOAppCore.sol";
import {TelcoinBridge} from "../src/TelcoinBridge.sol";
import {TelcoinV3} from "../src/TelcoinV3.sol";
import {MockEndpoint} from "./mocks/MockEndpoint.sol";
import {ITelcoinBridge} from "../src/interfaces/ITelcoinBridge.sol";

/**
 * @title TelcoinBridgeTest
 * @notice This test file is meant to verify the basic functions of the TelcoinBridge contract.
 */
contract TelcoinBridgeTest is Test {
    // Contracts
    TelcoinV3 public telcoinA;
    TelcoinV3 public telcoinB;
    TelcoinBridge public bridgeA;
    TelcoinBridge public bridgeB;
    MockEndpoint public endpointA;
    MockEndpoint public endpointB;

    // Actors
    address public owner = makeAddr("owner");
    address public user1 = makeAddr("user 1");
    address public user2 = makeAddr("user 2");

    // Constants
    uint32 constant EID_A = 1;
    uint32 constant EID_B = 2;
    uint256 constant INITIAL_SUPPLY = 1_000_000_000 ether; // 1B tokens
    uint256 constant USER_BALANCE = 1_000_000 ether; // 1M tokens

    // Events (copied from TelcoinBridge for testing)
    event BridgeSent(
        bytes32 indexed guid,
        uint32 indexed dstEid,
        address indexed from,
        address to,
        uint256 amount
    );
    event BridgeReceived(
        bytes32 indexed guid,
        uint32 indexed srcEid,
        address indexed to,
        uint256 amount
    );
    event DstGasLimitSet(uint128 dstGasLimit);

    function setUp() public {
        // Deploy mock endpoints
        endpointA = new MockEndpoint(EID_A);
        endpointB = new MockEndpoint(EID_B);

        // Deploy TelcoinV3 on both "chains"
        vm.startPrank(owner);

        telcoinA = new TelcoinV3(INITIAL_SUPPLY, owner, owner);
        telcoinB = new TelcoinV3(INITIAL_SUPPLY, owner, owner);

        // Deploy bridges
        bridgeA = new TelcoinBridge(
            address(telcoinA),
            address(endpointA),
            owner
        );
        bridgeB = new TelcoinBridge(
            address(telcoinB),
            address(endpointB),
            owner
        );

        // Setup peers (wire the bridges together)
        bridgeA.setPeer(EID_B, _addressToBytes32(address(bridgeB)));
        bridgeB.setPeer(EID_A, _addressToBytes32(address(bridgeA)));

        // Set bridges on their respective TelcoinV3
        telcoinA.setBridge(address(bridgeA));
        telcoinB.setBridge(address(bridgeB));

        // Fund users with tokens on chain A
        telcoinA.transfer(user1, USER_BALANCE);
        telcoinA.transfer(user2, USER_BALANCE);

        vm.stopPrank();

        // Give users ETH for gas
        vm.deal(user1, 100 ether);
        vm.deal(user2, 100 ether);
    }

    // -------
    // Helpers
    // -------

    function _addressToBytes32(address _addr) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(_addr)));
    }

    function _createBasicOptions() internal pure returns (bytes memory) {
        // Minimal TYPE_3 options for testing
        return abi.encodePacked(uint16(3));
    }

    // -------------------
    // Initial State Tests
    // -------------------

    /// @dev Verifies initial state of the TelcoinBridge contract.
    function test_Constructor() public view {
        assertEq(address(bridgeA.telcoin()), address(telcoinA));
        assertEq(bridgeA.owner(), owner);
        assertEq(bridgeA.dstGasLimit(), 200_000);
    }

    // ------------
    // Bridge Tests
    // ------------

    /// @dev Verifies successful call to TelcoinBridge::bridge with no expectation of txn landing.
    function test_Bridge_Success() public {
        uint256 bridgeAmount = 1000 ether;
        bytes memory options = _createBasicOptions();

        // Get quote
        MessagingFee memory fee = bridgeA.quote(EID_B, user2, bridgeAmount, options);

        // Check balances before
        uint256 user1BalanceBefore = telcoinA.balanceOf(user1);

        // Bridge tokens
        vm.prank(user1);
        MessagingReceipt memory receipt = bridgeA.bridge{value: fee.nativeFee}(
            EID_B,
            user2,
            bridgeAmount,
            options
        );

        // Verify tokens were burned on chain A
        assertEq(telcoinA.balanceOf(user1), user1BalanceBefore - bridgeAmount);

        // Verify receipt
        assertTrue(receipt.guid != bytes32(0));
        assertEq(receipt.fee.nativeFee, fee.nativeFee);
    }

    /// @dev Verifies a successful call to bridge emits the intended `BridgeSent` event.
    function test_Bridge_EmitsEvent() public {
        uint256 bridgeAmount = 1000 ether;
        bytes memory options = _createBasicOptions();

        vm.startPrank(user1);
        MessagingFee memory fee = bridgeA.quote(EID_B, user1, bridgeAmount, options);

        // Check event (guid is unpredictable, so we use false for first indexed param)
        vm.expectEmit(false, true, true, true);
        emit BridgeSent(bytes32(0), EID_B, user1, user1, bridgeAmount);

        bridgeA.bridge{value: fee.nativeFee}(EID_B, user1, bridgeAmount, options);
        vm.stopPrank();
    }

    /// @dev Verifies if amount == 0, contract reverts with the `ZeroAmount` error.
    function test_Bridge_RevertZeroAmount() public {
        bytes memory options = _createBasicOptions();

        vm.startPrank(user1);
        vm.expectRevert(ITelcoinBridge.ZeroAmount.selector);
        bridgeA.bridge{value: 0.1 ether}(EID_B, user1, 0, options);
        vm.stopPrank();
    }

    /// @dev Verifies if recipient == address(0), contract reverts with the `ZeroAddress` error.
    function test_Bridge_RevertZeroRecipient() public {
        bytes memory options = _createBasicOptions();

        vm.startPrank(user1);
        vm.expectRevert(ITelcoinBridge.ZeroAddress.selector);
        bridgeA.bridge{value: 0.1 ether}(EID_B, address(0), 1000, options);
        vm.stopPrank();
    }

    /// @dev Verifies if contract is paused, a call to bridge will revert.
    function test_Bridge_RevertWhenPaused() public {
        bytes memory options = _createBasicOptions();

        vm.prank(owner);
        bridgeA.pause();

        vm.startPrank(user1);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        bridgeA.bridge{value: 0.1 ether}(EID_B, user1, 1000, options);
        vm.stopPrank();
    }

    /// @dev Verifies if contract is bridged to a chain with no peer, contract reverts.
    function test_Bridge_RevertNoPeer() public {
        // Deploy a new bridge without setting peer
        TelcoinBridge bridgeNoPeer = new TelcoinBridge(
            address(telcoinA),
            address(endpointA),
            owner
        );

        // Set bridgeNoPeer as the bridge so it can burn
        vm.prank(owner);
        telcoinA.setBridge(address(bridgeNoPeer));

        bytes memory options = _createBasicOptions();

        vm.startPrank(user1);
        vm.expectRevert(abi.encodeWithSelector(IOAppCore.NoPeer.selector, EID_B));
        bridgeNoPeer.bridge{value: 0.1 ether}(EID_B, user1, 1000, options);
        vm.stopPrank();
    }

    /// @dev Uses fuzzing to verify successful call to TelcoinBridge::bridge with no expectation of
    ///      txn landing.
    function testFuzz_Bridge(uint256 amount) public {
        // Bound amount to valid range
        amount = bound(amount, 1, USER_BALANCE);

        bytes memory options = _createBasicOptions();
        uint256 balanceBefore = telcoinA.balanceOf(user1);

        vm.startPrank(user1);
        MessagingFee memory fee = bridgeA.quote(EID_B, user1, amount, options);
        bridgeA.bridge{value: fee.nativeFee}(EID_B, user1, amount, options);
        vm.stopPrank();

        // Verify burn on source chain
        assertEq(telcoinA.balanceOf(user1), balanceBefore - amount);
    }

    // ---------------
    // LzReceive Tests
    // ---------------

    /// @dev Verifies proper state changes when TelcoinBridge::lzReceive is executed successfully.
    function test_LzReceive_MintsTokens() public {
        uint256 mintAmount = 2000 ether;

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

        Origin memory origin = Origin({
            srcEid: EID_A,
            sender: _addressToBytes32(address(bridgeA)),
            nonce: 1
        });

        bytes memory message = abi.encode(recipient, amount);
        bytes32 guid = keccak256(abi.encodePacked(recipient, amount));

        vm.prank(address(endpointB));
        bridgeB.lzReceive(origin, guid, message, address(0), bytes(""));

        assertEq(telcoinB.balanceOf(recipient), amount);
    }

    // ----------------
    // Round Trip Tests
    // ----------------

    /// @dev Verifies a round trip bridging of tokens from chain A to chain B and back to chain A.
    function test_FullRoundTrip() public {
        uint256 bridgeAmount = 5000 ether;
        bytes memory options = _createBasicOptions();

        // STEP 1: Bridge from A to B
        vm.startPrank(user1);
        MessagingFee memory feeAtoB = bridgeA.quote(EID_B, user1, bridgeAmount, options);
        MessagingReceipt memory receiptAtoB = bridgeA.bridge{value: feeAtoB.nativeFee}(
            EID_B,
            user1,
            bridgeAmount,
            options
        );
        vm.stopPrank();

        // Verify burn on chain A
        assertEq(telcoinA.balanceOf(user1), USER_BALANCE - bridgeAmount);

        // Simulate delivery on chain B using mock endpoint
        endpointB.deliverPacket(
            EID_A,
            _addressToBytes32(address(bridgeA)),
            1, // nonce
            receiptAtoB.guid,
            abi.encode(user1, bridgeAmount),
            address(bridgeB)
        );

        // Verify mint on chain B
        assertEq(telcoinB.balanceOf(user1), bridgeAmount);

        // STEP 2: Bridge back from B to A
        vm.startPrank(user1);
        MessagingFee memory feeBtoA = bridgeB.quote(EID_A, user1, bridgeAmount, options);
        MessagingReceipt memory receiptBtoA = bridgeB.bridge{value: feeBtoA.nativeFee}(
            EID_A,
            user1,
            bridgeAmount,
            options
        );
        vm.stopPrank();

        // Verify burn on chain B
        assertEq(telcoinB.balanceOf(user1), 0);

        // Simulate delivery on chain A
        endpointA.deliverPacket(
            EID_B,
            _addressToBytes32(address(bridgeB)),
            1, // nonce
            receiptBtoA.guid,
            abi.encode(user1, bridgeAmount),
            address(bridgeA)
        );

        // Verify mint on chain A - back to original balance
        assertEq(telcoinA.balanceOf(user1), USER_BALANCE);
    }

    // -----------
    // Quote Tests
    // -----------

    /// @dev Verifies the quote method returns the intended values.
    function test_Quote() public view {
        bytes memory options = _createBasicOptions();

        MessagingFee memory fee = bridgeA.quote(EID_B, user1, 1000, options);

        // Fee should be non-zero (mock returns 0.001 ether)
        assertEq(fee.nativeFee, 0.001 ether);
        assertEq(fee.lzTokenFee, 0);
    }

    /// @dev Verifies the quote method returns the intended fees with different amounts.
    function test_Quote_DifferentAmountsSameFee() public view {
        bytes memory options = _createBasicOptions();

        // Quote for different amounts - fee should be the same since payload size is same
        MessagingFee memory fee1 = bridgeA.quote(EID_B, user1, 1000, options);
        MessagingFee memory fee2 = bridgeA.quote(EID_B, user1, 1_000_000, options);

        // Fees should be equal (same payload structure)
        assertEq(fee1.nativeFee, fee2.nativeFee);
    }

    // ----------------------------
    // Permissioned Functions Tests
    // ----------------------------

    // ~ setDstGasLimit ~

    /// @dev Verifies TelcoinBridge::setDstGasLimit results in the expected state changes.
    function test_SetDstGasLimit() public {
        uint128 newGasLimit = 300_000;

        vm.prank(owner);
        bridgeA.setDstGasLimit(newGasLimit);

        assertEq(bridgeA.dstGasLimit(), newGasLimit);
    }

    /// @dev Verifies TelcoinBridge::setDstGasLimit emits the `DstGasLimitSet` event.
    function test_SetDstGasLimit_EmitsEvent() public {
        uint128 newGasLimit = 400_000;

        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit DstGasLimitSet(newGasLimit);

        bridgeA.setDstGasLimit(newGasLimit);
    }

    /// @dev Verifies TelcoinBridge::setDstGasLimit can only be called by the owner.
    function test_SetDstGasLimit_RevertNotOwner() public {
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user1));
        bridgeA.setDstGasLimit(300_000);
    }

    // ~ pause/unpause ~

    /// @dev Verifies TelcoinBridge::pause results in the expected state changes.
    function test_Pause() public {
        vm.prank(owner);
        bridgeA.pause();

        assertTrue(bridgeA.paused());
    }

    /// @dev Verifies TelcoinBridge::pause can only be called by the owner.
    function test_Pause_RevertNotOwner() public {
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user1));
        bridgeA.pause();
    }

    /// @dev Verifies TelcoinBridge::unpause results in the expected state changes.
    function test_Unpause() public {
        vm.startPrank(owner);
        bridgeA.pause();
        assertTrue(bridgeA.paused());

        bridgeA.unpause();
        assertFalse(bridgeA.paused());
        vm.stopPrank();
    }

    /// @dev Verifies TelcoinBridge::unpause can only be called by the owner.
    function test_Unpause_RevertNotOwner() public {
        vm.prank(owner);
        bridgeA.pause();

        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user1));
        bridgeA.unpause();
    }

    // ~ rescueTokens ~

    /// @dev Verifies TelcoinBridge::rescueTokens results in the expected state changes.
    function test_RescueTokens() public {
        // Send some tokens to the bridge accidentally
        uint256 stuckAmount = 100 ether;
        vm.prank(user1);
        telcoinA.transfer(address(bridgeA), stuckAmount);

        uint256 bridgeBalanceBefore = telcoinA.balanceOf(address(bridgeA));
        uint256 ownerBalanceBefore = telcoinA.balanceOf(owner);

        assertEq(bridgeBalanceBefore, stuckAmount);

        // Rescue tokens
        vm.prank(owner);
        bridgeA.rescueTokens(address(telcoinA), stuckAmount);

        assertEq(telcoinA.balanceOf(address(bridgeA)), 0);
        assertEq(telcoinA.balanceOf(owner), ownerBalanceBefore + stuckAmount);
    }

    /// @dev Verifies TelcoinBridge::rescueTokens can only be called by the owner.
    function test_RescueTokens_RevertNotOwner() public {
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user1));
        bridgeA.rescueTokens(address(telcoinA), 100);
    }

    /// @dev Verifies TelcoinBridge::rescueTokens reverts if amount == 0.
    function test_RescueTokens_RevertZeroAmount() public {
        vm.prank(owner);
        vm.expectRevert(ITelcoinBridge.ZeroAmount.selector);
        bridgeA.rescueTokens(address(telcoinA), 0);
    }

    /// @dev Verifies TelcoinBridge::rescueTokens reverts if token == address(0).
    function test_RescueTokens_RevertZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(ITelcoinBridge.ZeroAddress.selector);
        bridgeA.rescueTokens(address(0), 100);
    } 
}
