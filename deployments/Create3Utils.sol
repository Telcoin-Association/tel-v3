/// SPDX-License-Identifier MIT
pragma solidity ^0.8.26;

import "create3/Create3.sol";

/// @dev Configuration and utilities for Create3 deterministic deployments

abstract contract Create3Utils {
    /// @dev Deploys a contract using `CREATE3`
    function deploy(
        bytes32 salt,
        bytes memory creationCode
    ) external payable returns (address) {
        return Create3.create3(salt, creationCode);
    }

    /// @dev Returns the expected contract deployment address using `CREATE3`
    function addressOf(bytes32 salt) external view returns (address) {
        return Create3.addressOf(salt);
    }
}

contract Create3Impl is Create3Utils {}
