// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

// --------------------
// Authorized Addresses
// --------------------

// Mirrors script/mainnet/utils/Roles.sol so testnet deployments match mainnet
// as closely as possible. ADMIN is the mainnet governance Safe, replayed at the
// same address on the Sepolias (same factory + setup + saltNonce), and MUST
// equal DEPLOYER_SAFE_ADDRESS — the deploy batches execute grantRole calls as
// the deployer Safe, which only works if it holds DEFAULT_ADMIN_ROLE.

address constant ADMIN = 0x6012dBcb4350Ab297FeB7f96D4d86258062aeB03; // Governance Safe (2/8)
address constant PAUSER = 0xC4D09Da0825dBf89A2B755E20b35f39fF455B086; // same pauser EOA as mainnet
address constant UNPAUSER = 0xf0700ccbf77F05CB1bDB6b9EdbEc6B0d33214f07; // same unpauser EOA as mainnet
address constant TREASURY = 0x6012dBcb4350Ab297FeB7f96D4d86258062aeB03; // TODO: mirror mainnet treasury once set
