// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {console} from "forge-std/console.sol";
import {Safe} from "@safe-utils/Safe.sol";
import {DeployBase} from "forge-deploy-utils/DeployBase.sol";
import {TelcoinV3} from "../../src/TelcoinV3.sol";
import {Roles} from "../../src/helpers/Roles.sol";

/// @title BaseDeployToken
/// @notice Deploys TelcoinV3 via CREATE3 and configures PAUSER/UNPAUSER roles.
/// @dev    Step 0 in the deployment pipeline. Children populate configuration in setUp().
///
///         Per chain:
///         1. Deploy TelcoinV3 (mints initialSupply to _admin)
///         2. Grant PAUSER_ROLE to _pauser
///         3. Grant UNPAUSER_ROLE to _unpauser
///         4. Save address to deployments JSON
abstract contract BaseDeployToken is DeployBase, Roles {
    using Safe for *;

    // -----
    // Roles
    // -----

    address internal _admin;
    address internal _pauser;
    address internal _unpauser;

    // ---------
    // Variables
    // ---------

    bytes32 internal _telcoinV3Salt;

    struct TokenChainConfig {
        string chainName;
        string rpcUrl;
        uint256 evmChainId;
        uint256 initialSupply;
    }

    TokenChainConfig[] internal allChains;

    // ------
    // Script
    // ------

    /// @dev Iterates all configured chains, fork-switches, and deploys TelcoinV3 + roles on each.
    function run() public {
        uint256 len = allChains.length;

        for (uint256 i; i < len; ++i) {
            vm.createSelectFork(allChains[i].rpcUrl);
            currentNonce = safe.getNonce();

            console.log("=== Deploy TelcoinV3 on %s ===", allChains[i].chainName);

            _deployAndConfigure(allChains[i]);
        }
    }

    // ------
    // Deploy
    // ------

    /// @dev Deploys TelcoinV3, grants PAUSER/UNPAUSER to designated addresses, and persists to JSON.
    function _deployAndConfigure(TokenChainConfig memory chain) internal {
        require(
            block.chainid == chain.evmChainId,
            string.concat(
                "Chain ID mismatch: expected ",
                vm.toString(chain.evmChainId),
                " but connected to ",
                vm.toString(block.chainid)
            )
        );

        // 1. Deploy TelcoinV3
        address token = _deployTelcoinV3(chain.initialSupply);

        // 2. Configure roles
        TelcoinV3 telcoinContract = TelcoinV3(token);

        if (!telcoinContract.hasRole(PAUSER_ROLE, _pauser)) {
            _proposeTransaction(
                token,
                abi.encodeCall(telcoinContract.grantRole, (PAUSER_ROLE, _pauser)),
                "Grant PAUSER_ROLE to pauser"
            );
        }
        if (!telcoinContract.hasRole(UNPAUSER_ROLE, _unpauser)) {
            _proposeTransaction(
                token,
                abi.encodeCall(telcoinContract.grantRole, (UNPAUSER_ROLE, _unpauser)),
                "Grant UNPAUSER_ROLE to unpauser"
            );
        }

        // 3. Save address
        _saveDeploymentAddress(chain.chainName, "TelcoinV3", token);
    }

    /// @dev Deploys TelcoinV3 via CREATE3. Mints `initSupply` to _admin at construction. Idempotent.
    function _deployTelcoinV3(uint256 initSupply) internal returns (address) {
        bytes memory params = abi.encode(initSupply, _admin);
        bytes memory bytecode = bytes.concat(type(TelcoinV3).creationCode, params);
        (address addr, bool isNew) = _deployCreate3(_telcoinV3Salt, bytecode, "Deploy TelcoinV3");

        if (isNew) {
            console.log("Deployed TelcoinV3 at:", addr);
        } else {
            console.log("TelcoinV3 already deployed at:", addr);
        }

        return addr;
    }
}
