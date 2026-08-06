// Verified production source of the live SimplePlugin stack (Polygonscan,
// 0xDb0e60A38Bf7d04c8ae0B396A65E5aa550f9885A). Extracted for fork tests to
// deploy the REAL referral plugin wired to TEL3. Do not edit.
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IPlugin} from "./IPlugin.sol";
import {DeactivationTimelock} from "./DeactivationTimelock.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Checkpoints} from "./Checkpoints.sol";

/// @title Simple Plugin
/// @notice This contract is the simplest IPlugin possible
/// @dev A designated address (`increaser`) can call a function to increase rewards for a given user
contract SimplePlugin is DeactivationTimelock, IPlugin, Ownable {
    using Checkpoints for Checkpoints.History;
    using SafeERC20 for IERC20;

    /// @dev This address is allowed to call `increaseClaimableBy`
    address public increaser;

    /// @dev Addres of the StakingModule
    address public immutable staking;

    /// @dev TEL ERC20 address
    IERC20 public immutable tel;

    /// @dev Amount claimable by an account
    mapping(address => Checkpoints.History) private _claimable;

    /// @dev Total amount claimable by all accounts
    uint256 private _totalOwed;

    /// @notice Event that's emitted when a user claims some rewards
    event Claimed(address indexed account, uint256 amount);
    /// @notice Event that's emitted when a user's claimable rewards are increased
    event ClaimableIncreased(
        address indexed account,
        uint256 oldClaimable,
        uint256 newClaimable
    );
    /// @notice Event that's emitted when a the increaser is changed
    event IncreaserChanged(
        address indexed oldIncreaser,
        address indexed newIncreaser
    );

    constructor(
        address _stakingAddress,
        IERC20 tel_
    ) DeactivationTimelock(1 days) Ownable(_msgSender()) {
        staking = _stakingAddress;
        tel = tel_;
    }

    modifier onlyStaking() {
        require(
            _msgSender() == staking,
            "SimplePlugin: Caller is not onlyStaking"
        );
        _;
    }

    modifier onlyIncreaser() {
        require(
            _msgSender() == increaser,
            "SimplePlugin: Caller is not onlyIncreaser"
        );
        _;
    }

    /************************************************
     *   view functions
     ************************************************/

    /// @return amount claimable by `account`
    function claimable(
        address account,
        bytes calldata
    ) external view override returns (uint256) {
        return _claimable[account].latest();
    }

    /// @return total amount claimable by all accounts
    function totalClaimable() external view override returns (uint256) {
        return _totalOwed;
    }

    /// @return amount claimable by account at a specific block
    function claimableAt(
        address account,
        uint256 blockNumber,
        bytes calldata
    ) external view override returns (uint256) {
        return _claimable[account].getAtBlock(blockNumber);
    }

    /// @return true if plugin is deactivated
    function deactivated() public view override returns (bool) {
        return _deactivated();
    }

    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override returns (bool) {
        return interfaceId == type(IPlugin).interfaceId;
    }

    /************************************************
     *   onlyStaking functions
     ************************************************/

    /// @notice Claims all earned yield on behalf of account
    /// @param account the account to claim on behalf of
    /// @param to the account to send the rewards to
    function claim(
        address account,
        address to,
        bytes calldata
    ) external override whenNotDeactivated onlyStaking returns (uint256) {
        uint256 amt = _claimable[account].latest();

        // if claimable amount is 0, do nothing
        if (amt <= 0) {
            return 0;
        }

        // update _claimable checkpoints
        _claimable[account].push(0);

        // update _totalOwed
        _totalOwed -= amt;

        // transfer TEL
        tel.safeTransfer(to, amt);

        emit Claimed(account, amt);

        return amt;
    }

    /// @notice Returns true if this plugin requires notifications when users' stakes change
    function requiresNotification() external pure override returns (bool) {
        // This plugin does not require notifications from the staking module.
        return false;
    }

    /// @notice Do nothing
    /// @dev If this function did anything, it would have onlyStaking modifier
    function notifyStakeChange(
        address,
        uint256,
        uint256
    ) external pure override {}

    /************************************************
     *   onlyIncreaser functions
     ************************************************/

    /// @notice increases rewards of an account
    /// @dev This function will pull TEL from the increaser, so this contract must be approved by the increaser first
    /// @param account account to credit tokens to
    /// @param amount amount to credit
    /// @return false if amount is 0, otherwise true
    function increaseClaimableBy(
        address account,
        uint256 amount
    ) external whenNotDeactivated onlyIncreaser returns (bool) {
        // if amount is zero do nothing
        if (amount == 0) {
            return false;
        }

        // keep track of old claimable and new claimable
        uint256 oldClaimable = _claimable[account].latest();
        uint256 newClaimable = oldClaimable + amount;

        // update _claimable[account] with newClaimable
        _claimable[account].push(newClaimable);

        // update _totalOwed
        _totalOwed += amount;

        // transfer TEL
        tel.safeTransferFrom(msg.sender, address(this), amount);

        emit ClaimableIncreased(account, oldClaimable, newClaimable);

        return true;
    }

    /************************************************
     *   onlyOwner functions
     ************************************************/

    /// @notice Sets increaser address
    /// @dev Only callable by contract Owner
    function setIncreaser(address newIncreaser) external onlyOwner {
        address old = increaser;
        increaser = newIncreaser;
        emit IncreaserChanged(old, increaser);
    }

    /// @notice rescues any stuck erc20
    /// @dev if the token is TEL, then it only allows maximum of balanceOf(this) - _totalOwed to be rescued
    function rescueTokens(IERC20 token, address to) external onlyOwner {
        if (token == tel) {
            // if the token is TEL, only send the extra amount. Do not send anything that is meant for users.
            token.safeTransfer(to, token.balanceOf(address(this)) - _totalOwed);
        } else {
            // if the token isn't TEL, it's not supposed to be here. Send all of it.
            token.safeTransfer(to, token.balanceOf(address(this)));
        }
    }

    /// @notice Starts deactivation timer
    function startDeactivation() external override onlyOwner {
        _startDeactivation();
    }

    /************************************************
     *   other functions
     ************************************************/

    /// @notice Clean up post deactivation
    /// @dev Transfers any remaining TEL to plugin owner
    function cleanupPostDeactivation() public whenDeactivated {
        tel.safeTransfer(owner(), tel.balanceOf(address(this)));
    }
}
