// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {TelcoinV3} from "../../src/TelcoinV3.sol";
import {TokenMigration} from "../../src/TokenMigration.sol";
import {Create3Utils} from "../utils/Create3Utils.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Roles} from "../../src/helpers/Roles.sol";

contract TokenMigrationTest is Test, Roles {
    // contracts
    IERC20 public oldToken;
    TelcoinV3 public telcoinV3;
    TokenMigration public migration;
    Create3Utils public create3;

    // addresses
    address public user1 = 0xf10a701111111111111111111111111111111111;
    address public user2 = 0x7e75333333333333333333333333333333333300;
    address public owner = 0xF262D0995Da87FFF7a1d20635eA440Fac96CC5C1;
    address public deployer = 0x369921b758B1228882EFbd997a67075211b93835;

    // constants
    address constant OLDTOKEN_ADDRESS = 0x467Bccd9d29f223BcE8043b84E8C8B282827790F; // ethereum
    uint256 constant OLDTOKEN_SUPPLY = 100_000_000_000 * 10 ** 2; // 100B with 2 decimals
    uint256 constant INITIAL_NEW_TOKEN_SUPPLY = 10_000_000_000 * 10 ** 18; // 10B with 18 decimals
    uint256 constant INITIAL_USER_BAL = 1_000_000 * 10 ** 2;

    // fork
    string ethereumRpcUrl = vm.envString("ETHEREUM_RPC_URL");
    uint256 ethereumFork;

    function setUp() public {
        // fork ethereum
        ethereumFork = vm.createFork(ethereumRpcUrl);
        vm.selectFork(ethereumFork);

        // existing token
        oldToken = IERC20(OLDTOKEN_ADDRESS);

        // verify oldToken has 2 decimals
        assertEq(IERC20Metadata(address(oldToken)).decimals(), 2, "OldToken should have 2 decimals");

        // deploy create3 util contract
        create3 = new Create3Utils();

        // give deployer some eth
        vm.deal(deployer, 1 ether);

        vm.startPrank(deployer);

        // deploy new token using create3 and mint to migration contract
        bytes32 tokenSalt = keccak256("NEW_TOKEN_SALT");
        bytes memory tokenArgs = abi.encodePacked(
            type(TelcoinV3).creationCode, abi.encode(INITIAL_NEW_TOKEN_SUPPLY, owner)
        );
        address deployment = create3.deploy(tokenSalt, tokenArgs);
        telcoinV3 = TelcoinV3(deployment);

        // verify TelcoinV3 has 18 decimals
        assertEq(IERC20Metadata(address(telcoinV3)).decimals(), 18, "Telcoin V3 should have 18 decimals");

        // deploy token migration contract
        bytes32 migrationSalt = keccak256("TOKEN_MIGRATION_SALT");
        bytes memory migrationArgs = abi.encodePacked(
            type(TokenMigration).creationCode, abi.encode(address(oldToken), address(telcoinV3), owner, 365 days)
        );
        address migrationAddress = create3.deploy(migrationSalt, migrationArgs);
        migration = TokenMigration(migrationAddress);

        vm.stopPrank();

        // set minter role on TelcoinV3
        vm.prank(owner);
        telcoinV3.grantRole(MINTER_ROLE, address(migration));

        // fund accounts
        deal(address(oldToken), user1, INITIAL_USER_BAL);
        deal(address(oldToken), user2, INITIAL_USER_BAL);
    }

    function testMigration() public {
        vm.startPrank(user1);

        // check initial balances
        assertEq(oldToken.balanceOf(user1), INITIAL_USER_BAL);
        assertEq(telcoinV3.balanceOf(user1), 0);
        uint256 preSupply = telcoinV3.totalSupply();

        // take current burn balance since this forks live
        uint256 currentBurnBalance = oldToken.balanceOf(migration.BURN_ADDRESS());

        // approve migration contract
        oldToken.approve(address(migration), INITIAL_USER_BAL);

        // perform migration
        migration.migrate();

        // check user's final balances
        assertEq(oldToken.balanceOf(user1), 0);
        assertEq(telcoinV3.balanceOf(user1), INITIAL_USER_BAL * migration.DECIMAL_MULTIPLIER());
        assertEq(telcoinV3.totalSupply(), preSupply + INITIAL_USER_BAL * migration.DECIMAL_MULTIPLIER());
        // check tokens were burned
        uint256 expectedBurnBalance = currentBurnBalance + INITIAL_USER_BAL;
        assertEq(oldToken.balanceOf(migration.BURN_ADDRESS()), expectedBurnBalance);

        vm.stopPrank();
    }

    function testPauseUnpause() public {
        vm.prank(owner);
        migration.pause();

        vm.startPrank(user1);
        oldToken.approve(address(migration), INITIAL_USER_BAL);

        vm.expectRevert(Pausable.EnforcedPause.selector);
        migration.migrate();
        vm.stopPrank();

        vm.prank(owner);
        migration.unpause();

        vm.prank(user1);
        migration.migrate();
    }

    function testUserHasNotApprovedFullAmount() public {
        // check initial balances
        assertEq(oldToken.balanceOf(user1), INITIAL_USER_BAL);
        assertEq(telcoinV3.balanceOf(user1), 0);

        vm.startPrank(user1);
        // approve less than full balance for migration contract
        uint256 notEnough = INITIAL_USER_BAL - 1000;
        oldToken.approve(address(migration), notEnough);
        vm.expectRevert();
        migration.migrate();
        vm.stopPrank();
    }

    function testRecoverStuckOldToken() public {
        address migrationContract = address(migration);
        // sanity check
        assertEq(oldToken.balanceOf(migrationContract), 0);

        // transfer old token instead of migrating
        vm.startPrank(user1);
        oldToken.approve(migrationContract, INITIAL_USER_BAL);
        require(oldToken.transfer(migrationContract, INITIAL_USER_BAL));
        vm.stopPrank();

        // check old tokens received
        assertEq(oldToken.balanceOf(migrationContract), INITIAL_USER_BAL);
        assertEq(oldToken.balanceOf(user1), 0);

        // recover old tokens
        vm.prank(owner);
        migration.recoverERC20(user1, OLDTOKEN_ADDRESS);
        assertEq(oldToken.balanceOf(user1), INITIAL_USER_BAL);
        assertEq(oldToken.balanceOf(migrationContract), 0);
    }

    function testOnlyOwnerFunctions() public {
        vm.startPrank(user1);

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user1));
        migration.pause();

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user1));
        migration.unpause();

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user1));
        migration.recoverERC20(user1, OLDTOKEN_ADDRESS);

        vm.stopPrank();
    }

    function testMigrateWithZeroAmount() public {
        address zeroBalance = address(400);
        // sanity check
        assertEq(oldToken.balanceOf(zeroBalance), 0);

        vm.prank(zeroBalance);
        vm.expectRevert(TokenMigration.InvalidAmount.selector);
        migration.migrate();
    }

    function testMaxBalance() public {
        vm.startPrank(user1);
        uint256 userBalance = oldToken.balanceOf(user1);
        uint256 tooMuch = userBalance + 1000;
        oldToken.approve(address(migration), tooMuch);
        migration.migrate();
        vm.stopPrank();

        // amount up to user's balance migrated
        uint256 expectedBalance = userBalance * migration.DECIMAL_MULTIPLIER();
        assertEq(telcoinV3.balanceOf(user1), expectedBalance);
    }
}
