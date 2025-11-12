// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "../src/NewToken.sol";
import "../src/TokenMigration.sol";

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
        bytes32 NewTokenSalt = keccak256(
            abi.encodePacked("NewToken", block.timestamp, deployer)
        );
        bytes32 migrationSalt = keccak256(
            abi.encodePacked("TokenMigration", block.timestamp, deployer)
        );

        // Get predicted addresses
        address predictedNewToken = CREATE3_FACTORY.getDeployed(
            deployer,
            NewTokenSalt
        );
        address predictedMigration = CREATE3_FACTORY.getDeployed(
            deployer,
            migrationSalt
        );

        console.log("Predicted NewToken address:", predictedNewToken);
        console.log("Predicted Migration address:", predictedMigration);

        // Deploy Migration contract first
        bytes memory migrationBytecode = abi.encodePacked(
            type(TokenMigration).creationCode,
            abi.encode(OLD_TOKEN_ADDRESS, predictedNewToken)
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

        // Deploy NewToken token with migration contract as initial mint recipient
        bytes memory NewTokenBytecode = abi.encodePacked(
            type(NewToken).creationCode,
            abi.encode(migrationAddress)
        );

        address NewTokenAddress = CREATE3_FACTORY.deploy(
            NewTokenSalt,
            NewTokenBytecode
        );
        console.log("NewToken token deployed at:", NewTokenAddress);
        require(
            NewTokenAddress == predictedNewToken,
            "NewToken address mismatch"
        );

        // Verify deployment
        NewToken token = NewToken(NewTokenAddress);
        console.log("NewToken total supply:", token.totalSupply());
        console.log(
            "Migration contract NewToken balance:",
            token.balanceOf(migrationAddress)
        );

        vm.stopBroadcast();

        // Log deployment info
        console.log("\n=== Deployment Complete ===");
        console.log("NewToken Token:", NewTokenAddress);
        console.log("Migration Contract:", migrationAddress);
        console.log("OldToken Token (existing):", OldToken_ADDRESS);
        console.log("\nSalts used:");
        console.log("NewToken Salt:", vm.toString(NewTokenSalt));
        console.log("Migration Salt:", vm.toString(migrationSalt));
    }
}

// Alternative deployment script with better salt management
contract DeployWithCustomSalt is Script {
    ICREATE3Factory constant CREATE3_FACTORY =
        ICREATE3Factory(0xba5Ed099633D3B313e4D5F7bdc1305d3c28ba5Ed);
    address constant OLD_TOKEN_ADDRESS = address(0); // TODO: Replace with actual OldToken address

    function run(
        string memory NewTokenSaltString,
        string memory migrationSaltString
    ) external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        // Use provided salt strings or generate random ones
        bytes32 NewTokenSalt = bytes(NewTokenSaltString).length > 0
            ? keccak256(abi.encodePacked(NewTokenSaltString))
            : keccak256(
                abi.encodePacked(
                    "NewToken",
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
        address predictedNewToken = CREATE3_FACTORY.getDeployed(
            deployer,
            NewTokenSalt
        );
        address predictedMigration = CREATE3_FACTORY.getDeployed(
            deployer,
            migrationSalt
        );

        console.log("Deploying with salts:");
        console.log("NewToken Salt:", vm.toString(NewTokenSalt));
        console.log("Migration Salt:", vm.toString(migrationSalt));
        console.log("\nPredicted addresses:");
        console.log("NewToken:", predictedNewToken);
        console.log("Migration:", predictedMigration);

        // Deploy contracts
        bytes memory migrationBytecode = abi.encodePacked(
            type(TokenMigration).creationCode,
            abi.encode(OLD_TOKEN_ADDRESS, predictedNewToken)
        );

        address migrationAddress = CREATE3_FACTORY.deploy(
            migrationSalt,
            migrationBytecode
        );

        bytes memory NewTokenBytecode = abi.encodePacked(
            type(NewToken).creationCode,
            abi.encode(migrationAddress)
        );

        address NewTokenAddress = CREATE3_FACTORY.deploy(
            NewTokenSalt,
            NewTokenBytecode
        );

        vm.stopBroadcast();

        console.log("\n=== Deployment Complete ===");
        console.log("NewToken Token:", NewTokenAddress);
        console.log("Migration Contract:", migrationAddress);
    }
}
