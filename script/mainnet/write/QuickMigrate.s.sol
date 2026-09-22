// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {console} from "forge-std/console.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {DeployBase} from "forge-deploy-utils/DeployBase.sol";
import {TokenMigration} from "../../../src/TokenMigration.sol";
import {Roles} from "../../../src/helpers/Roles.sol";
import "../utils/Constants.sol";

/// @title QuickMigrate (Mainnet)
/// @notice Pre-launch migration of the admin Safe's legacy TEL to TelcoinV3 while
///         TokenMigration remains paused to the public (e.g. to seed pools before launch).
///
///         Executes as a SINGLE MultiSend Safe transaction so the migration window is
///         never open to the public, even transiently:
///         1. Grant PAUSER_ROLE / UNPAUSER_ROLE to the admin Safe (only if paused and
///            not already held — the admin Safe keeps both roles afterward)
///         2. unpause()                             (only if currently paused)
///         3. approve legacy TEL to TokenMigration  (full Safe balance)
///         4. migrate()                             (migrates the Safe's entire legacy balance)
///         5. pause()                               (only if it was originally paused)
///
///         Run with DEPLOYER_SAFE_ADDRESS set to the admin Safe (holds DEFAULT_ADMIN_ROLE
///         and PAUSER_ROLE on TokenMigration).
///
/// ## How to Run
///
/// Simulation:
/// ```
/// forge script script/mainnet/write/QuickMigrate.s.sol --rpc-url $RPC_URL --ffi -vvvv
/// ```
///
/// Broadcast (proposes to Safe TX Service):
/// ```
/// forge script script/mainnet/write/QuickMigrate.s.sol --rpc-url $RPC_URL --broadcast --ffi -vvvv
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
contract QuickMigrate is DeployBase, Roles {
    bytes32 internal constant DEFAULT_ADMIN_ROLE = 0x00;

    address[] internal _batchTargets;
    bytes[] internal _batchDatas;

    function setUp() public {
        _initializeSafeMultiSig();
    }

    function run() public {
        (string memory chainAlias, address legacyTelcoin) = _chainConfig();

        address migrator = _loadDeploymentAddress(chainAlias, "TokenMigration");
        address telcoinV3 = _loadDeploymentAddress(chainAlias, "TelcoinV3");
        require(migrator != address(0), "TokenMigration not deployed");
        require(telcoinV3 != address(0), "TelcoinV3 not deployed");

        TokenMigration migration = TokenMigration(migrator);
        IAccessControl access = IAccessControl(migrator);

        // Pre-flight checks
        require(access.hasRole(DEFAULT_ADMIN_ROLE, deployerSafeAddress), "Safe lacks DEFAULT_ADMIN_ROLE");
        require(!migration.migrationClosed(), "Migration permanently closed");
        require(block.timestamp < migration.migrationExpiry(), "Migration expired");

        uint256 legacyBalance = IERC20(legacyTelcoin).balanceOf(deployerSafeAddress);
        require(legacyBalance > 0, "Safe holds no legacy TEL");

        bool wasPaused = migration.paused();
        bool grantUnpauser = wasPaused && !access.hasRole(UNPAUSER_ROLE, deployerSafeAddress);
        bool grantPauser = wasPaused && !access.hasRole(PAUSER_ROLE, deployerSafeAddress);

        console.log("=== QuickMigrate (Safe) ===");
        console.log("Chain:", chainAlias);
        console.log("Safe:", deployerSafeAddress);
        console.log("Legacy TEL:", legacyTelcoin);
        console.log("TokenMigration:", migrator);
        console.log("Legacy TEL balance (2 dec):", legacyBalance);
        console.log("TEL v3 to be minted (18 dec):", migration.getAmountOut(legacyBalance));
        console.log("Currently paused:", wasPaused);
        console.log("");

        // 1. Grant pause roles to the admin Safe if needed (kept afterward)
        if (grantUnpauser) {
            _batchTargets.push(migrator);
            _batchDatas.push(abi.encodeCall(IAccessControl.grantRole, (UNPAUSER_ROLE, deployerSafeAddress)));
        }
        if (grantPauser) {
            _batchTargets.push(migrator);
            _batchDatas.push(abi.encodeCall(IAccessControl.grantRole, (PAUSER_ROLE, deployerSafeAddress)));
        }

        // 2. Unpause for the duration of this batch only
        if (wasPaused) {
            _batchTargets.push(migrator);
            _batchDatas.push(abi.encodeCall(TokenMigration.unpause, ()));
        }

        // 3. Approve TokenMigration for the Safe's full legacy balance
        _batchTargets.push(legacyTelcoin);
        _batchDatas.push(abi.encodeCall(IERC20.approve, (migrator, legacyBalance)));

        // 4. Migrate (entire legacy balance of the Safe)
        _batchTargets.push(migrator);
        _batchDatas.push(abi.encodeCall(TokenMigration.migrate, ()));

        // 5. Restore original pause state
        if (wasPaused) {
            _batchTargets.push(migrator);
            _batchDatas.push(abi.encodeCall(TokenMigration.pause, ()));
        }

        _proposeTransactions(_batchTargets, _batchDatas, "Quick migrate legacy TEL to TelcoinV3");

        // Simulation executes the batch on the fork — verify the end state
        if (isSimulation()) {
            require(migration.paused() == wasPaused, "Pause state not restored");
            require(IERC20(legacyTelcoin).balanceOf(deployerSafeAddress) == 0, "Legacy TEL not fully migrated");
            console.log("Simulation OK: migrated, pause state restored.");
            console.log("Safe TEL v3 balance:", IERC20(telcoinV3).balanceOf(deployerSafeAddress));
        } else {
            console.log("Quick migrate batch proposed.");
        }
    }

    function _chainConfig() internal view returns (string memory chainAlias, address legacyTelcoin) {
        if (block.chainid == ETH_MAINNET_CHAIN_ID) return ("ethereum", LEGACY_TELCOIN_ETHEREUM);
        if (block.chainid == BASE_MAINNET_CHAIN_ID) return ("base", LEGACY_TELCOIN_BASE);
        if (block.chainid == POLYGON_MAINNET_CHAIN_ID) return ("polygon", LEGACY_TELCOIN_POLYGON);
        revert("Unsupported chain");
    }
}
