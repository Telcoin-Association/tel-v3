// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {OApp, Origin, MessagingFee, MessagingReceipt} from "@layerzerolabs/oapp-evm/contracts/oapp/OApp.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20Mintable} from "./interfaces/IERC20Mintable.sol";
import {ITelcoinBridge} from "./interfaces/ITelcoinBridge.sol";

/**
 * @title TelcoinBridge
 * @author Telcoin Labs
 * @notice LayerZero V2 bridge for TelcoinV3 cross-chain transfers
 * @dev Burns tokens on source chain, mints on destination chain
 */
contract TelcoinBridge is ITelcoinBridge, OApp, Pausable {
    using SafeERC20 for IERC20;

    // ~ Constants ~

    /// @dev Default gas limit for destination execution
    uint128 private constant DEFAULT_DST_GAS_LIMIT = 200_000;

    /// @notice The TelcoinV3 token contract
    IERC20Mintable public immutable telcoin;

    // ~ Storage ~

    /// @notice Gas limit for lzReceive execution on destination chain
    uint128 public dstGasLimit;

    // ~ Constructor ~

    /**
     * @notice Constructor
     * @param _telcoin The TelcoinV3 token address
     * @param _endpoint The local LayerZero endpoint address
     * @param _delegate The delegate/owner address for OApp configuration
     */
    constructor(
        address _telcoin,
        address _endpoint,
        address _delegate
    ) OApp(_endpoint, _delegate) Ownable(_delegate) {
        if (_telcoin == address(0)) revert ZeroAddress();
        telcoin = IERC20Mintable(_telcoin);
        dstGasLimit = DEFAULT_DST_GAS_LIMIT;
    }

    // ~ Core Methods ~

    /**
     * @notice Bridge tokens to another chain
     * @param _dstEid Destination chain endpoint ID
     * @param _to Recipient address on destination chain
     * @param _amount Amount of tokens to bridge
     * @param _options LayerZero executor options (gas, etc.)
     * @return receipt The LayerZero messaging receipt
     */
    function bridge(
        uint32 _dstEid,
        address _to,
        uint256 _amount,
        bytes calldata _options
    ) external payable whenNotPaused returns (MessagingReceipt memory receipt) {
        if (_amount == 0) revert ZeroAmount();
        if (_to == address(0)) revert ZeroAddress();

        // Burn tokens from sender
        telcoin.burn(msg.sender, _amount);

        // Encode message payload
        bytes memory payload = abi.encode(_to, _amount);

        // Send cross-chain message
        receipt = _lzSend(
            _dstEid,
            payload,
            _options,
            MessagingFee({nativeFee: msg.value, lzTokenFee: 0}),
            msg.sender // refund address
        );

        emit BridgeSent(receipt.guid, _dstEid, msg.sender, _to, _amount);
    }

    /**
     * @notice Quote the fee for bridging tokens
     * @param _dstEid Destination chain endpoint ID
     * @param _to Recipient address on destination chain
     * @param _amount Amount of tokens to bridge
     * @param _options LayerZero executor options
     * @return fee The estimated messaging fee
     */
    function quote(
        uint32 _dstEid,
        address _to,
        uint256 _amount,
        bytes calldata _options
    ) external view returns (MessagingFee memory fee) {
        bytes memory payload = abi.encode(_to, _amount);
        return _quote(_dstEid, payload, _options, false);
    }

    /**
     * @notice Internal handler for receiving cross-chain messages
     * @param _origin Origin information (source chain, sender, nonce)
     * @param _guid Global unique identifier for the message
     * @param _message Encoded payload (recipient, amount)
     */
    function _lzReceive(
        Origin calldata _origin,
        bytes32 _guid,
        bytes calldata _message,
        address /*_executor*/,
        bytes calldata /*_extraData*/
    ) internal whenNotPaused override {
        // Decode payload
        (address to, uint256 amount) = abi.decode(_message, (address, uint256));

        // Mint tokens to recipient
        telcoin.mint(to, amount);

        emit BridgeReceived(_guid, _origin.srcEid, to, amount);
    }

    // ~ Permissioned Methods ~

    /**
     * @notice Set the gas limit for destination chain execution
     * @param _dstGasLimit New gas limit
     */
    function setDstGasLimit(uint128 _dstGasLimit) external onlyOwner {
        dstGasLimit = _dstGasLimit;
        emit DstGasLimitSet(_dstGasLimit);
    }

    /**
     * @notice Rescue ERC20 tokens accidentally sent to this contract
     * @param _token The token address to rescue
     * @param _amount The amount to rescue
     */
    function rescueTokens(address _token, uint256 _amount) external onlyOwner {
        if (_amount == 0) revert ZeroAmount();
        if (_token == address(0)) revert ZeroAddress();

        IERC20(_token).safeTransfer(msg.sender, _amount);
    }

    /**
     * @notice Pause the bridge
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @notice Unpause the bridge
     */
    function unpause() external onlyOwner {
        _unpause();
    }
}
