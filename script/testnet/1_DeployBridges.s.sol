// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BaseDeployBridges} from "../base/BaseDeployBridges.s.sol";
import "./utils/Constants.sol";
import "./utils/Roles.sol";

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
contract DeployBridges is BaseDeployBridges {
    function setUp() public {
        _initializeSafeMultiSig();

        _admin = ADMIN;
        _pauser = PAUSER;
        _unpauser = UNPAUSER;
        _mintBurnWrapperSalt = keccak256("RAW_MINT_BURN_WRAPPER_SALT_V3");
        _bridgeSalt = keccak256("RAW_TELCOIN_BRIDGE_SALT_V3");

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
