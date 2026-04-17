# Archethect/sc-auditor — rounding-entitlement — Coverage

**Checked — clean.**

No rounded entitlement calculations in scope. Migration math is exact multiplication (`bal × 1e16`). Bridge `_removeDust` truncates sub-1e12 wei on send — this is documented and symmetric (dust stays with sender, no "favourable rounding to protocol").

No fee calculation, no pro-rata share distribution, no TWAP averaging. Nothing to round.
