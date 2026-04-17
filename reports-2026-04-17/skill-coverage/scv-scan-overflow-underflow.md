# kadenzipfel/scv-scan#overflow-underflow — Coverage

**Checked — not vulnerable because:**

- Solidity 0.8.26 / 0.8.30 — checked arithmetic by default.
- No `unchecked { … }` blocks in `src/` (verified by `grep -rn 'unchecked' src/` → no hits outside dependencies).
- Migration math: `amountNewToken = userBalance * 1e16`. Maximum `userBalance` = OldToken total supply = `10^13` (100B × 10^2). Product = `10^29`, well under `2^256 ≈ 1.16e77`.
- `totalMigrated += amountNewToken` — maximum aggregate = `10^29`, no overflow.
- `TelcoinV3._update` inherits OZ ERC-20 math; cap-check enforced after `_mint`.
- `block.timestamp + _migrationDuration` (src/TokenMigration.sol:65) — `block.timestamp < 2^64`, `_migrationDuration ≤ 2^256 - 2^64`, so `_migrationDuration` practically bounded to 365 days in deployment and can't overflow.
- `uint64` bridge cap enforced by `OFTCore._toSD` (`if (_amountSD > type(uint64).max) revert AmountSDOverflowed(_amountSD)`).
