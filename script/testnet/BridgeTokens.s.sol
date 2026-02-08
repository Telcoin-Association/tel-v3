// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {console} from "forge-std/console.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {DeployUtility} from "../utils/DeployUtility.sol";
import {TelcoinBridge} from "../../src/TelcoinBridge.sol";
import {MessagingFee, MessagingReceipt} from "@layerzerolabs/oapp-evm/contracts/oapp/OApp.sol";
import "../utils/Constants.sol";

/**
 * @title BridgeTokens
 * @author chasebrownn
 * @notice Script to bridge TelcoinV3 tokens across chains via TelcoinBridge (LayerZero V2).
 *
 * ## How to Run
 *
 * Dry run (Sepolia -> Base Sepolia):
 * ```
 * forge script script/testnet/BridgeTokens.s.sol --rpc-url $ETH_SEPOLIA_RPC_URL
 * ```
 *
 * Live execution (Sepolia -> Base Sepolia):
 * ```
 * forge script script/testnet/BridgeTokens.s.sol --rpc-url $ETH_SEPOLIA_RPC_URL --broadcast -vvvv
 * ```
 *
 * Note: Change SOURCE_CHAIN and DESTINATION_EID constants to bridge in the other direction.
 */
contract BridgeTokens is DeployUtility {
    // ---------
    // Variables
    // ---------

    /// @dev Amount of TelcoinV3 to bridge
    uint256 internal constant BRIDGE_AMOUNT = 1_000_000 ether;

    /// @dev Source chain alias (where we're bridging FROM)
    string internal constant SOURCE_CHAIN = "eth-sepolia";

    /// @dev Destination chain LayerZero endpoint ID
    uint32 internal constant DESTINATION_EID = BASE_SEPOLIA_LZ_CHAIN_ID_V2;

    /// @dev Destination chain alias (for logging)
    string internal constant DESTINATION_CHAIN = "base-sepolia";

    // ------
    // Script
    // ------

    function run() public {
        _setup();

        // Load deployed contract addresses
        address telcoinV3 = _loadDeploymentAddress(SOURCE_CHAIN, "TelcoinV3");
        address bridgeContract = _loadDeploymentAddress(SOURCE_CHAIN, "TelcoinBridge");

        require(telcoinV3 != address(0), "TelcoinV3 not deployed on source chain");
        require(bridgeContract != address(0), "TelcoinBridge not deployed on source chain");

        console.log("=== Bridge Script ===");
        console.log("Source Chain:", SOURCE_CHAIN);
        console.log("Destination Chain:", DESTINATION_CHAIN);
        console.log("Destination EID:", DESTINATION_EID);
        console.log("Bridger:", _deployer);
        console.log("");
        console.log("TelcoinV3:", telcoinV3);
        console.log("TelcoinBridge:", bridgeContract);
        console.log("");

        IERC20 token = IERC20(telcoinV3);
        TelcoinBridge bridge = TelcoinBridge(bridgeContract);

        // --- PRE-BRIDGE CHECKS ---
        console.log("=== Pre-Bridge State ===");

        uint256 balanceBefore = token.balanceOf(_deployer);
        uint256 totalSupplyBefore = token.totalSupply();

        console.log("Deployer TelcoinV3 Balance:", balanceBefore);
        console.log("TelcoinV3 Total Supply:", totalSupplyBefore);
        console.log("Amount to Bridge:", BRIDGE_AMOUNT);
        console.log("");

        require(balanceBefore >= BRIDGE_AMOUNT, "Insufficient TelcoinV3 balance");

        // Build options (TYPE_3 minimal options)
        bytes memory options = abi.encodePacked(uint16(3));

        // Get quote for the bridge transaction
        MessagingFee memory fee = bridge.quote(DESTINATION_EID, _deployer, BRIDGE_AMOUNT, options);

        console.log("LayerZero Fee (native):", fee.nativeFee);
        console.log("LayerZero Fee (lzToken):", fee.lzTokenFee);
        console.log("");

        // Check deployer has enough ETH for the fee
        uint256 ethBalance = _deployer.balance;
        console.log("Deployer ETH Balance:", ethBalance);
        require(ethBalance >= fee.nativeFee, "Insufficient ETH for LayerZero fee");
        console.log("");

        // --- EXECUTE BRIDGE ---
        console.log("=== Executing Bridge ===");

        vm.startBroadcast(_pk);

        // Step 1: Approve bridge contract to spend tokens
        console.log("Step 1: Approving bridge contract...");
        token.approve(bridgeContract, BRIDGE_AMOUNT);

        // Step 2: Execute bridge
        console.log("Step 2: Calling bridge()...");
        MessagingReceipt memory receipt = bridge.bridge{value: fee.nativeFee}(
            DESTINATION_EID,
            _deployer, // Send to same address on destination
            BRIDGE_AMOUNT,
            options
        );

        vm.stopBroadcast();

        // --- POST-BRIDGE CHECKS ---
        console.log("");
        console.log("=== Post-Bridge State ===");

        uint256 balanceAfter = token.balanceOf(_deployer);
        uint256 totalSupplyAfter = token.totalSupply();

        console.log("Deployer TelcoinV3 Balance:", balanceAfter);
        console.log("TelcoinV3 Total Supply:", totalSupplyAfter);
        console.log("");

        // Verify state changes
        console.log("=== Verification ===");

        bool tokensBurned = (balanceBefore - balanceAfter) == BRIDGE_AMOUNT;
        bool supplyReduced = (totalSupplyBefore - totalSupplyAfter) == BRIDGE_AMOUNT;

        console.log("Tokens burned from sender:", tokensBurned ? "PASS" : "FAIL");
        console.log("Total supply reduced:", supplyReduced ? "PASS" : "FAIL");
        console.log("");

        // Log receipt details
        console.log("=== LayerZero Receipt ===");
        console.log("GUID:");
        console.logBytes32(receipt.guid);
        console.log("Nonce:", receipt.nonce);
        console.log("Fee Paid:", receipt.fee.nativeFee);
        console.log("");

        if (tokensBurned && supplyReduced) {
            console.log("Bridge transaction successful!");
            console.log("");
            console.log("Tokens will be minted on destination chain once LayerZero delivers the message.");
            console.log("Track the message at: https://layerzeroscan.com/");
        } else {
            console.log("Bridge verification failed!");
        }
    }
}
