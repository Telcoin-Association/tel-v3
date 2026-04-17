# trailofbits/skills — differential-review — Coverage

**Methodology applied** — diff against prior Cantina scope.

| Contract | In Cantina scope? | Status |
|---|---|---|
| TelcoinV3.sol | Yes (@ c5cad30a) | Cantina: 0 Critical/High/Med/Low, 1 Gas, 12 Info — all fixed except "TOTAL_SUPPLY naming" (renamed). This audit re-verifies at commit 5e9cdf9 and confirms no regressions. |
| TokenMigration.sol | Yes | Cantina same result. "recoverERC20 granularity" acknowledged. This audit flags no new issues. |
| MintBurnWrapper.sol | **No — added PR #8 after Cantina** | This audit produces **L-01**, **I-03** (stale ITelcoinBridge) citations |
| TelcoinBridge.sol | No — added PR #8 | This audit: no direct bugs; I-06 (inherited LZ platform quirk) |
| NativeBridge.sol | No — added PR #8 | This audit: I-01 (reserve non-recoverable), I-06 |
| src/helpers/Roles.sol | No | Trivial constants |
| src/interfaces/* | No | **I-03** (ITelcoinBridge stale) |

Differential delta since Cantina: L-01 + I-01 + I-03 + I-04 + I-05 + I-06 + I-07 (I-02 applies to TelcoinV3 which Cantina did cover but the check `rescueTokens` doesn't appear on Cantina's checklist either).
