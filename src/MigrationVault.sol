// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {ReentrancyGuardTransient} from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";

/**
 * @title MigrationVault
 * @author Telcoin Digital Asset Bank
 * @notice One-way migration vault for converting OLD tokens to NEW tokens at a 1:1 value rate.
 * @dev Originally designed as a Peg Stability Vault (PSV) providing bi-directional 1:1 swaps
 * between a stablecoin and its backing asset to maintain peg stability via arbitrage.
 *
 * This contract has been adapted for Phase 2 of the TEL v2 -> TEL v3 token migration:
 *   - Phase 1: TokenMigration contract provides a temporary window for 1:1 migration via minting.
 *   - Phase 2: Remaining TEL v3 supply is minted to this vault. Any remaining TEL v2 holders
 *     can swap their tokens here at 1:1 value, depleting the remaining TEL v3 balance.
 *
 * Modifications from the original PSV:
 *   - Swap direction is one-way only (OLD -> NEW).
 *   - Fee system removed (all swaps are fee-free).
 *   - Rate limiting removed.
 *   - Whitelist removed.
 *
 * Key Features:
 *   - 1:1 value swaps from OLD to NEW token (supports different decimals)
 *   - UUPS upgradeable, pausable, access controlled
 *   - Reentrancy protected
 *   - Treasury can withdraw tokens (e.g., to sell off legacy liquidity pool positions)
 *
 * Decimal Handling:
 *   - All internal calculations are normalized to 18 decimals (WAD)
 *   - Supports tokens with up to 18 decimals
 *   - Conversion factors are computed at construction time
 */
contract MigrationVault is
    AccessControlUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardTransient,
    UUPSUpgradeable
{
    using SafeERC20 for IERC20Metadata;

    // ---------
    // Constants
    // ---------

    /// @notice Precision for internal math (100% = 1e18)
    uint256 public constant WAD = 1e18;
    /// @notice Maximum supported decimals
    uint8 public constant MAX_DECIMALS = 18;
    /// @notice Role for treasury management (withdraw tokens)
    bytes32 public constant TREASURY_ROLE = keccak256("TREASURY_ROLE");
    /// @notice Role for pausing contract's core functionality
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    /// @notice Role for unpausing contract's core functionality
    bytes32 public constant UNPAUSER_ROLE = keccak256("UNPAUSER_ROLE");

    // ----------
    // Immutables
    // ----------

    /// @notice The old token to migrate from (e.g., TEL v2)
    IERC20Metadata public immutable OLD_TOKEN;
    /// @notice The new token to migrate to (e.g., TEL v3)
    IERC20Metadata public immutable NEW_TOKEN;
    /// @notice Factor to convert OLD_TOKEN amounts to WAD (10^(18 - oldDecimals))
    uint256 public immutable oldToWad;
    /// @notice Factor to convert NEW_TOKEN amounts to WAD (10^(18 - newDecimals))
    uint256 public immutable newToWad;

    // ------
    // Events
    // ------

    /// @notice Emitted when a migration swap is executed
    event Migrated(
        address indexed sender,
        address indexed recipient,
        uint256 amountIn,
        uint256 amountOut
    );
    /// @notice Emitted when treasury withdraws tokens
    event Withdrawn(address indexed token, address indexed to, uint256 amount);

    // ------
    // Errors
    // ------

    error ZeroAddress();
    error ZeroAmount();
    error InsufficientReserves();
    error DecimalsExceedMax();

    // ------------------
    // Constructor / Init
    // ------------------

    /**
     * @notice Sets immutable token configuration. Called once per implementation deployment.
     * @dev When deploying a new implementation for an upgrade, pass the same token addresses
     *      to preserve identical bytecode-embedded values across the proxy's lifetime.
     * @param _oldToken Address of the old token (e.g., TEL v2)
     * @param _newToken Address of the new token (e.g., TEL v3)
     */
    /// @custom:oz-upgrades-unsafe-allow constructor state-variable-immutable
    constructor(address _oldToken, address _newToken) {
        if (_oldToken == address(0) || _newToken == address(0)) revert ZeroAddress();

        uint8 oldDecimals = IERC20Metadata(_oldToken).decimals();
        uint8 newDecimals = IERC20Metadata(_newToken).decimals();

        if (oldDecimals > MAX_DECIMALS || newDecimals > MAX_DECIMALS) revert DecimalsExceedMax();

        OLD_TOKEN = IERC20Metadata(_oldToken);
        NEW_TOKEN = IERC20Metadata(_newToken);
        oldToWad = 10 ** (MAX_DECIMALS - oldDecimals);
        newToWad = 10 ** (MAX_DECIMALS - newDecimals);

        _disableInitializers();
    }

    /**
     * @notice Initializes access control roles for the proxy.
     * @param _admin Address of the contract admin (receives DEFAULT_ADMIN_ROLE)
     * @param _pauser Permissioned address in charge of contract pausability
     * @param _unpauser Permissioned address in charge of unpausing contract
     */
    function initialize(
        address _admin,
        address _pauser,
        address _unpauser
    ) external initializer {
        if (_admin == address(0) || _pauser == address(0) || _unpauser == address(0)) revert ZeroAddress();

        __AccessControl_init();
        __Pausable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(PAUSER_ROLE, _pauser);
        _grantRole(UNPAUSER_ROLE, _unpauser);
    }

    // -------
    // Migrate
    // -------

    /**
     * @notice Swap OLD tokens for NEW tokens at 1:1 value rate
     * @param recipient Address to receive NEW tokens
     * @param amountIn Amount of OLD tokens to swap (in OLD token decimals)
     * @return amountOut Amount of NEW tokens received (in NEW token decimals)
     */
    function migrate(
        address recipient,
        uint256 amountIn
    ) external whenNotPaused nonReentrant returns (uint256 amountOut) {
        if (recipient == address(0)) revert ZeroAddress();
        if (amountIn == 0) revert ZeroAmount();

        amountOut = _calculateMigration(amountIn);
        if (amountOut == 0) revert ZeroAmount();

        // Check reserves
        if (NEW_TOKEN.balanceOf(address(this)) < amountOut) revert InsufficientReserves();

        // Transfer OLD tokens from sender
        OLD_TOKEN.safeTransferFrom(msg.sender, address(this), amountIn);

        // Transfer NEW tokens to recipient
        NEW_TOKEN.safeTransfer(recipient, amountOut);

        emit Migrated(msg.sender, recipient, amountIn, amountOut);
    }

    // ----------------------
    // Permissioned Functions
    // ----------------------

    /// @notice Pause all migration operations
    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    /// @notice Unpause migration operations
    function unpause() external onlyRole(UNPAUSER_ROLE) {
        _unpause();
    }

    /**
     * @notice Withdraw tokens from the vault
     * @param token Address of token to withdraw
     * @param to Recipient address
     * @param amount Amount to withdraw
     */
    function withdraw(
        address token,
        address to,
        uint256 amount
    ) external nonReentrant onlyRole(TREASURY_ROLE) {
        if (token == address(0) || to == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();

        IERC20Metadata(token).safeTransfer(to, amount);

        emit Withdrawn(token, to, amount);
    }

    // ----
    // View
    // ----

    /**
     * @notice Preview the output amount for migrating OLD to NEW tokens
     * @param amountIn Amount of OLD tokens to swap (in OLD token decimals)
     * @return amountOut Amount of NEW tokens that would be received (in NEW token decimals)
     */
    function previewMigrate(uint256 amountIn) external view returns (uint256 amountOut) {
        return _calculateMigration(amountIn);
    }

    /**
     * @notice Get current reserves of both tokens
     * @return oldReserve Current OLD token balance (in OLD token decimals)
     * @return newReserve Current NEW token balance (in NEW token decimals)
     */
    function getReserves() external view returns (uint256 oldReserve, uint256 newReserve) {
        oldReserve = OLD_TOKEN.balanceOf(address(this));
        newReserve = NEW_TOKEN.balanceOf(address(this));
    }

    /**
     * @notice Get the decimal configuration
     * @return oldDecimals OLD token decimals
     * @return newDecimals NEW token decimals
     */
    function getDecimals() external view returns (uint8 oldDecimals, uint8 newDecimals) {
        oldDecimals = OLD_TOKEN.decimals();
        newDecimals = NEW_TOKEN.decimals();
    }

    // --------
    // Internal
    // --------

    /**
     * @notice Calculate output amount for migrating OLD to NEW tokens
     * @param amountIn Amount of OLD tokens (in OLD token decimals)
     * @return amountOut Amount of NEW tokens (in NEW token decimals)
     */
    function _calculateMigration(uint256 amountIn) internal view returns (uint256 amountOut) {
        // Convert input to WAD, then to output decimals (1:1 value conversion)
        uint256 amountInWad = amountIn * oldToWad;
        amountOut = amountInWad / newToWad;
    }

    /**
     * @notice Authorize contract upgrades (only admin)
     * @param newImplementation Address of new implementation
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}
}
