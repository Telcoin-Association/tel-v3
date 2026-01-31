// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {console} from "forge-std/console.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IOAppCore} from "@layerzerolabs/oapp-evm/contracts/oapp/interfaces/IOAppCore.sol";
import {DeployUtility} from "../utils/DeployUtility.sol";
import {TelcoinV3} from "../../src/TelcoinV3.sol";
import {TelcoinBridge} from "../../src/TelcoinBridge.sol";
import {TokenMigration} from "../../src/TokenMigration.sol";
import {SaltMath} from "../libraries/SaltMath.sol";
import {Roles} from "../../src/helpers/Roles.sol";
import "../utils/Constants.sol";
import "../utils/Addresses.sol";

/**
 * @title DeployAllToTestnet
 * @author Chase Brown
 * @dev This script performs a multi-chain deployment of:
 *      - Legacy Telcoin (mock for testing migration flow)
 *      - TelcoinV3 (new 18-decimal token)
 *      - TokenMigration (handles legacy -> V3 token migration)
 *      - TelcoinBridge (LayerZero V2 cross-chain bridge)
 *
 *      All contracts are deployed using CREATE3 for deterministic addresses across chains.
 *      After deployment, the script configures LayerZero peers to enable cross-chain bridging.
 *
 * ## How to Run
 *
 * Dry run (simulation):
 * ```
 * forge script script/testnet/DeployAllToTestnet.s.sol --multi
 * ```
 *
 * Live deployment:
 * ```
 * forge script script/testnet/DeployAllToTestnet.s.sol --multi --broadcast --verify
 * ```
 *
 * ## Deployment Order
 *
 * For each chain:
 * 1. Deploy Legacy Telcoin (if LEGACY_TEL == address(0))
 * 2. Deploy TelcoinV3 (initial supply sent to TokenMigration address)
 * 3. Deploy TokenMigration (receives initial TelcoinV3 supply)
 * 4. Deploy TelcoinBridge
 * 5. Grant MINTER_ROLE and BURNER_ROLE to TelcoinBridge
 *
 * After all chains deployed:
 * 6. Configure LayerZero peers between all bridge contracts
 *
 * ## Output
 *
 * Deployment addresses are saved to `deployments/<chainName>.json`
 */
contract DeployAllToTestnet is DeployUtility, Roles {
    // ~ Variables ~

    /// @dev TODO: Configure all constants

    bytes32 internal constant RAW_TELCOIN_V3_SALT = keccak256("TELCOIN_V3_SALT_0");
    bytes32 internal constant RAW_TELCOIN_MIGRATION_SALT = keccak256("TELCOIN_BRIDGE_SALT_0");
    bytes32 internal constant RAW_TELCOIN_BRIDGE_SALT = keccak256("TELCOIN_BRIDGE_SALT_0");

    uint256 internal constant INITIAL_TELV3_SUPPLY = 100_000_000 ether; // initial supply of 100M tokens per chain
    uint256 internal constant MIGRATION_DURATION = 365 * 1 days;

    address internal constant LEGACY_TEL = address(0);

    NetworkData[] internal allChains;
    mapping(string rpc => RuntimeData) internal getRuntimeData;

    struct NetworkData {
        string chainName;
        string rpc_url;
        address lz_endpoint;
        uint32 chainId;
        uint256 initialSupply;
        bool mainChain;
    }

    struct RuntimeData {
        uint256 forkId;
        address tokenAddress;
        address migrationAddress;
        address bridgeAddress;
    }

    // ~ Setup ~
    
    function setUp() public {
        _setup();

        /// @dev TODO: Configure all chain data

        allChains.push(NetworkData(
            {
                chainName: "eth-sepolia",
                rpc_url: vm.envString("ETH_SEPOLIA_RPC_URL"),
                lz_endpoint: ETH_SEPOLIA_LZ_ENDPOINT_V2,
                chainId: ETH_SEPOLIA_LZ_CHAIN_ID_V2,
                initialSupply: 1_000_000 ether,
                mainChain: true
            }
        ));
        allChains.push(NetworkData(
            {
                chainName: "base-sepolia",
                rpc_url: vm.envString("BASE_SEPOLIA_RPC_URL"),
                lz_endpoint: BASE_SEPOLIA_LZ_ENDPOINT_V2,
                chainId: BASE_SEPOLIA_LZ_CHAIN_ID_V2,
                initialSupply: 1_000_000 ether,
                mainChain: false
            }
        ));
    }

    // ~ Script ~

    function run() public {

        // Deploy
        uint256 len = allChains.length;
        for (uint256 i; i < len; ++i) {
            string memory rpcUrl = allChains[i].rpc_url;

            vm.createSelectFork(rpcUrl);
            vm.startBroadcast(_deployer);

            console.log("Deploying for chain:", allChains[i].chainName);

            (address tokenAddress, address migratorAddress, address bridgeAddress) = _deployAndConfigure(allChains[i]);

            // store in getRuntimeData mapping
            getRuntimeData[rpcUrl] = RuntimeData({
                forkId: i,
                tokenAddress: tokenAddress,
                migrationAddress: migratorAddress,
                bridgeAddress: bridgeAddress
            });

            vm.stopBroadcast();
        }

        // Configure peers
        for (uint256 i; i < len; ++i) {
            string memory rpcUrl = allChains[i].rpc_url;

            vm.selectFork(getRuntimeData[rpcUrl].forkId);
            vm.startBroadcast(_deployer);

            IOAppCore bridge = IOAppCore(getRuntimeData[rpcUrl].bridgeAddress);

            // Set peer address on all other chains for each bridge
            for (uint256 j; j < len; ++j) {
                if (i != j) {
                    bytes32 peerAddress = bytes32(uint256(uint160(getRuntimeData[allChains[j].rpc_url].bridgeAddress)));
                    uint32 peerEid = allChains[j].chainId;

                    // Only set peer if not already configured
                    if (bridge.peers(peerEid) != peerAddress) {
                        bridge.setPeer(peerEid, peerAddress);
                    }
                }
            }

            vm.stopBroadcast();
        }
    }
 
    // -----------
    // Core Deploy
    // -----------

    function _deployAndConfigure(NetworkData memory networkData) internal returns (address token, address migrator, address bridge) {
        address legacyTelcoin;
        if (LEGACY_TEL == address(0)) legacyTelcoin = _deployLegacyTelcoin(networkData.chainName);
        else legacyTelcoin = LEGACY_TEL;

        // 1. Deploy

        token = _deployTelcoinV3(networkData.chainName, networkData.initialSupply);
        migrator = _deployTelcoinMigration(networkData.chainName, legacyTelcoin, token, networkData.initialSupply);
        bridge = _deployTelcoinBridge(networkData.chainName, token, networkData.lz_endpoint);

        // 2. Configure

        TelcoinV3 telcoinContract = TelcoinV3(token);
        if (!telcoinContract.hasRole(MINTER_ROLE, address(bridge))) {
            telcoinContract.grantRole(MINTER_ROLE, address(bridge));
        }
        if (!telcoinContract.hasRole(BURNER_ROLE, address(bridge))) {
            telcoinContract.grantRole(BURNER_ROLE, address(bridge));
        }
    }

    // ----------------------
    // Individual Deployments
    // ----------------------

    function _deployLegacyTelcoin(string memory chainName) internal returns (address) {
        // Deploy legacy Telcoin using deployCode to handle incompatible pragma (^0.4.18)
        // Constructor takes a distributor address that receives the total supply
        address legacyTelcoin = deployCode("Telcoin.sol:Telcoin", abi.encode(_deployer));
        console.log("Legacy Telcoin deployed at:", legacyTelcoin);

        _saveDeploymentAddress(chainName, "TelcoinLegacy", legacyTelcoin);

        return legacyTelcoin;
    }

    function _deployTelcoinV3(string memory chainName, uint256 initSupply) internal returns (address) {
        // build deployment params
        bytes memory telcoinV3Params = abi.encode(
            initSupply,
            ADMIN,
            _computeCreate3Address(SaltMath.guardSalt(_deployer, RAW_TELCOIN_MIGRATION_SALT))
        );
        // build init bytecode
        bytes memory telcoinV3Bytecode = bytes.concat(type(TelcoinV3).creationCode, telcoinV3Params);
        // deploy with params
        (address contractAddress, bool newDeployment) = _deployCreate3(RAW_TELCOIN_V3_SALT, telcoinV3Bytecode, _deployer);

        if (newDeployment) {
            console.log("Deployed TelcoinV3 at address:", contractAddress);
            _saveDeploymentAddress(chainName, "TelcoinV3", contractAddress);
        } else {
            console.log("TelcoinV3 already deployed at:", contractAddress);
            console.log("Skipping...");
        }

        return contractAddress;
    }

    function _deployTelcoinMigration(string memory chainName, address legacyToken, address telcoinV3, uint256 initSupply) internal returns (address) {
        // build deployment params
        bytes memory telcoinMigratorParams = abi.encode(
            legacyToken,
            telcoinV3,
            ADMIN,
            MIGRATION_DURATION
        );
        // build init bytecode
        bytes memory telcoinMigratorBytecode = bytes.concat(type(TokenMigration).creationCode, telcoinMigratorParams);
        // deploy with params
        (address contractAddress, bool newDeployment) = _deployCreate3(RAW_TELCOIN_MIGRATION_SALT, telcoinMigratorBytecode, _deployer);

        if (newDeployment) {
            console.log("Deployed Telcoin Migrator at address:", contractAddress);
            require(IERC20(telcoinV3).balanceOf(contractAddress) == initSupply, "Migrator contract did not receive initial tokens");
            _saveDeploymentAddress(chainName, "TelcoinMigration", contractAddress);
        } else {
            console.log("Telcoin Migrator already deployed at:", contractAddress);
            console.log("Skipping...");
        }

        return contractAddress;
    }

    function _deployTelcoinBridge(string memory chainName, address telcoinV3, address endpoint) internal returns (address) {
        // build deployment params
        bytes memory telcoinBridgeParams = abi.encode(
            telcoinV3,
            endpoint,
            ADMIN
        );
        // build init bytecode
        bytes memory telcoinBridgeBytecode = bytes.concat(type(TokenMigration).creationCode, telcoinBridgeParams);
        // deploy with params
        (address contractAddress, bool newDeployment) = _deployCreate3(RAW_TELCOIN_MIGRATION_SALT, telcoinBridgeBytecode, _deployer);

        if (newDeployment) {
            console.log("Deployed Telcoin Bridge at address:", contractAddress);
            _saveDeploymentAddress(chainName, "TelcoinBridge", contractAddress);
        } else {
            console.log("Telcoin Bridge already deployed at:", contractAddress);
            console.log("Skipping...");
        }

        return contractAddress;
    }
}