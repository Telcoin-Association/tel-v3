// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuardTransient} from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";
import {IERC20Mintable} from "./interfaces/IERC20Mintable.sol";

/**
 * @title TokenMigration
 * @author Telcoin Association
 * @dev Migration contract for swapping oldToken (2 decimals) to TelcoinV3 (18 decimals) at 1:1 rate.
 * Old tokens are escrowed in this contract during migration and can be withdrawn by the owner
 * after a secondary withdrawal delay following migration expiry.
 */
contract TokenMigration is Ownable2Step, Pausable, ReentrancyGuardTransient {
    using SafeERC20 for IERC20Mintable;

    /// @notice Decimal difference multiplier (10^16)
    uint256 public constant DECIMAL_MULTIPLIER = 10 ** 16;

    /// @notice The delay after migrationExpiry before escrowed old tokens can be withdrawn
    uint256 public immutable withdrawalDelay;

    /// @dev TEL token addresses per chain
    IERC20Mintable public immutable oldToken;
    IERC20Mintable public immutable telcoinV3;

    /// @notice The timestamp when migration has come to a conclusion. All attempts to migrate will
    /// revert if block.timestamp is beyond migrationExpiry.
    uint256 public migrationExpiry;

    /// @notice Set permanently once escrowed old tokens are withdrawn.
    bool public migrationClosed;

    // events
    event TokensMigrated(address indexed user, uint256 amount);
    event StuckTokensRecovered(address indexed token, address indexed to, uint256 amount);
    event MigrationExpirySet(uint256 oldExpiry, uint256 newExpiry);
    event OldTokensWithdrawn(address indexed to, uint256 amount);
    event MigrationClosed();

    // errors
    error InvalidAmount();
    error InvalidExpiry();
    error ZeroAddress();
    error SameAddress();
    error MigrationConcluded();
    error CannotRenounceOwnership();
    error WithdrawalLocked();
    error CannotRecoverOldToken();

    /**
     * @dev Constructor
     * @param _oldToken Address of the old TEL token (2 decimals)
     * @param _telcoinV3 Address of the new TelcoinV3 token (18 decimals)
     * @param _initialOwner Owner address of this contract
     * @param _migrationDuration Duration of migration in seconds
     * @param _withdrawalDelay Duration after migrationExpiry before old tokens can be withdrawn
     */
    constructor(
        address _oldToken, 
        address _telcoinV3,
        address _initialOwner,
        uint256 _migrationDuration,
        uint256 _withdrawalDelay
    ) Ownable(_initialOwner) {
        if (_oldToken == address(0) || _telcoinV3 == address(0)) revert ZeroAddress();
        if (_oldToken == _telcoinV3) revert SameAddress();
        if (_migrationDuration == 0) revert InvalidExpiry();

        oldToken = IERC20Mintable(_oldToken);
        telcoinV3 = IERC20Mintable(_telcoinV3);

        migrationExpiry = block.timestamp + _migrationDuration;
        withdrawalDelay = _withdrawalDelay;
    }

    /**
     * @dev Migrate oldToken to TelcoinV3
     * @notice Migrates entire balance and escrows oldToken in this contract
     * @return amountNewToken Amount of tokens minted in response to migration
     */
    function migrate() external nonReentrant whenNotPaused returns (uint256 amountNewToken) {
        if (migrationClosed || block.timestamp >= migrationExpiry) revert MigrationConcluded();
        // user must have sufficient balance
        uint256 userBalance = oldToken.balanceOf(msg.sender);
        if (userBalance == 0) revert InvalidAmount();

        // convert from 2 decimals to 18 decimals
        amountNewToken = getAmountOut(userBalance);

        // transfer oldToken from user to this contract (escrowed)
        oldToken.safeTransferFrom(msg.sender, address(this), userBalance);

        // mint telcoinV3 to user
        telcoinV3.mint(msg.sender, amountNewToken);
        emit TokensMigrated(msg.sender, amountNewToken);
    }

    /**
     * @notice Withdraw all escrowed old tokens after the withdrawal delay has passed.
     * @dev Can only be called by the owner after migrationExpiry + withdrawalDelay.
     *      Permanently closes migration so withdrawn old tokens can never be recycled
     *      through migrate() to mint additional new tokens.
     * @param destination The address to send the escrowed old tokens
     */
    function withdrawOldTokens(address destination) external onlyOwner {
        if (destination == address(0)) revert ZeroAddress();
        if (block.timestamp < migrationExpiry + withdrawalDelay) revert WithdrawalLocked();

        uint256 balance = oldToken.balanceOf(address(this));
        if (balance == 0) revert InvalidAmount();

        if (!migrationClosed) {
            migrationClosed = true;
            emit MigrationClosed();
        }

        oldToken.safeTransfer(destination, balance);
        emit OldTokensWithdrawn(destination, balance);
    }

    /**
     * @dev Allows the admin to set the migration expiry date - when migration will be concluded.
     * @notice New migration timestamp must be greater than the current expiry. Reverts once
     * migration has been permanently closed by a withdrawal of the escrowed old tokens.
     * @param newMigrationExpiry New timestamp when migrations will be concluded
     */
    function setMigrationExpiry(uint256 newMigrationExpiry) external onlyOwner {
        if (migrationClosed) revert MigrationConcluded();
        if (newMigrationExpiry == 0 || migrationExpiry > newMigrationExpiry) revert InvalidExpiry();
        emit MigrationExpirySet(migrationExpiry, newMigrationExpiry);
        migrationExpiry = newMigrationExpiry;
    }

    /**
     * @notice Recover ERC20 tokens that were sent by mistake to this contract.
     * @dev This can only be done by the contract owner
     * @param destination The address to send the recovered tokens
     * @param tokenAddress The address of the token to recover
     * @param amount Amount of tokens to recover from this contract
     */
    function recoverERC20(address destination, address tokenAddress, uint256 amount) external onlyOwner {
        if (destination == address(0) || tokenAddress == address(0)) revert ZeroAddress();
        if (tokenAddress == address(oldToken)) revert CannotRecoverOldToken();

        // check balance
        IERC20Mintable tokenContract = IERC20Mintable(tokenAddress);
        uint256 balance = tokenContract.balanceOf(address(this));
        if (balance == 0 || amount == 0 || amount > balance) revert InvalidAmount();

        // transfer recovery amount
        tokenContract.safeTransfer(destination, amount);
        emit StuckTokensRecovered(tokenAddress, destination, amount);
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
     * @notice Disabled - renouncing ownership would permanently prevent pausing, expiry extension, and token recovery.
     */
    function renounceOwnership() public view override onlyOwner {
        revert CannotRenounceOwnership();
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
