// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title ERC-20 Token
 * @dev ERC20 token with 18 decimals and initial mint to migration contract
 */
contract nGMUNY is ERC20, Ownable {
    uint256 public constant TOTAL_SUPPLY = 100_000_000_000 * 10 ** 18; // 100B tokens with 18 decimals

    /**
     * @dev Constructor that mints total supply to the migration contract
     * @param _migrationContract Address that will receive the initial mint
     */
    constructor(
        address _migrationContract
    ) ERC20("New G-Money", "nGMUNY") Ownable(msg.sender) {
        require(_migrationContract != address(0), "Invalid migration contract");
        _mint(_migrationContract, TOTAL_SUPPLY);
    }

    /**
     * @dev Returns the number of decimals used
     */
    function decimals() public pure override returns (uint8) {
        return 18;
    }
}
