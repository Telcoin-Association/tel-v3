// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BaseDeployFaucets} from "../base/BaseDeployFaucets.s.sol";
import "./utils/Constants.sol";
import "./utils/Roles.sol";
import "./utils/Salts.sol";

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
/// ## Queueing behind pending Safe txns
///
/// Proposal nonces derive from the on-chain Safe nonce, which only advances on
/// execution. If an earlier step is proposed but not yet executed, broadcasting
/// this step would collide at the same nonce. Set SAFE_NONCE_OFFSET to the
/// number of pending (unexecuted) proposals so this one queues behind them:
/// ```
/// SAFE_NONCE_OFFSET=1 SAFE_BROADCAST=true forge script <this script> --rpc-url $RPC_URL --broadcast --ffi -vvvv
/// ```
contract DeployFaucets is BaseDeployFaucets {
    function setUp() public {
        _initializeSafeMultiSig();

        _admin = ADMIN;

        _dripAmount = 1_000 ether; // 1,000 TEL v3 (18 decimals)
        _legacyDripAmount = 1_000 * 1e2; // 1,000 TEL v2 (2 decimals)
        _cooldown = 1 hours;

        _v3FaucetSalt = TELCOIN_V3_FAUCET_SALT;
        _legacyFaucetSalt = LEGACY_TELCOIN_FAUCET_SALT;

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
