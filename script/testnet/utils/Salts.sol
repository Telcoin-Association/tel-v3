// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

// -------------
// CREATE3 Salts
// -------------

// CREATE3 addresses depend only on the salt and the deployer Safe — NOT on the
// contract bytecode. Redeploying updated code therefore requires bumping the
// version suffix of the salt string; reusing a salt resolves to the existing
// deployment and the pipeline will skip it ("already deployed").
//
// Salts are shared by all testnet chains (eth-sepolia, base-sepolia) so each
// contract lands at the same address on both.

bytes32 constant TELCOIN_V3_SALT = keccak256("RAW_TELCOIN_V3_SALT_V4");

bytes32 constant MINT_BURN_WRAPPER_SALT = keccak256("RAW_MINT_BURN_WRAPPER_SALT_V4");
bytes32 constant TELCOIN_BRIDGE_SALT = keccak256("RAW_TELCOIN_BRIDGE_SALT_V4");

bytes32 constant TELCOIN_MIGRATION_SALT = keccak256("RAW_TELCOIN_MIGRATION_SALT_V4");
bytes32 constant MIGRATION_VAULT_IMPL_SALT = keccak256("RAW_MIGRATION_VAULT_IMPL_SALT_V4");
bytes32 constant MIGRATION_VAULT_PROXY_SALT = keccak256("RAW_MIGRATION_VAULT_PROXY_SALT_V4");

bytes32 constant TELCOIN_V3_FAUCET_SALT = keccak256("RAW_TELCOIN_V3_FAUCET_SALT_V2");

// This salt only needs a bump if the legacy Telcoin (TEL v2) contract is redeployed.
bytes32 constant LEGACY_TELCOIN_FAUCET_SALT = keccak256("RAW_LEGACY_TELCOIN_FAUCET_SALT_V1");
