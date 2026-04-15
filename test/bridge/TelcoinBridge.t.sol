// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BaseSetup} from "./BaseSetup.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {TelcoinBridge} from "../../src/TelcoinBridge.sol";
import {MintBurnWrapper} from "../../src/MintBurnWrapper.sol";
import {IMintableBurnable} from "@layerzerolabs/oft-evm/contracts/interfaces/IMintableBurnable.sol";
import {SendParam, OFTReceipt} from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";
import {MessagingFee, MessagingReceipt} from "@layerzerolabs/oapp-evm/contracts/oapp/OApp.sol";

contract TelcoinBridgeTest is BaseSetup {
    function setUp() public override {
        super.setUp();
    }

    // -------------------
    // Initial State Tests
    // -------------------

    /// @notice Token, minterBurner, and owner are set correctly at deployment.
    function test_Constructor() public view {
        assertEq(bridgeA.token(), address(telcoinA));
        assertEq(address(bridgeA.minterBurner()), address(wrapperA));
        assertEq(bridgeA.owner(), owner);
        assertTrue(bridgeA.approvalRequired());
    }

    // ----------------
    // Round Trip Tests
    // ----------------

    /// @notice ERC20 TEL burned on Chain A is minted on Chain B, then burned on B and minted back on A.
    function test_FullRoundTrip() public {
        uint256 bridgeAmount = 5000 ether;
        bytes memory options = _createBasicOptions();
        SendParam memory sendParam = _createSendParam(EID_B, user1, bridgeAmount, options);

        // STEP 1: Bridge from A to B
        vm.startPrank(user1);
        MessagingFee memory feeAtoB = bridgeA.quoteSend(sendParam, false);
        (MessagingReceipt memory receiptAtoB, ) = bridgeA.send{value: feeAtoB.nativeFee}(sendParam, feeAtoB, user1);
        vm.stopPrank();

        assertEq(telcoinA.balanceOf(user1), USER_BALANCE - bridgeAmount);

        // Simulate delivery on chain B
        endpointB.deliverPacket(
            EID_A,
            _addressToBytes32(address(bridgeA)),
            1,
            receiptAtoB.guid,
            _encodeOFTMessage(user1, bridgeAmount),
            address(bridgeB)
        );

        assertEq(telcoinB.balanceOf(user1), bridgeAmount);

        // STEP 2: Bridge back from B to A
        SendParam memory sendParamBack = _createSendParam(EID_A, user1, bridgeAmount, options);
        vm.startPrank(user1);
        MessagingFee memory feeBtoA = bridgeB.quoteSend(sendParamBack, false);
        (MessagingReceipt memory receiptBtoA, ) = bridgeB.send{value: feeBtoA.nativeFee}(sendParamBack, feeBtoA, user1);
        vm.stopPrank();

        assertEq(telcoinB.balanceOf(user1), 0);

        // Simulate delivery on chain A
        endpointA.deliverPacket(
            EID_B,
            _addressToBytes32(address(bridgeB)),
            1,
            receiptBtoA.guid,
            _encodeOFTMessage(user1, bridgeAmount),
            address(bridgeA)
        );

        assertEq(telcoinA.balanceOf(user1), USER_BALANCE);
    }

    // -----------
    // Quote Tests
    // -----------

    /// @notice quoteSend returns the correct LZ messaging fee for a given send.
    function test_Quote() public view {
        bytes memory options = _createBasicOptions();
        SendParam memory sendParam = _createSendParam(EID_B, user1, 1000 ether, options);

        MessagingFee memory fee = bridgeA.quoteSend(sendParam, false);

        assertEq(fee.nativeFee, 0.001 ether);
        assertEq(fee.lzTokenFee, 0);
    }

    /// @notice LZ messaging fee is independent of the bridged token amount.
    function test_Quote_DifferentAmountsSameFee() public view {
        bytes memory options = _createBasicOptions();

        MessagingFee memory fee1 = bridgeA.quoteSend(_createSendParam(EID_B, user1, 1000 ether, options), false);
        MessagingFee memory fee2 = bridgeA.quoteSend(_createSendParam(EID_B, user1, 1_000_000 ether, options), false);

        assertEq(fee1.nativeFee, fee2.nativeFee);
    }

    // ----------------------------
    // Permissioned Functions Tests
    // ----------------------------

    /// @notice Owner can pause the bridge.
    function test_Pause() public {
        vm.prank(owner);
        bridgeA.pause();
        assertTrue(bridgeA.paused());
    }

    /// @notice pause reverts when called by a non-owner.
    function test_Pause_RevertNotOwner() public {
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user1));
        bridgeA.pause();
    }

    /// @notice Owner can unpause the bridge after pausing.
    function test_Unpause() public {
        vm.startPrank(owner);
        bridgeA.pause();
        bridgeA.unpause();
        assertFalse(bridgeA.paused());
        vm.stopPrank();
    }

    /// @notice unpause reverts when called by a non-owner.
    function test_Unpause_RevertNotOwner() public {
        vm.prank(owner);
        bridgeA.pause();

        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user1));
        bridgeA.unpause();
    }

    /// @notice Owner can rescue ERC20 tokens accidentally sent to the bridge to a specified address.
    function test_RescueTokens() public {
        uint256 stuckAmount = 100 ether;
        vm.prank(user1);
        telcoinA.transfer(address(bridgeA), stuckAmount);

        uint256 user2Before = telcoinA.balanceOf(user2);

        vm.prank(owner);
        bridgeA.rescueTokens(address(telcoinA), stuckAmount, user2);

        assertEq(telcoinA.balanceOf(address(bridgeA)), 0);
        assertEq(telcoinA.balanceOf(user2), user2Before + stuckAmount);
    }

    /// @notice rescueTokens reverts when called by a non-owner.
    function test_RescueTokens_RevertNotOwner() public {
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user1));
        bridgeA.rescueTokens(address(telcoinA), 100, user2);
    }

    /// @notice rescueTokens reverts when _to is the zero address.
    function test_RescueTokens_RevertZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(TelcoinBridge.ZeroAddress.selector);
        bridgeA.rescueTokens(address(telcoinA), 100, address(0));
    }

    /// @notice rescueTokens reverts when _amount is zero.
    function test_RescueTokens_RevertZeroAmount() public {
        vm.prank(owner);
        vm.expectRevert(TelcoinBridge.ZeroAmount.selector);
        bridgeA.rescueTokens(address(telcoinA), 0, user2);
    }

    // ----------------------
    // Ownership Safety Tests
    // ----------------------

    /// @notice transferOwnership sets pendingOwner but does not change owner yet (two-step).
    function test_TransferOwnership_SetsPendingOwner() public {
        address newOwner = makeAddr("newOwner");
        vm.prank(owner);
        bridgeA.transferOwnership(newOwner);

        assertEq(bridgeA.pendingOwner(), newOwner);
        assertEq(bridgeA.owner(), owner);
    }

    /// @notice Ownership transfer completes only after the pending owner calls acceptOwnership().
    function test_TransferOwnership_AcceptOwnership() public {
        address newOwner = makeAddr("newOwner");

        vm.prank(owner);
        bridgeA.transferOwnership(newOwner);

        vm.prank(newOwner);
        bridgeA.acceptOwnership();

        assertEq(bridgeA.owner(), newOwner);
        assertEq(bridgeA.pendingOwner(), address(0));
    }

    /// @notice A non-pending-owner cannot call acceptOwnership().
    function test_TransferOwnership_RevertNotPendingOwner() public {
        address newOwner = makeAddr("newOwner");

        vm.prank(owner);
        bridgeA.transferOwnership(newOwner);

        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user1));
        bridgeA.acceptOwnership();
    }

    /// @notice Only the current owner can initiate a transfer.
    function test_TransferOwnership_RevertNotOwner() public {
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user1));
        bridgeA.transferOwnership(user1);
    }

    /// @notice renounceOwnership always reverts to prevent bricking bridge configuration.
    function test_RenounceOwnership_Reverts() public {
        vm.prank(owner);
        vm.expectRevert(TelcoinBridge.CannotRenounceOwnership.selector);
        bridgeA.renounceOwnership();
    }

    // ----------------------
    // MintBurnWrapper Tests
    // ----------------------

    /// @notice MintBurnWrapper reverts when an unauthorized address calls mint().
    function test_Wrapper_RevertUnauthorizedMint() public {
        vm.prank(user1);
        vm.expectRevert(MintBurnWrapper.UnauthorizedBridge.selector);
        wrapperA.mint(user1, 1 ether);
    }

    /// @notice MintBurnWrapper reverts when an unauthorized address calls burn().
    function test_Wrapper_RevertUnauthorizedBurn() public {
        vm.prank(user1);
        vm.expectRevert(MintBurnWrapper.UnauthorizedBridge.selector);
        wrapperA.burn(user1, 1 ether);
    }

    /// @notice Revoking a bridge via the wrapper prevents it from burning tokens on send.
    function test_Wrapper_RevokeBridge_BlocksMint() public {
        vm.prank(owner);
        wrapperA.revokeBridge(address(bridgeA));

        assertEq(wrapperA.bridge(), address(0));

        bytes memory options = _createBasicOptions();
        SendParam memory sendParam = _createSendParam(EID_B, user1, 1000 ether, options);

        vm.startPrank(user1);
        MessagingFee memory fee = bridgeA.quoteSend(sendParam, false);
        vm.expectRevert();
        bridgeA.send{value: fee.nativeFee}(sendParam, fee, user1);
        vm.stopPrank();
    }

    /// @notice revokeBridge emits BridgeRevoked.
    function test_Wrapper_RevokeBridge_EmitsEvent() public {
        vm.prank(owner);
        vm.expectEmit(true, false, false, false);
        emit MintBurnWrapper.BridgeRevoked(address(bridgeA));
        wrapperA.revokeBridge(address(bridgeA));
    }

    /// @notice authorizeBridge emits BridgeAuthorized and updates the bridge address.
    function test_Wrapper_AuthorizeBridge_EmitsEvent() public {
        address newBridge = makeAddr("newBridge");
        vm.prank(owner);
        vm.expectEmit(true, false, false, false);
        emit MintBurnWrapper.BridgeAuthorized(newBridge);
        wrapperA.authorizeBridge(newBridge);
        assertEq(wrapperA.bridge(), newBridge);
    }

    /// @notice mint emits BridgeMinted with the calling bridge, recipient, and amount.
    function test_Wrapper_Mint_EmitsBridgeMinted() public {
        uint256 amount = 500 ether;
        vm.prank(address(bridgeA));
        vm.expectEmit(true, true, false, true);
        emit MintBurnWrapper.BridgeMinted(address(bridgeA), user1, amount);
        wrapperA.mint(user1, amount);
    }

    /// @notice burn emits BridgeBurned with the calling bridge, burned address, and amount.
    function test_Wrapper_Burn_EmitsBridgeBurned() public {
        uint256 amount = 500 ether;
        // Give user1 tokens to burn, then approve wrapperA
        vm.prank(address(bridgeA));
        wrapperA.mint(user1, amount);

        vm.prank(user1);
        telcoinA.approve(address(wrapperA), amount);

        vm.prank(address(bridgeA));
        vm.expectEmit(true, true, false, true);
        emit MintBurnWrapper.BridgeBurned(address(bridgeA), user1, amount);
        wrapperA.burn(user1, amount);
    }

    /// @notice authorizeBridge reverts when passed address(0).
    function test_Wrapper_AuthorizeBridge_RevertZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(MintBurnWrapper.ZeroAddress.selector);
        wrapperA.authorizeBridge(address(0));
    }

    /// @notice authorizeBridge reverts when the bridge is already set to the given address.
    function test_Wrapper_AuthorizeBridge_RevertAlreadySet() public {
        vm.prank(owner);
        vm.expectRevert(MintBurnWrapper.BridgeAlreadySet.selector);
        wrapperA.authorizeBridge(address(bridgeA));
    }

    /// @notice revokeBridge reverts when no bridge is currently authorized.
    function test_Wrapper_RevokeBridge_RevertNotSet() public {
        vm.startPrank(owner);
        wrapperA.revokeBridge(address(bridgeA));
        vm.expectRevert(MintBurnWrapper.BridgeNotSet.selector);
        wrapperA.revokeBridge(address(bridgeA));
        vm.stopPrank();
    }

    /// @notice revokeBridge reverts when the supplied address does not match the current bridge.
    function test_Wrapper_RevokeBridge_RevertWrongBridge() public {
        vm.prank(owner);
        vm.expectRevert(MintBurnWrapper.UnauthorizedBridge.selector);
        wrapperA.revokeBridge(address(0x999));
    }

    /// @notice MintBurnWrapper constructor reverts when token is address(0).
    function test_Wrapper_Constructor_RevertZeroToken() public {
        vm.expectRevert(MintBurnWrapper.ZeroAddress.selector);
        new MintBurnWrapper(address(0), owner);
    }

    /// @notice MintBurnWrapper renounceOwnership always reverts.
    function test_Wrapper_RenounceOwnership_Reverts() public {
        vm.prank(owner);
        vm.expectRevert(MintBurnWrapper.CannotRenounceOwnership.selector);
        wrapperA.renounceOwnership();
    }

    // ---------------------
    // Interchangeable Bridge
    // ---------------------

    /// @notice Swapping bridges only requires updating the wrapper's authorized bridges — no TelcoinV3 role changes needed.
    function test_BridgeIsInterchangeable() public {
        uint256 bridgeAmount = 1000 ether;
        bytes memory options = _createBasicOptions();
        SendParam memory sendParam = _createSendParam(EID_B, user1, bridgeAmount, options);

        uint256 preBalUser1 = telcoinA.balanceOf(user1);
        uint256 preSupply = telcoinA.totalSupply();

        // STEP 1: Successful send with original bridgeA
        vm.startPrank(user1);
        MessagingFee memory fee = bridgeA.quoteSend(sendParam, false);
        bridgeA.send{value: fee.nativeFee}(sendParam, fee, user1);
        vm.stopPrank();

        assertEq(telcoinA.balanceOf(user1), preBalUser1 - bridgeAmount);
        assertEq(telcoinA.totalSupply(), preSupply - bridgeAmount);

        // STEP 2: Deploy new bridge, swap it in on the wrapper (no TelcoinV3 role changes)
        vm.startPrank(owner);
        TelcoinBridge newBridgeA = new TelcoinBridge(
            address(telcoinA),
            IMintableBurnable(address(wrapperA)),
            address(endpointA),
            owner
        );
        wrapperA.revokeBridge(address(bridgeA));
        wrapperA.authorizeBridge(address(newBridgeA));
        newBridgeA.setPeer(EID_B, _addressToBytes32(address(bridgeB)));
        bridgeB.setPeer(EID_A, _addressToBytes32(address(newBridgeA)));
        vm.stopPrank();

        // STEP 3: Old bridge can NO LONGER send (wrapper rejects the burn)
        vm.startPrank(user1);
        fee = bridgeA.quoteSend(sendParam, false);
        vm.expectRevert();
        bridgeA.send{value: fee.nativeFee}(sendParam, fee, user1);
        vm.stopPrank();

        preBalUser1 = telcoinA.balanceOf(user1);
        preSupply = telcoinA.totalSupply();

        // STEP 4: New bridge CAN send
        vm.startPrank(user1);
        fee = newBridgeA.quoteSend(sendParam, false);
        (MessagingReceipt memory receipt, ) = newBridgeA.send{value: fee.nativeFee}(sendParam, fee, user1);
        vm.stopPrank();

        assertEq(telcoinA.balanceOf(user1), preBalUser1 - bridgeAmount);
        assertEq(telcoinA.totalSupply(), preSupply - bridgeAmount);

        // STEP 5: Receiving on chain B still works from the new bridge
        endpointB.deliverPacket(
            EID_A,
            _addressToBytes32(address(newBridgeA)),
            1,
            receipt.guid,
            _encodeOFTMessage(user1, bridgeAmount),
            address(bridgeB)
        );

        assertEq(telcoinB.balanceOf(user1), bridgeAmount);
    }
}