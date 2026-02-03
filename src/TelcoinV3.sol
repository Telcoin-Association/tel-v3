// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {AccessControlEnumerable} from "@openzeppelin/contracts/access/extensions/AccessControlEnumerable.sol";
import {ERC20Pausable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Pausable.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {Roles} from "./helpers/Roles.sol";

/**
 * @title Telcoin
 * @author Telcoin Labs
 * @notice Telcoin V3
 */
contract TelcoinV3 is ERC20Pausable, Roles, AccessControlEnumerable {
    uint256 public constant MIGRATION_SUPPLY_CAP = 100_000_000_000 ether; // 100B tokens with 18 decimals

    error InvalidMintAmount();

    /**
     * @dev Constructor that mints amount specified to the migration contract
     * @param initialSupply_ The initial supply to mint on this chain. Tokens go to admin. Can be 0.
     * @param admin_ The owner (Telcoin TAO Governance Safe)
     */
    constructor(uint256 initialSupply_, address admin_) ERC20("Telcoin", "TEL") {
        if (initialSupply_ > MIGRATION_SUPPLY_CAP) revert InvalidMintAmount();
        _mint(admin_, initialSupply_);
        _grantRole(DEFAULT_ADMIN_ROLE, admin_);
    }

    // ------------
    // Permissioned
    // ------------

    /// @notice Mint tokens - only callable by the bridge
    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) whenNotPaused {
        _mint(to, amount);
    }

    /// @notice Burn tokens - only callable by the bridge
    function burn(address from, uint256 amount) external onlyRole(BURNER_ROLE) whenNotPaused {
        _burn(from, amount);
    }

    /// @notice Pauses minting and burning functionality from this contract.
    function pause() public onlyRole(PAUSER_ROLE) {
        _pause();
    }

    /// @notice Unpauses minting and burning functionality from this contract.
    function unpause() public onlyRole(UNPAUSER_ROLE) {
        _unpause();
    }
}
