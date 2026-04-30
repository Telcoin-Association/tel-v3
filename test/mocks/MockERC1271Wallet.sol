// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @dev Mock EIP-1271 wallet that validates a pre-set hash. Used for permit and EIP-3009 tests.
contract MockERC1271Wallet {
    bytes32 private _validHash;

    function setValidHash(bytes32 hash) external {
        _validHash = hash;
    }

    function isValidSignature(bytes32 hash, bytes calldata) external view returns (bytes4) {
        if (hash == _validHash) {
            return 0x1626ba7e; // EIP-1271 magic value
        }
        return 0xffffffff;
    }
}
