// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BaseSetup} from "./BaseSetup.sol";
import {SendParam, OFTReceipt} from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";
import {MessagingFee, MessagingReceipt} from "@layerzerolabs/oapp-evm/contracts/oapp/OApp.sol";

/**
 * @title RoundTripTest
 * @notice End-to-end conservation tests verifying that tokens burned/locked on one chain
 *         are credited exactly 1:1 on the destination chain — no tokens created or destroyed
 *         in transit.
 *
 * @dev Uses MockEndpoint.deliverPacket() to simulate the LZ executor, which is more
 *      realistic than calling lzReceive() directly as it routes through the endpoint.
 */
contract RoundTripTest is BaseSetup {
    function setUp() public override {
        super.setUp();
    }

    // -------
    // Helpers
    // -------

    /// @dev Burns ERC20 TEL on satellite A and delivers the packet to NativeBridge on TelcoinNetwork.
    function _stepSatelliteToTN(uint256 bridgeAmount) internal {
        SendParam memory toTN = _createSendParam(EID_TN, user1, bridgeAmount, _createBasicOptions());
        vm.startPrank(user1);
        MessagingFee memory fee = bridgeA.quoteSend(toTN, false);
        (MessagingReceipt memory receipt, ) = bridgeA.send{value: fee.nativeFee}(toTN, fee, user1);
        vm.stopPrank();
        endpointTN.deliverPacket(EID_A, _addressToBytes32(address(bridgeA)), 1, receipt.guid, _encodeOFTMessage(user1, bridgeAmount), address(nativeBridge));
    }

    /// @dev Locks native TEL in NativeBridge on TelcoinNetwork and delivers the packet to satellite A.
    function _stepTNToSatellite(uint256 bridgeAmount) internal {
        SendParam memory toA = _createSendParam(EID_A, user1, bridgeAmount, _createBasicOptions());
        vm.startPrank(user1);
        MessagingFee memory fee = nativeBridge.quoteSend(toA, false);
        (MessagingReceipt memory receipt, ) = nativeBridge.send{value: fee.nativeFee + bridgeAmount}(toA, fee, user1);
        vm.stopPrank();
        endpointA.deliverPacket(EID_TN, _addressToBytes32(address(nativeBridge)), 1, receipt.guid, _encodeOFTMessage(user1, bridgeAmount), address(bridgeA));
    }

    // --------------------------
    // Satellite → TN Round Trips
    // --------------------------

    /// @notice ERC20 TEL burned on satellite A credits exactly the same amount of native TEL on TelcoinNetwork.
    function test_RoundTrip_SatelliteToTN() public {
        uint256 bridgeAmount = 1000 ether;

        uint256 user1ERC20Before = telcoinA.balanceOf(user1);
        uint256 user1NativeBefore = user1.balance;
        uint256 reserveBefore = address(nativeBridge).balance;

        SendParam memory sendParam = _createSendParam(EID_TN, user1, bridgeAmount, _createBasicOptions());

        vm.startPrank(user1);
        MessagingFee memory fee = bridgeA.quoteSend(sendParam, false);
        (MessagingReceipt memory receipt, ) = bridgeA.send{value: fee.nativeFee}(sendParam, fee, user1);
        vm.stopPrank();

        assertEq(telcoinA.balanceOf(user1), user1ERC20Before - bridgeAmount);

        endpointTN.deliverPacket(
            EID_A,
            _addressToBytes32(address(bridgeA)),
            1,
            receipt.guid,
            _encodeOFTMessage(user1, bridgeAmount),
            address(nativeBridge)
        );

        assertEq(user1.balance, user1NativeBefore - fee.nativeFee + bridgeAmount);
        assertEq(address(nativeBridge).balance,  reserveBefore - bridgeAmount);
    }

    /// @notice Amounts with sub-1e12 dust are stripped consistently on both sides —
    ///         burned amount equals credited amount, dust stays with the sender.
    function test_RoundTrip_DustRemovedConsistently() public {
        // 1.5 TEL + 999 wei of sub-1e12 dust
        uint256 sendAmount = 1.5 ether + 999;
        uint256 expectedLD = (sendAmount / 1e12) * 1e12;

        uint256 supplyBefore   = telcoinA.totalSupply();
        uint256 user1TelBefore = telcoinA.balanceOf(user1);
        uint256 user2NatBefore = user2.balance;

        SendParam memory sendParam = _createSendParam(EID_TN, user2, sendAmount, _createBasicOptions());

        vm.startPrank(user1);
        MessagingFee memory fee = bridgeA.quoteSend(sendParam, false);
        (MessagingReceipt memory receipt, OFTReceipt memory oftReceipt) = bridgeA.send{value: fee.nativeFee}(sendParam, fee, user1);
        vm.stopPrank();

        assertEq(oftReceipt.amountReceivedLD, expectedLD, "dust not stripped as expected");
        assertEq(telcoinA.totalSupply(),       supplyBefore   - expectedLD);
        assertEq(telcoinA.balanceOf(user1),    user1TelBefore - expectedLD);

        endpointTN.deliverPacket(
            EID_A,
            _addressToBytes32(address(bridgeA)),
            1,
            receipt.guid,
            _encodeOFTMessage(user2, expectedLD),
            address(nativeBridge)
        );

        assertEq(user2.balance - user2NatBefore, expectedLD);
    }

    /// @notice Fuzz: for any local-decimal amount, ERC20 burned on satellite == native TEL credited on TN.
    ///         Sub-1e12 dust is stripped by the protocol before burning — the credited amount equals
    ///         the burned amount, and any dust remains with the sender.
    function testFuzz_RoundTrip_SatelliteToTN(uint256 amountLD) public {
        // Minimum 1e12 so at least 1 SD unit survives dust removal; cap at user balance
        amountLD = bound(amountLD, 1e12, USER_BALANCE);

        uint256 supplyBefore   = telcoinA.totalSupply();
        uint256 user1TelBefore = telcoinA.balanceOf(user1);
        uint256 user1NatBefore = user1.balance;
        uint256 reserveBefore  = address(nativeBridge).balance;

        SendParam memory sendParam = _createSendParam(EID_TN, user1, amountLD, _createBasicOptions());

        vm.startPrank(user1);
        MessagingFee memory fee = bridgeA.quoteSend(sendParam, false);
        (MessagingReceipt memory receipt, OFTReceipt memory oftReceipt) = bridgeA.send{value: fee.nativeFee}(sendParam, fee, user1);
        vm.stopPrank();

        uint256 amountCredited = oftReceipt.amountReceivedLD;

        assertEq(telcoinA.balanceOf(user1), user1TelBefore - amountCredited);
        assertEq(telcoinA.totalSupply(),    supplyBefore   - amountCredited);

        endpointTN.deliverPacket(
            EID_A,
            _addressToBytes32(address(bridgeA)),
            1,
            receipt.guid,
            _encodeOFTMessage(user1, amountCredited),
            address(nativeBridge)
        );

        assertEq(user1.balance,                 user1NatBefore - fee.nativeFee + amountCredited);
        assertEq(address(nativeBridge).balance,  reserveBefore - amountCredited);
    }

    // --------------------------
    // TN → Satellite Round Trips
    // --------------------------

    /// @notice Native TEL locked in NativeBridge on TN mints exactly the same amount of ERC20 TEL on satellite A.
    function test_RoundTrip_TNToSatellite() public {
        uint256 bridgeAmount = 10 ether;

        uint256 user1ERC20Before = telcoinA.balanceOf(user1);
        uint256 reserveBefore    = address(nativeBridge).balance;

        SendParam memory sendParam = _createSendParam(EID_A, user1, bridgeAmount, _createBasicOptions());

        vm.startPrank(user1);
        MessagingFee memory fee = nativeBridge.quoteSend(sendParam, false);
        (MessagingReceipt memory receipt, ) = nativeBridge.send{value: fee.nativeFee + bridgeAmount}(sendParam, fee, user1);
        vm.stopPrank();

        assertEq(address(nativeBridge).balance, reserveBefore + bridgeAmount);

        endpointA.deliverPacket(
            EID_TN,
            _addressToBytes32(address(nativeBridge)),
            1,
            receipt.guid,
            _encodeOFTMessage(user1, bridgeAmount),
            address(bridgeA)
        );

        assertEq(telcoinA.balanceOf(user1), user1ERC20Before + bridgeAmount);
    }

    /// @notice Fuzz: for any dust-free amount, native TEL locked on TN == ERC20 TEL minted on satellite.
    ///         Uses uint64 amountSD so amounts are always exact multiples of 1e12 — no dust to reason about.
    function testFuzz_RoundTrip_TNToSatellite(uint64 amountSD) public {
        // Bound so amountLD fits within user1's 100 ether native budget (minus fee headroom)
        amountSD = uint64(bound(amountSD, 1, 50_000_000)); // max 50 TEL
        uint256 amountLD = uint256(amountSD) * 1e12;

        uint256 erc20Before   = telcoinA.balanceOf(user1);
        uint256 reserveBefore = address(nativeBridge).balance;

        SendParam memory sendParam = _createSendParam(EID_A, user1, amountLD, _createBasicOptions());

        vm.startPrank(user1);
        MessagingFee memory fee = nativeBridge.quoteSend(sendParam, false);
        (MessagingReceipt memory receipt, ) = nativeBridge.send{value: fee.nativeFee + amountLD}(sendParam, fee, user1);
        vm.stopPrank();

        assertEq(address(nativeBridge).balance, reserveBefore + amountLD);

        endpointA.deliverPacket(
            EID_TN,
            _addressToBytes32(address(nativeBridge)),
            1,
            receipt.guid,
            _encodeOFTMessage(user1, amountLD),
            address(bridgeA)
        );

        assertEq(telcoinA.balanceOf(user1), erc20Before + amountLD);
    }

    // -------------------
    // Bidirectional Cycle
    // -------------------

    /// @notice Full bi-directional cycle: satellite → TN → satellite returns to the original ERC20 balance.
    function test_RoundTrip_Complete() public {
        uint256 bridgeAmount = 500 ether;
        uint256 erc20Before  = telcoinA.balanceOf(user1);

        _stepSatelliteToTN(bridgeAmount);
        assertEq(telcoinA.balanceOf(user1), erc20Before - bridgeAmount);

        _stepTNToSatellite(bridgeAmount);
        assertEq(telcoinA.balanceOf(user1), erc20Before);
    }
}
