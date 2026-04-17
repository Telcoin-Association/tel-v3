# Plamen evm/migration-analysis — Coverage

**Checked — all invariants from `invariants.md` exercised via Echidna + Medusa + Foundry invariant + Halmos (see `tob-property-based-testing.md`).**

Key properties:

1. **Exact 1:1 value ratio** via `DECIMAL_MULTIPLIER = 1e16` — Halmos-proven `check_getAmountOut_pure` holds for uint128 inputs.
2. **Whole-balance semantics** — `migrate()` reads `oldToken.balanceOf(msg.sender)` at call time; partial migration not possible. Prevents step-by-step loss.
3. **Irreversibility** — OldToken sent to `0xdEaD`; new TEL minted on demand. Migration cannot be undone.
4. **Time-bounded** — `block.timestamp >= migrationExpiry` reverts. Owner can `setMigrationExpiry` to extend (not shrink).
5. **Pausable** — emergency pause gates `migrate`.
6. **Role decoupling** — `MINTER_ROLE` on migration is revocable by governance post-expiry; rollout does not require a pre-funded reserve.
7. **Re-entry safety** — `ReentrancyGuardTransient`.
8. **Mint revert rolls back burn** — if `telcoinV3.mint` reverts (e.g., cap exceeded), the `safeTransferFrom(msg.sender, BURN_ADDRESS, bal)` is rolled back because the whole tx reverts. No lost funds.

No migration-specific issues found in this review. (Cantina's earlier review produced 12 Informational items all since fixed.)
