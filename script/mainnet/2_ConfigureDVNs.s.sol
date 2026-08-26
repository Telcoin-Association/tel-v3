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
/// ## Queueing behind pending Safe txns
///
/// Proposal nonces derive from the on-chain Safe nonce, which only advances on
/// execution. If an earlier step is proposed but not yet executed, broadcasting
/// this step would collide at the same nonce. Set SAFE_NONCE_OFFSET to the
/// number of pending (unexecuted) proposals so this one queues behind them:
/// ```
/// SAFE_NONCE_OFFSET=1 SAFE_BROADCAST=true forge script <this script> --rpc-url $RPC_URL --broadcast --ffi -vvvv
/// ```
contract ConfigureDVNs is BaseConfigureDVNs {
    function setUp() public {
        _initializeSafeMultiSig();

        // --- DVN Parameters ---
        _maxMessageSize = 10000;

        // --- Chains ---

        // Ethereum Mainnet
        allChains.push(_buildChainConfig(
            "ethereum",
            vm.envString("ETHEREUM_RPC_URL"),
            ETH_MAINNET_CHAIN_ID,
            ETH_MAINNET_LZ_CHAIN_ID_V2,
            ETH_MAINNET_LZ_ENDPOINT_V2,
            _ethRequiredDVNs(),
            _ethOptionalDVNs(),
            1, // 1-of-2 optional DVNs must sign (Nethermind, FCAT)
            ETH_MAINNET_LZ_SEND_ULN_302,
            ETH_MAINNET_LZ_RECEIVE_ULN_302,
            ETH_MAINNET_LZ_EXECUTOR,
            false,
            15, // matches LZ default for messages sent FROM Ethereum
            100_000 // lzReceive gas on this chain; validated on testnet
        ));

        // Base Mainnet
        allChains.push(_buildChainConfig(
            "base",
            vm.envString("BASE_RPC_URL"),
            BASE_MAINNET_CHAIN_ID,
            BASE_MAINNET_LZ_CHAIN_ID_V2,
            BASE_MAINNET_LZ_ENDPOINT_V2,
            _baseRequiredDVNs(),
            _baseOptionalDVNs(),
            1, // 1-of-2 optional DVNs must sign (Nethermind, FCAT)
            BASE_MAINNET_LZ_SEND_ULN_302,
            BASE_MAINNET_LZ_RECEIVE_ULN_302,
            BASE_MAINNET_LZ_EXECUTOR,
            false,
            10, // matches LZ default for messages sent FROM Base
            100_000 // lzReceive gas on this chain; validated on testnet
        ));

        // Polygon Mainnet
        allChains.push(_buildChainConfig(
            "polygon",
            vm.envString("POLYGON_RPC_URL"),
            POLYGON_MAINNET_CHAIN_ID,
            POLYGON_MAINNET_LZ_CHAIN_ID_V2,
            POLYGON_MAINNET_LZ_ENDPOINT_V2,
            _polygonRequiredDVNs(),
            _polygonOptionalDVNs(),
            1, // 1-of-2 optional DVNs must sign (Nethermind, FCAT)
            POLYGON_MAINNET_LZ_SEND_ULN_302,
            POLYGON_MAINNET_LZ_RECEIVE_ULN_302,
            POLYGON_MAINNET_LZ_EXECUTOR,
            false,
            120, // matches LZ default for messages sent FROM Polygon (PoS reorg depth)
            100_000 // lzReceive gas on this chain; validated on testnet
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

    // ----------------------
    // DVN Arrays (per chain)
    // ----------------------

    // Mesh (decided 2026-08-26, see docs/custom-dvn-mesh.md):
    //   Required: LayerZero Labs, Canary, Deutsche Telekom (all must sign)
    //   Optional: Nethermind, FCAT (1-of-2 must sign) — 4 of 5 total must agree
    // Addresses live in utils/Constants.sol (verified vs LZ metadata API).
    // ULN302 requires each array sorted ascending by address with no
    // duplicates (reverts LZ_ULN_Unsorted otherwise), so provider order
    // differs per chain below.

    function _ethRequiredDVNs() internal pure returns (address[] memory dvns) {
        dvns = new address[](3);
        dvns[0] = ETH_MAINNET_DVN_DEUTSCHE_TELEKOM;
        dvns[1] = ETH_MAINNET_DVN_LAYERZERO_LABS;
        dvns[2] = ETH_MAINNET_DVN_CANARY;
    }

    function _ethOptionalDVNs() internal pure returns (address[] memory dvns) {
        dvns = new address[](2);
        dvns[0] = ETH_MAINNET_DVN_NETHERMIND;
        dvns[1] = ETH_MAINNET_DVN_FCAT;
    }

    function _baseRequiredDVNs() internal pure returns (address[] memory dvns) {
        dvns = new address[](3);
        dvns[0] = BASE_MAINNET_DVN_CANARY;
        dvns[1] = BASE_MAINNET_DVN_LAYERZERO_LABS;
        dvns[2] = BASE_MAINNET_DVN_DEUTSCHE_TELEKOM;
    }

    function _baseOptionalDVNs() internal pure returns (address[] memory dvns) {
        dvns = new address[](2);
        dvns[0] = BASE_MAINNET_DVN_NETHERMIND;
        dvns[1] = BASE_MAINNET_DVN_FCAT;
    }

    function _polygonRequiredDVNs() internal pure returns (address[] memory dvns) {
        dvns = new address[](3);
        dvns[0] = POLYGON_MAINNET_DVN_CANARY;
        dvns[1] = POLYGON_MAINNET_DVN_LAYERZERO_LABS;
        dvns[2] = POLYGON_MAINNET_DVN_DEUTSCHE_TELEKOM;
    }

    function _polygonOptionalDVNs() internal pure returns (address[] memory dvns) {
        dvns = new address[](2);
        dvns[0] = POLYGON_MAINNET_DVN_FCAT;
        dvns[1] = POLYGON_MAINNET_DVN_NETHERMIND;
    }

    // -------
    // Helpers
    // -------

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
