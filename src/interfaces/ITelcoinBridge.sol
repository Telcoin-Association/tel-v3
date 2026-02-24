// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {MessagingFee, MessagingReceipt} from "@layerzerolabs/oapp-evm/contracts/oapp/OApp.sol";

interface ITelcoinBridge {
    // ~ Events ~

    /// @notice Emitted when tokens are bridged to another chain
    event BridgeSent(bytes32 indexed guid, uint32 indexed dstEid, address indexed from, address to, uint256 amount);

    /// @notice Emitted when tokens are received from another chain
    event BridgeReceived(bytes32 indexed guid, uint32 indexed srcEid, address indexed to, uint256 amount);

    /// @notice Emitted when destination gas limit is updated
    event DstGasLimitSet(uint128 dstGasLimit);

    // ~ Errors ~

    error ZeroAmount();
    error ZeroAddress();

    // ~ Functions ~

    function bridge(uint32 _dstEid, address _to, uint256 _amount, bytes calldata _options)
        external
        payable
        returns (MessagingReceipt memory receipt);

    function quote(uint32 _dstEid, address _to, uint256 _amount, bytes calldata _options)
        external
        view
        returns (MessagingFee memory fee);

    function setDstGasLimit(uint128 _dstGasLimit) external;

    function rescueTokens(address _token, uint256 _amount) external;
}
