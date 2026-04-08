// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {console} from "forge-std/console.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {DeployUtility} from "../utils/DeployUtility.sol";
import {TelcoinBridge} from "../../src/TelcoinBridge.sol";
import {MessagingFee, MessagingReceipt} from "@layerzerolabs/oapp-evm/contracts/oapp/OApp.sol";
import {SendParam, OFTReceipt} from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";
import "../utils/Constants.sol";

/**
 * @title BridgeTokens
 * @author chasebrownn
 * @notice Script to bridge TelcoinV3 tokens across chains via TelcoinBridge (LayerZero V2).
 *
 * @dev Configure the `pathway` array in setUp():
 *      - pathway[0] = source chain (where tokens are burned)
 *      - pathway[1] = destination chain (where tokens are minted)
 *
 * ## How to Run
 *
 * Dry run:
 * ```
 * forge script script/testnet/BridgeTokens.s.sol --rpc-url <SOURCE_CHAIN_RPC>
 * ```
 *
 * Live execution:
 * ```
 * forge script script/testnet/BridgeTokens.s.sol --rpc-url <SOURCE_CHAIN_RPC> --broadcast -vvvv
 * ```
 */
contract BridgeTokens is DeployUtility {
    // ---------
    // Constants
    // ---------

    /// @dev Amount of TelcoinV3 to bridge
    uint256 internal constant BRIDGE_AMOUNT = 1_000_000 ether;

    /// @dev Gas limit for lzReceive on destination
    uint128 internal constant DST_GAS_LIMIT = 200_000;

    // ---------
    // Variables
    // ---------

    ChainConfig[2] internal pathway;

    struct ChainConfig {
        string chainName;       // Chain alias for deployment JSON lookup
        string rpcUrl;          // RPC URL for this chain
        uint32 eid;             // LayerZero endpoint ID
    }

    // -----
    // Setup
    // -----

    function setUp() public {
        _setup();

        // ---------------------------------------------------
        // CONFIGURE PATHWAY HERE
        // ---------------------------------------------------
        // pathway[0] = SOURCE chain (tokens burned here)
        // pathway[1] = DESTINATION chain (tokens minted here)
        // ---------------------------------------------------

        // Source:
        pathway[0] = ChainConfig({
            chainName: "base-sepolia",
            rpcUrl: vm.envString("BASE_SEPOLIA_RPC_URL"),
            eid: BASE_SEPOLIA_LZ_CHAIN_ID_V2
        });

        // Destination:
        pathway[1] = ChainConfig({
            chainName: "eth-sepolia",
            rpcUrl: vm.envString("ETH_SEPOLIA_RPC_URL"),
            eid: ETH_SEPOLIA_LZ_CHAIN_ID_V2
        });
    }

    // ------
    // Script
    // ------

    function run() public {
        ChainConfig memory src = pathway[0];
        ChainConfig memory dst = pathway[1];

        // Load deployed contract addresses
        address telcoinV3 = _loadDeploymentAddress(src.chainName, "TelcoinV3");
        address bridgeContract = _loadDeploymentAddress(src.chainName, "TelcoinBridge");

        require(telcoinV3 != address(0), "TelcoinV3 not deployed on source chain");
        require(bridgeContract != address(0), "TelcoinBridge not deployed on source chain");

        console.log("=== Bridge Script ===");
        console.log("Source Chain:", src.chainName);
        console.log("Destination Chain:", dst.chainName);
        console.log("Destination EID:", dst.eid);
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

        // Build LayerZero V2 TYPE_3 options with executor lzReceive gas
        // Format: [TYPE_3][WORKER_ID][size][option_type][gas]
        // - TYPE_3 = 0x0003 (uint16)
        // - WORKER_ID = 0x01 (uint8, executor)
        // - size = 17 (uint16, 1 byte option_type + 16 bytes gas)
        // - option_type = 0x01 (uint8, LZRECEIVE)
        // - gas = uint128 (16 bytes)
        bytes memory options = abi.encodePacked(
            uint16(3),           // TYPE_3
            uint8(1),            // WORKER_ID (executor)
            uint16(17),          // size (1 + 16)
            uint8(1),            // OPTION_TYPE_LZRECEIVE
            DST_GAS_LIMIT        // gas as uint128
        );

        console.log("Options:");
        console.logBytes(options);
        console.log("");

        // Get quote for the bridge transaction
        SendParam memory sendParam = SendParam({
            dstEid: dst.eid,
            to: bytes32(uint256(uint160(_deployer))),
            amountLD: BRIDGE_AMOUNT,
            minAmountLD: 0,
            extraOptions: options,
            composeMsg: bytes(""),
            oftCmd: bytes("")
        });
        MessagingFee memory fee = bridge.quoteSend(sendParam, false);

        console.log("LayerZero Fee (native):", fee.nativeFee);
        console.log("LayerZero Fee (lzToken):", fee.lzTokenFee);
        console.log("");

        // Check deployer has enough native token for the fee
        uint256 nativeBalance = _deployer.balance;
        console.log("Deployer Native Balance:", nativeBalance);
        require(nativeBalance >= fee.nativeFee, "Insufficient native token for LayerZero fee");
        console.log("");

        // --- EXECUTE BRIDGE ---
        console.log("=== Executing Bridge ===");

        vm.startBroadcast(_pk);

        // Execute bridge
        console.log("Calling send()...");
        (MessagingReceipt memory receipt, ) = bridge.send{value: fee.nativeFee}(sendParam, fee, _deployer);

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
            console.log("Track the message at: https://testnet.layerzeroscan.com/");
        } else {
            console.log("Bridge verification failed!");
        }
    }
}
