// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BaseDeployToken} from "../base/BaseDeployToken.s.sol";
import "./utils/Constants.sol";
import "./utils/Roles.sol";

/// @title DeployToken (Testnet)
/// @notice Deploys TelcoinV3 to testnet chains via Gnosis Safe.
///
/// ## How to Run
///
/// Simulation:
/// ```
/// forge script script/testnet/0_DeployToken.s.sol --rpc-url $RPC_URL --ffi -vvvv
/// ```
///
/// Broadcast:
/// ```
/// forge script script/testnet/0_DeployToken.s.sol --rpc-url $RPC_URL --broadcast --ffi -vvvv
/// ```
contract DeployToken is BaseDeployToken {
    function setUp() public {
        _initializeSafe();

        _admin = ADMIN;
        _pauser = PAUSER;
        _unpauser = UNPAUSER;
        _telcoinV3Salt = keccak256("RAW_TELCOIN_V3_SALT_V2");

        allChains.push(TokenChainConfig({
            chainName: "eth-sepolia",
            rpcUrl: vm.envString("ETH_SEPOLIA_RPC_URL"),
            evmChainId: ETH_SEPOLIA_CHAIN_ID,
            initialSupply: 100_000_000 ether
        }));

        allChains.push(TokenChainConfig({
            chainName: "base-sepolia",
            rpcUrl: vm.envString("BASE_SEPOLIA_RPC_URL"),
            evmChainId: BASE_SEPOLIA_CHAIN_ID,
            initialSupply: 100_000_000 ether
        }));
    }
}
