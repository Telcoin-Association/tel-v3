// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {MintBurnOFTAdapter} from "@layerzerolabs/oft-evm/contracts/MintBurnOFTAdapter.sol";
import {OFTMsgCodec} from "@layerzerolabs/oft-evm/contracts/libs/OFTMsgCodec.sol";
import {IMintableBurnable} from "@layerzerolabs/oft-evm/contracts/interfaces/IMintableBurnable.sol";
import {Origin, MessagingFee, MessagingReceipt} from "@layerzerolabs/oapp-evm/contracts/oapp/OApp.sol";
import {SendParam, OFTReceipt} from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";
import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title TelcoinBridge
 * @author Telcoin Association
 * @notice LayerZero V2 OFT-compatible bridge for TelcoinV3 cross-chain transfers.
 * @dev Inherits MintBurnOFTAdapter unmodified. Mint and burn are delegated to MintBurnWrapper
 *      (the minterBurner) which holds MINTER_ROLE and BURNER_ROLE on TelcoinV3, decoupling
 *      bridge upgrades from token role management.
 *
 *      Compatible with NativeOFTAdapter deployed on TelcoinNetwork where TEL is the native
 *      gas token — both use OFTMsgCodec for message encoding.
 *
 *      Use send() and quoteSend() from OFTCore for all bridging operations.
 *
 *      sharedDecimals defaults to 6, giving a decimalConversionRate of 1e12 against TEL's
 *      18 local decimals. Amounts are rounded to the nearest 1e-6 TEL (dust) before send.
 *      Max transferable per message: uint64.max * 1e12 ~= 18.4 trillion TEL.
 */
contract TelcoinBridge is MintBurnOFTAdapter, Ownable2Step, Pausable {
    using SafeERC20 for IERC20;
    using OFTMsgCodec for bytes;
    using OFTMsgCodec for bytes32;

    // ~ Errors ~

    error CannotRenounceOwnership();
    error ZeroAddress();
    error ZeroAmount();

    // ~ Constructor ~

    /**
     * @param _token The TelcoinV3 token address
     * @param _minterBurner The MintBurnWrapper address (holds MINTER_ROLE/BURNER_ROLE on TelcoinV3)
     * @param _endpoint The local LayerZero endpoint address
     * @param _delegate The delegate/owner address for OApp configuration
     */
    constructor(
        address _token,
        IMintableBurnable _minterBurner,
        address _endpoint,
        address _delegate
    ) MintBurnOFTAdapter(_token, _minterBurner, _endpoint, _delegate) Ownable(_delegate) {}

    // ~ OFTCore Overrides ~

    /**
     * @notice Signals that callers must approve the MintBurnWrapper before bridging.
     * @dev Overrides MintBurnOFTAdapter.approvalRequired() which returns false by default.
     *      TelcoinV3.burn() enforces an allowance check, so the wrapper must be approved.
     */
    function approvalRequired() external pure override returns (bool) {
        return true;
    }

    /**
     * @notice Pauses the bridge — blocks send and receive.
     * @dev Overrides OFTCore.send() to enforce pausability on the standard OFT entry point.
     */
    function send(
        SendParam calldata _sendParam,
        MessagingFee calldata _fee,
        address _refundAddress
    ) external payable override whenNotPaused returns (MessagingReceipt memory msgReceipt, OFTReceipt memory oftReceipt) {
        return _send(_sendParam, _fee, _refundAddress);
    }

    /**
     * @dev Enforces pausability on inbound messages and emits BridgeReceived for indexing.
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
     * @notice Rescue ERC20 tokens accidentally sent to this contract.
     */
    function rescueTokens(address _token, uint256 _amount, address _to) external onlyOwner {
        if (_to == address(0)) revert ZeroAddress();
        if (_amount == 0) revert ZeroAmount();
        IERC20(_token).safeTransfer(_to, _amount);
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

    /// @notice Disabled — renouncing ownership would permanently brick pause, rescue, and delegate config.
    function renounceOwnership() public view override onlyOwner {
        revert CannotRenounceOwnership();
    }
}