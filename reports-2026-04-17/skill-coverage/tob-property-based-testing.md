# trailofbits/skills — property-based-testing — Coverage

**Methodology applied.**

Written for this review:

- `test/echidna/EchidnaProps.sol` — 10 properties exercised 500,087 times without failure.
- `test/invariant/MigrationInvariant.t.sol` — 6 invariants × 256 runs × depth 15, 3,840 handler calls.
- `test/symbolic/SymbolicMigration.t.sol` — 5 Halmos symbolic checks.
- Medusa runs against the same property contract: 10/10 properties × 224,150 calls.

Properties cover the invariants.md categories: Supply Conservation (ST1), Decimal Conversion (I2), Supply Cap, Monotonicity (F2), Burn Approval (S1b), Pause Blocks Transfer (S2), Constants (IM2/IM3), Wrapper Authorisation (W1), rescueBurn Supply Reduction.
