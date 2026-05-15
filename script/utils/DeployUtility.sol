// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {SafeScriptBase} from "@safe-utils/SafeScriptBase.sol";
import {console} from "forge-std/console.sol";
import {ICreateX} from "../interfaces/ICreateX.sol";
import {SaltMath} from "../libraries/SaltMath.sol";

/// @title DeployUtility
/// @notice Base utility for Gnosis Safe-based deployments via CreateX.
///         All deployments are proposed as Safe transactions (simulated or broadcast).
/// @dev    Children call _initializeSafe() or _initializeSafeMultiSig() in setUp().
///         The deployer address is always `deployerSafeAddress` (inherited from SafeScriptBase).
abstract contract DeployUtility is SafeScriptBase {
    address constant CREATEX = 0xba5Ed099633D3B313e4D5F7bdc1305d3c28ba5Ed;

    bytes32 internal constant PROXY_IMPLEMENTATION_SLOT =
        0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    // -------------------
    // Address Computation
    // -------------------

    function _computeCreate2Address(bytes32 guardedSalt, bytes32 initCodeHash) internal view returns (address) {
        bytes32 transformedSalt = SaltMath.getCreateXGuardedSalt(guardedSalt, deployerSafeAddress);
        return ICreateX(CREATEX).computeCreate2Address(transformedSalt, initCodeHash);
    }

    function _computeCreate3Address(bytes32 guardedSalt) internal view returns (address) {
        bytes32 transformedSalt = SaltMath.getCreateXGuardedSalt(guardedSalt, deployerSafeAddress);
        return ICreateX(CREATEX).computeCreate3Address(transformedSalt, CREATEX);
    }

    function _computeProxyAdminAddress(address proxy) internal pure returns (address) {
        return address(uint160(uint256(keccak256(abi.encodePacked(bytes1(0xd6), bytes1(0x94), proxy, bytes1(0x01))))));
    }

    // ------------------
    // Deployment Helpers
    // ------------------

    function _deployCreate3(bytes32 rawSalt, bytes memory initCode, string memory label)
        internal
        returns (address contractAddress, bool newDeployment)
    {
        bytes32 guardedSalt = SaltMath.guardSalt(deployerSafeAddress, rawSalt);
        require(SaltMath.extractGuard(guardedSalt) == deployerSafeAddress, "guarded salt incorrect");

        address expectedAddress = _computeCreate3Address(guardedSalt);

        if (expectedAddress.code.length > 0) {
            console.log("[safe] %s already deployed at %s, skipping", label, expectedAddress);
            return (expectedAddress, false);
        }

        bytes memory data = abi.encodeCall(ICreateX.deployCreate3, (guardedSalt, initCode));
        _proposeTransactionWithVerification(CREATEX, data, expectedAddress, label);

        return (expectedAddress, true);
    }

    function _deployCreate2(bytes32 rawSalt, bytes memory initCode, bytes32 initCodeHash, string memory label)
        internal
        returns (address)
    {
        bytes32 guardedSalt = SaltMath.guardSalt(deployerSafeAddress, rawSalt);
        require(SaltMath.extractGuard(guardedSalt) == deployerSafeAddress, "guarded salt incorrect");

        address expectedAddress = _computeCreate2Address(guardedSalt, initCodeHash);

        if (expectedAddress.code.length > 0) {
            console.log("[safe] %s already deployed at %s, skipping", label, expectedAddress);
            return expectedAddress;
        }

        bytes memory data = abi.encodeCall(ICreateX.deployCreate2, (guardedSalt, initCode));
        _proposeTransactionWithVerification(CREATEX, data, expectedAddress, label);

        return expectedAddress;
    }

    // --------------------
    // JSON File Read/Write
    // --------------------

    function _saveDeploymentAddress(string memory _alias, string memory name, address addr) internal {
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/deployments/", _alias, ".json");
        string memory json;
        string memory output;
        string[] memory keys;

        if (vm.exists(path)) {
            json = vm.readFile(path);
            keys = vm.parseJsonKeys(json, "$");
        } else {
            keys = new string[](0);
        }

        bool serialized;

        for (uint256 i; i < keys.length; i++) {
            if (keccak256(bytes(keys[i])) == keccak256(bytes(name))) {
                output = vm.serializeAddress(_alias, name, addr);
                serialized = true;
            } else {
                address value = vm.parseJsonAddress(json, string.concat(".", keys[i]));
                output = vm.serializeAddress(_alias, keys[i], value);
            }
        }

        if (!serialized) {
            output = vm.serializeAddress(_alias, name, addr);
        }

        vm.writeJson(output, path);
    }

    function _loadDeploymentAddress(string memory _alias, string memory name) internal view returns (address) {
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/deployments/", _alias, ".json");

        if (vm.exists(path)) {
            string memory json = vm.readFile(path);
            string[] memory keys = vm.parseJsonKeys(json, "$");
            for (uint256 i; i < keys.length; i++) {
                if (keccak256(bytes(keys[i])) == keccak256(bytes(name))) {
                    return vm.parseJsonAddress(json, string.concat(".", keys[i]));
                }
            }
        }

        return address(0);
    }
}
