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
// Salts are shared by all mainnet chains (ethereum, base, polygon) so each
// contract lands at the same address on every chain.

// Mined vanity salt (raw bytes32, NOT a hashed string) — low 11 bytes are the
// mined suffix. Valid only when deployed from Safe 0x6012dBcb4350Ab297FeB7f96D4d86258062aeB03;
// yields 0x7e13B43065380acDEC1c2D138c579cbbbAfA0731 on every chain.
bytes32 constant TELCOIN_V3_SALT = 0x000000000000000000000000000000000000000000398d56afaa84959f9780a7;

bytes32 constant MINT_BURN_WRAPPER_SALT = keccak256("RAW_MINT_BURN_WRAPPER_SALT_MAINNET_V0");
bytes32 constant TELCOIN_BRIDGE_SALT = keccak256("RAW_TELCOIN_BRIDGE_SALT_MAINNET_V0");
bytes32 constant NATIVE_BRIDGE_SALT = keccak256("RAW_NATIVE_BRIDGE_SALT_MAINNET_V0");

bytes32 constant TELCOIN_MIGRATION_SALT = keccak256("RAW_TELCOIN_MIGRATION_SALT_MAINNET_V0");
bytes32 constant MIGRATION_VAULT_IMPL_SALT = keccak256("RAW_MIGRATION_VAULT_IMPL_SALT_MAINNET_V0");
bytes32 constant MIGRATION_VAULT_PROXY_SALT = keccak256("RAW_MIGRATION_VAULT_PROXY_SALT_MAINNET_V0");
