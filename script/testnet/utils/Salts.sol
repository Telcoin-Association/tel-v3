// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

// Production salts (token, bridges, migration) are shared with the mainnet
// pipeline so testnet and mainnet contracts land at identical addresses —
// see script/utils/Salts.sol.
import "../../utils/Salts.sol";

// ------------------
// Testnet-only Salts
// ------------------

// Faucets and the legacy TEL mock have no mainnet counterpart.

bytes32 constant TELCOIN_V3_FAUCET_SALT = keccak256("RAW_TELCOIN_V3_FAUCET_SALT_V2");

// This salt only needs a bump if the legacy Telcoin (TEL v2) contract is redeployed.
bytes32 constant LEGACY_TELCOIN_FAUCET_SALT = keccak256("RAW_LEGACY_TELCOIN_FAUCET_SALT_V1");
