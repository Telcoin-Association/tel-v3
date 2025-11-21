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
    // CreateX Factory on Ethereum mainnet note: not compatible with Axelar
    ICREATE3Factory constant CREATE3_FACTORY =
        ICREATE3Factory(0xba5Ed099633D3B313e4D5F7bdc1305d3c28ba5Ed);

    function run(address telcoinV2, address owner, uint256 initialSupply) external {
        // Get private key from environment
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        // use CreateX encoded salt allowing cross-chain replication
        bytes1 allowCrossChain = 0x00;
        bytes11 telcoinV3Entropy = bytes11(keccak256("TelcoinV3"));
        bytes11 migrationEntropy = bytes11(keccak256("TokenMigration"));
        bytes32 telcoinV3Salt = bytes32(abi.encodePacked(deployer, allowCrossChain, telcoinV3Entropy));
        bytes32 migrationSalt = bytes32(abi.encodePacked(deployer, allowCrossChain, migrationEntropy));

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
            abi.encode(telcoinV2, predictedTelcoinV3, owner)
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
            abi.encode(initialSupply, owner, migrationAddress)
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
        require(token.totalSupply() == 10e29, "total supply");
        require(
            token.balanceOf(migrationAddress) == initialSupply,
            "initial supply"
        );

        vm.stopBroadcast();

        // Log deployment info
        console.log("\n=== Deployment Complete ===");
        console.log("TelcoinV3 Token:", telcoinV3Address);
        console.log("Migration Contract:", migrationAddress);
        console.log("\nSalts used:");
        console.log("Telcoin V3 Salt:", vm.toString(telcoinV3Salt));
        console.log("Migration Salt:", vm.toString(migrationSalt));
    }
}
