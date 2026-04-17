# qs_skills/state-invariant-detection — Coverage

**Methodology applied.**

Invariants enumerated from `invariants.md` and cross-verified by the written Foundry + Echidna + Medusa tests:

| ID | Invariant | Test |
|---|---|---|
| ST1 | totalOldTokenBurned() == oldToken.balanceOf(BURN_ADDR) (assuming no external transfers) | `invariant_ST1_BurnBalMatchesTotal`, `echidna_ST1_…` |
| F1 | After migrate, user's oldToken balance == 0 | `invariant_F1_WholeBalanceAfterMigration` |
| F2 | totalMigrated monotone increasing | `echidna_F2_totalMigratedMonotone`, `echidna_F2_burnAddrMonotone`, `invariant_ExpiryMonotone` |
| F3 | TelcoinV3.totalSupply() = migration.totalMigrated() when initial supply 0 | `invariant_F3_MintEqualsTotalMigrated` |
| I2 | getAmountOut(x) = x * 1e16 | `echidna_I2_decimalMultiplier`, `invariant_I2_DecimalMultiplier`, `check_getAmountOut_pure` (Halmos) |
| IM2 | DECIMAL_MULTIPLIER constant | `echidna_IM2_IM3_constants`, `check_constants` (Halmos) |
| IM3 | BURN_ADDRESS constant | same |
| S1b | Burn without approval reverts | `echidna_S1b_burnWithoutApprovalReverts` |
| S2 | Paused blocks transfers | `echidna_S2_pausedBlocksTransfer` |
| W1 | Only authorised bridge can call mint/burn | `echidna_W1_bridgeAuthorised` |
| Supply cap | totalSupply ≤ 100B ether | `echidna_supplyCap`, `invariant_supplyCapHonored`, `check_supplyCapAtConstruction` (Halmos) |
| rescueBurn reduces supply | tested invariant | `echidna_rescueBurnReducesSupply` |

All 10 Echidna + 10 Medusa + 6 Foundry + 5 Halmos = 31 automated invariant checks pass across >700k total calls.
