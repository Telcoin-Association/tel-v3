// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @notice Pause-related role constants shared by all pausable contracts.
abstract contract PauseRoles {
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant UNPAUSER_ROLE = keccak256("UNPAUSER_ROLE");
}

/// @notice Full role set for TelcoinV3 token administration.
abstract contract Roles is PauseRoles {
    // Custom Roles
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");
}
