// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title LegacyTelcoinFaucet
/// @notice Testnet faucet that dispenses pre-funded legacy Telcoin (2 decimals) to callers. Rate-limited per address.
contract LegacyTelcoinFaucet is Ownable {
    using SafeERC20 for IERC20;

    IERC20 public immutable token;

    uint256 public dripAmount;
    uint256 public cooldown;

    mapping(address => uint256) public lastDrip;
    mapping(address => bool) public whitelisted;

    error CooldownNotElapsed(uint256 availableAt);
    error InsufficientFaucetBalance();
    error NotWhitelisted();

    event Dripped(address indexed to, uint256 amount);
    event DripAmountUpdated(uint256 newAmount);
    event CooldownUpdated(uint256 newCooldown);
    event WhitelistUpdated(address indexed account, bool status);

    constructor(address token_, uint256 dripAmount_, uint256 cooldown_, address admin_) Ownable(admin_) {
        token = IERC20(token_);
        dripAmount = dripAmount_;
        cooldown = cooldown_;
    }

    /// @notice Transfer `dripAmount` of legacy TEL to the caller.
    function drip() external {
        _drip(msg.sender);
    }

    /// @notice Transfer `dripAmount` of legacy TEL to a specified address.
    function drip(address to) external {
        _drip(to);
    }

    function setDripAmount(uint256 newAmount) external onlyOwner {
        dripAmount = newAmount;
        emit DripAmountUpdated(newAmount);
    }

    function setCooldown(uint256 newCooldown) external onlyOwner {
        cooldown = newCooldown;
        emit CooldownUpdated(newCooldown);
    }

    function setWhitelist(address account, bool status) external onlyOwner {
        whitelisted[account] = status;
        emit WhitelistUpdated(account, status);
    }

    /// @notice Allows the owner to withdraw tokens from the faucet.
    function withdraw(address to, uint256 amount) external onlyOwner {
        token.safeTransfer(to, amount);
    }

    /// @notice Whitelisted callers can transfer an arbitrary amount, bypassing cooldown and dripAmount.
    function transferWhitelisted(address to, uint256 amount) external {
        if (!whitelisted[msg.sender]) revert NotWhitelisted();
        if (token.balanceOf(address(this)) < amount) revert InsufficientFaucetBalance();
        token.safeTransfer(to, amount);
        emit Dripped(to, amount);
    }

    function _drip(address to) internal {
        if (!whitelisted[msg.sender]) {
            uint256 last = lastDrip[to];
            if (last != 0) {
                uint256 availableAt = last + cooldown;
                if (block.timestamp < availableAt) revert CooldownNotElapsed(availableAt);
            }
        }
        if (token.balanceOf(address(this)) < dripAmount) revert InsufficientFaucetBalance();

        lastDrip[to] = block.timestamp;
        token.safeTransfer(to, dripAmount);

        emit Dripped(to, dripAmount);
    }
}
