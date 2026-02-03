// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script, console} from "forge-std/Script.sol";
import {ICreateX} from "../interfaces/ICreateX.sol";
import {SaltMath} from "../libraries/SaltMath.sol";

abstract contract DeployUtility is Script {
    /// @notice CreateX contract address used for CREATE2/CREATE3 computations.
    /// @dev Must be deployed on each target chain for CreateX-based flows.
    address constant CREATEX = 0xba5Ed099633D3B313e4D5F7bdc1305d3c28ba5Ed;

     /// @notice Slot for the proxy's implementation address, based on EIP-1967.
    bytes32 internal constant PROXY_IMPLEMENTATION_SLOT =
        0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    /// @notice Address of the deployer.
    address internal _deployer;

    /// @dev Private key used for broadcasting.
    uint256 internal _pk;

    function _setup() public {
        _loadPrivateKey();
    }

    /// @dev Loads private key from env.DEPLOYER_PRIVATE_KEY
    function _loadPrivateKey() internal {
        _pk = vm.envUint("DEPLOYER_PRIVATE_KEY");
        _deployer = vm.addr(_pk);
    }

    // -------------------
    // Address Computation
    // -------------------

    /**
     * @notice Compute CREATE2 address by calling CreateX on-chain
     */
    function _computeCreate2Address(bytes32 guardedSalt, bytes32 initCodeHash, address deployer) internal view returns (address) {
        // Call CreateX on-chain
        bytes32 transformedSalt = SaltMath.getCreateXGuardedSalt(guardedSalt, deployer);
        return ICreateX(CREATEX).computeCreate2Address(transformedSalt, initCodeHash);
    }

    /**
     * @notice Compute the CREATE3 deployment address by calling CreateX on-chain
     * @param guardedSalt The guarded salt (with deployer address in first 20 bytes)
     * @param deployer The address that will call CreateX (msg.sender during deployment)
     */
    function _computeCreate3Address(bytes32 guardedSalt, address deployer) internal view returns (address) {
        bytes32 transformedSalt = SaltMath.getCreateXGuardedSalt(guardedSalt, deployer);
        return ICreateX(CREATEX).computeCreate3Address(transformedSalt, CREATEX);
    }

    /**
     * @notice Compute ProxyAdmin address from proxy address
     * @dev In OZ v5, TransparentUpgradeableProxy deploys ProxyAdmin with CREATE (nonce 1)
     * @param proxy The proxy address
     * @return The ProxyAdmin address
     */
    function _computeProxyAdminAddress(address proxy) internal pure returns (address) {
        return address(uint160(uint256(keccak256(abi.encodePacked(bytes1(0xd6), bytes1(0x94), proxy, bytes1(0x01))))));
    }

    // ------------------
    // Deployment Helpers
    // ------------------

    function _deployCreate2(bytes32 rawSalt, bytes memory initCode, bytes32 creationCode, address deployer) internal returns (address) {
        // create guarded salt
        bytes32 guardedSalt = SaltMath.guardSalt(deployer, rawSalt);
        // sanity check guarded salt
        require(SaltMath.extractGuard(guardedSalt) == deployer, "guarded salt incorrect");

        // Pre-calculate Create2 deployment address
        address expectedAddress = _computeCreate2Address(guardedSalt, creationCode, deployer);
        if (_isDeployed(expectedAddress)) {
            console.log("Contract already deployed at:", expectedAddress);
            console.log("Skipping...");

            return expectedAddress;
        }

        // Call CreateX on-chain
        address newContract = ICreateX(CREATEX).deployCreate2(guardedSalt, initCode);
        require(newContract == expectedAddress, "New contract does not match expected");

        return newContract;
    }

    function _deployCreate3(bytes32 rawSalt, bytes memory initCode, address deployer) internal returns (address, bool) {
        // create guarded salt
        bytes32 guardedSalt = SaltMath.guardSalt(deployer, rawSalt);
        // sanity check guarded salt
        require(SaltMath.extractGuard(guardedSalt) == deployer, "guarded salt incorrect");

        // Pre-calculate Create3 deployment address
        address expectedAddress = _computeCreate3Address(guardedSalt, deployer);
        if (_isDeployed(expectedAddress)) return (expectedAddress, false);

        // Call CreateX on-chain
        address newContract = ICreateX(CREATEX).deployCreate3(guardedSalt, initCode);
        require(newContract == expectedAddress, "New contract does not match expected");

        return (newContract, true);
    }

    /// @dev Checks whether a contract is deployed at a given address.
    function _isDeployed(address contractAddress) internal view returns (bool isDeployed) {
        // slither-disable-next-line assembly
        assembly {
            let cs := extcodesize(contractAddress)
            if iszero(iszero(cs)) { isDeployed := true }
        }
    }

    // --------------------
    // JSON File Read/Write
    // --------------------

    /**
     * @dev Saves the deployment address of a contract to the chain's deployment address JSON file. This function is
     * essential for tracking the deployment of contracts and ensuring that the contract's address is stored for future
     * reference.
     * @param name The name of the contract for which the deployment address is being saved.
     * @param addr The address of the deployed contract.
     */
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

    /**
     * @dev Loads the deployment address of a contract from the chain's deployment address JSON file. This function is
     * crucial for retrieving the address of a previously deployed contract, particularly when the address is needed for
     * subsequent operations, like proxy upgrades.
     * @param name The name of the contract for which the deployment address is being loaded.
     * @return addr The address of the deployed contract.
     */
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