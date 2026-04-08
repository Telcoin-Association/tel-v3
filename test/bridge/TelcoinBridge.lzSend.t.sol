// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BaseSetup} from "./BaseSetup.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {IOAppCore} from "@layerzerolabs/oapp-evm/contracts/oapp/interfaces/IOAppCore.sol";
import {TelcoinBridge} from "../../src/TelcoinBridge.sol";
import {MintBurnWrapper} from "../../src/MintBurnWrapper.sol";
import {IMintableBurnable} from "@layerzerolabs/oft-evm/contracts/interfaces/IMintableBurnable.sol";
import {SendParam, OFTReceipt} from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";
import {MessagingFee, MessagingReceipt} from "@layerzerolabs/oapp-evm/contracts/oapp/OApp.sol";

contract TelcoinBridgeLzSendTest is BaseSetup {
    function setUp() public override {
        super.setUp();
    }

    // ----------
    // Send Tests
    // ----------

    function test_LzSend_Success() public {
        uint256 bridgeAmount = 1000 ether;
        bytes memory options = _createBasicOptions();
        uint256 preSupply = telcoinA.totalSupply();
        uint256 user1BalanceBefore = telcoinA.balanceOf(user1);

        SendParam memory sendParam = _createSendParam(EID_B, user2, bridgeAmount, options);

        vm.startPrank(user1);
        MessagingFee memory fee = bridgeA.quoteSend(sendParam, false);
        (MessagingReceipt memory receipt, ) = bridgeA.send{value: fee.nativeFee}(sendParam, fee, user1);
        vm.stopPrank();

        assertEq(telcoinA.balanceOf(user1), user1BalanceBefore - bridgeAmount);
        assertEq(telcoinA.totalSupply(), preSupply - bridgeAmount);
        assertTrue(receipt.guid != bytes32(0));
        assertEq(receipt.fee.nativeFee, fee.nativeFee);
    }

    function test_LzSend_EmitsEvent() public {
        uint256 bridgeAmount = 1000 ether;
        bytes memory options = _createBasicOptions();
        SendParam memory sendParam = _createSendParam(EID_B, user1, bridgeAmount, options);

        vm.startPrank(user1);
        MessagingFee memory fee = bridgeA.quoteSend(sendParam, false);

        // OFTSent has 2 indexed params (guid, fromAddress); dstEid is non-indexed data
        vm.expectEmit(false, true, false, true);
        emit OFTSent(bytes32(0), EID_B, user1, bridgeAmount, bridgeAmount);

        bridgeA.send{value: fee.nativeFee}(sendParam, fee, user1);
        vm.stopPrank();
    }

    function test_LzSend_RevertWhenPaused() public {
        bytes memory options = _createBasicOptions();
        SendParam memory sendParam = _createSendParam(EID_B, user1, 1000 ether, options);

        vm.prank(owner);
        bridgeA.pause();

        vm.startPrank(user1);
        MessagingFee memory fee = bridgeA.quoteSend(sendParam, false);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        bridgeA.send{value: fee.nativeFee}(sendParam, fee, user1);
        vm.stopPrank();
    }

    function test_LzSend_RevertNoPeer() public {
        // Deploy a bridge with no peer set
        vm.startPrank(owner);
        TelcoinBridge bridgeNoPeer = new TelcoinBridge(
            address(telcoinA),
            IMintableBurnable(address(wrapperA)),
            address(endpointA),
            owner
        );
        wrapperA.authorizeBridge(address(bridgeNoPeer));
        vm.stopPrank();

        SendParam memory sendParam = _createSendParam(EID_B, user1, 1000 ether, _createBasicOptions());

        // quoteSend also calls _getPeerOrRevert internally, so skip it and use a hardcoded fee
        vm.startPrank(user1);
        vm.expectRevert(abi.encodeWithSelector(IOAppCore.NoPeer.selector, EID_B));
        bridgeNoPeer.send{value: 0.1 ether}(sendParam, MessagingFee(0.1 ether, 0), user1);
        vm.stopPrank();
    }

    function testFuzz_LzSend(uint256 amount) public {
        // Minimum 1e12 to avoid full dust removal; max USER_BALANCE
        amount = bound(amount, 1e12, USER_BALANCE);

        bytes memory options = _createBasicOptions();
        uint256 balanceBefore = telcoinA.balanceOf(user1);
        uint256 preSupply = telcoinA.totalSupply();

        SendParam memory sendParam = _createSendParam(EID_B, user1, amount, options);

        vm.startPrank(user1);
        MessagingFee memory fee = bridgeA.quoteSend(sendParam, false);
        bridgeA.send{value: fee.nativeFee}(sendParam, fee, user1);
        vm.stopPrank();

        // Dust-removed amount is what was actually burned
        uint256 amountSent = (amount / 1e12) * 1e12;
        assertEq(telcoinA.balanceOf(user1), balanceBefore - amountSent);
        assertEq(telcoinA.totalSupply(), preSupply - amountSent);
    }
}