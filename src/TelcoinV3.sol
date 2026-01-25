// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

/**
 * @title Telcoin
 * @author Telcoin Labs
 * @notice Telcoin V3
 */
contract TelcoinV3 is ERC20, Ownable2Step, Pausable {
    uint256 public constant MIGRATION_SUPPLY_CAP = 100_000_000_000 ether; // 100B tokens with 18 decimals

    /// @notice The bridge contract authorized to mint/burn
    address public bridge;

    /// @notice Emitted when the bridge address is updated
    event BridgeSet(address indexed bridge);

    error NotBridge();
    error ZeroAddress();
    error InvalidMintAmount();

    /// @notice Verifies msg.sender to be the `bridge` address.
    modifier onlyBridge() {
        if (msg.sender != bridge) revert NotBridge();
        _;
    }

    /**
     * @dev Constructor that mints amount specified to the migration contract
     * @param initialSupply_ The initial supply to mint on this chain
     * @param owner_ The owner (Telcoin TAO Governance Safe)
     * @param migration_ The TokenMigration contract that receives `initialSupply_` for this chain
     */
    constructor(uint256 initialSupply_, address owner_, address migration_) ERC20("Telcoin", "TEL") Ownable(owner_) {
        if (initialSupply_ > MIGRATION_SUPPLY_CAP) revert InvalidMintAmount();
        _mint(migration_, initialSupply_);
    }

    /// @notice Mint tokens - only callable by the bridge
    function mint(address to, uint256 amount) external onlyBridge whenNotPaused {
        _mint(to, amount);
    }

    /// @notice Burn tokens - only callable by the bridge
    function burn(address from, uint256 amount) external onlyBridge whenNotPaused {
        _burn(from, amount);
    }

    // ------------
    // Permissioned
    // ------------

    /// @notice Set the bridge address
    /// @param _bridge The new bridge address
    function setBridge(address _bridge) external onlyOwner {
        if (_bridge == address(0)) revert ZeroAddress();
        bridge = _bridge;
        emit BridgeSet(_bridge);
    }

    /// @notice Pauses minting and burning functionality from this contract.
    function pause() public onlyOwner {
        _pause();
    }

    /// @notice Unpauses minting and burning functionality from this contract.
    function unpause() public onlyOwner {
        _unpause();
    }
}
