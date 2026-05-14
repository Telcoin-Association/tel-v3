// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

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

// Ethereum Mainnet

address constant ETH_MAINNET_LZ_ENDPOINT_V2 = 0x1a44076050125825900e736c501f859c50fE728c;
uint32 constant ETH_MAINNET_LZ_CHAIN_ID_V2 = 30101;

address constant ETH_MAINNET_LZ_DVN = address(0); // TODO
address constant ETH_MAINNET_LZ_EXECUTOR = address(0); // TODO
address constant ETH_MAINNET_LZ_SEND_ULN_302 = address(0); // TODO
address constant ETH_MAINNET_LZ_RECEIVE_ULN_302 = address(0); // TODO

// Base Mainnet

address constant BASE_MAINNET_LZ_ENDPOINT_V2 = 0x1a44076050125825900e736c501f859c50fE728c;
uint32 constant BASE_MAINNET_LZ_CHAIN_ID_V2 = 30184;

address constant BASE_MAINNET_LZ_DVN = address(0); // TODO
address constant BASE_MAINNET_LZ_EXECUTOR = address(0); // TODO
address constant BASE_MAINNET_LZ_SEND_ULN_302 = address(0); // TODO
address constant BASE_MAINNET_LZ_RECEIVE_ULN_302 = address(0); // TODO

// Polygon Mainnet

address constant POLYGON_MAINNET_LZ_ENDPOINT_V2 = 0x1a44076050125825900e736c501f859c50fE728c;
uint32 constant POLYGON_MAINNET_LZ_CHAIN_ID_V2 = 30109;

address constant POLYGON_MAINNET_LZ_DVN = address(0); // TODO
address constant POLYGON_MAINNET_LZ_EXECUTOR = address(0); // TODO
address constant POLYGON_MAINNET_LZ_SEND_ULN_302 = address(0); // TODO
address constant POLYGON_MAINNET_LZ_RECEIVE_ULN_302 = address(0); // TODO

// Telcoin Network (Main Chain — NativeBridge)
// address constant TELCOIN_NETWORK_LZ_ENDPOINT_V2 = address(0); // TODO
// uint32 constant TELCOIN_NETWORK_LZ_CHAIN_ID_V2 = 0; // TODO
// address constant TELCOIN_NETWORK_LZ_DVN = address(0); // TODO
// address constant TELCOIN_NETWORK_LZ_EXECUTOR = address(0); // TODO
// address constant TELCOIN_NETWORK_LZ_SEND_ULN_302 = address(0); // TODO
// address constant TELCOIN_NETWORK_LZ_RECEIVE_ULN_302 = address(0); // TODO
