// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {IMintableBurnable} from "@layerzerolabs/oft-evm/contracts/interfaces/IMintableBurnable.sol";
import {IERC20Mintable} from "./interfaces/IERC20Mintable.sol";

/**
 * @title MintBurnWrapper
 * @author Telcoin Association
 * @notice Adapts TelcoinV3's void-returning mint/burn to the IMintableBurnable interface
 *         required by MintBurnOFTAdapter.
 * @dev Acts as the minterBurner for TelcoinBridge. Holds MINTER_ROLE and BURNER_ROLE on
 *      TelcoinV3 so the bridge itself does not need direct token roles. This decouples bridge
 *      upgrades from token role management — new bridges are added/removed here without
 *      touching TelcoinV3's access control.
 */
contract MintBurnWrapper is IMintableBurnable, Ownable2Step {
    // ~ State ~

    /// @notice The TelcoinV3 token this wrapper delegates to
    IERC20Mintable public immutable token;

    /// @notice Bridges authorised to call mint and burn through this wrapper
    mapping(address => bool) public authorizedBridges;

    // ~ Events ~

    event BridgeAuthorized(address indexed bridge);
    event BridgeRevoked(address indexed bridge);

    // ~ Errors ~

    error UnauthorizedBridge();
    error ZeroAddress();
    error CannotRenounceOwnership();

    // ~ Modifiers ~

    modifier onlyBridge() {
        if (!authorizedBridges[msg.sender]) revert UnauthorizedBridge();
        _;
    }

    // ~ Constructor ~

    /**
     * @param _token The TelcoinV3 token address
     * @param _owner The initial owner (admin) of this wrapper
     */
    constructor(address _token, address _owner) Ownable(_owner) {
        if (_token == address(0)) revert ZeroAddress();
        token = IERC20Mintable(_token);
    }

    // ~ IMintableBurnable ~

    /**
     * @notice Mints tokens to the recipient. Called by MintBurnOFTAdapter on lzReceive.
     * @param _to Recipient address
     * @param _amount Amount to mint in local decimals
     * @return success Always true — reverts on failure
     */
    function mint(address _to, uint256 _amount) external onlyBridge returns (bool) {
        token.mint(_to, _amount);
        return true;
    }

    /**
     * @notice Burns tokens from an address. Called by MintBurnOFTAdapter on send.
     * @param _from Address to burn from
     * @param _amount Amount to burn in local decimals
     * @return success Always true — reverts on failure
     */
    function burn(address _from, uint256 _amount) external onlyBridge returns (bool) {
        token.burn(_from, _amount);
        return true;
    }

    // ~ Bridge Management ~

    /**
     * @notice Authorize a bridge to call mint and burn through this wrapper.
     * @param _bridge The bridge contract address
     */
    function authorizeBridge(address _bridge) external onlyOwner {
        if (_bridge == address(0)) revert ZeroAddress();
        authorizedBridges[_bridge] = true;
        emit BridgeAuthorized(_bridge);
    }

    /**
     * @notice Revoke a bridge's authorization.
     * @param _bridge The bridge contract address
     */
    function revokeBridge(address _bridge) external onlyOwner {
        authorizedBridges[_bridge] = false;
        emit BridgeRevoked(_bridge);
    }

    // ~ Ownership ~

    /**
     * @notice Disabled — renouncing ownership would permanently brick bridge management.
     */
    function renounceOwnership() public view override onlyOwner {
        revert CannotRenounceOwnership();
    }
}