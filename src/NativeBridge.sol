// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {NativeOFTAdapter} from "@layerzerolabs/oft-evm/contracts/NativeOFTAdapter.sol";
import {Origin, MessagingFee, MessagingReceipt} from "@layerzerolabs/oapp-evm/contracts/oapp/OApp.sol";
import {SendParam, OFTReceipt} from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";
import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title NativeBridge
 * @author Telcoin Association
 * @notice LayerZero V2 OFT-compatible bridge deployed on TelcoinNetwork where TEL is the native
 *         gas token. Locks native TEL when bridging out to satellite chains; credits native TEL
 *         to recipients when messages arrive from satellite chains.
 *
 * @dev Inherits NativeOFTAdapter unmodified. Compatible with TelcoinBridge (MintBurnOFTAdapter)
 *      on satellite chains — both use OFTMsgCodec for message encoding.
 *
 *      WARNING: Only one NativeBridge should exist across the entire OFT mesh.
 *
 *      sharedDecimals defaults to 6, matching the satellite chain TelcoinBridge configuration.
 *      decimalConversionRate = 1e12 (localDecimals=18, sharedDecimals=6).
 *      Max transferable per message: uint64.max * 1e12 ~= 18.4 trillion TEL.
 */
contract NativeBridge is NativeOFTAdapter, Ownable2Step, Pausable {
    using SafeERC20 for IERC20;

    // ~ Errors ~

    error WithdrawFailed();
    error CannotRenounceOwnership();

    // ~ Constructor ~

    /**
     * @param _endpoint The local LayerZero endpoint address
     * @param _delegate The delegate/owner address for OApp configuration
     */
    constructor(
        address _endpoint,
        address _delegate
    ) NativeOFTAdapter(18, _endpoint, _delegate) Ownable(_delegate) {}

    // ~ Receive ~

    /// @notice Allows direct funding of the adapter's native TEL reserve.
    receive() external payable {}

    // ~ NativeOFTAdapter Overrides ~

    /**
     * @notice Pauses the bridge — blocks send and receive.
     * @dev Overrides NativeOFTAdapter.send() to enforce pausability. Delegates to super
     *      which validates msg.value == fee + amount before executing the send.
     */
    function send(
        SendParam calldata _sendParam,
        MessagingFee calldata _fee,
        address _refundAddress
    ) public payable override whenNotPaused returns (MessagingReceipt memory msgReceipt, OFTReceipt memory oftReceipt) {
        return super.send(_sendParam, _fee, _refundAddress);
    }

    /**
     * @dev Enforces pausability on inbound messages.
     */
    function _lzReceive(
        Origin calldata _origin,
        bytes32 _guid,
        bytes calldata _message,
        address _executor,
        bytes calldata _extraData
    ) internal whenNotPaused override {
        super._lzReceive(_origin, _guid, _message, _executor, _extraData);
    }

    // ~ Permissioned Methods ~

    /**
     * @notice Withdraw native TEL from the adapter reserve.
     * @dev The adapter accumulates native TEL as users bridge out to satellite chains.
     *      Owner can withdraw at any time, e.g. to rebalance reserves cross-chain.
     * @param _amount Amount of native TEL to withdraw in wei
     */
    function withdrawNative(uint256 _amount) external onlyOwner {
        (bool success, ) = payable(msg.sender).call{value: _amount}("");
        if (!success) revert WithdrawFailed();
    }

    /**
     * @notice Rescue ERC20 tokens accidentally sent to this contract.
     */
    function rescueTokens(address _token, uint256 _amount) external onlyOwner {
        IERC20(_token).safeTransfer(msg.sender, _amount);
    }

    function pause() external onlyOwner { _pause(); }

    function unpause() external onlyOwner { _unpause(); }

    // ~ Ownership ~

    function transferOwnership(address newOwner) public override(Ownable, Ownable2Step) onlyOwner {
        Ownable2Step.transferOwnership(newOwner);
    }

    function _transferOwnership(address newOwner) internal override(Ownable, Ownable2Step) {
        Ownable2Step._transferOwnership(newOwner);
    }

    /// @notice Disabled — renouncing ownership would permanently brick pause and withdraw.
    function renounceOwnership() public override onlyOwner {
        revert CannotRenounceOwnership();
    }
}