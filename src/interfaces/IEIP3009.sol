// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/**
 * @title IEIP3009
 * @notice Interface for EIP-3009: Transfer With Authorization
 * @dev https://eips.ethereum.org/EIPS/eip-3009
 */
interface IEIP3009 {
    event AuthorizationUsed(address indexed authorizer, bytes32 indexed nonce);
    event AuthorizationCanceled(address indexed authorizer, bytes32 indexed nonce);

    /**
     * @notice Execute a transfer with a signed authorization
     * @param from        Payer's address (authorizer)
     * @param to          Payee's address
     * @param value       Amount to transfer
     * @param validAfter  Earliest unix timestamp the authorization is valid
     * @param validBefore Latest unix timestamp the authorization is valid
     * @param nonce       Unique nonce (random bytes32, not sequential)
     * @param v           v of the signature
     * @param r           r of the signature
     * @param s           s of the signature
     */
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
    ) external;

    /**
     * @notice Receive a transfer with a signed authorization from the payer
     * @dev This has an additional check that the caller is the payee, preventing front-running
     * @param from        Payer's address (authorizer)
     * @param to          Payee's address
     * @param value       Amount to transfer
     * @param validAfter  Earliest unix timestamp the authorization is valid
     * @param validBefore Latest unix timestamp the authorization is valid
     * @param nonce       Unique nonce (random bytes32, not sequential)
     * @param v           v of the signature
     * @param r           r of the signature
     * @param s           s of the signature
     */
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
    ) external;

    /**
     * @notice Attempt to cancel an authorization
     * @param authorizer  Authorizer's address
     * @param nonce       Nonce of the authorization
     * @param v           v of the signature
     * @param r           r of the signature
     * @param s           s of the signature
     */
    function cancelAuthorization(
        address authorizer,
        bytes32 nonce,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;

    /**
     * @notice Returns the state of an authorization
     * @param authorizer  Authorizer's address
     * @param nonce       Nonce of the authorization
     * @return True if the nonce has been used
     */
    function authorizationState(address authorizer, bytes32 nonce) external view returns (bool);
}
