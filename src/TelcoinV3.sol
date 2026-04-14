// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {AccessControlEnumerable} from "@openzeppelin/contracts/access/extensions/AccessControlEnumerable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20Mintable} from "./interfaces/IERC20Mintable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {Roles} from "./helpers/Roles.sol";

/**
 * @title TelcoinV3
 * @author Telcoin Association
 * @notice Telcoin ERC20 token with 18 decimals. Supports role-based minting/burning and pausable transfers.
 */
contract TelcoinV3 is IERC20Mintable, ERC20, Pausable, Roles, AccessControlEnumerable {
    using SafeERC20 for IERC20;

    uint256 public constant MIGRATION_SUPPLY_CAP = 100_000_000_000 ether; // 100B tokens with 18 decimals

    error SupplyCapExceeded();

    /**
     * @dev Constructor that optionally mints an initial supply to the admin address
     * @param initialSupply_ The initial supply to mint on this chain. Tokens go to admin. Can be 0.
     * @param admin_ The owner (Telcoin TAO Governance Safe)
     */
    constructor(uint256 initialSupply_, address admin_) ERC20("Telcoin", "TEL") {
        if (initialSupply_ > MIGRATION_SUPPLY_CAP) revert SupplyCapExceeded();
        _mint(admin_, initialSupply_);
        _grantRole(DEFAULT_ADMIN_ROLE, admin_);
    }

    // ------------
    // Permissioned
    // ------------

    /// @notice Mint tokens. Only callable by MINTER_ROLE
    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) {
        _mint(to, amount);
        if (totalSupply() > MIGRATION_SUPPLY_CAP) revert SupplyCapExceeded();
    }

    /// @notice Burn tokens. Only callable by BURNER_ROLE
    function burn(address from, uint256 amount) external onlyRole(BURNER_ROLE) {
        _burn(from, amount);
    }

    /// @notice Pauses token transfers between non-zero addresses. Mints and burns remain active.
    function pause() public onlyRole(PAUSER_ROLE) {
        _pause();
    }

    /// @notice Resumes token transfers between non-zero addresses
    function unpause() public onlyRole(UNPAUSER_ROLE) {
        _unpause();
    }

    /// @notice Rescue ERC20 tokens accidentally sent to this contract.
    function rescueTokens(address _token, uint256 _amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        IERC20(_token).safeTransfer(msg.sender, _amount);
    }

    // --------
    // Internal
    // --------

    /// @notice Overrides ERC20::_update function to add pausability.
    function _update(address from, address to, uint256 value) internal override(ERC20) {
        if (paused() && from != address(0) && to != address(0)) {
            revert EnforcedPause();
        }
        ERC20._update(from, to, value);
    }
}
