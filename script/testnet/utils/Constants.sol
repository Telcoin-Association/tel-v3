// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

// -------------
// EVM Chain IDs
// -------------

uint256 constant ETH_SEPOLIA_CHAIN_ID = 11155111;
uint256 constant BASE_SEPOLIA_CHAIN_ID = 84532;
uint256 constant ADIRI_CHAIN_ID = 2017;

// -------------
// Layer Zero V2
// -------------

// Base Sepolia

address constant BASE_SEPOLIA_LZ_ENDPOINT_V2 = 0x6EDCE65403992e310A62460808c4b910D972f10f;
uint16 constant BASE_SEPOLIA_LZ_CHAIN_ID_V2 = 40245;

address constant BASE_SEPOLIA_LZ_DVN = 0xe1a12515F9AB2764b887bF60B923Ca494EBbB2d6;
address constant BASE_SEPOLIA_LZ_EXECUTOR = 0x8A3D588D9f6AC041476b094f97FF94ec30169d3D;
address constant BASE_SEPOLIA_LZ_SEND_ULN_302 = 0xC1868e054425D378095A003EcbA3823a5D0135C9;
address constant BASE_SEPOLIA_LZ_RECEIVE_ULN_302 = 0x12523de19dc41c91F7d2093E0CFbB76b17012C8d;

// Ethereum Sepolia

address constant ETH_SEPOLIA_LZ_ENDPOINT_V2 = 0x6EDCE65403992e310A62460808c4b910D972f10f;
uint16 constant ETH_SEPOLIA_LZ_CHAIN_ID_V2 = 40161;

address constant ETH_SEPOLIA_LZ_DVN = 0x8eebf8b423B73bFCa51a1Db4B7354AA0bFCA9193;
address constant ETH_SEPOLIA_LZ_EXECUTOR = 0x718B92b5CB0a5552039B593faF724D182A881eDA;
address constant ETH_SEPOLIA_LZ_SEND_ULN_302 = 0xcc1ae8Cf5D3904Cef3360A9532B477529b177cCE;
address constant ETH_SEPOLIA_LZ_RECEIVE_ULN_302 = 0xdAf00F5eE2158dD58E0d3857851c432E34A3A851;

// Adiri (Telcoin Network testnet — TEL is the native gas token, NativeBridge chain)
// Source: LayerZero metadata API, chainKey "adiri-testnet". Verified on-chain
// 2026-08-21 (endpoint has code at this address). See docs/notes/adiri-deployment.md.

address constant ADIRI_LZ_ENDPOINT_V2 = 0x3aCAAf60502791D199a5a5F0B173D78229eBFe32;
uint32 constant ADIRI_LZ_CHAIN_ID_V2 = 40463;

address constant ADIRI_LZ_DVN = 0xa78A78a13074eD93aD447a26Ec57121f29E8feC2; // LayerZero Labs (only live DVN)
address constant ADIRI_LZ_EXECUTOR = 0x701f3927871EfcEa1235dB722f9E608aE120d243;
address constant ADIRI_LZ_SEND_ULN_302 = 0x45841dd1ca50265Da7614fC43A361e526c0e6160;
address constant ADIRI_LZ_RECEIVE_ULN_302 = 0xd682ECF100f6F4284138AA925348633B0611Ae21;
