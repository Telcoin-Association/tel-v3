// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {TelcoinV3} from "../src/TelcoinV3.sol";
import {TelcoinV3BaseSetup} from "./BaseSetup.sol";
import {MockERC1271Wallet} from "./mocks/MockERC1271Wallet.sol";

/**
 * @title TelcoinV3ERC2612Test
 * @notice Tests for EIP-2612 (permit) functionality on TelcoinV3, verifying gasless approvals
 *         via EIP-712 signed messages including valid permits, expired deadlines, invalid signers,
 *         pausability interactions, and EIP-1271 smart contract wallet support.
 */
contract TelcoinV3ERC2612Test is TelcoinV3BaseSetup {
    bytes32 internal constant PERMIT_TYPEHASH =
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

    /// @notice permit() sets allowance with a valid signature.
    function test_Permit() public {
        uint256 amount = 1000 ether;
        uint256 deadline = block.timestamp + 1 hours;
        uint256 nonce = token.nonces(signer);

        bytes32 structHash = keccak256(
            abi.encode(PERMIT_TYPEHASH, signer, user, amount, nonce, deadline)
        );
        bytes32 digest = _buildDigest(structHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPk, digest);

        token.permit(signer, user, amount, deadline, v, r, s);

        assertEq(token.allowance(signer, user), amount);
        assertEq(token.nonces(signer), nonce + 1);
    }

    /// @notice permit() reverts with an expired deadline.
    function test_RevertIf_Permit_ExpiredDeadline() public {
        uint256 deadline = block.timestamp - 1;

        bytes32 structHash = keccak256(
            abi.encode(PERMIT_TYPEHASH, signer, user, 1000 ether, token.nonces(signer), deadline)
        );
        bytes32 digest = _buildDigest(structHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPk, digest);

        vm.expectRevert();
        token.permit(signer, user, 1000 ether, deadline, v, r, s);
    }

    /// @notice permit() reverts with a wrong signer.
    function test_RevertIf_Permit_WrongSigner() public {
        (, uint256 wrongPk) = makeAddrAndKey("wrong");
        uint256 deadline = block.timestamp + 1 hours;

        bytes32 structHash = keccak256(
            abi.encode(PERMIT_TYPEHASH, signer, user, 1000 ether, token.nonces(signer), deadline)
        );
        bytes32 digest = _buildDigest(structHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(wrongPk, digest);

        vm.expectRevert();
        token.permit(signer, user, 1000 ether, deadline, v, r, s);
    }

    /// @notice permit() succeeds while paused (approvals are not transfers).
    function test_Permit_WhilePaused() public {
        vm.prank(owner);
        token.pause();

        uint256 amount = 500 ether;
        uint256 deadline = block.timestamp + 1 hours;
        uint256 nonce = token.nonces(signer);

        bytes32 structHash = keccak256(
            abi.encode(PERMIT_TYPEHASH, signer, user, amount, nonce, deadline)
        );
        bytes32 digest = _buildDigest(structHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPk, digest);

        token.permit(signer, user, amount, deadline, v, r, s);

        assertEq(token.allowance(signer, user), amount);
    }

    /// @notice permit() works with an EIP-1271 contract wallet.
    function test_Permit_EIP1271Wallet() public {
        MockERC1271Wallet wallet = new MockERC1271Wallet();

        // Fund the wallet (it needs tokens for the approval to be meaningful)
        vm.prank(bridge);
        token.mint(address(wallet), 1000 ether);

        uint256 amount = 500 ether;
        uint256 deadline = block.timestamp + 1 hours;
        uint256 nonce = token.nonces(address(wallet));

        bytes32 structHash = keccak256(
            abi.encode(PERMIT_TYPEHASH, address(wallet), user, amount, nonce, deadline)
        );
        bytes32 digest = _buildDigest(structHash);

        wallet.setValidHash(digest);

        // v, r, s values don't matter — the mock wallet checks the digest directly
        token.permit(address(wallet), user, amount, deadline, 27, bytes32(uint256(1)), bytes32(uint256(2)));

        assertEq(token.allowance(address(wallet), user), amount);
        assertEq(token.nonces(address(wallet)), nonce + 1);
    }

    /// @notice permit() reverts when EIP-1271 wallet rejects the signature.
    function test_RevertIf_Permit_EIP1271WalletRejects() public {
        MockERC1271Wallet wallet = new MockERC1271Wallet();

        vm.prank(bridge);
        token.mint(address(wallet), 1000 ether);

        uint256 deadline = block.timestamp + 1 hours;

        // Don't set valid hash — wallet will reject
        vm.expectRevert(TelcoinV3.InvalidSignature.selector);
        token.permit(address(wallet), user, 500 ether, deadline, 27, bytes32(uint256(1)), bytes32(uint256(2)));
    }

    // -----------------------------------
    // bytes signature overload (EIP-1271)
    // -----------------------------------

    /// @notice permit(bytes) sets allowance with a valid EOA signature passed as bytes.
    function test_Permit_BytesSignature_EOA() public {
        uint256 amount = 1000 ether;
        uint256 deadline = block.timestamp + 1 hours;
        uint256 nonce = token.nonces(signer);

        bytes32 structHash = keccak256(
            abi.encode(PERMIT_TYPEHASH, signer, user, amount, nonce, deadline)
        );
        bytes32 digest = _buildDigest(structHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPk, digest);

        token.permit(signer, user, amount, deadline, abi.encodePacked(r, s, v));

        assertEq(token.allowance(signer, user), amount);
        assertEq(token.nonces(signer), nonce + 1);
    }

    /// @notice permit(bytes) works with EIP-1271 contract wallet passing arbitrary blob.
    function test_Permit_BytesSignature_EIP1271Wallet() public {
        MockERC1271Wallet wallet = new MockERC1271Wallet();

        vm.prank(bridge);
        token.mint(address(wallet), 1000 ether);

        uint256 amount = 500 ether;
        uint256 deadline = block.timestamp + 1 hours;
        uint256 nonce = token.nonces(address(wallet));

        bytes32 structHash = keccak256(
            abi.encode(PERMIT_TYPEHASH, address(wallet), user, amount, nonce, deadline)
        );
        bytes32 digest = _buildDigest(structHash);

        wallet.setValidHash(digest);

        // Pass an arbitrary-length signature blob (simulating multi-sig)
        bytes memory fakeSig = abi.encodePacked(bytes32(uint256(1)), bytes32(uint256(2)), uint8(27), bytes("extra-multisig-data"));
        token.permit(address(wallet), user, amount, deadline, fakeSig);

        assertEq(token.allowance(address(wallet), user), amount);
        assertEq(token.nonces(address(wallet)), nonce + 1);
    }

    /// @notice permit(bytes) reverts with expired deadline.
    function test_RevertIf_Permit_BytesSignature_ExpiredDeadline() public {
        uint256 deadline = block.timestamp - 1;

        bytes32 structHash = keccak256(
            abi.encode(PERMIT_TYPEHASH, signer, user, 1000 ether, token.nonces(signer), deadline)
        );
        bytes32 digest = _buildDigest(structHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPk, digest);

        vm.expectRevert();
        token.permit(signer, user, 1000 ether, deadline, abi.encodePacked(r, s, v));
    }

    /// @notice permit(bytes) reverts when EIP-1271 wallet rejects.
    function test_RevertIf_Permit_BytesSignature_EIP1271WalletRejects() public {
        MockERC1271Wallet wallet = new MockERC1271Wallet();

        vm.prank(bridge);
        token.mint(address(wallet), 1000 ether);

        uint256 deadline = block.timestamp + 1 hours;

        // Don't set valid hash — wallet will reject
        vm.expectRevert(TelcoinV3.InvalidSignature.selector);
        token.permit(address(wallet), user, 500 ether, deadline, bytes("invalid-sig"));
    }
}
