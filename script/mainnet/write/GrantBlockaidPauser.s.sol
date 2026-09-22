// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {console} from "forge-std/console.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {DeployBase} from "forge-deploy-utils/DeployBase.sol";
import {Roles} from "../../../src/helpers/Roles.sol";
import "../utils/Constants.sol";

interface IOwnable {
    function owner() external view returns (address);
}

/// @title GrantBlockaidPauser (Mainnet)
/// @notice Grants PAUSER_ROLE to the Blockaid incident-response wallet on all pausable
///         TEL v3 contracts, so Blockaid can pause the protocol in an emergency:
///         TelcoinV3, TelcoinBridge, TokenMigration, MigrationVault.
///
///         All grants are batched into ONE MultiSend Safe transaction, proposed by the
///         admin Safe (DEPLOYER_SAFE_ADDRESS). Note the grant is DEFAULT_ADMIN_ROLE-gated
///         on TelcoinV3 / TokenMigration / MigrationVault but onlyOwner-gated on
///         TelcoinBridge — the admin Safe satisfies both. Idempotent: contracts where
///         Blockaid already holds PAUSER_ROLE are skipped.
///
/// ## How to Run
///
/// Simulation:
/// ```
/// forge script script/mainnet/write/GrantBlockaidPauser.s.sol --rpc-url $RPC_URL --ffi -vvvv
/// ```
///
/// Broadcast (proposes to Safe TX Service):
/// ```
/// forge script script/mainnet/write/GrantBlockaidPauser.s.sol --rpc-url $RPC_URL --broadcast --ffi -vvvv
/// ```
///
/// ## Queueing behind pending Safe txns
///
/// Proposal nonces derive from the on-chain Safe nonce, which only advances on
/// execution. If an earlier txn is proposed but not yet executed, set SAFE_NONCE_OFFSET
/// to the number of pending (unexecuted) proposals so this one queues behind them:
/// ```
/// SAFE_NONCE_OFFSET=1 forge script <this script> --rpc-url $RPC_URL --broadcast --ffi -vvvv
/// ```
contract GrantBlockaidPauser is DeployBase, Roles {
    bytes32 internal constant DEFAULT_ADMIN_ROLE = 0x00;

    /// @notice Blockaid incident-response wallet, read from .env.
    address internal blockaidResponseWallet;

    address[] internal _batchTargets;
    bytes[] internal _batchDatas;

    string[] internal _grantedNames;

    function setUp() public {
        _initializeSafeMultiSig();
        blockaidResponseWallet = vm.envAddress("BLOCKAID_RESPONSE_WALLET");
        require(blockaidResponseWallet != address(0), "BLOCKAID_RESPONSE_WALLET is zero");
    }

    function run() public {
        // SAFE_NONCE_OFFSET queues this proposal behind pending-but-unexecuted
        // Safe txns (on-chain nonce doesn't advance until execution).
        currentNonce = getSafeNonce() + vm.envOr("SAFE_NONCE_OFFSET", uint256(0));

        string memory chainAlias = _chainAlias();

        console.log("=== Grant Blockaid PAUSER_ROLE (Safe) ===");
        console.log("Chain:", chainAlias);
        console.log("Safe:", deployerSafeAddress);
        console.log("Blockaid response wallet:", blockaidResponseWallet);
        console.log("");

        string[4] memory names = ["TelcoinV3", "TelcoinBridge", "TokenMigration", "MigrationVault"];
        for (uint256 i; i < names.length; ++i) {
            address target = _loadDeploymentAddress(chainAlias, names[i]);
            require(target != address(0), string.concat(names[i], " not deployed"));

            if (IAccessControl(target).hasRole(PAUSER_ROLE, blockaidResponseWallet)) {
                console.log("  %s: Blockaid already has PAUSER_ROLE, skipping", names[i]);
                continue;
            }

            // TelcoinBridge gates grantRole on ownership; the rest on DEFAULT_ADMIN_ROLE
            if (keccak256(bytes(names[i])) == keccak256("TelcoinBridge")) {
                require(IOwnable(target).owner() == deployerSafeAddress, "Safe is not TelcoinBridge owner");
            } else {
                require(
                    IAccessControl(target).hasRole(DEFAULT_ADMIN_ROLE, deployerSafeAddress),
                    string.concat("Safe lacks DEFAULT_ADMIN_ROLE on ", names[i])
                );
            }

            console.log("  [batch] Grant PAUSER_ROLE on %s (%s)", names[i], target);
            _batchTargets.push(target);
            _batchDatas.push(abi.encodeCall(IAccessControl.grantRole, (PAUSER_ROLE, blockaidResponseWallet)));
            _grantedNames.push(names[i]);
        }

        if (_batchTargets.length == 0) {
            console.log("Nothing to grant, all contracts already configured.");
            return;
        }

        _proposeTransactions(
            _batchTargets, _batchDatas, string.concat("Grant Blockaid PAUSER_ROLE on ", chainAlias)
        );

        // Simulation executes the batch on the fork — verify the end state
        if (isSimulation()) {
            for (uint256 i; i < _batchTargets.length; ++i) {
                require(
                    IAccessControl(_batchTargets[i]).hasRole(PAUSER_ROLE, blockaidResponseWallet),
                    string.concat("PAUSER_ROLE not granted on ", _grantedNames[i])
                );
            }
            console.log("Simulation OK: Blockaid holds PAUSER_ROLE on all %d contracts.", _batchTargets.length);
        } else {
            console.log("Grant batch proposed (%d grants).", _batchTargets.length);
        }
    }

    function _chainAlias() internal view returns (string memory) {
        if (block.chainid == ETH_MAINNET_CHAIN_ID) return "ethereum";
        if (block.chainid == BASE_MAINNET_CHAIN_ID) return "base";
        if (block.chainid == POLYGON_MAINNET_CHAIN_ID) return "polygon";
        revert("Unsupported chain");
    }
}
