# AmirX × TEL v3 — Backend Integration Guide

**Audience:** backend/swapper service team
**Status:** draft — pending v3 SimplePlugin deployment
**Contract:** AmirX proxy `0x4eB4A35257458C1a87A4124CE02B3329Ed6b8D5a` (Polygon — address does not change)

## What is changing

When TEL v3 launches on Polygon, the AmirX **implementation** is upgraded in place.
The only on-chain change is the `TELCOIN` constant:

| | Before | After |
|---|---|---|
| `TELCOIN` | legacy TEL `0xdF7837DE1F2Fa4631D716CF2502f8b230F1dcc32` | TEL3 `0x7E13B43065380aCdeC1c2d138c579cbBbafA0731` |
| TEL decimals | 2 | 18 |

**No ABI changes.** Every entry point, struct, and role is identical. The proxy address,
swapper EOAs, and user-wallet approval flows are untouched. What changes is *behavioral*:
everything in fee dispersal that says "TEL" — the buyback target, the referral currency,
the sweep currency — now means **TEL3**.

## What keeps working, what breaks

| Scenario | Today | After upgrade | Backend action |
|---|---|---|---|
| User trades TEL **v2** in `walletData` (0x quote) | works | **still works** — `walletData` is opaque to AmirX; v2 remains tradable while its liquidity exists | none |
| `feeToken` = USDC / USDT / other, with `swapData` | buys back legacy TEL | works, but route must output **TEL3** | request 0x/router quotes targeting TEL3 |
| `feeToken` = legacy TEL, **no** `aggregator`/`swapData` (~17% of current traffic) | works (matches `TELCOIN`, direct sweep) | **REVERTS** `ZeroValueInput("BUYBACK")` | stop sending this shape at the upgrade block — see fee rule below |
| `feeToken` = legacy TEL **with** legacy→TEL3 `swapData` | n/a | works (treated as ordinary buyback token) | valid transition path for v2-denominated fees |
| `feeToken` = TEL3 | n/a | direct sweep to `defiSafe`, no buyback params needed | end-state for TEL3-denominated fees |
| `feeToken` = `address(0)` (~29% of current traffic) | skips dispersal | unchanged — skips dispersal; fee accumulates in AmirX for a later flush | safe fallback whenever no route exists |
| `feeToken` = POL | POL→TEL buyback | works, route must output TEL3 | update quote target |
| `referrer` set, current plugin `0xDb0e...885A` (~62% of traffic) | works | **REVERTS** — AmirX approves the plugin in TEL3, plugin pulls legacy TEL | switch `plugin` to the new v3 SimplePlugin (address TBD), or send `referrer = address(0)` until it exists |
| Stablecoin legs (eGBP/eXOF mint/burn) | works | unchanged | none |

## The fee rule (post-upgrade)

`feeToken` must be exactly one of:

1. **TEL3** — no `aggregator`/`swapData` required; swept directly to `defiSafe`.
2. **`address(0)`** — dispersal skipped entirely; whatever fee `walletData` delivered
   accumulates in AmirX and can be flushed later (single `defiSwap` with empty
   `walletData`, `feeToken` = accumulated token, `swapData` = route for the full balance).
3. **Any other token (including legacy TEL) with `aggregator` + `swapData` attached**,
   where the route outputs TEL3 to the AmirX address.

Anything else — a non-TEL3 `feeToken` with empty `swapData` — reverts before the user's
swap executes. There is no silent-failure mode here; the whole transaction fails.

## Decimals

Legacy TEL has **2** decimals; TEL3 has **18**. Same face value ⇒ raw amount × **1e16**.

| Face value | Legacy raw (2 dec) | TEL3 raw (18 dec) |
|---|---|---|
| 1 TEL | `100` | `1000000000000000000` (1e18) |
| 250 TEL | `25000` | `250000000000000000000` (250e18) |
| conversion | raw_v3 = raw_v2 × 1e16 | raw_v2 = raw_v3 ÷ 1e16 |

> ⚠️ The dangerous field is **`referralFee`**: it is a raw backend-authored amount and
> wrong units **do not revert** — they pay out 10^16× too much or too little. Amounts
> inside 0x quotes are handled by the quote API; audit every TEL amount the backend
> computes itself (referral fees, min-out sanity checks, display/accounting).

## Referral plugin cutover

The live SimplePlugin cannot be reused (its `tel` and `staking` addresses are
immutable). Sequence, owner = `0xBF58...415C` Safe:

1. Deploy `SimplePlugin(stakingModule, TEL3)` — address will be provided.
2. Register it with the StakingModule (users claim through the module).
3. `setIncreaser(AmirX proxy)`.
4. Backend flips the `plugin` field in `DefiSwap`.

**Until all four are done, send `referrer = address(0)`.** Any swap with a nonzero
referrer and the old plugin reverts. Outstanding claimables on the old plugin remain
in legacy TEL and stay claimable there — do not deactivate it at cutover.

Additional gotcha: with buyback disabled (`feeToken = address(0)`), AmirX holds no TEL3,
so a nonzero `referrer` reverts even with the *correct* plugin. Referrals require either
an active buyback in the same swap or TEL3 pre-funded in AmirX.

## Cutover sequencing

The upgrade (3-of-6 Safe via ProxyAdmin) and the backend config flip must land as one
event — every swap sent with the *old* fee shape after the upgrade block reverts, and
every swap sent with the *new* shape before it misbehaves. Recommended:

- **Phase 0 (before):** v3 plugin deployed + registered; config flags staged; TEL3
  address confirmed on-chain.
- **Phase 1 (upgrade block):** flip to transition config — `feeToken = address(0)`,
  `referrer = address(0)`, referral/TEL amounts switched to 18-dec. All swap traffic
  continues; fees accumulate.
- **Phase 2 (TEL3 pool seeded and 0x routing TEL3):** re-enable buyback quotes and
  referrals; flush accumulated fees.

Note on liquidity: ~91% of current swaps move TEL at the user's wallet (63% are TEL
*buys*), so user-facing TEL3 trades depend on **0x indexing TEL3**, not just a pool
existing. Until then, wallets can only trade v2.

## Failure signatures to monitor

| Revert | Meaning |
|---|---|
| `ZeroValueInput("BUYBACK")` | non-TEL3 `feeToken` sent without `aggregator`/`swapData` |
| `ZeroValueInput("PLUGIN")` | `referrer` set but `plugin` zero |
| `AmirX: wallet transaction failed` | user wallet call reverted (same as today — cf. Aug 2 incident) |
| `AmirX: token swap transaction failed` | buyback route reverted (bad quote, slippage, unseeded pool) |
| revert inside plugin `transferFrom` | wrong plugin (legacy) or referral without TEL3 on hand |
| `EnforcedPause()` | TEL3 is paused — **new coupling**: a TEL3 pause blocks all fee dispersal |

## Addresses

| What | Address | Notes |
|---|---|---|
| AmirX proxy | `0x4eB4A35257458C1a87A4124CE02B3329Ed6b8D5a` | unchanged |
| Legacy TEL | `0xdF7837DE1F2Fa4631D716CF2502f8b230F1dcc32` | 2 decimals |
| TEL3 | `0x7E13B43065380aCdeC1c2d138c579cbBbafA0731` | 18 decimals |
| SimplePlugin (legacy) | `0xDb0e60A38Bf7d04c8ae0B396A65E5aa550f9885A` | do **not** reference after cutover |
| SimplePlugin (v3) | **TBD** | use after cutover |
| StakingModule | `0x92e43Aec69207755CB1E6A8Dc589aAE630476330` | unchanged |
| 0x AllowanceHolder | `0x0000000000001fF3684f28c67538D4D072C22734` | current aggregator, unchanged |

## Verification

A 15-test Polygon-mainnet fork suite covering every row of the behavior table above
(including the revert cases and the real v3 SimplePlugin deployment) lives in
`tel-v3` on branch `test/amirx-tel3-fork` — `test/fork/AmirXTel3Fork.t.sol`. Run with
`POLYGON_RPC_URL` set: `forge test --mc AmirXTel3ForkTest`.

## Open items

- v3 SimplePlugin address (TEL3 itself is live at the address above).
- Whether legacy-TEL fees in Phase 1 use `address(0)`-accumulate or a legacy→TEL3 route
  (depends on whether a legacy/TEL3 pool is seeded at launch).
- Exact upgrade-block coordination mechanism (BE feature flag vs. scheduled deploy).
