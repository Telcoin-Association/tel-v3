// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20Mintable} from "../interfaces/IERC20Mintable.sol";

/// @title TelcoinV3Faucet
/// @notice Testnet faucet that mints TelcoinV3 tokens to callers. Rate-limited per address.
/// @dev Requires MINTER_ROLE on the TelcoinV3 token contract.
contract TelcoinV3Faucet is Ownable {
    IERC20Mintable public immutable token;

    uint256 public dripAmount;
    uint256 public cooldown;

    mapping(address => uint256) public lastDrip;
    mapping(address => bool) public whitelisted;

    error CooldownNotElapsed(uint256 availableAt);
    error NotWhitelisted();

    event Dripped(address indexed to, uint256 amount);
    event DripAmountUpdated(uint256 newAmount);
    event CooldownUpdated(uint256 newCooldown);
    event WhitelistUpdated(address indexed account, bool status);

    constructor(address token_, uint256 dripAmount_, uint256 cooldown_, address admin_) Ownable(admin_) {
        token = IERC20Mintable(token_);
        dripAmount = dripAmount_;
        cooldown = cooldown_;
    }

    /// @notice Mint `dripAmount` of TelcoinV3 to the caller.
    function drip() external {
        _drip(msg.sender);
    }

    /// @notice Mint `dripAmount` of TelcoinV3 to a specified address.
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

    /// @notice Whitelisted callers can mint an arbitrary amount, bypassing cooldown and dripAmount.
    function mintWhitelisted(address to, uint256 amount) external {
        if (!whitelisted[msg.sender]) revert NotWhitelisted();
        token.mint(to, amount);
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

        lastDrip[to] = block.timestamp;
        token.mint(to, dripAmount);

        emit Dripped(to, dripAmount);
    }
}
