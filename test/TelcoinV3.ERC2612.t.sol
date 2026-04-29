// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {TelcoinV3BaseSetup} from "./BaseSetup.sol";

/**
 * @title TelcoinV3ERC2612Test
 * @notice Tests for EIP-2612 (permit) functionality on TelcoinV3, verifying gasless approvals
 *         via EIP-712 signed messages including valid permits, expired deadlines, and invalid signers.
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
}
