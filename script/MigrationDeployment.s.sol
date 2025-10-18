// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "../src/nGMUNY.sol";
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

    // Existing GMUNY token address (you'll need to set this)
    address constant GMUNY_ADDRESS = address(0); // TODO: Replace with actual GMUNY address

    function run() external {
        // Get private key from environment
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        // Generate random salts for CREATE3
        bytes32 nGMUNYSalt = keccak256(
            abi.encodePacked("nGMUNY", block.timestamp, deployer)
        );
        bytes32 migrationSalt = keccak256(
            abi.encodePacked("TokenMigration", block.timestamp, deployer)
        );

        // Get predicted addresses
        address predictedNGMUNY = CREATE3_FACTORY.getDeployed(
            deployer,
            nGMUNYSalt
        );
        address predictedMigration = CREATE3_FACTORY.getDeployed(
            deployer,
            migrationSalt
        );

        console.log("Predicted nGMUNY address:", predictedNGMUNY);
        console.log("Predicted Migration address:", predictedMigration);

        // Deploy Migration contract first
        bytes memory migrationBytecode = abi.encodePacked(
            type(TokenMigration).creationCode,
            abi.encode(GMUNY_ADDRESS, predictedNGMUNY)
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

        // Deploy nGMUNY token with migration contract as initial mint recipient
        bytes memory nGMUNYBytecode = abi.encodePacked(
            type(nGMUNY).creationCode,
            abi.encode(migrationAddress)
        );

        address nGMUNYAddress = CREATE3_FACTORY.deploy(
            nGMUNYSalt,
            nGMUNYBytecode
        );
        console.log("nGMUNY token deployed at:", nGMUNYAddress);
        require(nGMUNYAddress == predictedNGMUNY, "nGMUNY address mismatch");

        // Verify deployment
        nGMUNY token = nGMUNY(nGMUNYAddress);
        console.log("nGMUNY total supply:", token.totalSupply());
        console.log(
            "Migration contract nGMUNY balance:",
            token.balanceOf(migrationAddress)
        );

        vm.stopBroadcast();

        // Log deployment info
        console.log("\n=== Deployment Complete ===");
        console.log("nGMUNY Token:", nGMUNYAddress);
        console.log("Migration Contract:", migrationAddress);
        console.log("GMUNY Token (existing):", GMUNY_ADDRESS);
        console.log("\nSalts used:");
        console.log("nGMUNY Salt:", vm.toString(nGMUNYSalt));
        console.log("Migration Salt:", vm.toString(migrationSalt));
    }
}

// Alternative deployment script with better salt management
contract DeployWithCustomSalt is Script {
    ICREATE3Factory constant CREATE3_FACTORY =
        ICREATE3Factory(0xba5Ed099633D3B313e4D5F7bdc1305d3c28ba5Ed);
    address constant GMUNY_ADDRESS = address(0); // TODO: Replace with actual GMUNY address

    function run(
        string memory nGMUNYSaltString,
        string memory migrationSaltString
    ) external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        // Use provided salt strings or generate random ones
        bytes32 nGMUNYSalt = bytes(nGMUNYSaltString).length > 0
            ? keccak256(abi.encodePacked(nGMUNYSaltString))
            : keccak256(
                abi.encodePacked(
                    "nGMUNY",
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
        address predictedNGMUNY = CREATE3_FACTORY.getDeployed(
            deployer,
            nGMUNYSalt
        );
        address predictedMigration = CREATE3_FACTORY.getDeployed(
            deployer,
            migrationSalt
        );

        console.log("Deploying with salts:");
        console.log("nGMUNY Salt:", vm.toString(nGMUNYSalt));
        console.log("Migration Salt:", vm.toString(migrationSalt));
        console.log("\nPredicted addresses:");
        console.log("nGMUNY:", predictedNGMUNY);
        console.log("Migration:", predictedMigration);

        // Deploy contracts
        bytes memory migrationBytecode = abi.encodePacked(
            type(TokenMigration).creationCode,
            abi.encode(GMUNY_ADDRESS, predictedNGMUNY)
        );

        address migrationAddress = CREATE3_FACTORY.deploy(
            migrationSalt,
            migrationBytecode
        );

        bytes memory nGMUNYBytecode = abi.encodePacked(
            type(nGMUNY).creationCode,
            abi.encode(migrationAddress)
        );

        address nGMUNYAddress = CREATE3_FACTORY.deploy(
            nGMUNYSalt,
            nGMUNYBytecode
        );

        vm.stopBroadcast();

        console.log("\n=== Deployment Complete ===");
        console.log("nGMUNY Token:", nGMUNYAddress);
        console.log("Migration Contract:", migrationAddress);
    }
}
