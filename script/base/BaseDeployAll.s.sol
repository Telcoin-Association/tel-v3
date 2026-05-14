// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {VmSafe} from "forge-std/Vm.sol";
import {console} from "forge-std/console.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IOAppCore} from "@layerzerolabs/oapp-evm/contracts/oapp/interfaces/IOAppCore.sol";
import {IMintableBurnable} from "@layerzerolabs/oft-evm/contracts/interfaces/IMintableBurnable.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {DeployUtility} from "../utils/DeployUtility.sol";
import {TelcoinV3} from "../../src/TelcoinV3.sol";
import {TelcoinBridge} from "../../src/TelcoinBridge.sol";
import {NativeBridge} from "../../src/NativeBridge.sol";
import {MintBurnWrapper} from "../../src/MintBurnWrapper.sol";
import {TokenMigration} from "../../src/TokenMigration.sol";
import {MigrationVault} from "../../src/MigrationVault.sol";
import {SaltMath} from "../libraries/SaltMath.sol";
import {Roles} from "../../src/helpers/Roles.sol";

/**
 * @title BaseDeployAll
 * @author chasebrownn
 * @notice Abstract base script for multi-chain deployment of all Telcoin V3 contracts.
 *
 * @dev Children inherit this and populate configuration in setUp():
 *      - `_admin` address (EOA or multisig)
 *      - CREATE3 salts
 *      - supply/duration parameters
 *      - `allChains` array with per-chain NetworkData
 *
 *      Deployment order per chain:
 *      1. Legacy Telcoin (if legacyTel == address(0), testnet only)
 *      2. TelcoinV3
 *      3. TokenMigration
 *      4. MigrationVault (UUPS proxy)
 *      5. MintBurnWrapper (satellite chains only)
 *      6. TelcoinBridge (satellite chains) OR NativeBridge (main chain)
 *      7. Role grants + bridge authorization
 *
 *      After all chains deployed:
 *      8. Configure LayerZero peers between all bridge contracts
 *
 *      Output: Deployment addresses saved to `deployments/<chainName>.json`
 */
abstract contract BaseDeployAll is DeployUtility, Roles {
    // ---------
    // Variables
    // ---------

    /// @dev Children MUST set these in setUp()
    address internal _admin;
    uint256 internal _migrationDuration;
    uint256 internal _withdrawalDelay;

    /// @dev CREATE3 salts — children MUST set these in setUp()
    bytes32 internal _telcoinV3Salt;
    bytes32 internal _migrationSalt;
    bytes32 internal _migrationVaultImplSalt;
    bytes32 internal _migrationVaultProxySalt;
    bytes32 internal _mintBurnWrapperSalt;
    bytes32 internal _bridgeSalt;
    bytes32 internal _nativeBridgeSalt;

    NetworkData[] internal allChains;
    mapping(string rpc => RuntimeData) internal getRuntimeData;

    struct NetworkData {
        string chainName;
        string rpcUrl;
        address lzEndpoint;
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
        address migrationVaultAddress;
        address wrapperAddress;
        address bridgeAddress;
    }

    // ------
    // Script
    // ------

    /// @notice Deploys all contracts to every configured chain, then wires LayerZero peers.
    function run() public {

        // Deploy
        uint256 len = allChains.length;
        for (uint256 i; i < len; ++i) {
            string memory rpcUrl = allChains[i].rpcUrl;

            vm.createSelectFork(rpcUrl);
            vm.startBroadcast(_pk);

            console.log("Deploying for chain:", allChains[i].chainName);

            (
                address tokenAddress,
                address migratorAddress,
                address migrationVaultAddress,
                address wrapperAddress,
                address bridgeAddress
            ) = _deployAndConfigure(allChains[i]);

            // store in getRuntimeData mapping
            getRuntimeData[rpcUrl] = RuntimeData({
                forkId: i,
                tokenAddress: tokenAddress,
                migrationAddress: migratorAddress,
                migrationVaultAddress: migrationVaultAddress,
                wrapperAddress: wrapperAddress,
                bridgeAddress: bridgeAddress
            });

            vm.stopBroadcast();
        }

        // Configure peers
        for (uint256 i; i < len; ++i) {
            string memory rpcUrl = allChains[i].rpcUrl;

            vm.selectFork(getRuntimeData[rpcUrl].forkId);
            vm.startBroadcast(_pk);

            IOAppCore bridge = IOAppCore(getRuntimeData[rpcUrl].bridgeAddress);

            // Set peer address on all other chains for each bridge
            for (uint256 j; j < len; ++j) {
                if (i != j) {
                    bytes32 peerAddress = bytes32(uint256(uint160(getRuntimeData[allChains[j].rpcUrl].bridgeAddress)));
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
     *
     *      For `mainChain == true`: deploys NativeBridge (no MintBurnWrapper needed).
     *      For satellite chains: deploys MintBurnWrapper + TelcoinBridge.
     *
     * @param networkData Chain-specific parameters (name, endpoint, initial supply, etc.)
     * @return token          Deployed TelcoinV3 address
     * @return migrator       Deployed TokenMigration address
     * @return migrationVault Deployed MigrationVault proxy address
     * @return wrapper        Deployed MintBurnWrapper address (address(0) on main chain)
     * @return bridge         Deployed TelcoinBridge or NativeBridge address
     */
    function _deployAndConfigure(NetworkData memory networkData)
        internal
        returns (address token, address migrator, address migrationVault, address wrapper, address bridge)
    {
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

        // 1. Deploy core contracts

        address legacyTelcoin = networkData.legacyTel;
        if (legacyTelcoin == address(0)) {
            legacyTelcoin = _deployLegacyTelcoin();
        }

        token = _deployTelcoinV3(networkData.initialSupply);
        migrator = _deployTelcoinMigration(legacyTelcoin, token);
        migrationVault = _deployMigrationVault(legacyTelcoin, token);

        // 2. Deploy bridge infrastructure (chain-type dependent)

        if (networkData.mainChain) {
            // Main chain: NativeBridge only, no wrapper needed
            bridge = _deployNativeBridge(networkData.lzEndpoint);
        } else {
            // Satellite chain: MintBurnWrapper + TelcoinBridge
            wrapper = _deployMintBurnWrapper(token);
            bridge = _deployTelcoinBridge(token, wrapper, networkData.lzEndpoint);
        }

        // 3. Configure roles on TelcoinV3

        TelcoinV3 telcoinContract = TelcoinV3(token);

        if (!networkData.mainChain) {
            // MintBurnWrapper holds the burn/mint roles (satellite only)
            if (!telcoinContract.hasRole(MINTER_ROLE, wrapper)) {
                telcoinContract.grantRole(MINTER_ROLE, wrapper);
            }
            if (!telcoinContract.hasRole(BURNER_ROLE, wrapper)) {
                telcoinContract.grantRole(BURNER_ROLE, wrapper);
            }
        }

        // TokenMigration mints directly on this chain
        if (!telcoinContract.hasRole(MINTER_ROLE, migrator)) {
            telcoinContract.grantRole(MINTER_ROLE, migrator);
        }
        if (!telcoinContract.hasRole(PAUSER_ROLE, _admin)) {
            telcoinContract.grantRole(PAUSER_ROLE, _admin);
        }
        if (!telcoinContract.hasRole(UNPAUSER_ROLE, _admin)) {
            telcoinContract.grantRole(UNPAUSER_ROLE, _admin);
        }

        // 4. Authorize bridge on MintBurnWrapper (satellite only)

        if (!networkData.mainChain) {
            MintBurnWrapper wrapperContract = MintBurnWrapper(wrapper);
            if (wrapperContract.bridge() != bridge) {
                wrapperContract.authorizeBridge(bridge);
            }
        }

        // 5. Save Addresses (If broadcast)

        if (vm.isContext(VmSafe.ForgeContext.ScriptBroadcast)) {
            _saveDeploymentAddress(networkData.chainName, "TelcoinLegacy", legacyTelcoin);
            _saveDeploymentAddress(networkData.chainName, "TelcoinV3", token);
            _saveDeploymentAddress(networkData.chainName, "TelcoinMigration", migrator);
            _saveDeploymentAddress(networkData.chainName, "MigrationVault", migrationVault);

            if (networkData.mainChain) {
                _saveDeploymentAddress(networkData.chainName, "NativeBridge", bridge);
            } else {
                _saveDeploymentAddress(networkData.chainName, "MintBurnWrapper", wrapper);
                _saveDeploymentAddress(networkData.chainName, "TelcoinBridge", bridge);
            }
        }
    }

    // ----------------------
    // Individual Deployments
    // ----------------------

    /// @notice Deploys legacy Telcoin (^0.4.18) using deployCode to bypass pragma incompatibility.
    function _deployLegacyTelcoin() internal returns (address) {
        address legacyTelcoin = deployCode("Telcoin.sol:Telcoin", abi.encode(_deployer));
        console.log("Legacy Telcoin deployed at:", legacyTelcoin);
        return legacyTelcoin;
    }

    /// @notice Deploys TelcoinV3 via CREATE3. Mints `initSupply` to _admin at construction.
    function _deployTelcoinV3(uint256 initSupply) internal returns (address) {
        bytes memory telcoinV3Params = abi.encode(initSupply, _admin);
        bytes memory telcoinV3Bytecode = bytes.concat(type(TelcoinV3).creationCode, telcoinV3Params);
        (address contractAddress, bool newDeployment) = _deployCreate3(_telcoinV3Salt, telcoinV3Bytecode, _deployer);

        if (newDeployment) {
            console.log("Deployed TelcoinV3 at address:", contractAddress);
        } else {
            console.log("TelcoinV3 already deployed at:", contractAddress);
        }

        return contractAddress;
    }

    /// @notice Deploys TokenMigration via CREATE3.
    function _deployTelcoinMigration(address legacyToken, address telcoinV3) internal returns (address) {
        bytes memory telcoinMigratorParams = abi.encode(
            legacyToken,
            telcoinV3,
            _admin,
            _migrationDuration,
            _withdrawalDelay
        );
        bytes memory telcoinMigratorBytecode = bytes.concat(type(TokenMigration).creationCode, telcoinMigratorParams);
        (address contractAddress, bool newDeployment) = _deployCreate3(_migrationSalt, telcoinMigratorBytecode, _deployer);

        if (newDeployment) {
            console.log("Deployed TokenMigration at address:", contractAddress);
        } else {
            console.log("TokenMigration already deployed at:", contractAddress);
        }

        return contractAddress;
    }

    /// @notice Deploys MigrationVault implementation + ERC1967Proxy via CREATE3.
    function _deployMigrationVault(address legacyToken, address telcoinV3) internal returns (address) {
        // Deploy implementation
        bytes memory implParams = abi.encode(legacyToken, telcoinV3);
        bytes memory implBytecode = bytes.concat(type(MigrationVault).creationCode, implParams);
        (address implAddress, bool implNew) = _deployCreate3(_migrationVaultImplSalt, implBytecode, _deployer);

        if (implNew) {
            console.log("Deployed MigrationVault impl at:", implAddress);
        } else {
            console.log("MigrationVault impl already deployed at:", implAddress);
        }

        // Deploy proxy
        bytes memory initData = abi.encodeCall(MigrationVault.initialize, (_admin, _admin, _admin));
        bytes memory proxyParams = abi.encode(implAddress, initData);
        bytes memory proxyBytecode = bytes.concat(type(ERC1967Proxy).creationCode, proxyParams);
        (address proxyAddress, bool proxyNew) = _deployCreate3(_migrationVaultProxySalt, proxyBytecode, _deployer);

        if (proxyNew) {
            console.log("Deployed MigrationVault proxy at:", proxyAddress);
        } else {
            console.log("MigrationVault proxy already deployed at:", proxyAddress);
        }

        return proxyAddress;
    }

    /// @notice Deploys MintBurnWrapper via CREATE3. Satellite chains only.
    function _deployMintBurnWrapper(address telcoinV3) internal returns (address) {
        bytes memory wrapperParams = abi.encode(telcoinV3, _admin);
        bytes memory wrapperBytecode = bytes.concat(type(MintBurnWrapper).creationCode, wrapperParams);
        (address contractAddress, bool newDeployment) = _deployCreate3(_mintBurnWrapperSalt, wrapperBytecode, _deployer);

        if (newDeployment) {
            console.log("Deployed MintBurnWrapper at address:", contractAddress);
        } else {
            console.log("MintBurnWrapper already deployed at:", contractAddress);
        }

        return contractAddress;
    }

    /// @notice Deploys TelcoinBridge via CREATE3. Satellite chains only.
    function _deployTelcoinBridge(address telcoinV3, address wrapper, address endpoint) internal returns (address) {
        bytes memory telcoinBridgeParams = abi.encode(
            telcoinV3,
            IMintableBurnable(wrapper),
            endpoint,
            _admin
        );
        bytes memory telcoinBridgeBytecode = bytes.concat(type(TelcoinBridge).creationCode, telcoinBridgeParams);
        (address contractAddress, bool newDeployment) = _deployCreate3(_bridgeSalt, telcoinBridgeBytecode, _deployer);

        if (newDeployment) {
            console.log("Deployed TelcoinBridge at address:", contractAddress);
        } else {
            console.log("TelcoinBridge already deployed at:", contractAddress);
        }

        return contractAddress;
    }

    /// @notice Deploys NativeBridge via CREATE3. Main chain only.
    function _deployNativeBridge(address endpoint) internal returns (address) {
        bytes memory nativeBridgeParams = abi.encode(endpoint, _admin);
        bytes memory nativeBridgeBytecode = bytes.concat(type(NativeBridge).creationCode, nativeBridgeParams);
        (address contractAddress, bool newDeployment) = _deployCreate3(_nativeBridgeSalt, nativeBridgeBytecode, _deployer);

        if (newDeployment) {
            console.log("Deployed NativeBridge at address:", contractAddress);
        } else {
            console.log("NativeBridge already deployed at:", contractAddress);
        }

        return contractAddress;
    }
}
