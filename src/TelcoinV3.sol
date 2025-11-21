// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title ERC-20 Token
 * @dev ERC20 token with 18 decimals
 */
contract TelcoinV3 is ERC20, Ownable {
    uint256 public constant TOTAL_SUPPLY = 100_000_000_000 * 10 ** 18; // 100B tokens with 18 decimals

    /**
     * @dev Constructor that mints amount specified to the migration contract
     * @param _initialSupply The initial supply to mint
     * @param _owner The owner
     * @param _minter The address that receives mint
     */
    constructor(
        uint256 _initialSupply,
        address _owner,
        address _minter
    ) ERC20("Telcoin", "TEL") Ownable(_owner) {
        require(_initialSupply < TOTAL_SUPPLY, "Invalid mint amount");
        _mint(_minter, _initialSupply);
    }

    /**
     * @dev Returns the number of decimals used
     */
    function decimals() public pure override returns (uint8) {
        return 18;
    }
}
