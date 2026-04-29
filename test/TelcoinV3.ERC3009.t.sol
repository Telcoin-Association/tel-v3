// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {TelcoinV3} from "../src/TelcoinV3.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {TelcoinV3BaseSetup} from "./BaseSetup.sol";

/**
 * @title TelcoinV3ERC3009Test
 * @notice Tests for EIP-3009 (transferWithAuthorization) functionality on TelcoinV3, covering
 *         authorized transfers, receive authorization, cancellation, replay protection,
 *         time-window validation, signature verification, and pausability interactions.
 */
contract TelcoinV3ERC3009Test is TelcoinV3BaseSetup {
    // -------------------------
    // transferWithAuthorization
    // -------------------------

    /// @notice transferWithAuthorization succeeds with a valid signature.
    function test_TransferWithAuthorization() public {
        uint256 amount = 500 ether;
        uint256 validAfter = block.timestamp - 1;
        uint256 validBefore = block.timestamp + 1 hours;
        bytes32 nonce = bytes32(uint256(1));

        bytes32 structHash = keccak256(
            abi.encode(
                token.TRANSFER_WITH_AUTHORIZATION_TYPEHASH(),
                signer, user, amount, validAfter, validBefore, nonce
            )
        );
        bytes32 digest = _buildDigest(structHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPk, digest);

        uint256 preBal = token.balanceOf(user);

        vm.prank(user2); // anyone can submit
        token.transferWithAuthorization(signer, user, amount, validAfter, validBefore, nonce, v, r, s);

        assertEq(token.balanceOf(user), preBal + amount);
        assertTrue(token.authorizationState(signer, nonce));
    }

    /// @notice transferWithAuthorization reverts when nonce is reused.
    function test_RevertIf_TransferAuth_NonceReused() public {
        uint256 amount = 100 ether;
        uint256 validAfter = block.timestamp - 1;
        uint256 validBefore = block.timestamp + 1 hours;
        bytes32 nonce = bytes32(uint256(42));

        bytes32 structHash = keccak256(
            abi.encode(
                token.TRANSFER_WITH_AUTHORIZATION_TYPEHASH(),
                signer, user, amount, validAfter, validBefore, nonce
            )
        );
        bytes32 digest = _buildDigest(structHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPk, digest);

        token.transferWithAuthorization(signer, user, amount, validAfter, validBefore, nonce, v, r, s);

        vm.expectRevert(TelcoinV3.AuthorizationAlreadyUsed.selector);
        token.transferWithAuthorization(signer, user, amount, validAfter, validBefore, nonce, v, r, s);
    }

    /// @notice transferWithAuthorization reverts when not yet valid.
    function test_RevertIf_TransferAuth_NotYetValid() public {
        uint256 validAfter = block.timestamp + 1 hours; // future
        uint256 validBefore = block.timestamp + 2 hours;
        bytes32 nonce = bytes32(uint256(2));

        bytes32 structHash = keccak256(
            abi.encode(
                token.TRANSFER_WITH_AUTHORIZATION_TYPEHASH(),
                signer, user, 100 ether, validAfter, validBefore, nonce
            )
        );
        bytes32 digest = _buildDigest(structHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPk, digest);

        vm.expectRevert(TelcoinV3.AuthorizationNotYetValid.selector);
        token.transferWithAuthorization(signer, user, 100 ether, validAfter, validBefore, nonce, v, r, s);
    }

    /// @notice transferWithAuthorization reverts when expired.
    function test_RevertIf_TransferAuth_Expired() public {
        vm.warp(10_000); // ensure block.timestamp is large enough
        uint256 validAfter = block.timestamp - 2 hours;
        uint256 validBefore = block.timestamp - 1; // past
        bytes32 nonce = bytes32(uint256(3));

        bytes32 structHash = keccak256(
            abi.encode(
                token.TRANSFER_WITH_AUTHORIZATION_TYPEHASH(),
                signer, user, 100 ether, validAfter, validBefore, nonce
            )
        );
        bytes32 digest = _buildDigest(structHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPk, digest);

        vm.expectRevert(TelcoinV3.AuthorizationExpired.selector);
        token.transferWithAuthorization(signer, user, 100 ether, validAfter, validBefore, nonce, v, r, s);
    }

    /// @notice transferWithAuthorization reverts with a wrong signer.
    function test_RevertIf_TransferAuth_WrongSigner() public {
        (, uint256 wrongPk) = makeAddrAndKey("wrongSigner");
        uint256 validAfter = block.timestamp - 1;
        uint256 validBefore = block.timestamp + 1 hours;
        bytes32 nonce = bytes32(uint256(4));

        bytes32 structHash = keccak256(
            abi.encode(
                token.TRANSFER_WITH_AUTHORIZATION_TYPEHASH(),
                signer, user, 100 ether, validAfter, validBefore, nonce
            )
        );
        bytes32 digest = _buildDigest(structHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(wrongPk, digest);

        vm.expectRevert(ECDSA.ECDSAInvalidSignature.selector);
        token.transferWithAuthorization(signer, user, 100 ether, validAfter, validBefore, nonce, v, r, s);
    }

    /// @notice transferWithAuthorization respects pause.
    function test_RevertIf_TransferAuth_WhilePaused() public {
        uint256 validAfter = block.timestamp - 1;
        uint256 validBefore = block.timestamp + 1 hours;
        bytes32 nonce = bytes32(uint256(5));

        bytes32 structHash = keccak256(
            abi.encode(
                token.TRANSFER_WITH_AUTHORIZATION_TYPEHASH(),
                signer, user, 100 ether, validAfter, validBefore, nonce
            )
        );
        bytes32 digest = _buildDigest(structHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPk, digest);

        vm.prank(owner);
        token.pause();

        vm.expectRevert();
        token.transferWithAuthorization(signer, user, 100 ether, validAfter, validBefore, nonce, v, r, s);
    }

    // ------------------------
    // receiveWithAuthorization
    // ------------------------

    /// @notice receiveWithAuthorization succeeds when caller is the payee.
    function test_ReceiveWithAuthorization() public {
        uint256 amount = 200 ether;
        uint256 validAfter = block.timestamp - 1;
        uint256 validBefore = block.timestamp + 1 hours;
        bytes32 nonce = bytes32(uint256(10));

        bytes32 structHash = keccak256(
            abi.encode(
                token.RECEIVE_WITH_AUTHORIZATION_TYPEHASH(),
                signer, user, amount, validAfter, validBefore, nonce
            )
        );
        bytes32 digest = _buildDigest(structHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPk, digest);

        uint256 preBal = token.balanceOf(user);

        vm.prank(user); // caller must be payee
        token.receiveWithAuthorization(signer, user, amount, validAfter, validBefore, nonce, v, r, s);

        assertEq(token.balanceOf(user), preBal + amount);
    }

    /// @notice receiveWithAuthorization reverts when caller is not the payee.
    function test_RevertIf_ReceiveAuth_CallerNotPayee() public {
        uint256 validAfter = block.timestamp - 1;
        uint256 validBefore = block.timestamp + 1 hours;
        bytes32 nonce = bytes32(uint256(11));

        bytes32 structHash = keccak256(
            abi.encode(
                token.RECEIVE_WITH_AUTHORIZATION_TYPEHASH(),
                signer, user, 100 ether, validAfter, validBefore, nonce
            )
        );
        bytes32 digest = _buildDigest(structHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPk, digest);

        vm.prank(attacker); // not the payee
        vm.expectRevert(TelcoinV3.CallerMustBePayee.selector);
        token.receiveWithAuthorization(signer, user, 100 ether, validAfter, validBefore, nonce, v, r, s);
    }

    // -------------------
    // cancelAuthorization
    // -------------------

    /// @notice cancelAuthorization prevents future use of a nonce.
    function test_CancelAuthorization() public {
        bytes32 nonce = bytes32(uint256(20));

        bytes32 structHash = keccak256(
            abi.encode(token.CANCEL_AUTHORIZATION_TYPEHASH(), signer, nonce)
        );
        bytes32 digest = _buildDigest(structHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPk, digest);

        token.cancelAuthorization(signer, nonce, v, r, s);

        assertTrue(token.authorizationState(signer, nonce));

        // Now try to use the canceled nonce — should revert
        _expectRevertTransferAuth(signer, user, 100 ether, nonce, TelcoinV3.AuthorizationAlreadyUsed.selector);
    }

    /// @notice cancelAuthorization reverts if nonce was already used.
    function test_RevertIf_CancelAuth_AlreadyUsed() public {
        bytes32 nonce = bytes32(uint256(21));

        // First, use the nonce via transferWithAuthorization
        _executeTransferAuth(signer, user, 100 ether, nonce);

        // Now try to cancel
        bytes32 cancelStructHash = keccak256(
            abi.encode(token.CANCEL_AUTHORIZATION_TYPEHASH(), signer, nonce)
        );
        bytes32 cancelDigest = _buildDigest(cancelStructHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPk, cancelDigest);

        vm.expectRevert(TelcoinV3.AuthorizationAlreadyUsed.selector);
        token.cancelAuthorization(signer, nonce, v, r, s);
    }
}
