// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20Mintable} from "./interfaces/IERC20Mintable.sol";

/**
 * @title TokenMigration
 * @author Telcoin Labs
 * @dev Migration contract for swapping oldToken (2 decimals) to TelcoinV3 (18 decimals) at 1:1 rate
 */
contract TokenMigration is Ownable2Step, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20Mintable;

    /// @dev TEL token addresses per chain
    IERC20Mintable public immutable oldToken;
    IERC20Mintable public immutable telcoinV3;
    
    /// @dev TEL disallows transfers to zero address
    address public constant BURN_ADDRESS = 0x000000000000000000000000000000000000dEaD;

    /// @notice Decimal difference multiplier (10^16)
    uint256 public constant DECIMAL_MULTIPLIER = 10 ** 16;

    /// @notice The total amount of TEL migrated via this contract,
    /// denominated using TelcoinV3's 18 decimals
    uint256 public totalMigrated;

    /// @notice The timestamp when migration has come to a conclusion. All attempts to migrate will
    /// revert if block.timestamp is beyond migrationExpiry.
    uint256 public migrationExpiry;

    // events
    event TokensMigrated(address indexed user, uint256 amount);
    event StuckTokensRecovered(address indexed token, address indexed to, uint256 amount);
    event MigrationExpirySet(uint256 oldExpiry, uint256 newExpiry);

    // errors
    error InvalidAmount();
    error InvalidExpiry();
    error ZeroAddress();
    error MigrationConcluded();

    /**
     * @dev Constructor
     * @param _oldToken Address of the old oldToken token (2 decimals)
     * @param _telcoinV3 Address of the new TelcoinV3 token (18 decimals)
     * @param _owner Owner address of this contract
     * @param _migrationDuration Duration of migration in seconds
     */
    constructor(address _oldToken, address _telcoinV3, address _owner, uint256 _migrationDuration) Ownable(_owner) {
        if (_oldToken == address(0) || _telcoinV3 == address(0)) revert ZeroAddress();
        if (_migrationDuration == 0) revert InvalidExpiry();

        oldToken = IERC20Mintable(_oldToken);
        telcoinV3 = IERC20Mintable(_telcoinV3);

        migrationExpiry = block.timestamp + _migrationDuration;
    }

    /**
     * @dev Migrate oldToken to TelcoinV3
     * @notice Migrates entire balance and sends oldToken to BURN_ADDRESS
     * @return amountNewToken Amount of tokens minted in response to migration
     */
    function migrate() external whenNotPaused nonReentrant returns (uint256 amountNewToken) {
        if (block.timestamp > migrationExpiry) revert MigrationConcluded();
        // user must have sufficient balance
        uint256 userBalance = oldToken.balanceOf(msg.sender);
        if (userBalance == 0) revert InvalidAmount();

        // convert from 2 decimals to 18 decimals
        amountNewToken = getAmountOut(userBalance);
        totalMigrated += amountNewToken;

        // transfer oldToken from user to burn address (locked permanently)
        oldToken.safeTransferFrom(msg.sender, BURN_ADDRESS, userBalance);

        // mint telcoinV3 to user
        telcoinV3.mint(msg.sender, amountNewToken);
        emit TokensMigrated(msg.sender, amountNewToken);
    }

    /**
     * @dev Allows the admin to set the migration expiry date - when migration will be concluded.
     * @notice New migration timestamp must be greater than the current expiry
     * @param newMigrationExpiry New timestamp when migrations will be concluded
     */
    function setMigrationExpiry(uint256 newMigrationExpiry) external onlyOwner {
        if (newMigrationExpiry == 0 || migrationExpiry > newMigrationExpiry) revert InvalidExpiry();
        emit MigrationExpirySet(migrationExpiry, newMigrationExpiry);
        migrationExpiry = newMigrationExpiry;
    }

    /**
     * @notice Recover ERC20 tokens that were sent by mistake to this contract.
     * @dev This can only be done by the contract owner
     * @param destination The address to send the recovered tokens
     * @param tokenAddress The address of the token to recover
     */
    function recoverERC20(address destination, address tokenAddress) external nonReentrant onlyOwner {
        if (destination == address(0) || destination == BURN_ADDRESS || tokenAddress == address(0)) {
            revert ZeroAddress();
        }

        // check balance
        IERC20Mintable tokenContract = IERC20Mintable(tokenAddress);
        uint256 balance = tokenContract.balanceOf(address(this));
        if (balance == 0) revert InvalidAmount();

        // transfer recovery amount
        tokenContract.safeTransfer(destination, balance);
        emit StuckTokensRecovered(tokenAddress, destination, balance);
    }

    /**
     * @dev Pause the migration (owner only)
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @dev Unpause the migration (owner only)
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @notice Returns the amount of new tokens will be minted when `amountIn` of the oldToken is migrated.
     * @dev Converts `amountIn` from 2 decimals to 18 with decimal multiplier
     * @param amountIn Amount of oldToken to be migrated.
     * @return The amount of new token that will be minted during migration
     */
    function getAmountOut(uint256 amountIn) public pure returns (uint256) {
        return amountIn * DECIMAL_MULTIPLIER;
    }
}
