# trailofbits/skills — fp-check — Coverage

**Methodology applied** to every tool detector hit.

| Hit | Tool | Verdict |
|---|---|---|
| `incorrect-equality` `userBalance == 0` | Slither M | **FP** — correct zero-guard on migration input |
| `incorrect-equality` `amount > balance` chain | Slither M | **FP** — correct guard on recovery |
| `reentrancy-events` MintBurnWrapper.mint emits after external call | Slither L | **FP** — external call target is trusted TelcoinV3; event ordering doesn't affect accounting |
| `reentrancy-events` MintBurnWrapper.burn same | Slither L | **FP** — same reasoning |
| `timestamp` migrate() expiry check | Slither L | **FP** — miner manipulation window <<< expiry granularity |
| `timestamp` setMigrationExpiry guard | Slither L | **FP** — same |
| `solc-version` 0.4.18 | Slither I | **FP** (out of scope) — src/legacy/Telcoin.sol retained for reference, not linked |
| `naming-convention` `_camelCase` | Slither I ×21 | **FP** (style) — project convention, `.solhint.json` suppresses |
| Aderyn H-1 "Locks Ether without withdraw" NativeBridge | Aderyn H | **TP → I-01** |
| Aderyn H-1 "Locks Ether without withdraw" TelcoinBridge | Aderyn H | **FP** — TelcoinBridge has no `receive()`/`fallback()`; payable `send()` forwards msg.value to LZ endpoint |
| Aderyn L-1 to L-6, L-7 | Aderyn L | **FP (style)** except L-7 → I-03 |
| Semgrep non-payable-constructor | Semgrep | **FP (gas/style)** — no constructor funding path needed |
| Semgrep use-nested-if `_update` guard | Semgrep | **FP (gas/style)** — readability outweighs a few gas units |
| Semgrep inefficient-state-variable-increment | Semgrep | **FP (gas/style)** — `totalMigrated += x` is idiomatic |

No false negatives detected in triage. Each detector hit has a justification or citation to a finding.
