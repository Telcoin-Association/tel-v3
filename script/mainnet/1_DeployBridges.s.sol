// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BaseDeployBridges} from "../base/BaseDeployBridges.s.sol";
import "./utils/Constants.sol";
import "./utils/Roles.sol";

/// @title DeployBridges (Mainnet)
/// @notice Deploys bridge infrastructure to mainnet chains via Gnosis Safe.
///
/// ## How to Run
///
/// Simulation:
/// ```
/// forge script script/mainnet/1_DeployBridges.s.sol --rpc-url $RPC_URL --ffi -vvvv
/// ```
///
/// Broadcast:
/// ```
/// forge script script/mainnet/1_DeployBridges.s.sol --rpc-url $RPC_URL --broadcast --ffi -vvvv
/// ```
contract DeployBridges is BaseDeployBridges {
    function setUp() public {
        _initializeSafe();

        _admin = ADMIN;
        _pauser = PAUSER;
        _unpauser = UNPAUSER;
        _mintBurnWrapperSalt = keccak256("RAW_MINT_BURN_WRAPPER_SALT_MAINNET");
        _bridgeSalt = keccak256("RAW_TELCOIN_BRIDGE_SALT_MAINNET");
        _nativeBridgeSalt = keccak256("RAW_NATIVE_BRIDGE_SALT_MAINNET");

        // Ethereum Mainnet (satellite)
        allChains.push(BridgeChainConfig({
            chainName: "ethereum",
            rpcUrl: vm.envString("ETHEREUM_RPC_URL"),
            lzEndpoint: ETH_MAINNET_LZ_ENDPOINT_V2,
            lzChainId: ETH_MAINNET_LZ_CHAIN_ID_V2,
            evmChainId: ETH_MAINNET_CHAIN_ID,
            mainChain: false
        }));

        // Base Mainnet (satellite)
        allChains.push(BridgeChainConfig({
            chainName: "base",
            rpcUrl: vm.envString("BASE_RPC_URL"),
            lzEndpoint: BASE_MAINNET_LZ_ENDPOINT_V2,
            lzChainId: BASE_MAINNET_LZ_CHAIN_ID_V2,
            evmChainId: BASE_MAINNET_CHAIN_ID,
            mainChain: false
        }));

        // Polygon Mainnet (satellite)
        allChains.push(BridgeChainConfig({
            chainName: "polygon",
            rpcUrl: vm.envString("POLYGON_RPC_URL"),
            lzEndpoint: POLYGON_MAINNET_LZ_ENDPOINT_V2,
            lzChainId: POLYGON_MAINNET_LZ_CHAIN_ID_V2,
            evmChainId: POLYGON_MAINNET_CHAIN_ID,
            mainChain: false
        }));

        // TelcoinNetwork (main chain — NativeBridge)
        // TODO: Uncomment when TelcoinNetwork details are finalized
        // allChains.push(BridgeChainConfig({
        //     chainName: "telcoin-network",
        //     rpcUrl: vm.envString("TELCOIN_NETWORK_RPC_URL"),
        //     lzEndpoint: TELCOIN_NETWORK_LZ_ENDPOINT_V2,
        //     lzChainId: TELCOIN_NETWORK_LZ_CHAIN_ID_V2,
        //     evmChainId: TELCOIN_NETWORK_CHAIN_ID,
        //     mainChain: true
        // }));
    }
}
