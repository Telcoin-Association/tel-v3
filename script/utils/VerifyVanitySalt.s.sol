// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script, console} from "forge-std/Script.sol";
import {SaltMath} from "forge-deploy-utils/libraries/SaltMath.sol";
import {ICreateX} from "forge-deploy-utils/interfaces/ICreateX.sol";

/// @title VerifyVanitySalt
/// @notice Independently predicts the CreateX `deployCreate3` address for a raw salt,
///         using the production SaltMath the deploy pipeline itself uses. Companion to
///         the miner in script/utils/vanity/ — run every mined salt through this before
///         pasting it into script/mainnet/utils/Salts.sol.
///
/// The address depends ONLY on (CreateX, deployer Safe, low 11 bytes of the raw salt).
/// Contract bytecode and constructor args are irrelevant.
///
/// ## How to Run
///
/// Offline (pure derivation):
/// ```
/// VANITY_SALT=0x<raw salt> forge script script/utils/VerifyVanitySalt.s.sol -vvvv
/// ```
///
/// With an RPC (adds on-chain cross-check against CreateX + Safe code check):
/// ```
/// VANITY_SALT=0x<raw salt> forge script script/utils/VerifyVanitySalt.s.sol \
///     --rpc-url $ETHEREUM_RPC_URL -vvvv
/// ```
///
/// Optional env:
/// - DEPLOYER_SAFE_ADDRESS: deployer Safe (same var the deploy pipeline reads).
///   Falls back to the canonical mainnet Safe with a loud warning when unset.
/// - VANITY_EXPECTED_ADDRESS: hard gate — revert unless the prediction matches.
contract VerifyVanitySalt is Script {
    /// @dev CreateX factory, same address on all EVM chains.
    address constant CREATEX = 0xba5Ed099633D3B313e4D5F7bdc1305d3c28ba5Ed;

    /// @dev keccak256 of the CREATE3 proxy child bytecode
    ///      (lib/create3/contracts/Create3.sol: KECCAK256_PROXY_CHILD_BYTECODE).
    bytes32 constant PROXY_CHILD_HASH = 0x21c35dbe1b344a2488cf3321d6ce542f8e9f305544ff09e4993a62319a497c1f;

    /// @dev Canonical 2/7 mainnet deployer Safe. The deploy pipeline resolves the same
    ///      address from DEPLOYER_SAFE_ADDRESS (safe-utils SafeScriptBase).
    address constant CANONICAL_SAFE = 0x10DC2EFbd84ebFb92eef5f145e3D84CC8b511799;

    // Golden vector: the live (non-vanity) TelcoinV3 V0 deployment, explorer-verified on
    // ethereum/base/polygon. Proves this harness before it is trusted with a mined salt.
    bytes32 constant GOLDEN_RAW_SALT = keccak256("RAW_TELCOIN_V3_SALT_MAINNET_V0");
    address constant GOLDEN_ADDRESS = 0xE6B8f90D047A4f7294DC6C5E369Ec75EefD62C7b;

    function run() external view {
        _selfTest();

        bytes32 rawSalt = vm.envBytes32("VANITY_SALT");

        address safe = vm.envOr("DEPLOYER_SAFE_ADDRESS", address(0));
        if (safe == address(0)) {
            safe = CANONICAL_SAFE;
            console.log("");
            console.log("WARNING: DEPLOYER_SAFE_ADDRESS not set in env; assuming canonical mainnet Safe.");
            console.log("WARNING: The deploy pipeline reads the same variable. If it resolves to a");
            console.log("WARNING: different Safe there, the deployed address will NOT match this prediction.");
        }

        (address predicted, bytes32 guarded, bytes32 transformed) = _predict(safe, rawSalt);

        console.log("");
        console.log("deployer Safe:    %s", vm.toString(safe));
        console.log("raw salt:         %s", vm.toString(rawSalt));
        console.log("suffix (low 11B): %s", vm.toString(abi.encodePacked(uint88(uint256(rawSalt)))));
        console.log("guarded salt:     %s", vm.toString(guarded));
        console.log("transformed salt: %s", vm.toString(transformed));
        console.log("");
        console.log("predicted address: %s", vm.toString(predicted));

        _crossCheckOnChain(safe, transformed, predicted);
        _checkExpected(predicted);
    }

    /// @dev Full CREATE3 derivation using the production SaltMath:
    ///      guarded     = [safe(20B)][0x00][low 11B of rawSalt]         (SaltMath.guardSalt)
    ///      transformed = keccak256(pad32(safe) ++ guarded)             (CreateX _guard, x-chain mode)
    ///      proxy       = CREATE2(CreateX, transformed, proxy child)
    ///      final       = CREATE(proxy, nonce 1) = keccak256(0xd6 0x94 ++ proxy ++ 0x01)[12:]
    function _predict(address safe, bytes32 rawSalt)
        internal
        pure
        returns (address finalAddr, bytes32 guarded, bytes32 transformed)
    {
        guarded = SaltMath.guardSalt(safe, rawSalt);
        transformed = SaltMath.getCreateXGuardedSalt(guarded, safe);
        address proxy = address(
            uint160(uint256(keccak256(abi.encodePacked(hex"ff", CREATEX, transformed, PROXY_CHILD_HASH))))
        );
        finalAddr = address(uint160(uint256(keccak256(abi.encodePacked(hex"d6_94", proxy, hex"01")))));
    }

    /// @dev The golden vector must reproduce before any prediction is trusted.
    function _selfTest() internal pure {
        (address got,,) = _predict(CANONICAL_SAFE, GOLDEN_RAW_SALT);
        require(
            got == GOLDEN_ADDRESS,
            "self-test FAILED: golden vector (live TelcoinV3 V0) does not reproduce - derivation is broken"
        );
    }

    /// @dev When run against an RPC (CreateX has code), ask CreateX itself for the address
    ///      and require the Safe to exist on that chain. Skipped silently-but-loudly offline.
    function _crossCheckOnChain(address safe, bytes32 transformed, address predicted) internal view {
        if (CREATEX.code.length == 0) {
            console.log("");
            console.log("offline mode: no RPC / CreateX has no code here; on-chain cross-check skipped.");
            console.log("Re-run with --rpc-url to cross-check against CreateX on a live chain.");
            return;
        }
        address fromCreateX = ICreateX(CREATEX).computeCreate3Address(transformed, CREATEX);
        require(fromCreateX == predicted, "on-chain cross-check FAILED: CreateX.computeCreate3Address disagrees");
        console.log("on-chain cross-check OK: CreateX.computeCreate3Address agrees (chain %s)", block.chainid);
        require(safe.code.length > 0, "deployer Safe has NO code on this chain - wrong chain or wrong Safe");
        console.log("deployer Safe has code on this chain: OK");
    }

    /// @dev Optional hard gate for CI / paranoia.
    function _checkExpected(address predicted) internal view {
        address expected = vm.envOr("VANITY_EXPECTED_ADDRESS", address(0));
        if (expected == address(0)) return;
        require(predicted == expected, "VANITY_EXPECTED_ADDRESS mismatch");
        console.log("matches VANITY_EXPECTED_ADDRESS: OK");
    }
}
