// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

interface IProxyAdmin {
    function owner() external view returns (address);
    function upgradeAndCall(
        address proxy,
        address implementation,
        bytes calldata data
    ) external payable;
}