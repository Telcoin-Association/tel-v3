// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BaseDeployToken} from "../base/BaseDeployToken.s.sol";
import "./utils/Constants.sol";
import "./utils/Roles.sol";

/// @title DeployToken (Mainnet)
/// @notice Deploys TelcoinV3 to mainnet chains via Gnosis Safe.
///
/// ## How to Run
///
/// Simulation:
/// ```
/// forge script script/mainnet/0_DeployToken.s.sol --rpc-url $RPC_URL --ffi -vvvv
/// ```
///
/// Broadcast:
/// ```
/// forge script script/mainnet/0_DeployToken.s.sol --rpc-url $RPC_URL --broadcast --ffi -vvvv
/// ```
contract DeployToken is BaseDeployToken {
    function setUp() public {
        _initializeSafe();

        _admin = ADMIN;
        _pauser = PAUSER;
        _unpauser = UNPAUSER;
        _telcoinV3Salt = keccak256("RAW_TELCOIN_V3_SALT_MAINNET");

        // Ethereum Mainnet
        allChains.push(TokenChainConfig({
            chainName: "ethereum",
            rpcUrl: vm.envString("ETHEREUM_RPC_URL"),
            evmChainId: ETH_MAINNET_CHAIN_ID,
            initialSupply: 0 // TODO: Set mainnet initial supply
        }));

        // Base Mainnet
        allChains.push(TokenChainConfig({
            chainName: "base",
            rpcUrl: vm.envString("BASE_RPC_URL"),
            evmChainId: BASE_MAINNET_CHAIN_ID,
            initialSupply: 0 // TODO: Set mainnet initial supply
        }));

        // Polygon Mainnet
        allChains.push(TokenChainConfig({
            chainName: "polygon",
            rpcUrl: vm.envString("POLYGON_RPC_URL"),
            evmChainId: POLYGON_MAINNET_CHAIN_ID,
            initialSupply: 0 // TODO: Set mainnet initial supply
        }));

        // TelcoinNetwork
        // TODO: Uncomment when TelcoinNetwork details are finalized
        // allChains.push(TokenChainConfig({
        //     chainName: "telcoin-network",
        //     rpcUrl: vm.envString("TELCOIN_NETWORK_RPC_URL"),
        //     evmChainId: TELCOIN_NETWORK_CHAIN_ID,
        //     initialSupply: 0
        // }));
    }
}
