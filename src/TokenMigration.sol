// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title TokenMigration
 * @dev Migration contract for swapping oldToken (2 decimals) to TelcoinV3 (18 decimals) at 1:1 rate
 */
contract TokenMigration is Ownable, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // TEL token addresses per chain
    IERC20 public immutable oldToken;
    IERC20 public immutable telcoinV3;
    /// @dev TEL disallows transfers to zero address
    address public constant BURN_ADDRESS = 0x000000000000000000000000000000000000dEaD;

    // Decimal difference multiplier (10^16)
    uint256 public constant DECIMAL_MULTIPLIER = 10 ** 16;

    /// @notice The total amount of TEL migrated via this contract,
    /// denominated using TelcoinV3's 18 decimals
    uint256 public totalMigrated;

    // events
    event TokensMigrated(address indexed user, uint256 amount);
    event RemainingTokensWithdrawn(address indexed to, uint256 amount);
    event StuckTokensRecovered(address indexed token, address indexed to, uint256 amount);

    // errors
    error InsufficientContractBalance(uint256 required, uint256 available);
    error InvalidAmount();
    error ZeroAddress();
    error CannotRecoverProtectedToken();

    /**
     * @dev Constructor
     * @param _oldToken Address of the old oldToken token (2 decimals)
     * @param _telcoinV3 Address of the new TelcoinV3 token (18 decimals)
     * @param _owner Owner address
     */
    constructor(address _oldToken, address _telcoinV3, address _owner) Ownable(_owner) {
        if (_oldToken == address(0) || _telcoinV3 == address(0)) revert ZeroAddress();

        oldToken = IERC20(_oldToken);
        telcoinV3 = IERC20(_telcoinV3);
    }

    /**
     * @dev Migrate oldToken to TelcoinV3
     * @notice Migrates entire balance and sends oldToken to BURN_ADDRESS
     */
    function migrate() external whenNotPaused nonReentrant {
        // user must have sufficient balance
        uint256 userBalance = oldToken.balanceOf(msg.sender);
        if (userBalance == 0) revert InvalidAmount();

        // convert from 2 decimals to 18 decimals
        uint256 migrationAmount = userBalance * DECIMAL_MULTIPLIER;
        totalMigrated += migrationAmount;

        // check if migration contract has enough TelcoinV3 on this chain
        uint256 available = remainingTelcoinV3Balance();
        if (available < migrationAmount) {
            revert InsufficientContractBalance(migrationAmount, available);
        }

        // transfer oldToken from user to burn address (locked permanently)
        oldToken.safeTransferFrom(msg.sender, BURN_ADDRESS, userBalance);
        assert(oldToken.balanceOf(msg.sender) == 0);

        // transfer telcoinV3 to user
        telcoinV3.safeTransfer(msg.sender, migrationAmount);
        emit TokensMigrated(msg.sender, migrationAmount);
    }

    /**
     * @dev Withdraw remaining TelcoinV3 tokens (owner only)
     * @param to Address to send the tokens to
     */
    function withdrawRemainingTelcoinV3(address to) external onlyOwner {
        if (to == address(0) || to == BURN_ADDRESS) revert ZeroAddress();

        // check remaining balance
        uint256 balance = remainingTelcoinV3Balance();
        if (balance == 0) revert InvalidAmount();

        // transfer remaining
        telcoinV3.safeTransfer(to, balance);
        emit RemainingTokensWithdrawn(to, balance);
    }

    /**
     * @notice Recover ERC20 tokens that were sent by mistake to this contract.
     * @notice Cannot recover migration's TelcoinV3.
     * @dev This can only be done by the contract owner
     * @param destination The address to send the recovered tokens
     * @param tokenAddress The address of the token to recover
     */
    function recoverERC20(address destination, address tokenAddress) external onlyOwner {
        if (destination == address(0) || destination == BURN_ADDRESS) revert ZeroAddress();
        if (tokenAddress == address(0)) revert ZeroAddress();
        if (tokenAddress == address(telcoinV3)) revert CannotRecoverProtectedToken();

        // check balance
        IERC20 tokenContract = IERC20(tokenAddress);
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
     * @dev Check remaining TelcoinV3 balance in the migration contract
     * @return _ Remaining TelcoinV3 balance
     */
    function remainingTelcoinV3Balance() public view returns (uint256) {
        return telcoinV3.balanceOf(address(this));
    }
}
