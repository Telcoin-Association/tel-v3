// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

// --------------------
// Shared CREATE3 Salts
// --------------------

// CREATE3 addresses depend only on the salt and the deployer Safe — NOT on the
// contract bytecode, constructor args, or chain. These salts are shared by the
// mainnet AND testnet pipelines: both deploy from the governance Safe
// 0x6012dBcb4350Ab297FeB7f96D4d86258062aeB03 (replayed at the same address on
// the Sepolias), so every contract below lands at the SAME address on every
// chain, testnet and mainnet alike.
//
// Redeploying updated code requires bumping a salt (version suffix for hashed
// salts, freshly mined suffix for vanity salts — see script/utils/vanity/).
// A bump desyncs testnet from mainnet until the other side is redeployed with
// the same salt. NEVER bump TELCOIN_V3_SALT: TelcoinV3 is live on mainnet.

// Mined vanity salts (raw bytes32, NOT hashed strings) — low 11 bytes are the
// mined suffix. Valid only when deployed from Safe 0x6012…eB03; CreateX's
// sender guard means nobody else can squat these addresses.

// yields 0x7E13B43065380acDEC1c2D138c579cbbbAfA0731 (live on mainnet)
bytes32 constant TELCOIN_V3_SALT = 0x000000000000000000000000000000000000000000398d56afaa84959f9780a7;

// yields 0x2703E00cAE30A7707e4d18C38f8CB6A4a40c2703
bytes32 constant TELCOIN_MIGRATION_SALT = 0x000000000000000000000000000000000000000000b841cfb0ae7cbd5e6bb4a2;

// yields 0x222213DeB441C5A9F71Df2942db431978a733333
bytes32 constant MIGRATION_VAULT_PROXY_SALT = 0x0000000000000000000000000000000000000000001ecfbcbfe933c31761b8f5;

// Both bridges share ONE salt and therefore ONE address:
// 0x6A7E6616653e84eee0c70257eC2E3d79A4476a7e ("GATE…GATE") on every chain.
// This is safe only because the two contracts are mutually exclusive per
// chain — TelcoinBridge on satellite chains, NativeBridge on Telcoin Network
// (where TEL is the native gas token). CREATE3 can deploy exactly one
// contract per chain at this address, so they must NEVER both be needed on
// the same chain.
bytes32 constant TELCOIN_BRIDGE_SALT = 0x00000000000000000000000000000000000000000036a95bc1eef19819b6054c;
bytes32 constant NATIVE_BRIDGE_SALT = 0x00000000000000000000000000000000000000000036a95bc1eef19819b6054c;

// Hashed-string salts — matching testnet/mainnet addresses, no vanity.

bytes32 constant MIGRATION_VAULT_IMPL_SALT = keccak256("RAW_MIGRATION_VAULT_IMPL_SALT_MAINNET_V0");
bytes32 constant MINT_BURN_WRAPPER_SALT = keccak256("RAW_MINT_BURN_WRAPPER_SALT_MAINNET_V0");
