// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BaseConfigureDVNs} from "../base/BaseConfigureDVNs.s.sol";
import "./utils/Constants.sol";

/// @title ConfigureDVNs (Testnet)
/// @notice Testnet DVN and Executor configuration for TelcoinBridge via Gnosis Safe.
///
/// @dev Inherits BaseConfigureDVNs and configures testnet-specific parameters in setUp().
///
/// ## How to Run
///
/// Simulation (no HW wallet needed):
/// ```
/// forge script script/testnet/2_ConfigureDVNs.s.sol --rpc-url $RPC_URL --ffi -vvvv
/// ```
///
/// Broadcast (signs with Ledger, proposes to Safe TX Service):
/// ```
/// forge script script/testnet/2_ConfigureDVNs.s.sol --rpc-url $RPC_URL --broadcast --ffi -vvvv
/// ```
contract ConfigureDVNs is BaseConfigureDVNs {
    function setUp() public {
        _initializeSafe();

        // --- DVN Parameters ---
        _maxMessageSize = 10000;

        // --- Chains ---

        allChains.push(_buildChainConfig(
            "eth-sepolia",
            vm.envString("ETH_SEPOLIA_RPC_URL"),
            ETH_SEPOLIA_CHAIN_ID,
            ETH_SEPOLIA_LZ_CHAIN_ID_V2,
            ETH_SEPOLIA_LZ_ENDPOINT_V2,
            _singleDVN(ETH_SEPOLIA_LZ_DVN),
            new address[](0),
            0,
            ETH_SEPOLIA_LZ_SEND_ULN_302,
            ETH_SEPOLIA_LZ_RECEIVE_ULN_302,
            ETH_SEPOLIA_LZ_EXECUTOR,
            false,
            1,
            100_000 // TODO: Profile actual lzReceive gas
        ));

        allChains.push(_buildChainConfig(
            "base-sepolia",
            vm.envString("BASE_SEPOLIA_RPC_URL"),
            BASE_SEPOLIA_CHAIN_ID,
            BASE_SEPOLIA_LZ_CHAIN_ID_V2,
            BASE_SEPOLIA_LZ_ENDPOINT_V2,
            _singleDVN(BASE_SEPOLIA_LZ_DVN),
            new address[](0),
            0,
            BASE_SEPOLIA_LZ_SEND_ULN_302,
            BASE_SEPOLIA_LZ_RECEIVE_ULN_302,
            BASE_SEPOLIA_LZ_EXECUTOR,
            false,
            1,
            100_000 // TODO: Profile actual lzReceive gas
        ));
    }

    function _singleDVN(address dvn) internal pure returns (address[] memory dvns) {
        dvns = new address[](1);
        dvns[0] = dvn;
    }

    function _buildChainConfig(
        string memory chainName,
        string memory rpcUrl,
        uint256 evmChainId,
        uint32 eid,
        address endpoint,
        address[] memory requiredDVNs,
        address[] memory optionalDVNs,
        uint8 optionalDVNThreshold,
        address sendLib,
        address receiveLib,
        address executor,
        bool mainChain,
        uint64 confirmations,
        uint128 minDstGas
    ) internal pure returns (ChainConfig memory c) {
        c.chainName = chainName;
        c.rpcUrl = rpcUrl;
        c.evmChainId = evmChainId;
        c.eid = eid;
        c.endpoint = endpoint;
        c.requiredDVNs = requiredDVNs;
        c.optionalDVNs = optionalDVNs;
        c.optionalDVNThreshold = optionalDVNThreshold;
        c.sendLib = sendLib;
        c.receiveLib = receiveLib;
        c.executor = executor;
        c.mainChain = mainChain;
        c.confirmations = confirmations;
        c.minDstGas = minDstGas;
    }
}
