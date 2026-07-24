// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {AccessControlEnumerable} from "@openzeppelin/contracts/access/extensions/AccessControlEnumerable.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import {IERC20Mintable} from "./interfaces/IERC20Mintable.sol";
import {EIP3009} from "./helpers/EIP3009.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {Roles} from "./helpers/Roles.sol";

/**
 * @title TelcoinV3
 * @author Telcoin Association
 * @notice Telcoin ERC20 token with 18 decimals. Supports role-based minting/burning, pausable transfers,
 *         EIP-2612 (permit) and EIP-3009 (transferWithAuthorization).
 */
contract TelcoinV3 is IERC20Mintable, EIP3009, ERC20Permit, Pausable, Roles, AccessControlEnumerable {
    using SafeERC20 for IERC20;

    uint256 public constant MIGRATION_SUPPLY_CAP = 100_000_000_000 ether; // 100B tokens with 18 decimals

    bytes32 public constant PERMIT_TYPEHASH = keccak256(
        "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
    );

    error SupplyCapExceeded();
    error CannotRenounceRole();
    error ZeroAddress();
    error ZeroAmount();

    /**
     * @dev Constructor. Assigns initial state for TelcoinV3.
     * @param admin_ The owner (Telcoin TAO Governance Safe)
     */
    constructor(address admin_) ERC20("Telcoin", "TEL") ERC20Permit("Telcoin") {
        if (admin_ == address(0)) revert ZeroAddress();
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

    /**
     * @notice Burns tokens from `from`. Requires `from` to have approved the caller.
     * @dev Enforces allowance so a compromised BURNER_ROLE cannot drain arbitrary wallets.
     *      The bridge (MintBurnWrapper) must hold an allowance from the user before calling.
     * @param from Address to burn from
     * @param amount Amount to burn
     */
    function burn(address from, uint256 amount) external onlyRole(BURNER_ROLE) {
        _spendAllowance(from, msg.sender, amount);
        _burn(from, amount);
    }

    /**
     * @notice Burns tokens from any wallet without requiring an approval.
     * @dev Reserved for governance use in emergency situations (e.g. burning hacker balances).
     *      Gated by DEFAULT_ADMIN_ROLE — not callable by normal BURNER_ROLE holders.
     * @param from Address to burn from
     * @param amount Amount to burn
     */
    function rescueBurn(address from, uint256 amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
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
    function rescueTokens(address _token, uint256 _amount, address _to) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_to == address(0)) revert ZeroAddress();
        if (_amount == 0) revert ZeroAmount();
        IERC20(_token).safeTransfer(_to, _amount);
    }

    // --------
    // EIP-2612
    // --------

    /**
     * @notice Overrides ERC20Permit.permit to support EIP-1271 smart contract wallet signatures.
     * @dev EOA wallet signatures should be packed in the order of r, s, v.
     *      For multi-sig wallets (Gnosis Safe threshold > 1), use the bytes signature overload.
     */
    function permit(
        address owner_,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public override {
        permit(owner_, spender, value, deadline, abi.encodePacked(r, s, v));
    }

    /**
     * @notice Permit with arbitrary-length signature for full EIP-1271 support.
     * @dev Accepts any signature format — EOA (65 bytes packed r,s,v) or multi-sig blobs
     *      (Gnosis Safe concatenated signatures). Uses SignatureChecker which routes to
     *      ECDSA.recover for EOAs or IERC1271.isValidSignature for contract wallets.
     *
     *      Accounts with code — including EIP-7702 delegated EOAs — are validated exclusively
     *      via ERC-1271; raw ECDSA signatures from them are never accepted. This is intentional:
     *      a delegated account may have rotated or disabled its root key, or enforce policies
     *      through its delegate, and an ECDSA fallback would bypass them. Delegates that do not
     *      implement ERC-1271 cannot use permit.
     */
    function permit(
        address owner_,
        address spender,
        uint256 value,
        uint256 deadline,
        bytes memory signature
    ) public {
        if (block.timestamp > deadline) {
            revert ERC2612ExpiredSignature(deadline);
        }

        bytes32 structHash = keccak256(abi.encode(PERMIT_TYPEHASH, owner_, spender, value, _useNonce(owner_), deadline));
        bytes32 hash = _hashTypedDataV4(structHash);

        if (!SignatureChecker.isValidSignatureNow(owner_, hash, signature)) {
            revert InvalidSignature();
        }

        _approve(owner_, spender, value);
    }

    // --------------
    // Access Control
    // --------------

    /**
     * @notice Disabled — roles may only be revoked by an admin, never self-renounced.
     * @dev Overrides AccessControl.renounceRole to prevent any role holder, including
     *      the DEFAULT_ADMIN_ROLE, from voluntarily giving up their role.
     */
    function renounceRole(bytes32, address) public pure override(AccessControl, IAccessControl) {
        revert CannotRenounceRole();
    }

    /**
     * @notice Revoke a role, except an admin removing its own DEFAULT_ADMIN_ROLE.
     * @dev Closes the renounceRole bypass: DEFAULT_ADMIN_ROLE administers itself, so a sole
     *      admin could otherwise self-revoke and permanently disable role administration and
     *      rescue functions. Admin handover remains possible — grant the new admin, then the
     *      new admin revokes the old one.
     */
    function revokeRole(bytes32 role, address account) public override(AccessControl, IAccessControl) {
        if (role == DEFAULT_ADMIN_ROLE && account == msg.sender) revert CannotRenounceRole();
        super.revokeRole(role, account);
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
