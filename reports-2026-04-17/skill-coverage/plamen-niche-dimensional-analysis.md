# Plamen niche/dimensional-analysis — Coverage

**Checked — N/A (no dimensional arithmetic).**

The only arithmetic with "units" is decimal conversion in migration: 2-decimal OldToken base units × `10^16` = 18-decimal TelcoinV3 base units. This is **exact** (integer multiplication by a compile-time constant `DECIMAL_MULTIPLIER = 1e16`). No floating-point, no relative ratios, no mixed-unit operations.

The LZ shared-decimals conversion (`decimalConversionRate = 10^(18-6) = 1e12`) is similarly a compile-time integer constant (`_toLD`, `_toSD`, `_removeDust` in OFTCore). Sub-`1e12` wei is truncated (dust-stripped) before send — documented behaviour.

No dimensional mismatch risk.
