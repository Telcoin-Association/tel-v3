// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {VmSafe} from "forge-std/Vm.sol";
import {console} from "forge-std/console.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IOAppCore} from "@layerzerolabs/oapp-evm/contracts/oapp/interfaces/IOAppCore.sol";
import {IMintableBurnable} from "@layerzerolabs/oft-evm/contracts/interfaces/IMintableBurnable.sol";
import {DeployUtility} from "../utils/DeployUtility.sol";
import {TelcoinV3} from "../../src/TelcoinV3.sol";
import {TelcoinBridge} from "../../src/TelcoinBridge.sol";
import {MintBurnWrapper} from "../../src/MintBurnWrapper.sol";
import {TokenMigration} from "../../src/TokenMigration.sol";
import {SaltMath} from "../libraries/SaltMath.sol";
import {Roles} from "../../src/helpers/Roles.sol";
import "../utils/Constants.sol";
import "../utils/Addresses.sol";

/**
 * @title DeployAllToTestnet
 * @author chasebrownn
 * @dev This script performs a multi-chain deployment of:
 *      - Legacy Telcoin (mock for testing migration flow)
 *      - TelcoinV3 (new 18-decimal token)
 *      - TokenMigration (handles legacy -> V3 token migration)
 *      - MintBurnWrapper (delegates MINTER_ROLE/BURNER_ROLE to authorized bridges)
 *      - TelcoinBridge (LayerZero V2 MintBurnOFTAdapter, authorized on MintBurnWrapper)
 *
 *      NOTE: NativeBridge (NativeOFTAdapter for TelcoinNetwork) is not deployed here because
 *      no TelcoinNetwork testnet exists. It is a mainnet-only concern.
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
 * forge script script/testnet/DeployAllToTestnet.s.sol --multi --broadcast --verify -vvvv
 * ```
 *
 * ## Deployment Order
 *
 * For each chain:
 * 1. Deploy Legacy Telcoin (if LEGACY_TEL == address(0))
 * 2. Deploy TelcoinV3
 * 3. Deploy TokenMigration
 * 4. Deploy MintBurnWrapper (wraps TelcoinV3 mint/burn for the bridge)
 * 5. Deploy TelcoinBridge (takes MintBurnWrapper as minterBurner)
 * 6. Grant MINTER_ROLE and BURNER_ROLE to MintBurnWrapper on TelcoinV3
 * 7. Grant MINTER_ROLE to TokenMigration on TelcoinV3
 * 8. Authorize TelcoinBridge on MintBurnWrapper
 *
 * After all chains deployed:
 * 9. Configure LayerZero peers between all bridge contracts
 *
 * ## Output
 *
 * Deployment addresses are saved to `deployments/<chainName>.json`
 */
contract DeployAllToTestnet is DeployUtility, Roles {
    // ---------
    // Variables
    // ---------

    /// @dev TODO: Configure all constants

    bytes32 internal constant RAW_TELCOIN_V3_SALT = keccak256("RAW_TELCOIN_V3_SALT_V2");
    bytes32 internal constant RAW_TELCOIN_MIGRATION_SALT = keccak256("RAW_TELCOIN_MIGRATION_SALT_V2");
    bytes32 internal constant RAW_MINT_BURN_WRAPPER_SALT = keccak256("RAW_MINT_BURN_WRAPPER_SALT_V2");
    bytes32 internal constant RAW_TELCOIN_BRIDGE_SALT = keccak256("RAW_TELCOIN_BRIDGE_SALT_V2");

    uint256 internal constant INITIAL_TELV3_SUPPLY = 100_000_000 ether; // initial supply of 100M tokens per chain
    uint256 internal constant MIGRATION_DURATION = 365 * 1 days;

    address internal TESTNET_ADMIN = 0x28937C70A08390c55b65Eab24600c4b059A50991;

    NetworkData[] internal allChains;
    mapping(string rpc => RuntimeData) internal getRuntimeData;

    struct NetworkData {
        string chainName;
        string rpc_url;
        address lz_endpoint;
        uint32 lzChainId;
        uint256 evmChainId;
        address legacyTel;
        uint256 initialSupply;
        bool mainChain;
    }

    struct RuntimeData {
        uint256 forkId;
        address tokenAddress;
        address migrationAddress;
        address wrapperAddress;
        address bridgeAddress;
    }

    // -----
    // SetUp
    // -----
    
    /// @notice Loads the deployer key and populates the chain list before run().
    function setUp() public {
        _setup();

        /// @dev TODO: Configure all chain data

        allChains.push(NetworkData(
            {
                chainName: "eth-sepolia",
                rpc_url: vm.envString("ETH_SEPOLIA_RPC_URL"),
                lz_endpoint: ETH_SEPOLIA_LZ_ENDPOINT_V2,
                lzChainId: ETH_SEPOLIA_LZ_CHAIN_ID_V2,
                evmChainId: ETH_SEPOLIA_CHAIN_ID,
                legacyTel: _loadDeploymentAddress("eth-sepolia", "TelcoinLegacy"),
                initialSupply: 100_000_000 ether,
                mainChain: false
            }
        ));
        allChains.push(NetworkData(
            {
                chainName: "base-sepolia",
                rpc_url: vm.envString("BASE_SEPOLIA_RPC_URL"),
                lz_endpoint: BASE_SEPOLIA_LZ_ENDPOINT_V2,
                lzChainId: BASE_SEPOLIA_LZ_CHAIN_ID_V2,
                evmChainId: BASE_SEPOLIA_CHAIN_ID,
                legacyTel: _loadDeploymentAddress("base-sepolia", "TelcoinLegacy"),
                initialSupply: 100_000_000 ether,
                mainChain: false
            }
        ));
    }

    // ------
    // Script
    // ------

    /// @notice Deploys all contracts to every configured chain, then wires LayerZero peers.
    function run() public {

        // Deploy
        uint256 len = allChains.length;
        for (uint256 i; i < len; ++i) {
            string memory rpcUrl = allChains[i].rpc_url;

            vm.createSelectFork(rpcUrl);
            vm.startBroadcast(_pk);

            console.log("Deploying for chain:", allChains[i].chainName);

            (address tokenAddress, address migratorAddress, address wrapperAddress, address bridgeAddress) = _deployAndConfigure(allChains[i]);

            // store in getRuntimeData mapping
            getRuntimeData[rpcUrl] = RuntimeData({
                forkId: i,
                tokenAddress: tokenAddress,
                migrationAddress: migratorAddress,
                wrapperAddress: wrapperAddress,
                bridgeAddress: bridgeAddress
            });

            vm.stopBroadcast();
        }

        // Configure peers
        for (uint256 i; i < len; ++i) {
            string memory rpcUrl = allChains[i].rpc_url;

            vm.selectFork(getRuntimeData[rpcUrl].forkId);
            vm.startBroadcast(_pk);

            IOAppCore bridge = IOAppCore(getRuntimeData[rpcUrl].bridgeAddress);

            // Set peer address on all other chains for each bridge
            for (uint256 j; j < len; ++j) {
                if (i != j) {
                    bytes32 peerAddress = bytes32(uint256(uint160(getRuntimeData[allChains[j].rpc_url].bridgeAddress)));
                    uint32 peerEid = allChains[j].lzChainId;

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

    /**
     * @notice Deploys and fully configures all contracts for a single chain.
     * @dev Skips any contract already deployed at the expected CREATE3 address.
     *      Role grants and bridge authorization are also idempotent.
     * @param networkData Chain-specific parameters (name, endpoint, initial supply, etc.)
     * @return token     Deployed TelcoinV3 address
     * @return migrator  Deployed TokenMigration address
     * @return wrapper   Deployed MintBurnWrapper address
     * @return bridge    Deployed TelcoinBridge address
     */
    function _deployAndConfigure(NetworkData memory networkData) internal returns (address token, address migrator, address wrapper, address bridge) {

        // 0. Chain ID sanity check

        require(
            block.chainid == networkData.evmChainId,
            string.concat(
                "Chain ID mismatch: expected ",
                vm.toString(networkData.evmChainId),
                " but connected to ",
                vm.toString(block.chainid)
            )
        );

        // 1. Deploy

        address legacyTelcoin = networkData.legacyTel;
        if (legacyTelcoin == address(0)) {
            legacyTelcoin = _deployLegacyTelcoin();
        }

        token = _deployTelcoinV3(networkData.initialSupply);
        migrator = _deployTelcoinMigration(legacyTelcoin, token);
        wrapper = _deployMintBurnWrapper(token);
        bridge = _deployTelcoinBridge(token, wrapper, networkData.lz_endpoint);

        // 2. Configure roles on TelcoinV3

        TelcoinV3 telcoinContract = TelcoinV3(token);

        // MintBurnWrapper holds the burn/mint roles
        if (!telcoinContract.hasRole(MINTER_ROLE, wrapper)) {
            telcoinContract.grantRole(MINTER_ROLE, wrapper);
        }
        if (!telcoinContract.hasRole(BURNER_ROLE, wrapper)) {
            telcoinContract.grantRole(BURNER_ROLE, wrapper);
        }
        // TokenMigration mints directly on this chain
        if (!telcoinContract.hasRole(MINTER_ROLE, migrator)) {
            telcoinContract.grantRole(MINTER_ROLE, migrator);
        }
        if (!telcoinContract.hasRole(PAUSER_ROLE, TESTNET_ADMIN)) {
            telcoinContract.grantRole(PAUSER_ROLE, TESTNET_ADMIN);
        }
        if (!telcoinContract.hasRole(UNPAUSER_ROLE, TESTNET_ADMIN)) {
            telcoinContract.grantRole(UNPAUSER_ROLE, TESTNET_ADMIN);
        }

        // 3. Authorize bridge on MintBurnWrapper

        MintBurnWrapper wrapperContract = MintBurnWrapper(wrapper);
        if (wrapperContract.bridge() != bridge) {
            wrapperContract.authorizeBridge(bridge);
        }

        // 4. Save Addresses (If broadcast)

        if (vm.isContext(VmSafe.ForgeContext.ScriptBroadcast)) {
            _saveDeploymentAddress(networkData.chainName, "TelcoinLegacy", legacyTelcoin);
            _saveDeploymentAddress(networkData.chainName, "TelcoinV3", token);
            _saveDeploymentAddress(networkData.chainName, "TelcoinMigration", migrator);
            _saveDeploymentAddress(networkData.chainName, "MintBurnWrapper", wrapper);
            _saveDeploymentAddress(networkData.chainName, "TelcoinBridge", bridge);
        }
    }

    // ----------------------
    // Individual Deployments
    // ----------------------

    /// @notice Deploys legacy Telcoin (^0.4.18) using deployCode to bypass pragma incompatibility.
    function _deployLegacyTelcoin() internal returns (address) {
        // Deploy legacy Telcoin using deployCode to handle incompatible pragma (^0.4.18)
        // Constructor takes a distributor address that receives the total supply
        address legacyTelcoin = deployCode("Telcoin.sol:Telcoin", abi.encode(_deployer));
        console.log("Legacy Telcoin deployed at:", legacyTelcoin);

        return legacyTelcoin;
    }

    /// @notice Deploys TelcoinV3 via CREATE3. Mints `initSupply` to TESTNET_ADMIN at construction.
    function _deployTelcoinV3(uint256 initSupply) internal returns (address) {
        // build deployment params
        bytes memory telcoinV3Params = abi.encode(
            initSupply,
            TESTNET_ADMIN
        );
        // build init bytecode
        bytes memory telcoinV3Bytecode = bytes.concat(type(TelcoinV3).creationCode, telcoinV3Params);
        // deploy with params
        (address contractAddress, bool newDeployment) = _deployCreate3(RAW_TELCOIN_V3_SALT, telcoinV3Bytecode, _deployer);

        if (newDeployment) {
            console.log("Deployed TelcoinV3 at address:", contractAddress);
        } else {
            console.log("TelcoinV3 already deployed at:", contractAddress);
        }

        return contractAddress;
    }

    /// @notice Deploys TokenMigration via CREATE3. Grants MINTER_ROLE in _deployAndConfigure.
    function _deployTelcoinMigration(address legacyToken, address telcoinV3) internal returns (address) {
        // build deployment params
        bytes memory telcoinMigratorParams = abi.encode(
            legacyToken,
            telcoinV3,
            TESTNET_ADMIN,
            MIGRATION_DURATION
        );
        // build init bytecode
        bytes memory telcoinMigratorBytecode = bytes.concat(type(TokenMigration).creationCode, telcoinMigratorParams);
        // deploy with params
        (address contractAddress, bool newDeployment) = _deployCreate3(RAW_TELCOIN_MIGRATION_SALT, telcoinMigratorBytecode, _deployer);

        if (newDeployment) {
            console.log("Deployed Telcoin Migrator at address:", contractAddress);
        } else {
            console.log("Telcoin Migrator already deployed at:", contractAddress);
        }

        return contractAddress;
    }

    /// @notice Deploys MintBurnWrapper via CREATE3. Receives MINTER_ROLE/BURNER_ROLE in _deployAndConfigure.
    function _deployMintBurnWrapper(address telcoinV3) internal returns (address) {
        // build deployment params
        bytes memory wrapperParams = abi.encode(
            telcoinV3,
            TESTNET_ADMIN
        );
        // build init bytecode
        bytes memory wrapperBytecode = bytes.concat(type(MintBurnWrapper).creationCode, wrapperParams);
        // deploy with params
        (address contractAddress, bool newDeployment) = _deployCreate3(RAW_MINT_BURN_WRAPPER_SALT, wrapperBytecode, _deployer);

        if (newDeployment) {
            console.log("Deployed MintBurnWrapper at address:", contractAddress);
        } else {
            console.log("MintBurnWrapper already deployed at:", contractAddress);
        }

        return contractAddress;
    }

    /// @notice Deploys TelcoinBridge via CREATE3 with MintBurnWrapper as the minterBurner.
    function _deployTelcoinBridge(address telcoinV3, address wrapper, address endpoint) internal returns (address) {
        // build deployment params
        bytes memory telcoinBridgeParams = abi.encode(
            telcoinV3,
            IMintableBurnable(wrapper),
            endpoint,
            TESTNET_ADMIN
        );
        // build init bytecode
        bytes memory telcoinBridgeBytecode = bytes.concat(type(TelcoinBridge).creationCode, telcoinBridgeParams);
        // deploy with params
        (address contractAddress, bool newDeployment) = _deployCreate3(RAW_TELCOIN_BRIDGE_SALT, telcoinBridgeBytecode, _deployer);

        if (newDeployment) {
            console.log("Deployed Telcoin Bridge at address:", contractAddress);
        } else {
            console.log("Telcoin Bridge already deployed at:", contractAddress);
        }

        return contractAddress;
    }
}