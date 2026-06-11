// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {TelcoinV3} from "../src/TelcoinV3.sol";
import {EIP3009} from "../src/helpers/EIP3009.sol";
import {TelcoinV3BaseSetup} from "./BaseSetup.sol";
import {MockERC1271Wallet} from "./mocks/MockERC1271Wallet.sol";

/**
 * @title TelcoinV3ERC3009Test
 * @notice Tests for EIP-3009 (transferWithAuthorization) functionality on TelcoinV3, covering
 *         authorized transfers, receive authorization, cancellation, replay protection,
 *         time-window validation, signature verification, pausability interactions, edge cases,
 *         and EIP-1271 smart contract wallet signatures.
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

        vm.expectRevert(EIP3009.AuthorizationAlreadyUsed.selector);
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

        vm.expectRevert(EIP3009.AuthorizationNotYetValid.selector);
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

        vm.expectRevert(EIP3009.AuthorizationExpired.selector);
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

        vm.expectRevert(EIP3009.InvalidSignature.selector);
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
        vm.expectRevert(EIP3009.CallerMustBePayee.selector);
        token.receiveWithAuthorization(signer, user, 100 ether, validAfter, validBefore, nonce, v, r, s);
    }

    /// @notice receiveWithAuthorization reverts when paused.
    function test_RevertIf_ReceiveAuth_WhilePaused() public {
        uint256 validAfter = block.timestamp - 1;
        uint256 validBefore = block.timestamp + 1 hours;
        bytes32 nonce = bytes32(uint256(12));

        bytes32 structHash = keccak256(
            abi.encode(
                token.RECEIVE_WITH_AUTHORIZATION_TYPEHASH(),
                signer, user, 100 ether, validAfter, validBefore, nonce
            )
        );
        bytes32 digest = _buildDigest(structHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPk, digest);

        vm.prank(owner);
        token.pause();

        vm.prank(user);
        vm.expectRevert();
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
        _expectRevertTransferAuth(signer, user, 100 ether, nonce, EIP3009.AuthorizationAlreadyUsed.selector);
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

        vm.expectRevert(EIP3009.AuthorizationAlreadyUsed.selector);
        token.cancelAuthorization(signer, nonce, v, r, s);
    }

    /// @notice cancelAuthorization reverts with a wrong signer.
    function test_RevertIf_CancelAuth_WrongSigner() public {
        (, uint256 wrongPk) = makeAddrAndKey("wrongCancel");
        bytes32 nonce = bytes32(uint256(22));

        bytes32 structHash = keccak256(
            abi.encode(token.CANCEL_AUTHORIZATION_TYPEHASH(), signer, nonce)
        );
        bytes32 digest = _buildDigest(structHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(wrongPk, digest);

        vm.expectRevert(EIP3009.InvalidSignature.selector);
        token.cancelAuthorization(signer, nonce, v, r, s);
    }

    /// @notice cancelAuthorization blocks receiveWithAuthorization (not just transferWithAuthorization).
    function test_CancelAuth_BlocksReceiveAuth() public {
        bytes32 nonce = bytes32(uint256(23));

        // Cancel the nonce
        _cancelNonce(signer, nonce);

        // Now try receiveWithAuthorization with the canceled nonce — should revert
        _expectRevertReceiveAuth(signer, user, 100 ether, nonce, EIP3009.AuthorizationAlreadyUsed.selector);
    }

    // ----------
    // Edge Cases
    // ----------

    /// @notice Zero-value transferWithAuthorization succeeds and consumes nonce.
    function test_TransferAuth_ZeroValue() public {
        bytes32 nonce = bytes32(uint256(30));
        uint256 validAfter = block.timestamp - 1;
        uint256 validBefore = block.timestamp + 1 hours;

        bytes32 structHash = keccak256(
            abi.encode(token.TRANSFER_WITH_AUTHORIZATION_TYPEHASH(), signer, user, uint256(0), validAfter, validBefore, nonce)
        );
        bytes32 digest = _buildDigest(structHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPk, digest);

        token.transferWithAuthorization(signer, user, 0, validAfter, validBefore, nonce, v, r, s);

        assertTrue(token.authorizationState(signer, nonce));
    }

    /// @notice Self-transfer (from == to) succeeds as a no-op on balances.
    function test_TransferAuth_SelfTransfer() public {
        bytes32 nonce = bytes32(uint256(31));
        uint256 preBal = token.balanceOf(signer);

        _executeTransferAuth(signer, signer, 100 ether, nonce);

        assertEq(token.balanceOf(signer), preBal);
        assertTrue(token.authorizationState(signer, nonce));
    }

    /// @notice validAfter == validBefore creates an unusable authorization (no valid timestamp).
    function test_RevertIf_TransferAuth_EqualTimeBounds() public {
        uint256 t = block.timestamp;
        bytes32 nonce = bytes32(uint256(32));

        bytes32 structHash = keccak256(
            abi.encode(token.TRANSFER_WITH_AUTHORIZATION_TYPEHASH(), signer, user, 100 ether, t, t, nonce)
        );
        bytes32 digest = _buildDigest(structHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPk, digest);

        // block.timestamp == validAfter means <= check fails with AuthorizationNotYetValid
        vm.expectRevert(EIP3009.AuthorizationNotYetValid.selector);
        token.transferWithAuthorization(signer, user, 100 ether, t, t, nonce, v, r, s);
    }

    /// @notice validAfter=0, validBefore=type(uint256).max is the "no time restriction" case.
    function test_TransferAuth_NoTimeRestriction() public {
        bytes32 nonce = bytes32(uint256(33));
        uint256 validAfter = 0;
        uint256 validBefore = type(uint256).max;

        bytes32 structHash = keccak256(
            abi.encode(token.TRANSFER_WITH_AUTHORIZATION_TYPEHASH(), signer, user, 50 ether, validAfter, validBefore, nonce)
        );
        bytes32 digest = _buildDigest(structHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPk, digest);

        uint256 preBal = token.balanceOf(user);
        token.transferWithAuthorization(signer, user, 50 ether, validAfter, validBefore, nonce, v, r, s);

        assertEq(token.balanceOf(user), preBal + 50 ether);
    }

    /// @notice A transferWithAuthorization signature cannot be used for receiveWithAuthorization (different type hash).
    function test_RevertIf_CrossFunctionReplay_TransferAsReceive() public {
        uint256 validAfter = block.timestamp - 1;
        uint256 validBefore = block.timestamp + 1 hours;
        bytes32 nonce = bytes32(uint256(34));

        // Sign a transferWithAuthorization
        bytes32 transferHash = keccak256(
            abi.encode(token.TRANSFER_WITH_AUTHORIZATION_TYPEHASH(), signer, user, 100 ether, validAfter, validBefore, nonce)
        );
        bytes32 digest = _buildDigest(transferHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPk, digest);

        // Try to use it as a receiveWithAuthorization — different type hash means different digest
        vm.prank(user);
        vm.expectRevert(EIP3009.InvalidSignature.selector);
        token.receiveWithAuthorization(signer, user, 100 ether, validAfter, validBefore, nonce, v, r, s);
    }

    // ------------------------------
    // EIP-1271 Smart Contract Wallet
    // ------------------------------

    /// @notice transferWithAuthorization works with an EIP-1271 contract wallet.
    function test_TransferAuth_EIP1271Wallet() public {
        // Deploy a mock EIP-1271 wallet that approves everything
        MockERC1271Wallet wallet = new MockERC1271Wallet();

        // Fund the wallet
        vm.prank(bridge);
        token.mint(address(wallet), 1000 ether);

        bytes32 nonce = bytes32(uint256(40));
        uint256 validAfter = block.timestamp - 1;
        uint256 validBefore = block.timestamp + 1 hours;
        uint256 amount = 100 ether;

        bytes32 structHash = keccak256(
            abi.encode(token.TRANSFER_WITH_AUTHORIZATION_TYPEHASH(), address(wallet), user, amount, validAfter, validBefore, nonce)
        );
        bytes32 digest = _buildDigest(structHash);

        // Set the expected hash on the mock wallet
        wallet.setValidHash(digest);

        uint256 preBal = token.balanceOf(user);

        // v, r, s don't matter for the mock — it checks the hash directly
        token.transferWithAuthorization(address(wallet), user, amount, validAfter, validBefore, nonce, 27, bytes32(uint256(1)), bytes32(uint256(2)));

        assertEq(token.balanceOf(user), preBal + amount);
    }

    /// @notice transferWithAuthorization reverts when EIP-1271 wallet rejects the signature.
    function test_RevertIf_TransferAuth_EIP1271WalletRejects() public {
        MockERC1271Wallet wallet = new MockERC1271Wallet();

        vm.prank(bridge);
        token.mint(address(wallet), 1000 ether);

        bytes32 nonce = bytes32(uint256(41));
        uint256 validAfter = block.timestamp - 1;
        uint256 validBefore = block.timestamp + 1 hours;

        // Don't set a valid hash — wallet will reject

        vm.expectRevert(EIP3009.InvalidSignature.selector);
        token.transferWithAuthorization(address(wallet), user, 100 ether, validAfter, validBefore, nonce, 27, bytes32(uint256(1)), bytes32(uint256(2)));
    }

    // -----------------------------------
    // bytes signature overloads (EIP-1271)
    // -----------------------------------

    /// @notice transferWithAuthorization(bytes) works with EOA signature passed as bytes.
    function test_TransferAuth_BytesSignature_EOA() public {
        uint256 amount = 200 ether;
        uint256 validAfter = block.timestamp - 1;
        uint256 validBefore = block.timestamp + 1 hours;
        bytes32 nonce = bytes32(uint256(50));

        bytes32 structHash = keccak256(
            abi.encode(token.TRANSFER_WITH_AUTHORIZATION_TYPEHASH(), signer, user, amount, validAfter, validBefore, nonce)
        );
        bytes32 digest = _buildDigest(structHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPk, digest);

        uint256 preBal = token.balanceOf(user);

        token.transferWithAuthorization(signer, user, amount, validAfter, validBefore, nonce, abi.encodePacked(r, s, v));

        assertEq(token.balanceOf(user), preBal + amount);
        assertTrue(token.authorizationState(signer, nonce));
    }

    /// @notice transferWithAuthorization(bytes) works with EIP-1271 wallet passing arbitrary blob.
    function test_TransferAuth_BytesSignature_EIP1271Wallet() public {
        MockERC1271Wallet wallet = new MockERC1271Wallet();

        vm.prank(bridge);
        token.mint(address(wallet), 1000 ether);

        bytes32 nonce = bytes32(uint256(51));
        uint256 validAfter = block.timestamp - 1;
        uint256 validBefore = block.timestamp + 1 hours;
        uint256 amount = 100 ether;

        bytes32 structHash = keccak256(
            abi.encode(token.TRANSFER_WITH_AUTHORIZATION_TYPEHASH(), address(wallet), user, amount, validAfter, validBefore, nonce)
        );
        bytes32 digest = _buildDigest(structHash);
        wallet.setValidHash(digest);

        uint256 preBal = token.balanceOf(user);

        // Arbitrary-length signature blob (simulating multi-sig Safe)
        bytes memory fakeSig = abi.encodePacked(bytes32(uint256(1)), bytes32(uint256(2)), uint8(27), bytes("extra-safe-sigs"));
        token.transferWithAuthorization(address(wallet), user, amount, validAfter, validBefore, nonce, fakeSig);

        assertEq(token.balanceOf(user), preBal + amount);
    }

    /// @notice receiveWithAuthorization(bytes) works with EOA signature passed as bytes.
    function test_ReceiveAuth_BytesSignature_EOA() public {
        uint256 amount = 150 ether;
        uint256 validAfter = block.timestamp - 1;
        uint256 validBefore = block.timestamp + 1 hours;
        bytes32 nonce = bytes32(uint256(52));

        bytes32 structHash = keccak256(
            abi.encode(token.RECEIVE_WITH_AUTHORIZATION_TYPEHASH(), signer, user, amount, validAfter, validBefore, nonce)
        );
        bytes32 digest = _buildDigest(structHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPk, digest);

        uint256 preBal = token.balanceOf(user);

        vm.prank(user);
        token.receiveWithAuthorization(signer, user, amount, validAfter, validBefore, nonce, abi.encodePacked(r, s, v));

        assertEq(token.balanceOf(user), preBal + amount);
    }

    /// @notice cancelAuthorization(bytes) works with EOA signature passed as bytes.
    function test_CancelAuth_BytesSignature_EOA() public {
        bytes32 nonce = bytes32(uint256(53));

        bytes32 structHash = keccak256(
            abi.encode(token.CANCEL_AUTHORIZATION_TYPEHASH(), signer, nonce)
        );
        bytes32 digest = _buildDigest(structHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPk, digest);

        token.cancelAuthorization(signer, nonce, abi.encodePacked(r, s, v));

        assertTrue(token.authorizationState(signer, nonce));
    }

    /// @notice cancelAuthorization(bytes) with EIP-1271 wallet passing arbitrary blob.
    function test_CancelAuth_BytesSignature_EIP1271Wallet() public {
        MockERC1271Wallet wallet = new MockERC1271Wallet();
        bytes32 nonce = bytes32(uint256(54));

        bytes32 structHash = keccak256(
            abi.encode(token.CANCEL_AUTHORIZATION_TYPEHASH(), address(wallet), nonce)
        );
        bytes32 digest = _buildDigest(structHash);
        wallet.setValidHash(digest);

        bytes memory fakeSig = abi.encodePacked(bytes32(uint256(1)), bytes32(uint256(2)), uint8(27), bytes("safe-cancel-sig"));
        token.cancelAuthorization(address(wallet), nonce, fakeSig);

        assertTrue(token.authorizationState(address(wallet), nonce));
    }

    // ---------
    // Fuzz Test
    // ---------

    /// @notice Fuzz test for transferWithAuthorization with random amounts and nonces.
    function testFuzz_TransferWithAuthorization(uint256 amount, bytes32 nonce) public {
        amount = bound(amount, 0, token.balanceOf(signer));

        uint256 preBal = token.balanceOf(user);
        uint256 preBalSigner = token.balanceOf(signer);

        _executeTransferAuth(signer, user, amount, nonce);

        assertEq(token.balanceOf(user), preBal + amount);
        assertEq(token.balanceOf(signer), preBalSigner - amount);
        assertTrue(token.authorizationState(signer, nonce));
    }
}
