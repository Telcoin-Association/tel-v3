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
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {Nonces} from "@openzeppelin/contracts/utils/Nonces.sol";
import {IERC20Mintable} from "./interfaces/IERC20Mintable.sol";
import {IEIP3009} from "./interfaces/IEIP3009.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {Roles} from "./helpers/Roles.sol";

/**
 * @title TelcoinV3
 * @author Telcoin Association
 * @notice Telcoin ERC20 token with 18 decimals. Supports role-based minting/burning, pausable transfers,
 *         EIP-2612 (permit) and EIP-3009 (transferWithAuthorization).
 */
contract TelcoinV3 is IERC20Mintable, IEIP3009, ERC20Permit, Pausable, Roles, AccessControlEnumerable {
    using SafeERC20 for IERC20;

    uint256 public constant MIGRATION_SUPPLY_CAP = 100_000_000_000 ether; // 100B tokens with 18 decimals

    // EIP-3009 type hashes
    bytes32 public constant TRANSFER_WITH_AUTHORIZATION_TYPEHASH = keccak256(
        "TransferWithAuthorization(address from,address to,uint256 value,uint256 validAfter,uint256 validBefore,bytes32 nonce)"
    );
    bytes32 public constant RECEIVE_WITH_AUTHORIZATION_TYPEHASH = keccak256(
        "ReceiveWithAuthorization(address from,address to,uint256 value,uint256 validAfter,uint256 validBefore,bytes32 nonce)"
    );
    bytes32 public constant CANCEL_AUTHORIZATION_TYPEHASH = keccak256(
        "CancelAuthorization(address authorizer,bytes32 nonce)"
    );
    bytes32 private constant PERMIT_TYPEHASH = keccak256(
        "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
    );

    // EIP-3009 authorization states (authorizer => nonce => used)
    mapping(address => mapping(bytes32 => bool)) private _authorizationStates;

    error SupplyCapExceeded();
    error CannotRenounceRole();
    error ZeroAddress();
    error ZeroAmount();
    error AuthorizationNotYetValid();
    error AuthorizationExpired();
    error AuthorizationAlreadyUsed();
    error CallerMustBePayee();
    error InvalidSignature();

    /**
     * @dev Constructor that optionally mints an initial supply to the admin address
     * @param initialSupply_ The initial supply to mint on this chain. Tokens go to admin. Can be 0.
     * @param admin_ The owner (Telcoin TAO Governance Safe)
     */
    constructor(uint256 initialSupply_, address admin_) ERC20("Telcoin", "TEL") ERC20Permit("Telcoin") {
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
     * @dev Uses SignatureChecker instead of raw ECDSA.recover so both EOAs and contract wallets
     *      (Gnosis Safe, ERC-4337 accounts) can sign permits.
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
        if (block.timestamp > deadline) {
            revert ERC2612ExpiredSignature(deadline);
        }

        bytes32 structHash = keccak256(abi.encode(PERMIT_TYPEHASH, owner_, spender, value, _useNonce(owner_), deadline));
        bytes32 hash = _hashTypedDataV4(structHash);

        if (!SignatureChecker.isValidSignatureNow(owner_, hash, abi.encodePacked(r, s, v))) {
            revert InvalidSignature();
        }

        _approve(owner_, spender, value);
    }

    // --------
    // EIP-3009
    // --------

    /// @inheritdoc IEIP3009
    function authorizationState(address authorizer, bytes32 nonce) external view returns (bool) {
        return _authorizationStates[authorizer][nonce];
    }

    /// @inheritdoc IEIP3009
    function transferWithAuthorization(
        address from,
        address to,
        uint256 value,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        _requireValidAuthorization(from, validAfter, validBefore, nonce);

        bytes32 structHash = keccak256(
            abi.encode(TRANSFER_WITH_AUTHORIZATION_TYPEHASH, from, to, value, validAfter, validBefore, nonce)
        );
        _verifyEIP712Signature(from, structHash, v, r, s);

        _markAuthorizationUsed(from, nonce);
        _transfer(from, to, value);
    }

    /// @inheritdoc IEIP3009
    function receiveWithAuthorization(
        address from,
        address to,
        uint256 value,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        if (to != msg.sender) revert CallerMustBePayee();
        _requireValidAuthorization(from, validAfter, validBefore, nonce);

        bytes32 structHash = keccak256(
            abi.encode(RECEIVE_WITH_AUTHORIZATION_TYPEHASH, from, to, value, validAfter, validBefore, nonce)
        );
        _verifyEIP712Signature(from, structHash, v, r, s);

        _markAuthorizationUsed(from, nonce);
        _transfer(from, to, value);
    }

    /// @inheritdoc IEIP3009
    function cancelAuthorization(
        address authorizer,
        bytes32 nonce,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        if (_authorizationStates[authorizer][nonce]) revert AuthorizationAlreadyUsed();

        bytes32 structHash = keccak256(abi.encode(CANCEL_AUTHORIZATION_TYPEHASH, authorizer, nonce));
        _verifyEIP712Signature(authorizer, structHash, v, r, s);

        _authorizationStates[authorizer][nonce] = true;
        emit AuthorizationCanceled(authorizer, nonce);
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

    /// @dev Validates authorization timing and nonce state
    function _requireValidAuthorization(
        address authorizer,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce
    ) private view {
        if (block.timestamp <= validAfter) revert AuthorizationNotYetValid();
        if (block.timestamp >= validBefore) revert AuthorizationExpired();
        if (_authorizationStates[authorizer][nonce]) revert AuthorizationAlreadyUsed();
    }

    /// @dev Marks an authorization nonce as used
    function _markAuthorizationUsed(address authorizer, bytes32 nonce) private {
        _authorizationStates[authorizer][nonce] = true;
        emit AuthorizationUsed(authorizer, nonce);
    }

    /// @dev Verifies an EIP-712 signature against the expected signer (supports EOA and EIP-1271 contract wallets)
    function _verifyEIP712Signature(address signer_, bytes32 structHash, uint8 v, bytes32 r, bytes32 s) private view {
        bytes32 digest = _hashTypedDataV4(structHash);
        if (!SignatureChecker.isValidSignatureNow(signer_, digest, abi.encodePacked(r, s, v))) {
            revert InvalidSignature();
        }
    }
}
