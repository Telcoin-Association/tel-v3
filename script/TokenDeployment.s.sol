// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";
import "../src/NewToken.sol";

/**
 * @dev deploy NewToken
 */
contract DeployNewToken is Script {
    NewToken public newToken;

    function setUp() public {}

    function run() public {
        vm.startBroadcast();
        newToken = new NewToken(100 * 10 ** 18); // 100B
        vm.stopBroadcast();
    }
}
