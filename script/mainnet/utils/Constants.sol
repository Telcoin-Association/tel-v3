// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

// ----------
// Legacy TEL
// ----------

// All three are 2-decimal tokens (verified on-chain 2026-08-26) — required by
// TokenMigration's hardcoded 2→18 DECIMAL_MULTIPLIER. Ethereum is canonical;
// Polygon is the PoS-bridged representation; Base is the official deployment
// announced by the Telcoin Association (2025-02-25).
address constant LEGACY_TELCOIN_ETHEREUM = 0x467Bccd9d29f223BcE8043b84E8C8B282827790F;
address constant LEGACY_TELCOIN_POLYGON = 0xdF7837DE1F2Fa4631D716CF2502f8b230F1dcc32;
address constant LEGACY_TELCOIN_BASE = 0x09bE1692ca16e06f536F0038fF11D1dA8524aDB1;

// -------------
// EVM Chain IDs
// -------------

uint256 constant ETH_MAINNET_CHAIN_ID = 1;
uint256 constant BASE_MAINNET_CHAIN_ID = 8453;
uint256 constant POLYGON_MAINNET_CHAIN_ID = 137;
// uint256 constant TELCOIN_NETWORK_CHAIN_ID = TODO;

// -------------
// Layer Zero V2
// -------------

// All addresses verified against the LayerZero metadata API on 2026-08-26:
//   https://metadata.layerzero-api.com/v1/metadata/deployments (endpoint/ULN/executor)
//   https://metadata.layerzero-api.com/v1/metadata/dvns        (DVNs)
// DVN constants are the STANDARD messaging DVNs — each provider also runs a
// separate lzRead-compatible DVN at a different address; those must NOT be
// used here (docs/custom-dvn-mesh.md's 2026-05-30 table mixed some in).
// Which providers go in the required vs optional buckets is configured in
// 2_ConfigureDVNs.s.sol; this file is only the address registry.

// Ethereum Mainnet

address constant ETH_MAINNET_LZ_ENDPOINT_V2 = 0x1a44076050125825900e736c501f859c50fE728c;
uint32 constant ETH_MAINNET_LZ_CHAIN_ID_V2 = 30101;

address constant ETH_MAINNET_LZ_EXECUTOR = 0x173272739Bd7Aa6e4e214714048a9fE699453059;
address constant ETH_MAINNET_LZ_SEND_ULN_302 = 0xbB2Ea70C9E858123480642Cf96acbcCE1372dCe1;
address constant ETH_MAINNET_LZ_RECEIVE_ULN_302 = 0xc02Ab410f0734EFa3F14628780e6e695156024C2;

address constant ETH_MAINNET_DVN_LAYERZERO_LABS = 0x589dEDbD617e0CBcB916A9223F4d1300c294236b;
address constant ETH_MAINNET_DVN_NETHERMIND = 0xa59BA433ac34D2927232918Ef5B2eaAfcF130BA5;
address constant ETH_MAINNET_DVN_CANARY = 0xa4fE5A5B9A846458a70Cd0748228aED3bF65c2cd;
address constant ETH_MAINNET_DVN_DEUTSCHE_TELEKOM = 0x373a6E5c0C4E89E24819f00AA37ea370917AAfF4;
address constant ETH_MAINNET_DVN_FCAT = 0xc61aF5706b80Ca941a0aAb1C7B3D7a953E4dD8C4;

// Base Mainnet

address constant BASE_MAINNET_LZ_ENDPOINT_V2 = 0x1a44076050125825900e736c501f859c50fE728c;
uint32 constant BASE_MAINNET_LZ_CHAIN_ID_V2 = 30184;

address constant BASE_MAINNET_LZ_EXECUTOR = 0x2CCA08ae69E0C44b18a57Ab2A87644234dAebaE4;
address constant BASE_MAINNET_LZ_SEND_ULN_302 = 0xB5320B0B3a13cC860893E2Bd79FCd7e13484Dda2;
address constant BASE_MAINNET_LZ_RECEIVE_ULN_302 = 0xc70AB6f32772f59fBfc23889Caf4Ba3376C84bAf;

address constant BASE_MAINNET_DVN_LAYERZERO_LABS = 0x9e059a54699a285714207b43B055483E78FAac25;
address constant BASE_MAINNET_DVN_NETHERMIND = 0xcd37CA043f8479064e10635020c65FfC005d36f6;
address constant BASE_MAINNET_DVN_CANARY = 0x554833698Ae0FB22ECC90B01222903fD62CA4B47;
address constant BASE_MAINNET_DVN_DEUTSCHE_TELEKOM = 0xc2A0C36f5939A14966705c7Cec813163FaEEa1F0;
address constant BASE_MAINNET_DVN_FCAT = 0xEaE72C81F3FCe1313EeeE26717F42af91E178516;

// Polygon Mainnet

address constant POLYGON_MAINNET_LZ_ENDPOINT_V2 = 0x1a44076050125825900e736c501f859c50fE728c;
uint32 constant POLYGON_MAINNET_LZ_CHAIN_ID_V2 = 30109;

address constant POLYGON_MAINNET_LZ_EXECUTOR = 0xCd3F213AD101472e1713C72B1697E727C803885b;
address constant POLYGON_MAINNET_LZ_SEND_ULN_302 = 0x6c26c61a97006888ea9E4FA36584c7df57Cd9dA3;
address constant POLYGON_MAINNET_LZ_RECEIVE_ULN_302 = 0x1322871e4ab09Bc7f5717189434f97bBD9546e95;

address constant POLYGON_MAINNET_DVN_LAYERZERO_LABS = 0x23DE2FE932d9043291f870324B74F820e11dc81A;
address constant POLYGON_MAINNET_DVN_NETHERMIND = 0x31F748a368a893Bdb5aBB67ec95F232507601A73;
address constant POLYGON_MAINNET_DVN_CANARY = 0x13feb7234Ff60A97af04477d6421415766753Ba3;
address constant POLYGON_MAINNET_DVN_DEUTSCHE_TELEKOM = 0x5CcCb8DE6Cdba9D2Af9d84465653af7390FDf9Dd;
address constant POLYGON_MAINNET_DVN_FCAT = 0x14206011d192E4F41D694d21ac599D0e88c2c12A;

// Telcoin Network (Main Chain — NativeBridge)
// address constant TELCOIN_NETWORK_LZ_ENDPOINT_V2 = address(0); // TODO
// uint32 constant TELCOIN_NETWORK_LZ_CHAIN_ID_V2 = 0; // TODO
// address constant TELCOIN_NETWORK_LZ_DVN = address(0); // TODO
// address constant TELCOIN_NETWORK_LZ_EXECUTOR = address(0); // TODO
// address constant TELCOIN_NETWORK_LZ_SEND_ULN_302 = address(0); // TODO
// address constant TELCOIN_NETWORK_LZ_RECEIVE_ULN_302 = address(0); // TODO
