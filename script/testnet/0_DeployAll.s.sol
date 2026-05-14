// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BaseDeployAll} from "../base/BaseDeployAll.s.sol";
import "./utils/Constants.sol";

/**
 * @title DeployAll (Testnet)
 * @author chasebrownn
 * @notice Testnet multi-chain deployment of all Telcoin V3 contracts.
 *
 * @dev Inherits BaseDeployAll and configures testnet-specific parameters in setUp().
 *      Currently targets Ethereum Sepolia and Base Sepolia.
 *
 *      NOTE: NativeBridge is not deployed on testnet — no TelcoinNetwork testnet exists.
 *
 * ## How to Run
 *
 * Dry run (simulation):
 * ```
 * forge script script/testnet/0_DeployAll.s.sol --multi
 * ```
 *
 * Live deployment:
 * ```
 * forge script script/testnet/0_DeployAll.s.sol --multi --broadcast --verify -vvvv
 * ```
 */
contract DeployAll is BaseDeployAll {
    function setUp() public {
        _setup();

        // --- Admin ---
        _admin = 0x28937C70A08390c55b65Eab24600c4b059A50991;

        // --- CREATE3 Salts ---
        _telcoinV3Salt = keccak256("RAW_TELCOIN_V3_SALT_V2");
        _migrationSalt = keccak256("RAW_TELCOIN_MIGRATION_SALT_V2");
        _migrationVaultImplSalt = keccak256("RAW_MIGRATION_VAULT_IMPL_SALT_V2");
        _migrationVaultProxySalt = keccak256("RAW_MIGRATION_VAULT_PROXY_SALT_V2");
        _mintBurnWrapperSalt = keccak256("RAW_MINT_BURN_WRAPPER_SALT_V2");
        _bridgeSalt = keccak256("RAW_TELCOIN_BRIDGE_SALT_V2");

        // --- Durations ---
        _migrationDuration = 365 days;
        _withdrawalDelay = 90 days;

        // --- Chains ---

        allChains.push(NetworkData({
            chainName: "eth-sepolia",
            rpcUrl: vm.envString("ETH_SEPOLIA_RPC_URL"),
            lzEndpoint: ETH_SEPOLIA_LZ_ENDPOINT_V2,
            lzChainId: ETH_SEPOLIA_LZ_CHAIN_ID_V2,
            evmChainId: ETH_SEPOLIA_CHAIN_ID,
            legacyTel: _loadDeploymentAddress("eth-sepolia", "TelcoinLegacy"),
            initialSupply: 100_000_000 ether,
            mainChain: false
        }));

        allChains.push(NetworkData({
            chainName: "base-sepolia",
            rpcUrl: vm.envString("BASE_SEPOLIA_RPC_URL"),
            lzEndpoint: BASE_SEPOLIA_LZ_ENDPOINT_V2,
            lzChainId: BASE_SEPOLIA_LZ_CHAIN_ID_V2,
            evmChainId: BASE_SEPOLIA_CHAIN_ID,
            legacyTel: _loadDeploymentAddress("base-sepolia", "TelcoinLegacy"),
            initialSupply: 100_000_000 ether,
            mainChain: false
        }));
    }
}
