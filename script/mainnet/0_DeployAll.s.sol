// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BaseDeployAll} from "../base/BaseDeployAll.s.sol";
import "./utils/Constants.sol";

/**
 * @title DeployAll (Mainnet)
 * @author chasebrownn
 * @notice Mainnet multi-chain deployment of all Telcoin V3 contracts.
 *
 * @dev Inherits BaseDeployAll and configures mainnet-specific parameters in setUp().
 *      Targets Ethereum Mainnet (+ satellite chains) and TelcoinNetwork (NativeBridge).
 *
 *      Legacy TEL v2 address is loaded from deployments/ JSON — ensure it is populated
 *      before running this script (otherwise the script will attempt a mock deploy).
 *
 * ## How to Run
 *
 * Dry run (simulation):
 * ```
 * forge script script/mainnet/0_DeployAll.s.sol --multi
 * ```
 *
 * Live deployment:
 * ```
 * forge script script/mainnet/0_DeployAll.s.sol --multi --broadcast --verify -vvvv
 * ```
 */
contract DeployAll is BaseDeployAll {
    function setUp() public {
        _setup();

        // --- Admin ---
        _admin = address(0); // TODO: Set mainnet admin (multisig)

        // --- CREATE3 Salts ---
        _telcoinV3Salt = keccak256("RAW_TELCOIN_V3_SALT_MAINNET");
        _migrationSalt = keccak256("RAW_TELCOIN_MIGRATION_SALT_MAINNET");
        _migrationVaultImplSalt = keccak256("RAW_MIGRATION_VAULT_IMPL_SALT_MAINNET");
        _migrationVaultProxySalt = keccak256("RAW_MIGRATION_VAULT_PROXY_SALT_MAINNET");
        _mintBurnWrapperSalt = keccak256("RAW_MINT_BURN_WRAPPER_SALT_MAINNET");
        _bridgeSalt = keccak256("RAW_TELCOIN_BRIDGE_SALT_MAINNET");
        _nativeBridgeSalt = keccak256("RAW_NATIVE_BRIDGE_SALT_MAINNET");

        // --- Durations ---
        _migrationDuration = 365 days;
        _withdrawalDelay = 90 days;

        // --- Chains ---

        // Ethereum Mainnet (satellite)
        allChains.push(NetworkData({
            chainName: "ethereum",
            rpcUrl: vm.envString("ETHEREUM_RPC_URL"),
            lzEndpoint: ETH_MAINNET_LZ_ENDPOINT_V2,
            lzChainId: ETH_MAINNET_LZ_CHAIN_ID_V2,
            evmChainId: ETH_MAINNET_CHAIN_ID,
            legacyTel: _loadDeploymentAddress("ethereum", "TelcoinLegacy"),
            initialSupply: 0, // TODO: Set mainnet initial supply
            mainChain: false
        }));

        // Base Mainnet (satellite)
        allChains.push(NetworkData({
            chainName: "base",
            rpcUrl: vm.envString("BASE_RPC_URL"),
            lzEndpoint: BASE_MAINNET_LZ_ENDPOINT_V2,
            lzChainId: BASE_MAINNET_LZ_CHAIN_ID_V2,
            evmChainId: BASE_MAINNET_CHAIN_ID,
            legacyTel: _loadDeploymentAddress("base", "TelcoinLegacy"),
            initialSupply: 0, // TODO: Set mainnet initial supply
            mainChain: false
        }));

        // Polygon Mainnet (satellite)
        allChains.push(NetworkData({
            chainName: "polygon",
            rpcUrl: vm.envString("POLYGON_RPC_URL"),
            lzEndpoint: POLYGON_MAINNET_LZ_ENDPOINT_V2,
            lzChainId: POLYGON_MAINNET_LZ_CHAIN_ID_V2,
            evmChainId: POLYGON_MAINNET_CHAIN_ID,
            legacyTel: _loadDeploymentAddress("polygon", "TelcoinLegacy"),
            initialSupply: 0, // TODO: Set mainnet initial supply
            mainChain: false
        }));

        // TelcoinNetwork (main chain — NativeBridge)
        // TODO: Uncomment when TelcoinNetwork details are finalized
        // allChains.push(NetworkData({
        //     chainName: "telcoin-network",
        //     rpcUrl: vm.envString("TELCOIN_NETWORK_RPC_URL"),
        //     lzEndpoint: TELCOIN_NETWORK_LZ_ENDPOINT_V2,
        //     lzChainId: TELCOIN_NETWORK_LZ_CHAIN_ID_V2,
        //     evmChainId: TELCOIN_NETWORK_CHAIN_ID,
        //     legacyTel: address(0),
        //     initialSupply: 0,
        //     mainChain: true
        // }));
    }
}
