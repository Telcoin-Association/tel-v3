// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title ICreateX
/// @notice Interface for CreateX factory deployment functions
/// @notice See https://github.com/pcaversaccio/createx/blob/main/src/ICreateX.sol
/// @dev CreateX is deployed at 0xba5Ed099633D3B313e4D5F7bdc1305d3c28ba5Ed on all EVM chains
interface ICreateX {
    function computeCreate2Address(bytes32 salt, bytes32 initCodeHash) external view returns (address computedAddress);

    function computeCreate3Address(bytes32 salt, address deployer) external pure returns (address computedAddress);

    function deployCreate2(bytes32 salt, bytes memory initCode) external payable returns (address newContract);

    function deployCreate3(bytes32 salt, bytes memory initCode) external payable returns (address newContract);
}