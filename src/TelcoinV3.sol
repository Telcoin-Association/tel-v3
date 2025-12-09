// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {InterchainTokenStandard} from "interchain-token-service/contracts/interchain-token/InterchainTokenStandard.sol";
import {Minter} from "interchain-token-service/contracts/utils/Minter.sol";
import {Create3AddressFixed} from "interchain-token-service/contracts/utils/Create3AddressFixed.sol";

/**
 * @title Telcoin
 * @notice Telcoin V3 featuring interchain support and 18 decimals
 */
contract TelcoinV3 is ERC20, InterchainTokenStandard, Minter, Ownable, Create3AddressFixed, Pausable {
    error NotMinter(address addr);

    /// @notice Token factory flag to be create3-agnostic; see `InterchainTokenService::TOKEN_FACTORY_DEPLOYER`
    address private constant TOKEN_FACTORY_DEPLOYER = address(0x0);
    uint256 public constant TOTAL_SUPPLY = 100_000_000_000 * 10 ** 18; // 100B tokens with 18 decimals

    /// @dev The Axelar ITS TokenManager contract address for this token
    address private immutable tokenManager;
    /// @dev The Axelar ITS contract address for this contract's chain
    address private immutable _interchainTokenService;

    /// @dev Constants for deriving the origin chain's ITS custom linked deploy salt, token id, and TokenManager address
    address private immutable originLinker;
    bytes32 private immutable originSalt;
    bytes32 private immutable originChainNameHash;
    bytes32 private constant PREFIX_CUSTOM_TOKEN_SALT = keccak256("custom-token-salt");
    bytes32 private constant PREFIX_INTERCHAIN_TOKEN_ID = keccak256("its-interchain-token-id");

    /// @dev Modifier to restrict functions to only callers with Axelar::Minter library role
    modifier onlyMinter(address addr) {
        if (!hasRole(addr, uint8(Roles.MINTER))) revert NotMinter(addr);
        _;
    }

    /**
     * @dev Constructor that mints amount specified to the migration contract
     * @param initialSupply_ The initial supply to mint on this chain
     * @param owner_ The owner (Telcoin TAO Governance Safe)
     * @param migration_ The TokenMigration contract that receives `initialSupply_` for this chain
     * @param originLinker_ The origin chain's ITS Linker contract address
     * @param originSalt_ The origin chain's ITS Linker salt used for custom linking
     * @param originChainName_ The origin chain's name
     * @param interchainTokenService_ The ITS contract address for this chain
     */
    constructor(
        uint256 initialSupply_,
        address owner_,
        address migration_,
        address originLinker_,
        bytes32 originSalt_,
        string memory originChainName_,
        address interchainTokenService_
    ) ERC20("Telcoin", "TEL") Ownable(owner_) {
        require(initialSupply_ < TOTAL_SUPPLY, "Invalid mint amount");

        originLinker = originLinker_;
        originSalt = originSalt_;
        originChainNameHash = keccak256(bytes(originChainName_));
        _interchainTokenService = interchainTokenService_;
        tokenManager = tokenManagerAddress();

        _mint(migration_, initialSupply_);
        _addMinter(owner_);
        _addMinter(tokenManagerAddress());
    }

    /// @notice InterchainTEL implementation for ITS Token Manager's mint API
    /// @dev Used by a Axelar TokenManager to manage interchain transfers
    /// @notice Can be used for future supply inflation in line with long term Telcoin roadmap
    function mint(address to, uint256 amount) external onlyMinter(msg.sender) whenNotPaused {
        _mint(to, amount);
    }

    /// @notice TelcoinV3 implementation for ITS Token Manager's burn API
    function burn(address from, uint256 amount) external onlyMinter(msg.sender) whenNotPaused {
        _burn(from, amount);
    }

    /// @notice Returns the top-level ITS interchain token ID for InterchainTEL
    /// @dev The interchain token ID is *custom-linked*, ie based on Ethereum ERC20 TEL, and shared across chains
    function interchainTokenId() public view override returns (bytes32) {
        return keccak256(abi.encode(PREFIX_INTERCHAIN_TOKEN_ID, TOKEN_FACTORY_DEPLOYER, linkedTokenDeploySalt()));
    }

    /// @notice Returns the unique salt required for InterchainTEL ITS integration
    /// @dev Equivalent to `InterchainTokenFactory::linkedTokenDeploySalt()`
    function linkedTokenDeploySalt() public view returns (bytes32) {
        return keccak256(abi.encode(PREFIX_CUSTOM_TOKEN_SALT, originChainNameHash, originLinker, originSalt));
    }

    /// @notice Returns the create3 salt used by ITS for TokenManager deployment
    /// @dev This salt is used to deploy/derive TokenManagers for both Ethereum and TN
    /// @dev ITS uses `interchainTokenId()` as the create3 salt used to deploy TokenManagers
    function tokenManagerCreate3Salt() public view returns (bytes32) {
        return interchainTokenId();
    }

    /// @notice Returns the ITS TokenManager address for InterchainTEL, derived via create3
    /// @dev ITS uses `interchainTokenId()` as the create3 salt used to deploy TokenManagers
    function tokenManagerAddress() public view returns (address) {
        address createDeploy = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            hex"ff", interchainTokenService(), tokenManagerCreate3Salt(), CREATE_DEPLOY_BYTECODE_HASH
                        )
                    )
                )
            )
        );

        return address(uint160(uint256(keccak256(abi.encodePacked(hex"d694", createDeploy, hex"01")))));
    }

    /// @inheritdoc InterchainTokenStandard
    function interchainTokenService() public view virtual override returns (address) {
        return _interchainTokenService;
    }

    /// @dev Required by InterchainTokenStandard
    function _spendAllowance(address sender, address spender, uint256 amount)
        internal
        virtual
        override(ERC20, InterchainTokenStandard)
    {
        ERC20._spendAllowance(sender, spender, amount);
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

    function pause() public whenNotPaused onlyOwner {
        _pause();
    }

    function unpause() public whenPaused onlyOwner {
        _unpause();
    }
}
