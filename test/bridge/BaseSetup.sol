// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {TelcoinBridge} from "../../src/TelcoinBridge.sol";
import {MintBurnWrapper} from "../../src/MintBurnWrapper.sol";
import {NativeBridge} from "../../src/NativeBridge.sol";
import {TelcoinV3} from "../../src/TelcoinV3.sol";
import {MockEndpoint} from "../mocks/MockEndpoint.sol";
import {Roles} from "../../src/helpers/Roles.sol";
import {IMintableBurnable} from "@layerzerolabs/oft-evm/contracts/interfaces/IMintableBurnable.sol";
import {SendParam, OFTReceipt} from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";
import {MessagingFee, MessagingReceipt} from "@layerzerolabs/oapp-evm/contracts/oapp/OApp.sol";

/**
 * @title BaseSetup
 * @notice This serves as the base file for the TelcoinBridge tests
 */
contract BaseSetup is Test, Roles {
    // Contracts
    TelcoinV3 public telcoinA;
    TelcoinV3 public telcoinB;
    TelcoinBridge public bridgeA;
    TelcoinBridge public bridgeB;
    MintBurnWrapper public wrapperA;
    MintBurnWrapper public wrapperB;
    NativeBridge public nativeBridge;
    MockEndpoint public endpointA;
    MockEndpoint public endpointB;
    MockEndpoint public endpointTN;

    // Actors
    address public owner = makeAddr("owner");
    address public user1 = makeAddr("user 1");
    address public user2 = makeAddr("user 2");

    // Constants
    uint32 constant EID_A = 1;
    uint32 constant EID_B = 2;
    uint32 constant EID_TN = 3;
    uint256 constant INITIAL_SUPPLY = 1_000_000_000 ether;
    uint256 constant USER_BALANCE = 1_000_000 ether;
    uint256 constant NATIVE_RESERVE = 1_000_000 ether;

    // OFT events — must match IOFT.sol exactly (dstEid/srcEid are NOT indexed)
    event OFTSent(bytes32 indexed guid, uint32 dstEid, address indexed fromAddress, uint256 amountSentLD, uint256 amountReceivedLD);
    event OFTReceived(bytes32 indexed guid, uint32 srcEid, address indexed toAddress, uint256 amountReceivedLD);

    function setUp() public virtual {
        endpointA = new MockEndpoint(EID_A);
        endpointB = new MockEndpoint(EID_B);
        endpointTN = new MockEndpoint(EID_TN);

        vm.startPrank(owner);

        telcoinA = new TelcoinV3(INITIAL_SUPPLY, owner);
        telcoinB = new TelcoinV3(INITIAL_SUPPLY, owner);

        // Deploy wrappers — these hold MINTER/BURNER roles on the token
        wrapperA = new MintBurnWrapper(address(telcoinA), owner);
        wrapperB = new MintBurnWrapper(address(telcoinB), owner);

        // Deploy satellite bridges
        bridgeA = new TelcoinBridge(address(telcoinA), IMintableBurnable(address(wrapperA)), address(endpointA), owner);
        bridgeB = new TelcoinBridge(address(telcoinB), IMintableBurnable(address(wrapperB)), address(endpointB), owner);

        // Deploy NativeBridge on TelcoinNetwork
        nativeBridge = new NativeBridge(address(endpointTN), owner);

        // Wire satellite bridges to each other and to NativeBridge
        bridgeA.setPeer(EID_B, _addressToBytes32(address(bridgeB)));
        bridgeA.setPeer(EID_TN, _addressToBytes32(address(nativeBridge)));
        bridgeB.setPeer(EID_A, _addressToBytes32(address(bridgeA)));
        bridgeB.setPeer(EID_TN, _addressToBytes32(address(nativeBridge)));
        nativeBridge.setPeer(EID_A, _addressToBytes32(address(bridgeA)));
        nativeBridge.setPeer(EID_B, _addressToBytes32(address(bridgeB)));

        // Grant token roles to wrappers (not bridges directly)
        telcoinA.grantRole(MINTER_ROLE, address(wrapperA));
        telcoinA.grantRole(BURNER_ROLE, address(wrapperA));
        telcoinB.grantRole(MINTER_ROLE, address(wrapperB));
        telcoinB.grantRole(BURNER_ROLE, address(wrapperB));

        // Authorize bridges on their wrappers
        wrapperA.authorizeBridge(address(bridgeA));
        wrapperB.authorizeBridge(address(bridgeB));

        telcoinA.transfer(user1, USER_BALANCE);
        telcoinA.transfer(user2, USER_BALANCE);

        vm.stopPrank();

        // Fund users with native for LZ fees and NativeBridge sends
        vm.deal(user1, 100 ether);
        vm.deal(user2, 100 ether);

        // Seed NativeBridge reserve so it can credit native TEL on receive
        vm.deal(address(nativeBridge), NATIVE_RESERVE);
    }

    // -------
    // Helpers
    // -------

    function _addressToBytes32(address _addr) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(_addr)));
    }

    function _createBasicOptions() internal pure returns (bytes memory) {
        return abi.encodePacked(uint16(3));
    }

    /// @dev Builds a SendParam for the common case: no compose, no slippage enforcement.
    function _createSendParam(
        uint32 _dstEid,
        address _to,
        uint256 _amountLD,
        bytes memory _options
    ) internal pure returns (SendParam memory) {
        return SendParam({
            dstEid: _dstEid,
            to: bytes32(uint256(uint160(_to))),
            amountLD: _amountLD,
            minAmountLD: 0,
            extraOptions: _options,
            composeMsg: bytes(""),
            oftCmd: bytes("")
        });
    }

    /// @dev Encodes an OFT lzReceive message (no compose): bytes32(to) ++ uint64(amountSD).
    ///      decimalConversionRate = 1e12 (localDecimals=18, sharedDecimals=6).
    function _encodeOFTMessage(address _to, uint256 _amountLD) internal pure returns (bytes memory) {
        return abi.encodePacked(bytes32(uint256(uint160(_to))), uint64(_amountLD / 1e12));
    }
}