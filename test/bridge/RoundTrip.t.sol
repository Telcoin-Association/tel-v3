// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BaseSetup} from "./BaseSetup.sol";
import {SendParam, OFTReceipt} from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";
import {MessagingFee, MessagingReceipt} from "@layerzerolabs/oapp-evm/contracts/oapp/OApp.sol";
import {Origin} from "@layerzerolabs/oapp-evm/contracts/oapp/OApp.sol";

/**
 * @title RoundTripTest
 * @notice Verifies that the amount burned on a satellite chain equals the amount
 *         credited as native TEL on TelcoinNetwork — no tokens created or destroyed
 *         in transit.
 *
 * @dev Uses a two-step approach since MockEndpoint doesn't auto-relay:
 *      1. Call bridgeA.send() — burns ERC20 TEL, returns OFTReceipt with amountReceivedLD
 *      2. Manually call nativeBridge.lzReceive() with that exact amount
 *      This mirrors exactly what the LZ executor does in production.
 */
contract RoundTripTest is BaseSetup {
    function setUp() public override {
        super.setUp();
    }

    // -----------
    // Round Trips
    // -----------

    /// @notice 1 TEL burned on Chain A credits exactly 1 native TEL on TelcoinNetwork.
    function test_RoundTrip() public {
        uint256 sendAmount = 1 ether;

        uint256 supplyBefore   = telcoinA.totalSupply();
        uint256 user1TelBefore = telcoinA.balanceOf(user1);
        uint256 user2NatBefore = user2.balance;
        uint256 reserveBefore  = address(nativeBridge).balance;

        // Step 1: burn on Chain A
        SendParam memory sendParam = _createSendParam(EID_TN, user2, sendAmount, _createBasicOptions());

        vm.startPrank(user1);
        MessagingFee memory fee = bridgeA.quoteSend(sendParam, false);
        (, OFTReceipt memory oftReceipt) = bridgeA.send{value: fee.nativeFee}(sendParam, fee, user1);
        vm.stopPrank();

        uint256 amountCredited = oftReceipt.amountReceivedLD;

        assertEq(telcoinA.balanceOf(user1), user1TelBefore - amountCredited);
        assertEq(telcoinA.totalSupply(),    supplyBefore   - amountCredited);

        // Step 2: relay to NativeBridge — simulates the LZ executor
        Origin memory origin = Origin({srcEid: EID_A, sender: _addressToBytes32(address(bridgeA)), nonce: 1});

        vm.prank(address(endpointTN));
        nativeBridge.lzReceive(
            origin,
            keccak256("round-trip-1-tel"),
            _encodeOFTMessage(user2, amountCredited),
            address(0),
            bytes("")
        );

        assertEq(user2.balance, user2NatBefore + amountCredited);
        assertEq(address(nativeBridge).balance, reserveBefore  - amountCredited);
        assertEq(amountCredited, sendAmount);
    }

    /// @notice Verifies TEL burned on Chain A credits exactly 1:1 native TEL on TelcoinNetwork.
    function testFuzz_RoundTrip(uint256 amount) public {
        // USER_BALANCE = 1_000_000 ether
        amount = bound(amount, 1e12, USER_BALANCE);

        uint256 supplyBefore   = telcoinA.totalSupply();
        uint256 user1TelBefore = telcoinA.balanceOf(user1);
        uint256 user2NatBefore = user2.balance;
        uint256 reserveBefore  = address(nativeBridge).balance;

        // Step 1: burn on Chain A
        SendParam memory sendParam = _createSendParam(EID_TN, user2, amount, _createBasicOptions());

        vm.startPrank(user1);
        MessagingFee memory fee = bridgeA.quoteSend(sendParam, false);
        (, OFTReceipt memory oftReceipt) = bridgeA.send{value: fee.nativeFee}(sendParam, fee, user1);
        vm.stopPrank();

        uint256 amountCredited = oftReceipt.amountReceivedLD;

        assertEq(telcoinA.balanceOf(user1), user1TelBefore - amountCredited);
        assertEq(telcoinA.totalSupply(),    supplyBefore   - amountCredited);

        // Step 2: relay to NativeBridge — simulates the LZ executor
        Origin memory origin = Origin({srcEid: EID_A, sender: _addressToBytes32(address(bridgeA)), nonce: 1});

        vm.prank(address(endpointTN));
        nativeBridge.lzReceive(
            origin,
            keccak256(abi.encodePacked("round-trip-fuzz", amount)),
            _encodeOFTMessage(user2, amountCredited),
            address(0),
            bytes("")
        );

        assertEq(user2.balance,                 user2NatBefore + amountCredited);
        assertEq(address(nativeBridge).balance, reserveBefore  - amountCredited);
    }

    /// @notice Amounts with sub-1e12 dust are rounded down consistently on both sides —
    ///         the burned amount and the credited amount are always equal.
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
        (, OFTReceipt memory oftReceipt) = bridgeA.send{value: fee.nativeFee}(sendParam, fee, user1);
        vm.stopPrank();

        uint256 amountCredited = oftReceipt.amountReceivedLD;
        assertEq(amountCredited, expectedLD, "dust not stripped as expected");
        assertEq(telcoinA.totalSupply(), supplyBefore - expectedLD);

        Origin memory origin = Origin({srcEid: EID_A, sender: _addressToBytes32(address(bridgeA)), nonce: 1});

        vm.prank(address(endpointTN));
        nativeBridge.lzReceive(
            origin,
            keccak256("round-trip-dust"),
            _encodeOFTMessage(user2, amountCredited),
            address(0),
            bytes("")
        );

        assertEq(telcoinA.balanceOf(user1), user1TelBefore - expectedLD);
        assertEq(user2.balance - user2NatBefore, expectedLD);
    }
}
