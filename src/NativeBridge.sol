// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {NativeOFTAdapter} from "@layerzerolabs/oft-evm/contracts/NativeOFTAdapter.sol";
import {Origin, MessagingFee, MessagingReceipt} from "@layerzerolabs/oapp-evm/contracts/oapp/OApp.sol";
import {SendParam, OFTReceipt} from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";
import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {AccessControlEnumerable} from "@openzeppelin/contracts/access/extensions/AccessControlEnumerable.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {PauseRoles} from "./helpers/Roles.sol";

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
contract NativeBridge is NativeOFTAdapter, Ownable2Step, Pausable, PauseRoles, AccessControlEnumerable {
    using SafeERC20 for IERC20;

    // ~ Events ~

    /// @notice Emitted when native TEL is sent directly to the contract to top up the reserve.
    event ReserveFunded(address indexed funder, uint256 amount);

    // ~ Errors ~

    error CannotRenounceOwnership();
    error CannotRenounceRole();
    error ZeroAddress();
    error ZeroAmount();
    error ComposeNotSupported();

    // ~ Constructor ~

    /**
     * @dev Constructor.
     * @param _endpoint The local LayerZero endpoint address
     * @param _delegate The delegate/owner address for OApp configuration (receives DEFAULT_ADMIN_ROLE)
     */
    constructor(
        address _endpoint,
        address _delegate
    ) NativeOFTAdapter(18, _endpoint, _delegate) Ownable(_delegate) {
        _grantRole(DEFAULT_ADMIN_ROLE, _delegate);
    }

    // ~ Receive ~

    /// @notice Allows direct funding of the adapter's native TEL reserve.
    receive() external payable {
        emit ReserveFunded(msg.sender, msg.value);
    }

    // ~ NativeOFTAdapter Overrides ~

    /**
     * @notice Initiates an outbound bridge transfer of native TEL to the destination chain.
     *         Reverts while the bridge is paused. Rejects composed messages.
     * @dev Overrides NativeOFTAdapter.send() to add whenNotPaused and the compose check.
     *      Delegates to super, which validates msg.value == fee + amount before executing the
     *      send. Pause state is changed only by pause()/unpause(); the inbound path enforces
     *      it independently in _lzReceive().
     *      Nonempty composeMsg switches the LayerZero message type from SEND to SEND_AND_CALL,
     *      which bypasses the SEND-only enforced options (no minimum receive or compose gas).
     *      Compose is unused across the Telcoin OFT mesh, so it is rejected outright.
     */
    function send(
        SendParam calldata _sendParam,
        MessagingFee calldata _fee,
        address _refundAddress
    ) public payable override whenNotPaused returns (MessagingReceipt memory msgReceipt, OFTReceipt memory oftReceipt) {
        if (_sendParam.composeMsg.length > 0) revert ComposeNotSupported();
        return super.send(_sendParam, _fee, _refundAddress);
    }

    /**
     * @dev Inbound message delivery. Reverts while paused — the inbound path enforces pause
     *      state independently of send(). Delegates to the inherited implementation, which
     *      credits native TEL from the reserve and emits LayerZero's OFTReceived event.
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

    /// @notice Pauses the bridge. Separated from owner so a low-latency incident responder can
    ///         halt the bridge without holding configuration or rescue authority.
    function pause() external onlyRole(PAUSER_ROLE) { _pause(); }

    /// @notice Unpauses the bridge. High-trust action — resuming flow during an active incident
    ///         reopens the risk, so it is held by governance, separate from PAUSER_ROLE.
    function unpause() external onlyRole(UNPAUSER_ROLE) { _unpause(); }

    // ~ Access Control ~

    /**
     * @notice Disabled — roles may only be revoked by an admin, never self-renounced.
     */
    function renounceRole(bytes32, address) public pure override(AccessControl, IAccessControl) {
        revert CannotRenounceRole();
    }

    /**
     * @notice Revoke a role, except an admin removing its own DEFAULT_ADMIN_ROLE.
     * @dev Mirrors the TelcoinV3/MigrationVault guard: prevents the sole admin from
     *      permanently disabling role administration via self-revocation.
     */
    function revokeRole(bytes32 role, address account) public override(AccessControl, IAccessControl) {
        if (role == DEFAULT_ADMIN_ROLE && account == msg.sender) revert CannotRenounceRole();
        super.revokeRole(role, account);
    }

    // ~ Ownership ~

    /// @notice Transfers owner role from current owner to `newOwner`.
    function transferOwnership(address newOwner) public override(Ownable, Ownable2Step) onlyOwner {
        Ownable2Step.transferOwnership(newOwner);
    }

    /**
     * @dev Binds DEFAULT_ADMIN_ROLE to ownership so the two authority systems cannot silently
     *      diverge. On every ownership move (including acceptOwnership) the incoming owner is
     *      granted DEFAULT_ADMIN_ROLE and the outgoing owner has it revoked, atomically. Uses the
     *      internal _revokeRole so the self-revocation guard does not block the handover.
     */
    function _transferOwnership(address newOwner) internal override(Ownable, Ownable2Step) {
        address previousOwner = owner();
        Ownable2Step._transferOwnership(newOwner);
        if (newOwner != previousOwner) {
            if (newOwner != address(0)) _grantRole(DEFAULT_ADMIN_ROLE, newOwner);
            if (previousOwner != address(0)) _revokeRole(DEFAULT_ADMIN_ROLE, previousOwner);
        }
    }

    /// @notice Disabled — renouncing ownership would permanently brick pause and rescue.
    function renounceOwnership() public override onlyOwner {
        revert CannotRenounceOwnership();
    }
}