// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import {TelcoinV3} from "../src/TelcoinV3.sol";
import {Roles} from "../src/helpers/Roles.sol";

/**
 * @title TelcoinV3BaseSetup
 * @notice Shared test harness for TelcoinV3. Deploys the token with an initial 10B supply,
 *         grants minter/burner/pauser roles, and funds an ECDSA signer for EIP-712 tests.
 */
abstract contract TelcoinV3BaseSetup is Test, Roles {
    TelcoinV3 internal token;

    address internal owner = makeAddr("owner");
    address internal bridge = makeAddr("bridge");
    address internal user = makeAddr("user");
    address internal user2 = makeAddr("user2");
    address internal attacker = makeAddr("attacker");

    uint256 internal signerPk;
    address internal signer;

    uint256 internal constant INITIAL_SUPPLY = 10_000_000_000 ether;
    uint256 internal constant MINT_AMOUNT = 500 ether;

    // -----
    // setUp
    // -----

    function setUp() public virtual {
        (signer, signerPk) = makeAddrAndKey("signer");

        vm.prank(owner);
        token = new TelcoinV3(INITIAL_SUPPLY, owner);

        vm.startPrank(owner);
        token.grantRole(MINTER_ROLE, address(bridge));
        token.grantRole(BURNER_ROLE, address(bridge));
        token.grantRole(PAUSER_ROLE, address(owner));
        token.grantRole(UNPAUSER_ROLE, address(owner));
        vm.stopPrank();

        // Fund signer for signature-based tests
        vm.prank(bridge);
        token.mint(signer, 10_000 ether);
    }

    // -------
    // Helpers
    // -------

    /// @dev Builds an EIP-712 digest using the token's domain separator.
    function _buildDigest(bytes32 structHash) internal view returns (bytes32) {
        return keccak256(abi.encodePacked("\x19\x01", token.DOMAIN_SEPARATOR(), structHash));
    }

    /// @dev Executes a transferWithAuthorization with default time window.
    function _executeTransferAuth(address from, address to, uint256 amount, bytes32 nonce) internal {
        uint256 validAfter = block.timestamp - 1;
        uint256 validBefore = block.timestamp + 1 hours;

        bytes32 structHash = keccak256(
            abi.encode(
                token.TRANSFER_WITH_AUTHORIZATION_TYPEHASH(),
                from, to, amount, validAfter, validBefore, nonce
            )
        );
        bytes32 digest = _buildDigest(structHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPk, digest);

        token.transferWithAuthorization(from, to, amount, validAfter, validBefore, nonce, v, r, s);
    }

    /// @dev Signs and attempts a transferWithAuthorization, expecting a revert.
    function _expectRevertTransferAuth(
        address from,
        address to,
        uint256 amount,
        bytes32 nonce,
        bytes4 expectedError
    ) internal {
        uint256 validAfter = block.timestamp - 1;
        uint256 validBefore = block.timestamp + 1 hours;

        bytes32 structHash = keccak256(
            abi.encode(
                token.TRANSFER_WITH_AUTHORIZATION_TYPEHASH(),
                from, to, amount, validAfter, validBefore, nonce
            )
        );
        bytes32 digest = _buildDigest(structHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPk, digest);

        vm.expectRevert(expectedError);
        token.transferWithAuthorization(from, to, amount, validAfter, validBefore, nonce, v, r, s);
    }

    /// @dev Cancels a nonce for the signer.
    function _cancelNonce(address authorizer, bytes32 nonce) internal {
        bytes32 structHash = keccak256(abi.encode(token.CANCEL_AUTHORIZATION_TYPEHASH(), authorizer, nonce));
        bytes32 digest = _buildDigest(structHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPk, digest);
        token.cancelAuthorization(authorizer, nonce, v, r, s);
    }

    /// @dev Signs and attempts a receiveWithAuthorization, expecting a revert.
    function _expectRevertReceiveAuth(
        address from,
        address to,
        uint256 amount,
        bytes32 nonce,
        bytes4 expectedError
    ) internal {
        uint256 validAfter = block.timestamp - 1;
        uint256 validBefore = block.timestamp + 1 hours;

        bytes32 structHash = keccak256(
            abi.encode(token.RECEIVE_WITH_AUTHORIZATION_TYPEHASH(), from, to, amount, validAfter, validBefore, nonce)
        );
        bytes32 digest = _buildDigest(structHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPk, digest);

        vm.prank(to);
        vm.expectRevert(expectedError);
        token.receiveWithAuthorization(from, to, amount, validAfter, validBefore, nonce, v, r, s);
    }
}
