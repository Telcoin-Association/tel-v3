// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";
import "../src/NGMUNY.sol";

/**
 * @dev deploy nGMUNY
 */
contract DeployNewGMUNNY is Script {
    nGMUNY public ngmuny;

    function setUp() public {}

    function run() public {
        // vm.startBroadcast();
        // ngmuny = new nGMUNY(100 * 10 ** 18); // 100B
        // vm.stopBroadcast();
    }
}
