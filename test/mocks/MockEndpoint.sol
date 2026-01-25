// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {MessagingParams, MessagingFee, MessagingReceipt, Origin} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";

/**
 * @title MockEndpoint
 * @notice A mock LayerZero V2 endpoint for testing TelcoinBridge
 * @dev Simulates send/receive without actual cross-chain messaging
 */
contract MockEndpoint {
    uint32 public immutable eid;
    uint64 public nonce;

    mapping(address => address) public delegates;

    // For simulating cross-chain delivery
    address public connectedEndpoint;
    address public connectedBridge;

    event PacketSent(
        bytes32 guid,
        uint32 dstEid,
        address sender,
        bytes32 receiver,
        bytes message,
        bytes options
    );

    constructor(uint32 _eid) {
        eid = _eid;
    }

    /// @notice Connect this endpoint to another for simulated cross-chain delivery
    function connectEndpoint(address _remoteEndpoint, address _remoteBridge) external {
        connectedEndpoint = _remoteEndpoint;
        connectedBridge = _remoteBridge;
    }

    function setDelegate(address _delegate) external {
        delegates[msg.sender] = _delegate;
    }

    function quote(
        MessagingParams calldata,
        address
    ) external pure returns (MessagingFee memory fee) {
        fee = MessagingFee({nativeFee: 0.001 ether, lzTokenFee: 0});
    }

    function send(
        MessagingParams calldata _params,
        address
    ) external payable returns (MessagingReceipt memory receipt) {
        nonce++;
        bytes32 guid = keccak256(abi.encodePacked(block.timestamp, msg.sender, nonce));

        receipt = MessagingReceipt({
            guid: guid,
            nonce: nonce,
            fee: MessagingFee({nativeFee: msg.value, lzTokenFee: 0})
        });

        emit PacketSent(
            guid,
            _params.dstEid,
            msg.sender,
            _params.receiver,
            _params.message,
            _params.options
        );
    }

    /// @notice Simulate delivering a message to the connected bridge
    /// @dev Call this after send() to simulate the cross-chain delivery
    function deliverPacket(
        uint32 _srcEid,
        bytes32 _sender,
        uint64 _nonce,
        bytes32 _guid,
        bytes calldata _message,
        address _receiver
    ) external {
        Origin memory origin = Origin({
            srcEid: _srcEid,
            sender: _sender,
            nonce: _nonce
        });

        // Call lzReceive on the target bridge
        (bool success,) = _receiver.call(
            abi.encodeWithSignature(
                "lzReceive((uint32,bytes32,uint64),bytes32,bytes,address,bytes)",
                origin,
                _guid,
                _message,
                address(0),
                bytes("")
            )
        );
        require(success, "MockEndpoint: delivery failed");
    }

    function lzToken() external pure returns (address) {
        return address(0);
    }
}
