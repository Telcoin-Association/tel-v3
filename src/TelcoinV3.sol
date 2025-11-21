// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {InterchainTokenStandard} from "interchain-token-service/contracts/interchain-token/InterchainTokenStandard.sol";

/**
 * @title Telcoin
 * @notice Telcoin V3 featuring interchain support and 18 decimals
 */
contract TelcoinV3 is ERC20, InterchainTokenStandard, Ownable {
    error NotMinter(address addr);

    uint256 public constant TOTAL_SUPPLY = 100_000_000_000 * 10 ** 18; // 100B tokens with 18 decimals

    modifier onlyMinter(address addr) {
        if (!isMinter(addr)) revert NotMinter(addr);
        _;
    }

    /**
     * @dev Constructor that mints amount specified to the migration contract
     * @param _initialSupply The initial supply to mint on this chain
     * @param _owner The owner (Telcoin TAO Governance Safe)
     * @param _migration The TokenMigration contract that receives `_initialSupply` for this chain
     */
    constructor(
        uint256 _initialSupply,
        address _owner,
        address _migration
    ) ERC20("Telcoin", "TEL") Ownable(_owner) {
        require(_initialSupply < TOTAL_SUPPLY, "Invalid mint amount");
        _mint(_migration, _initialSupply);
    }

    /// @notice InterchainTEL implementation for ITS Token Manager's mint API
    /// @dev Used by a Axelar TokenManager to manage interchain transfers
    /// @notice Can be used for future supply inflation in line with long term Telcoin roadmap
    function mint(address to, uint256 amount) external onlyMinter(msg.sender) {
        _mint(to, amount);
    }

    /// @notice TelcoinV3 implementation for ITS Token Manager's burn API
    function burn(address from, uint256 amount) external onlyMinter(msg.sender) {
        _burn(from, amount);
    }

    /// @notice Required by Axelar ITS to complete interchain transfers during payload processing
    /// of `MESSAGE_TYPE_INTERCHAIN_TRANSFER` headers, which delegatecalls `TokenHandler::giveToken()`
    function isMinter(address addr) public view virtual returns (bool) {
        //todo
        // if (addr == tokenManager || addr == owner) return true;

        return false;
    }

    /// @notice Returns the top-level ITS interchain token ID for InterchainTEL
    /// @dev The interchain token ID is *custom-linked*, ie based on Ethereum ERC20 TEL, and shared across chains
    function interchainTokenId() public view override returns (bytes32) {
        //todo
        // return keccak256(abi.encode(PREFIX_INTERCHAIN_TOKEN_ID, TOKEN_FACTORY_DEPLOYER, linkedTokenDeploySalt()));
    }
    
    /// @inheritdoc InterchainTokenStandard
    function interchainTokenService() public view override returns (address) {
        //todo
        // return _interchainTokenService;
    }

    /// @dev Required by InterchainTokenStandard
    function _spendAllowance(
        address sender,
        address spender,
        uint256 amount
    )
        internal
        virtual
        override(ERC20, InterchainTokenStandard)
    {
        ERC20._spendAllowance(sender, spender, amount);
    }
}
