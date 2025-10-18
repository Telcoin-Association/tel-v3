// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {NGMUNY} from "../src/NGMUNY.sol";

contract DeployNewGMUNNY is Script {
    Counter public counter;

    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        counter = new NGMUNY();

        vm.stopBroadcast();
    }
}
