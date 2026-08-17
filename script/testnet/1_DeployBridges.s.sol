// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BaseDeployBridges} from "../base/BaseDeployBridges.s.sol";
import "./utils/Constants.sol";
import "./utils/Roles.sol";
import "./utils/Salts.sol";

/// @title DeployBridges (Testnet)
/// @notice Deploys bridge infrastructure to testnet chains via Gnosis Safe.
///
/// ## How to Run
///
/// Simulation:
/// ```
/// forge script script/testnet/1_DeployBridges.s.sol --rpc-url $RPC_URL --ffi -vvvv
/// ```
///
/// Broadcast:
/// ```
/// forge script script/testnet/1_DeployBridges.s.sol --rpc-url $RPC_URL --broadcast --ffi -vvvv
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
contract DeployBridges is BaseDeployBridges {
    function setUp() public {
        _initializeSafeMultiSig();

        _admin = ADMIN;
        _pauser = PAUSER;
        _unpauser = UNPAUSER;
        _mintBurnWrapperSalt = MINT_BURN_WRAPPER_SALT;
        _bridgeSalt = TELCOIN_BRIDGE_SALT;

        allChains.push(BridgeChainConfig({
            chainName: "eth-sepolia",
            rpcUrl: vm.envString("ETH_SEPOLIA_RPC_URL"),
            lzEndpoint: ETH_SEPOLIA_LZ_ENDPOINT_V2,
            lzChainId: ETH_SEPOLIA_LZ_CHAIN_ID_V2,
            evmChainId: ETH_SEPOLIA_CHAIN_ID,
            mainChain: false
        }));

        allChains.push(BridgeChainConfig({
            chainName: "base-sepolia",
            rpcUrl: vm.envString("BASE_SEPOLIA_RPC_URL"),
            lzEndpoint: BASE_SEPOLIA_LZ_ENDPOINT_V2,
            lzChainId: BASE_SEPOLIA_LZ_CHAIN_ID_V2,
            evmChainId: BASE_SEPOLIA_CHAIN_ID,
            mainChain: false
        }));
    }
}
