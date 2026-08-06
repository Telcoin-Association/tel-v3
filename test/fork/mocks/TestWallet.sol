// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @notice Stand-in for a Telcoin smart wallet. In production, AmirX calls the
///         wallet with `walletData` and the wallet executes the user's swap and
///         forwards the fee; here the fee transfer is the only observable effect.
contract TestWallet {
    function transferToken(IERC20 token, address to, uint256 amount) external {
        token.transfer(to, amount);
    }

    /// @dev Generic passthrough so tests can have the wallet approve tokens or
    ///      pull funds in, mimicking arbitrary smart-wallet execution.
    function execute(
        address target,
        bytes calldata data
    ) external returns (bytes memory) {
        (bool success, bytes memory result) = target.call(data);
        require(success, "TestWallet: execute failed");
        return result;
    }

    receive() external payable {}
}
