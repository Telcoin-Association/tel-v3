// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title TokenMigration
 * @dev Migration contract for swapping oldToken (2 decimals) to newToken (18 decimals) at 1:1 rate
 */
contract TokenMigration is Ownable, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // token addresses
    IERC20 public immutable oldToken;
    IERC20 public immutable newToken;
    address public constant BURN_ADDRESS =
        0x000000000000000000000000000000000000dEaD; /// @dev used bc TEL disallows transfers to zero address

    // Decimal difference multiplier (10^16)
    uint256 public constant DECIMAL_MULTIPLIER = 10 ** 16;

    // events
    event TokensMigrated(address indexed user, uint256 amount);
    event RemainingTokensWithdrawn(address indexed to, uint256 amount);
    event StuckTokensRecovered(
        address indexed token,
        address indexed to,
        uint256 amount
    );

    // errors
    error InsufficientContractBalance(uint256 required, uint256 available);
    error InvalidAmount();
    error ZeroAddress();
    error TokenLocked();
    error CannotRecoverProtectedToken();
    error InsufficientAllowance(uint256 balance, uint256 allowance);

    /**
     * @dev Constructor
     * @param _oldToken Address of the old oldToken token (2 decimals)
     * @param _newToken Address of the new newToken token (18 decimals)
     * @param _owner Owner address
     */
    constructor(
        address _oldToken,
        address _newToken,
        address _owner
    ) Ownable(_owner) {
        if (_oldToken == address(0)) revert ZeroAddress();
        if (_newToken == address(0)) revert ZeroAddress();

        oldToken = IERC20(_oldToken);
        newToken = IERC20(_newToken);
    }

    /**
     * @dev Migrate oldToken to newToken
     * @notice Migrates entire balance and sends oldToken to BURN_ADDRESS
     */
    function migrate() external whenNotPaused nonReentrant {
        // user must have sufficient balance
        uint256 userBalance = oldToken.balanceOf(msg.sender);
        if (userBalance == 0) revert InvalidAmount();

        /// @dev allowance checks are not strictly necessary since the token already does it
        /// however depending on what the frontend for this will look like, an approval check
        /// like this can be used to write a fn allowing migration on users' behalf (if useful)
        // user must have sufficient allowance
        uint256 allowance = oldToken.allowance(msg.sender, address(this));
        if (allowance < userBalance) {
            revert InsufficientAllowance(userBalance, allowance);
        }

        // convert from 2 decimals to 18 decimals
        uint256 migrationAmount = userBalance * DECIMAL_MULTIPLIER;

        // check if migration contract has enough newToken
        uint256 available = newToken.balanceOf(address(this));
        if (available < migrationAmount) {
            revert InsufficientContractBalance(migrationAmount, available);
        }

        // transfer oldToken from user to burn address (locked permanently)
        oldToken.safeTransferFrom(msg.sender, BURN_ADDRESS, userBalance);

        // transfer newToken to user
        newToken.safeTransfer(msg.sender, migrationAmount);
        emit TokensMigrated(msg.sender, migrationAmount);
    }

    /**
     * @dev Withdraw remaining newToken tokens (owner only)
     * @param to Address to send the tokens to
     */
    function withdrawRemainingNewToken(address to) external onlyOwner {
        /// @dev nit since it's onlyOwner but since we're using address(0xdead) as burn address, should disallow it here too
        if (to == address(0)) revert ZeroAddress();

        // check remaining balance
        uint256 balance = newToken.balanceOf(address(this));
        /// @dev like in `migrate()`, this is handled by ERC20 logic so it's not strictly necessary
        if (balance == 0) revert InvalidAmount();

        // transfer remaining
        newToken.safeTransfer(to, balance);
        emit RemainingTokensWithdrawn(to, balance);
    }

    /**
     * @notice Recover ERC20 tokens that were sent by mistake to this contract.
     * @notice Cannot recover migration's newToken.
     * @dev This can only be done by the contract owner
     * @param destination The address to send the recovered tokens
     * @param tokenAddress The address of the token to recover
     * @param amount The amount of the token to transfer
     */
    function recoverERC20(
        address destination,
        address tokenAddress,
        uint256 amount
    ) external onlyOwner {
        /// @dev nit since it's onlyOwner but since we're using address(0xdead) as burn address, should disallow it here too
        if (destination == address(0)) revert ZeroAddress();
        if (address(tokenAddress) == address(0)) revert ZeroAddress();
        if (address(tokenAddress) == address(newToken))
            revert CannotRecoverProtectedToken();
        if (amount == 0) revert InvalidAmount();

        // check balance
        IERC20 tokenContract = IERC20(tokenAddress);
        uint256 balance = tokenContract.balanceOf(address(this));
        if (balance < amount)
            revert InsufficientContractBalance(amount, balance);

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
     * @dev Check remaining newToken balance in the migration contract
     * @return Remaining newToken balance
     */
    function remainingNewTokenBalance() external view returns (uint256) {
        return newToken.balanceOf(address(this));
    }

    /**
     * @dev Check total oldToken burned to BURN_ADDRESS
     * @return Total oldToken removed from circulation
     */
    function totalOldTokenBurned() external view returns (uint256) {
        /// @dev also reflects when someone sends oldToken directly to BURN_ADDRESS without migrating 
        /// presumably nobody would do this but it does break one of the listed invariants that `balanceOf(BURN_ADDRESS) == totalMigrated`
        return oldToken.balanceOf(BURN_ADDRESS);
    }
}
