// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {TelcoinBridge} from "../../src/TelcoinBridge.sol";
import {TelcoinV3} from "../../src/TelcoinV3.sol";
import {MockEndpoint} from "../mocks/MockEndpoint.sol";

/**
 * @title BaseSetup
 * @notice This serves as the base file for the TelcoinBridge tests
 */
contract BaseSetup is Test {
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

    function setUp() public virtual {
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
}