# qs_skills/semantic-guard-analysis — Coverage

**Checked — clean.**

Every revert guard enumerated:

- TelcoinV3: `SupplyCapExceeded`, `CannotRenounceRole`, `ZeroAddress`, `ZeroAmount`, `EnforcedPause`.
- TokenMigration: `InvalidAmount`, `InvalidExpiry`, `ZeroAddress`, `SameAddress`, `MigrationConcluded`, `CannotRenounceOwnership`.
- MintBurnWrapper: `UnauthorizedBridge`, `ZeroAddress`, `CannotRenounceOwnership`, `BridgeAlreadySet`, `BridgeNotSet`.
- Bridges: `CannotRenounceOwnership`, `ZeroAddress`, `ZeroAmount`, `IncorrectMessageValue` (inherited), `CreditFailed` (inherited), `EnforcedPause`.
- Inherited: AccessControl/Ownable/OFTCore errors (`OnlyEndpoint`, `OnlyPeer`, `AmountSDOverflowed`, `SlippageExceeded`, `InvalidLocalDecimals`, etc.).

Each guard triggers only under its documented condition; none falsely succeed. See also the per-skill coverage files:
- `scv-scan-requirement-violation.md` coverage implicit via `semantic-guard-analysis`.
- `scv-scan-insufficient-access-control.md` covers the role gates.
