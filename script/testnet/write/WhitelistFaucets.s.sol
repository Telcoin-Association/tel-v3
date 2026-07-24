// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {console} from "forge-std/console.sol";
import {Safe} from "@safe-utils/Safe.sol";
import {DeployBase} from "forge-deploy-utils/DeployBase.sol";
import {TelcoinV3Faucet} from "../../../src/faucet/TelcoinV3Faucet.sol";
import {LegacyTelcoinFaucet} from "../../../src/faucet/LegacyTelcoinFaucet.sol";
import "../utils/Constants.sol";

/// @title WhitelistFaucets
/// @notice Whitelists addresses on all 4 faucet contracts (TelcoinV3Faucet + LegacyTelcoinFaucet
///         on eth-sepolia and base-sepolia) via Gnosis Safe.
///
/// @dev Add addresses to the `_whitelist` array in setUp().
///
/// ## How to Run
///
/// Simulation:
/// ```
/// forge script script/testnet/write/WhitelistFaucets.s.sol --rpc-url $ETH_SEPOLIA_RPC_URL --ffi -vvvv
/// ```
///
/// Broadcast (proposes to Safe TX Service):
/// ```
/// forge script script/testnet/write/WhitelistFaucets.s.sol --rpc-url $ETH_SEPOLIA_RPC_URL --broadcast --ffi -vvvv
/// ```
contract WhitelistFaucets is DeployBase {
    using Safe for *;
    // ---------
    // Variables
    // ---------

    struct ChainConfig {
        string chainName;
        string rpcUrl;
        uint256 evmChainId;
    }

    ChainConfig[] internal _chains;
    address[] internal _whitelist;

    // Batch accumulation
    address[] internal _batchTargets;
    bytes[] internal _batchDatas;

    // -----
    // Setup
    // -----

    function setUp() public {
        _initializeSafeMultiSig();

        _chains.push(ChainConfig({
            chainName: "eth-sepolia",
            rpcUrl: vm.envString("ETH_SEPOLIA_RPC_URL"),
            evmChainId: ETH_SEPOLIA_CHAIN_ID
        }));

        _chains.push(ChainConfig({
            chainName: "base-sepolia",
            rpcUrl: vm.envString("BASE_SEPOLIA_RPC_URL"),
            evmChainId: BASE_SEPOLIA_CHAIN_ID
        }));

        // ---- Add addresses to whitelist here ----
        _whitelist.push(0x936D600C0170fcce1053eEeEd80C8EA1e27c4745); /// @dev assign
    }

    // ------
    // Script
    // ------

    function run() public {
        require(_whitelist.length > 0, "No addresses to whitelist");

        for (uint256 i; i < _chains.length; ++i) {
            vm.createSelectFork(_chains[i].rpcUrl);
            currentNonce = safe.getNonce();

            console.log("=== Whitelist Faucets on %s ===", _chains[i].chainName);

            address v3Faucet = _loadDeploymentAddress(_chains[i].chainName, "TelcoinV3Faucet");
            address legacyFaucet = _loadDeploymentAddress(_chains[i].chainName, "LegacyTelcoinFaucet");

            require(v3Faucet != address(0), "TelcoinV3Faucet not deployed");
            require(legacyFaucet != address(0), "LegacyTelcoinFaucet not deployed");

            TelcoinV3Faucet v3 = TelcoinV3Faucet(v3Faucet);
            LegacyTelcoinFaucet legacy = LegacyTelcoinFaucet(legacyFaucet);

            for (uint256 j; j < _whitelist.length; ++j) {
                address account = _whitelist[j];
                require(account != address(0), "address(0) detected");

                if (!v3.whitelisted(account)) {
                    console.log("  [batch] Whitelist %s on TelcoinV3Faucet", account);
                    _batchTargets.push(v3Faucet);
                    _batchDatas.push(abi.encodeCall(v3.setWhitelist, (account, true)));
                } else {
                    console.log("  [skip] %s already whitelisted on TelcoinV3Faucet", account);
                }

                if (!legacy.whitelisted(account)) {
                    console.log("  [batch] Whitelist %s on LegacyTelcoinFaucet", account);
                    _batchTargets.push(legacyFaucet);
                    _batchDatas.push(abi.encodeCall(legacy.setWhitelist, (account, true)));
                } else {
                    console.log("  [skip] %s already whitelisted on LegacyTelcoinFaucet", account);
                }
            }

            _flushBatch(string.concat("Whitelist faucets on ", _chains[i].chainName));
        }

        console.log("Whitelist transactions proposed.");
    }

    function _flushBatch(string memory description) internal {
        uint256 len = _batchTargets.length;
        if (len == 0) {
            console.log("  No changes needed, skipping");
            return;
        }

        address[] memory targets = new address[](len);
        bytes[] memory datas = new bytes[](len);
        for (uint256 k; k < len; ++k) {
            targets[k] = _batchTargets[k];
            datas[k] = _batchDatas[k];
        }

        console.log("  Proposing %d txns as single MultiSend", len);
        _proposeTransactions(targets, datas, description);

        delete _batchTargets;
        delete _batchDatas;
    }
}
