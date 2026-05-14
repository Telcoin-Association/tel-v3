// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BaseConfigureDVNs} from "../base/BaseConfigureDVNs.s.sol";
import "./utils/Constants.sol";

/**
 * @title ConfigureDVNs (Testnet)
 * @author chasebrownn
 * @notice Testnet DVN and Executor configuration for TelcoinBridge across all supported chains.
 *
 * @dev Inherits BaseConfigureDVNs and configures testnet-specific parameters in setUp().
 *      For testnets, LayerZero Labs DVN is typically the only available DVN.
 *
 * ## How to Run
 *
 * Dry run (simulation):
 * ```
 * forge script script/testnet/1_ConfigureDVNs.s.sol --multi
 * ```
 *
 * Live execution:
 * ```
 * forge script script/testnet/1_ConfigureDVNs.s.sol --multi --broadcast -vvvv
 * ```
 */
contract ConfigureDVNs is BaseConfigureDVNs {
    function setUp() public {
        _setup();

        // --- DVN Parameters ---
        _confirmations = 1;
        _maxMessageSize = 10000;

        // --- Chains ---

        allChains.push(_buildChainConfig(
            "eth-sepolia",
            vm.envString("ETH_SEPOLIA_RPC_URL"),
            ETH_SEPOLIA_LZ_CHAIN_ID_V2,
            ETH_SEPOLIA_LZ_ENDPOINT_V2,
            _singleDVN(ETH_SEPOLIA_LZ_DVN),
            new address[](0),
            0,
            ETH_SEPOLIA_LZ_SEND_ULN_302,
            ETH_SEPOLIA_LZ_RECEIVE_ULN_302,
            ETH_SEPOLIA_LZ_EXECUTOR,
            false
        ));

        allChains.push(_buildChainConfig(
            "base-sepolia",
            vm.envString("BASE_SEPOLIA_RPC_URL"),
            BASE_SEPOLIA_LZ_CHAIN_ID_V2,
            BASE_SEPOLIA_LZ_ENDPOINT_V2,
            _singleDVN(BASE_SEPOLIA_LZ_DVN),
            new address[](0),
            0,
            BASE_SEPOLIA_LZ_SEND_ULN_302,
            BASE_SEPOLIA_LZ_RECEIVE_ULN_302,
            BASE_SEPOLIA_LZ_EXECUTOR,
            false
        ));
    }

    /// @dev Helper to create a single-element DVN array
    function _singleDVN(address dvn) internal pure returns (address[] memory dvns) {
        dvns = new address[](1);
        dvns[0] = dvn;
    }

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
