// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script, console} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SendParam, OFTReceipt} from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";
import {MessagingFee, MessagingReceipt} from "@layerzerolabs/oapp-evm/contracts/oapp/OApp.sol";
import {TelcoinBridge} from "../../../src/TelcoinBridge.sol";

/// @title SimulateBridge
/// @notice Simulates a bridge send by pranking the Safe. No hardware wallet needed.
contract SimulateBridge is Script {
    function run() external {
        address safe = 0x765327d1AeA74cC360B1C6Cc567200d7e4baC3fD;
        address telv3 = 0xdC08977D6DE250CBD8a41E29a88e1927aEAE8551;
        address bridgeAddr = 0x1b8E2695249850cF2379b574e0620D11CFE0c514;
        uint256 amount = 1_000_000 ether;

        TelcoinBridge bridge = TelcoinBridge(bridgeAddr);
        address wrapper = address(bridge.minterBurner());

        SendParam memory sp = SendParam({
            dstEid: 40161, // eth-sepolia
            to: bytes32(uint256(uint160(safe))),
            amountLD: amount,
            minAmountLD: 0,
            extraOptions: hex"00030100110100000000000000000000000000030d40",
            composeMsg: bytes(""),
            oftCmd: bytes("")
        });

        MessagingFee memory fee = bridge.quoteSend(sp, false);

        console.log("=== Bridge Simulation (base-sepolia -> eth-sepolia) ===");
        console.log("Safe TEL balance before:", IERC20(telv3).balanceOf(safe));
        console.log("Amount to bridge:", amount);
        console.log("LZ native fee:", fee.nativeFee);

        vm.startPrank(safe);
        vm.deal(safe, fee.nativeFee);
        IERC20(telv3).approve(wrapper, amount);
        bridge.send{value: fee.nativeFee}(sp, fee, safe);
        vm.stopPrank();

        console.log("Safe TEL balance after:", IERC20(telv3).balanceOf(safe));
        console.log("Tokens burned:", amount);
        console.log("Bridge simulation SUCCEEDED");
    }
}
