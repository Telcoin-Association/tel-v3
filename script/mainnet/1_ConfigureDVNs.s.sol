// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BaseConfigureDVNs} from "../base/BaseConfigureDVNs.s.sol";
import "./utils/Constants.sol";

/**
 * @title ConfigureDVNs (Mainnet)
 * @author chasebrownn
 * @notice Mainnet DVN and Executor configuration for TelcoinBridge / NativeBridge.
 *
 * @dev Inherits BaseConfigureDVNs and configures mainnet-specific parameters in setUp().
 *      Mainnet uses multiple required DVNs and an optional DVN quorum for additional security.
 *
 * ## How to Run
 *
 * Dry run (simulation):
 * ```
 * forge script script/mainnet/1_ConfigureDVNs.s.sol --multi
 * ```
 *
 * Live execution:
 * ```
 * forge script script/mainnet/1_ConfigureDVNs.s.sol --multi --broadcast -vvvv
 * ```
 */
contract ConfigureDVNs is BaseConfigureDVNs {
    function setUp() public {
        _setup();

        // --- DVN Parameters ---
        _confirmations = 15; // TODO: Finalize mainnet confirmations
        _maxMessageSize = 10000;

        // --- DVN Providers (TODO: Set addresses per chain) ---
        // Required: must ALL verify (e.g. LayerZero Labs + Google Cloud)
        // Optional: quorum of N-of-M must verify (e.g. 2-of-3: Polyhedra, Nethermind, Horizen)

        // --- Chains ---

        // Ethereum Mainnet
        allChains.push(_buildChainConfig(
            "ethereum",
            vm.envString("ETHEREUM_RPC_URL"),
            ETH_MAINNET_LZ_CHAIN_ID_V2,
            ETH_MAINNET_LZ_ENDPOINT_V2,
            _ethRequiredDVNs(),
            _ethOptionalDVNs(),
            0, // TODO: Set optional DVN threshold (e.g. 2)
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

    // TODO: Populate with actual mainnet DVN addresses per chain.
    //       Each chain may have different DVN provider addresses.

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

    /// @dev Helper to construct ChainConfig (workaround for structs with dynamic arrays)
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
