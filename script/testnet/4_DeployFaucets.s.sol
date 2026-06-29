// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BaseDeployFaucets} from "../base/BaseDeployFaucets.s.sol";
import "./utils/Constants.sol";
import "./utils/Roles.sol";

/// @title DeployFaucets (Testnet)
/// @notice Deploys TelcoinV3Faucet + LegacyTelcoinFaucet to testnet chains via Gnosis Safe.
///
/// ## How to Run
///
/// Simulation:
/// ```
/// forge script script/testnet/4_DeployFaucets.s.sol --rpc-url $RPC_URL --ffi -vvvv
/// ```
///
/// Broadcast:
/// ```
/// forge script script/testnet/4_DeployFaucets.s.sol --rpc-url $RPC_URL --broadcast --ffi -vvvv
/// ```
contract DeployFaucets is BaseDeployFaucets {
    function setUp() public {
        _initializeSafeMultiSig();

        _admin = ADMIN;

        _dripAmount = 1_000 ether; // 1,000 TEL v3 (18 decimals)
        _legacyDripAmount = 1_000 * 1e2; // 1,000 TEL v2 (2 decimals)
        _cooldown = 1 hours;

        _v3FaucetSalt = keccak256("RAW_TELCOIN_V3_FAUCET_SALT_V1");
        _legacyFaucetSalt = keccak256("RAW_LEGACY_TELCOIN_FAUCET_SALT_V1");

        allChains.push(FaucetChainConfig({
            chainName: "eth-sepolia",
            rpcUrl: vm.envString("ETH_SEPOLIA_RPC_URL"),
            evmChainId: ETH_SEPOLIA_CHAIN_ID
        }));

        allChains.push(FaucetChainConfig({
            chainName: "base-sepolia",
            rpcUrl: vm.envString("BASE_SEPOLIA_RPC_URL"),
            evmChainId: BASE_SEPOLIA_CHAIN_ID
        }));
    }
}
