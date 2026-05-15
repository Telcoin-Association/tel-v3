// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BaseConfigureDVNs} from "../base/BaseConfigureDVNs.s.sol";
import "./utils/Constants.sol";

/// @title ConfigureDVNs (Mainnet)
/// @notice Mainnet DVN and Executor configuration for TelcoinBridge / NativeBridge via Gnosis Safe.
///
/// @dev Inherits BaseConfigureDVNs and configures mainnet-specific parameters in setUp().
///
/// ## How to Run
///
/// Simulation (no HW wallet needed):
/// ```
/// forge script script/mainnet/2_ConfigureDVNs.s.sol --rpc-url $RPC_URL --ffi -vvvv
/// ```
///
/// Broadcast (signs with Ledger, proposes to Safe TX Service):
/// ```
/// forge script script/mainnet/2_ConfigureDVNs.s.sol --rpc-url $RPC_URL --broadcast --ffi -vvvv
/// ```
contract ConfigureDVNs is BaseConfigureDVNs {
    function setUp() public {
        _initializeSafe();

        // --- DVN Parameters ---
        _confirmations = 15; // TODO: Finalize mainnet confirmations
        _maxMessageSize = 10000;

        // --- Chains ---

        // Ethereum Mainnet
        allChains.push(_buildChainConfig(
            "ethereum",
            vm.envString("ETHEREUM_RPC_URL"),
            ETH_MAINNET_LZ_CHAIN_ID_V2,
            ETH_MAINNET_LZ_ENDPOINT_V2,
            _ethRequiredDVNs(),
            _ethOptionalDVNs(),
            0, // TODO: Set optional DVN threshold
            ETH_MAINNET_LZ_SEND_ULN_302,
            ETH_MAINNET_LZ_RECEIVE_ULN_302,
            ETH_MAINNET_LZ_EXECUTOR,
            false
        ));

        // Base Mainnet
        allChains.push(_buildChainConfig(
            "base",
            vm.envString("BASE_RPC_URL"),
            BASE_MAINNET_LZ_CHAIN_ID_V2,
            BASE_MAINNET_LZ_ENDPOINT_V2,
            _baseRequiredDVNs(),
            _baseOptionalDVNs(),
            0, // TODO: Set optional DVN threshold
            BASE_MAINNET_LZ_SEND_ULN_302,
            BASE_MAINNET_LZ_RECEIVE_ULN_302,
            BASE_MAINNET_LZ_EXECUTOR,
            false
        ));

        // Polygon Mainnet
        allChains.push(_buildChainConfig(
            "polygon",
            vm.envString("POLYGON_RPC_URL"),
            POLYGON_MAINNET_LZ_CHAIN_ID_V2,
            POLYGON_MAINNET_LZ_ENDPOINT_V2,
            _polygonRequiredDVNs(),
            _polygonOptionalDVNs(),
            0, // TODO: Set optional DVN threshold
            POLYGON_MAINNET_LZ_SEND_ULN_302,
            POLYGON_MAINNET_LZ_RECEIVE_ULN_302,
            POLYGON_MAINNET_LZ_EXECUTOR,
            false
        ));

        // TelcoinNetwork (main chain — NativeBridge)
        // TODO: Uncomment when TelcoinNetwork details are finalized
        // allChains.push(_buildChainConfig(
        //     "telcoin-network",
        //     vm.envString("TELCOIN_NETWORK_RPC_URL"),
        //     TELCOIN_NETWORK_LZ_CHAIN_ID_V2,
        //     TELCOIN_NETWORK_LZ_ENDPOINT_V2,
        //     _telcoinNetworkRequiredDVNs(),
        //     _telcoinNetworkOptionalDVNs(),
        //     0,
        //     TELCOIN_NETWORK_LZ_SEND_ULN_302,
        //     TELCOIN_NETWORK_LZ_RECEIVE_ULN_302,
        //     TELCOIN_NETWORK_LZ_EXECUTOR,
        //     true
        // ));
    }

    // ---------------------------
    // DVN Arrays (per chain)
    // ---------------------------

    function _ethRequiredDVNs() internal pure returns (address[] memory dvns) {
        dvns = new address[](1);
        dvns[0] = address(0); // TODO: e.g. LayerZero Labs DVN on Ethereum
    }

    function _ethOptionalDVNs() internal pure returns (address[] memory) {
        return new address[](0); // TODO: e.g. [Google Cloud, Polyhedra, Nethermind]
    }

    function _baseRequiredDVNs() internal pure returns (address[] memory dvns) {
        dvns = new address[](1);
        dvns[0] = address(0); // TODO: e.g. LayerZero Labs DVN on Base
    }

    function _baseOptionalDVNs() internal pure returns (address[] memory) {
        return new address[](0); // TODO
    }

    function _polygonRequiredDVNs() internal pure returns (address[] memory dvns) {
        dvns = new address[](1);
        dvns[0] = address(0); // TODO: e.g. LayerZero Labs DVN on Polygon
    }

    function _polygonOptionalDVNs() internal pure returns (address[] memory) {
        return new address[](0); // TODO
    }

    // ---------------------------
    // Helpers
    // ---------------------------

    function _buildChainConfig(
        string memory chainName,
        string memory rpcUrl,
        uint32 eid,
        address endpoint,
        address[] memory requiredDVNs,
        address[] memory optionalDVNs,
        uint8 optionalDVNThreshold,
        address sendLib,
        address receiveLib,
        address executor,
        bool mainChain
    ) internal pure returns (ChainConfig memory) {
        return ChainConfig({
            chainName: chainName,
            rpcUrl: rpcUrl,
            eid: eid,
            endpoint: endpoint,
            requiredDVNs: requiredDVNs,
            optionalDVNs: optionalDVNs,
            optionalDVNThreshold: optionalDVNThreshold,
            sendLib: sendLib,
            receiveLib: receiveLib,
            executor: executor,
            mainChain: mainChain
        });
    }
}
