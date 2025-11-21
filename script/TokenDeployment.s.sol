// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {TelcoinV3} from "../src/TelcoinV3.sol";

/**
 * @dev deploy TelcoinV3
 */
contract DeployTelcoinV3 is Script {
    TelcoinV3 public telcoinV3;

    uint256 constant TOTAL_SUPPLY = 100 * 10 ** 18; // 100B

    function setUp() public {}

    function run(address governance, address minter) public {
        vm.startBroadcast();
        telcoinV3 = new TelcoinV3(TOTAL_SUPPLY, governance, minter);
        vm.stopBroadcast();
    }
}
