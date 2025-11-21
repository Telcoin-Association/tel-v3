// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {TelcoinV3} from "../src/TelcoinV3.sol";
import {TokenMigration} from "../src/TokenMigration.sol";

interface ICREATE3Factory {
    function deploy(
        bytes32 salt,
        bytes memory bytecode
    ) external returns (address);

    function getDeployed(
        address deployer,
        bytes32 salt
    ) external view returns (address);
}

contract DeployScript is Script {
    // Axelar CREATE3 Factory on Ethereum mainnet
    ICREATE3Factory constant CREATE3_FACTORY =
        ICREATE3Factory(0xba5Ed099633D3B313e4D5F7bdc1305d3c28ba5Ed);

    // Existing OldToken token address
    address constant OLD_TOKEN_ADDRESS = address(0); // TODO: Replace with actual OldToken address

    function run() external {
        // Get private key from environment
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        /// @dev these salts can theoretically be frontrun after deployment to an initial chain
        /// attacker can watch for initial deployment tx, extract salts from tx, and deploy to other chains
        /// this type of attack is sometimes fine with create2 but with create3 the deterministic address 
        /// is not reliant on fixed contract bytecode + constructor args, so risk is higher since attacker
        /// can provide different constructor args or even use entirely new malicious contract bytecode
        /// @dev double check if we committed to custom-linked ITS tokenID, in case the deployment salt needs to be Axelar-compliant
        // Generate random salts for CREATE3
        bytes32 telcoinV3Salt = keccak256(
            abi.encodePacked("TelcoinV3", block.timestamp, deployer)
        );
        bytes32 migrationSalt = keccak256(
            abi.encodePacked("TokenMigration", block.timestamp, deployer)
        );

        // Get predicted addresses
        address predictedTelcoinV3 = CREATE3_FACTORY.getDeployed(
            deployer,
            telcoinV3Salt
        );
        address predictedMigration = CREATE3_FACTORY.getDeployed(
            deployer,
            migrationSalt
        );

        console.log("Predicted TelcoinV3 address:", predictedTelcoinV3);
        console.log("Predicted Migration address:", predictedMigration);

        // Deploy Migration contract first
        bytes memory migrationBytecode = abi.encodePacked(
            type(TokenMigration).creationCode,
            abi.encode(OLD_TOKEN_ADDRESS, predictedTelcoinV3)
        );

        address migrationAddress = CREATE3_FACTORY.deploy(
            migrationSalt,
            migrationBytecode
        );
        console.log("Migration contract deployed at:", migrationAddress);
        require(
            migrationAddress == predictedMigration,
            "Migration address mismatch"
        );

        // Deploy TelcoinV3 token with migration contract as initial mint recipient
        bytes memory telcoinV3Bytecode = abi.encodePacked(
            type(TelcoinV3).creationCode,
            abi.encode(migrationAddress)
        );

        address telcoinV3Address = CREATE3_FACTORY.deploy(
            telcoinV3Salt,
            telcoinV3Bytecode
        );
        console.log("TelcoinV3 token deployed at:", telcoinV3Address);
        require(
            telcoinV3Address == predictedTelcoinV3,
            "TelcoinV3 address mismatch"
        );

        // Verify deployment
        TelcoinV3 token = TelcoinV3(telcoinV3Address);
        console.log("TelcoinV3 total supply:", token.totalSupply());
        console.log(
            "Migration contract TelcoinV3 balance:",
            token.balanceOf(migrationAddress)
        );

        vm.stopBroadcast();

        // Log deployment info
        console.log("\n=== Deployment Complete ===");
        console.log("TelcoinV3 Token:", telcoinV3Address);
        console.log("Migration Contract:", migrationAddress);
        console.log("OldToken Token (existing):", OLD_TOKEN_ADDRESS);
        console.log("\nSalts used:");
        console.log("Telcoin V3 Salt:", vm.toString(telcoinV3Salt));
        console.log("Migration Salt:", vm.toString(migrationSalt));
    }
}

// Alternative deployment script with better salt management
contract DeployWithCustomSalt is Script {
    ICREATE3Factory constant CREATE3_FACTORY =
        ICREATE3Factory(0xba5Ed099633D3B313e4D5F7bdc1305d3c28ba5Ed);
    address constant OLD_TOKEN_ADDRESS = address(0); // TODO: Replace with actual OldToken address

    function run(
        string memory telcoinV3SaltString,
        string memory migrationSaltString
    ) external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        // Use provided salt strings or generate random ones
        bytes32 telcoinV3Salt = bytes(telcoinV3SaltString).length > 0
            ? keccak256(abi.encodePacked(telcoinV3SaltString))
            : keccak256(
                abi.encodePacked(
                    "TelcoinV3",
                    block.timestamp,
                    block.prevrandao,
                    deployer
                )
            );

        bytes32 migrationSalt = bytes(migrationSaltString).length > 0
            ? keccak256(abi.encodePacked(migrationSaltString))
            : keccak256(
                abi.encodePacked(
                    "Migration",
                    block.timestamp,
                    block.prevrandao,
                    deployer
                )
            );

        vm.startBroadcast(deployerPrivateKey);

        // Get predicted addresses
        address predictedTelcoinV3 = CREATE3_FACTORY.getDeployed(
            deployer,
            telcoinV3Salt
        );
        address predictedMigration = CREATE3_FACTORY.getDeployed(
            deployer,
            migrationSalt
        );

        console.log("Deploying with salts:");
        console.log("TelcoinV3 Salt:", vm.toString(telcoinV3Salt));
        console.log("Migration Salt:", vm.toString(migrationSalt));
        console.log("\nPredicted addresses:");
        console.log("TelcoinV3:", predictedTelcoinV3);
        console.log("Migration:", predictedMigration);

        // Deploy contracts
        bytes memory migrationBytecode = abi.encodePacked(
            type(TokenMigration).creationCode,
            abi.encode(OLD_TOKEN_ADDRESS, predictedTelcoinV3)
        );

        address migrationAddress = CREATE3_FACTORY.deploy(
            migrationSalt,
            migrationBytecode
        );

        bytes memory telcoinV3Bytecode = abi.encodePacked(
            type(TelcoinV3).creationCode,
            abi.encode(migrationAddress)
        );

        address telcoinV3Address = CREATE3_FACTORY.deploy(
            telcoinV3Salt,
            telcoinV3Bytecode
        );

        vm.stopBroadcast();

        console.log("\n=== Deployment Complete ===");
        console.log("TelcoinV3 Token:", telcoinV3Address);
        console.log("Migration Contract:", migrationAddress);
    }
}
