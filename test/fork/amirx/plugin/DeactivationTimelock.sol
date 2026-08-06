// Verified production source of the live SimplePlugin stack (Polygonscan,
// 0xDb0e60A38Bf7d04c8ae0B396A65E5aa550f9885A). Extracted for fork tests to
// deploy the REAL referral plugin wired to TEL3. Do not edit.
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

abstract contract DeactivationTimelock {
    /// @dev If nonzero, time at which this plugin will be deactivated
    uint256 public _deactivationTime;

    /// @dev Time delay for deactivation
    uint256 public _deactivationDelay;

    /// @notice Event that's emitted when a deactivation is initiated
    event DeactivationInitiated(uint256 deactivationTime);

    constructor(uint256 _delay) {
        _deactivationDelay = _delay;
    }

    modifier whenNotDeactivated() {
        require(
            !_deactivated(),
            "DeactivationTimelock::whenNotDeactivated: Plugin is deactivated"
        );
        _;
    }

    modifier whenDeactivated() {
        require(
            _deactivated(),
            "DeactivationTimelock::whenDeactivated: Plugin is not deactivated"
        );
        _;
    }

    function _deactivated() public view returns (bool) {
        return _deactivationTime != 0 && block.timestamp >= _deactivationTime;
    }

    function _startDeactivation() internal {
        require(
            _deactivationTime == 0,
            "DeactivationTimelock::deactivate: Deactivation already started"
        );
        _deactivationTime = block.timestamp + _deactivationDelay;
        emit DeactivationInitiated(_deactivationTime);
    }

    function startDeactivation() external virtual;
}
