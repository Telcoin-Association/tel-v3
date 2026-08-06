// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ISimplePlugin} from "../amirx/interfaces/ISimplePlugin.sol";

/// @notice TEL3-aware referral plugin stub. Mirrors the production plugin's
///         behavior of pulling the referral fee from AmirX's allowance and
///         crediting the referrer.
contract TestPlugin is ISimplePlugin {
    IERC20 public immutable tel;
    mapping(address => uint256) public claimable;

    constructor(IERC20 tel_) {
        tel = tel_;
    }

    function increaseClaimableBy(
        address account,
        uint256 amount
    ) external returns (bool) {
        tel.transferFrom(msg.sender, address(this), amount);
        claimable[account] += amount;
        return true;
    }

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return
            interfaceId == type(ISimplePlugin).interfaceId ||
            interfaceId == 0x01ffc9a7; // IERC165
    }
}
