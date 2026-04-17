# qs_skills/input-arithmetic-safety — Coverage

**Checked — clean.**

Arithmetic on user inputs:

| Input | Operation | Safety |
|---|---|---|
| userBalance (OldToken balance) | `× 1e16` | bounded by 10^13, product bounded by 10^29 < 2^256 |
| amountLD (bridge send amount) | `/ decimalConversionRate × decimalConversionRate` (dust-strip) | standard OFT pattern |
| amountSD (shared decimals, uint64) | `× 1e12` | bounded by uint64.max × 1e12 ≈ 1.84e22 |
| _migrationDuration (constructor) | `block.timestamp +` | `block.timestamp < 2^64`, duration practically bounded to years |
| _newMigrationExpiry | `>` comparison against current | monotonic, no underflow |
| _amount (rescueTokens, rescueBurn) | no arithmetic, only compared against balance | — |
| _value (ERC-20 transfers) | OZ ERC-20 checked arithmetic | OK |

No sub-zero, no div-by-zero (no division except constant `/ 1e16` in `totalOldTokenBurned`). No precision loss (migration uses multiplication, not division).
