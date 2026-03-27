// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Salt helpers for CreateX guarded salts + CreateX internal salt derivation.
library SaltMath {

    // Salt Lifecycle: Raw Salt -> Protected Salt (Implements settings) -> Guarded Salt (Used inside CreateX)

    /**
     * @notice Creates a guarded salt for CreateX deployment
     * @dev The first 20 bytes are the guard address (Safe), remaining 11 bytes from original salt
     *      CreateX's _guard() function verifies: address(bytes20(salt)) == msg.sender
     * @param guard The address to guard the salt (must be msg.sender during deployment)
     * @param originalSalt The original salt from config (last 11 bytes are used)
     * @return guardedSalt The salt with guard address prepended
     */
    function guardSalt(address guard, bytes32 originalSalt) internal pure returns (bytes32 guardedSalt) {
        // Combine: [20 bytes: guard address][1 byte: 0x0][11 bytes: suffix]
        //
        // NOTE: 21st bytes is `0x0` to allow cross-chain deployments
        // use the first 11 bytes from original salt as the unique suffix
        uint88 suffix = uint88(uint256(originalSalt));
        guardedSalt = bytes32(uint256(uint160(guard)) << 96) | bytes32(uint256(suffix));

        // Verify structure
        assert(address(bytes20(guardedSalt)) == guard); // First 20 bytes = guard
        assert(guardedSalt[20] == 0x00); // Byte 21 = 0x00 (cross-chain replayable)
    }

    /**
     * @notice Extracts the guard address from a guarded salt
     * @param guardedSalt The guarded salt
     * @return guard The address embedded in the first 20 bytes
     */
    function extractGuard(bytes32 guardedSalt) internal pure returns (address) {
        return address(bytes20(guardedSalt));
    }

    /**
     * @notice Replicates CreateX's internal _guard salt transformation
     * @dev When salt has msg.sender in first 20 bytes and 0x00 in byte 21 (cross-chain mode),
     *      CreateX transforms: guardedSalt = keccak256(abi.encodePacked(padded_sender, salt))
     * @param salt The salt you're passing to deployCreate2/deployCreate3
     * @param sender The msg.sender when CreateX is called (your Safe address)
     */
    function getCreateXGuardedSalt(bytes32 salt, address sender) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(bytes32(uint256(uint160(sender))), salt));
    }
}
