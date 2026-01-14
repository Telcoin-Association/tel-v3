// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {Minter} from "interchain-token-service/contracts/utils/Minter.sol";

/**
 * @title Telcoin
 * @notice Telcoin V3
 */
contract TelcoinV3 is ERC20, Minter, Ownable2Step, Pausable {
    error NotMinter(address addr);

    uint256 public constant MIGRATION_SUPPLY_CAP = 100_000_000_000 * 10 ** 18; // 100B tokens with 18 decimals

    /**
     * @dev Constructor that mints amount specified to the migration contract
     * @param initialSupply_ The initial supply to mint on this chain
     * @param owner_ The owner (Telcoin TAO Governance Safe)
     * @param migration_ The TokenMigration contract that receives `initialSupply_` for this chain
     */
    constructor(uint256 initialSupply_, address owner_, address migration_) ERC20("Telcoin", "TEL") Ownable(owner_) {
        require(initialSupply_ < MIGRATION_SUPPLY_CAP, "Invalid mint amount");

        _mint(migration_, initialSupply_);
        _addMinter(owner_);
    }

    /// @notice Can be used for future supply inflation in line with long term Telcoin roadmap
    function mint(address to, uint256 amount) external onlyRole(uint8(Roles.MINTER)) whenNotPaused {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external onlyRole(uint8(Roles.MINTER)) whenNotPaused {
        _burn(from, amount);
    }

    /**
     *
     *   permissioned
     *
     */

    /// @dev Minters can propose and transfer mintership roles; owner can remove minters
    function removeMinter(address minter) public onlyOwner {
        if (!hasRole(minter, uint8(Roles.MINTER))) revert NotMinter(minter);
        _removeRole(minter, uint8(Roles.MINTER));
    }

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }
}
