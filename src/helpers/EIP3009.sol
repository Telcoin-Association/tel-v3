// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IEIP3009} from "../interfaces/IEIP3009.sol";

/**
 * @title EIP3009
 * @author Telcoin Association
 * @notice Abstract implementation of EIP-3009 (Transfer With Authorization) with EIP-1271 support.
 * @dev Inheriting contracts must provide ERC20._transfer() and EIP712._hashTypedDataV4().
 *      All signature verification supports both EOA (65-byte packed r,s,v) and smart contract
 *      wallets (Gnosis Safe, ERC-4337) via SignatureChecker + EIP-1271.
 */
abstract contract EIP3009 is IEIP3009, ERC20, EIP712 {
    // ---------------
    // EIP-3009 State
    // ---------------

    bytes32 public constant TRANSFER_WITH_AUTHORIZATION_TYPEHASH = keccak256(
        "TransferWithAuthorization(address from,address to,uint256 value,uint256 validAfter,uint256 validBefore,bytes32 nonce)"
    );
    bytes32 public constant RECEIVE_WITH_AUTHORIZATION_TYPEHASH = keccak256(
        "ReceiveWithAuthorization(address from,address to,uint256 value,uint256 validAfter,uint256 validBefore,bytes32 nonce)"
    );
    bytes32 public constant CANCEL_AUTHORIZATION_TYPEHASH = keccak256(
        "CancelAuthorization(address authorizer,bytes32 nonce)"
    );

    /// @dev authorizer => nonce => used
    mapping(address => mapping(bytes32 => bool)) internal _authorizationStates;

    // ------
    // Errors
    // ------

    error AuthorizationNotYetValid();
    error AuthorizationExpired();
    error AuthorizationAlreadyUsed();
    error CallerMustBePayee();
    error InvalidSignature();

    // --------
    // External
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
        transferWithAuthorization(from, to, value, validAfter, validBefore, nonce, abi.encodePacked(r, s, v));
    }

    /**
     * @notice Execute a transfer with a signed authorization (arbitrary-length signature).
     * @dev Supports multi-sig wallets (Gnosis Safe) and ERC-4337 accounts via EIP-1271.
     *      EOA signatures should be packed as abi.encodePacked(r, s, v).
     */
    function transferWithAuthorization(
        address from,
        address to,
        uint256 value,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce,
        bytes memory signature
    ) public {
        _requireValidAuthorization(from, validAfter, validBefore, nonce);

        bytes32 structHash = keccak256(
            abi.encode(TRANSFER_WITH_AUTHORIZATION_TYPEHASH, from, to, value, validAfter, validBefore, nonce)
        );
        _verifyEIP712Signature(from, structHash, signature);

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
        receiveWithAuthorization(from, to, value, validAfter, validBefore, nonce, abi.encodePacked(r, s, v));
    }

    /**
     * @notice Receive a transfer with a signed authorization (arbitrary-length signature).
     * @dev Caller must be the payee (to == msg.sender) to prevent front-running.
     */
    function receiveWithAuthorization(
        address from,
        address to,
        uint256 value,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce,
        bytes memory signature
    ) public {
        if (to != msg.sender) revert CallerMustBePayee();
        _requireValidAuthorization(from, validAfter, validBefore, nonce);

        bytes32 structHash = keccak256(
            abi.encode(RECEIVE_WITH_AUTHORIZATION_TYPEHASH, from, to, value, validAfter, validBefore, nonce)
        );
        _verifyEIP712Signature(from, structHash, signature);

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
        cancelAuthorization(authorizer, nonce, abi.encodePacked(r, s, v));
    }

    /**
     * @notice Cancel an authorization (arbitrary-length signature).
     * @dev Marks the nonce as used, preventing future use by transfer or receive.
     */
    function cancelAuthorization(
        address authorizer,
        bytes32 nonce,
        bytes memory signature
    ) public {
        if (_authorizationStates[authorizer][nonce]) revert AuthorizationAlreadyUsed();

        bytes32 structHash = keccak256(abi.encode(CANCEL_AUTHORIZATION_TYPEHASH, authorizer, nonce));
        _verifyEIP712Signature(authorizer, structHash, signature);

        _authorizationStates[authorizer][nonce] = true;
        emit AuthorizationCanceled(authorizer, nonce);
    }

    // --------
    // Internal
    // --------

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

    /// @dev Verifies an EIP-712 signature (supports EOA and EIP-1271 contract wallets)
    function _verifyEIP712Signature(address signer_, bytes32 structHash, bytes memory signature) private view {
        bytes32 digest = _hashTypedDataV4(structHash);
        if (!SignatureChecker.isValidSignatureNow(signer_, digest, signature)) {
            revert InvalidSignature();
        }
    }
}
