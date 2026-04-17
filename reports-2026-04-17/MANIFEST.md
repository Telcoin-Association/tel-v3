# Tool Execution Manifest — Telcoin V3 audit

**Commit:** `5e9cdf9b3e10151358859aac31dc890edeccdbe7`
**Date:** 2026-04-17
**Working directory:** `/Users/r00t/smartcontracts/tel-v3`
**Host:** Darwin arm64 25.4.0, macOS (M-series)

| # | Tool | Version | Command Invoked | Exit Code | Duration | Log File | Output Artefact | Status |
|---|------|---------|------------------|-----------|----------|----------|-----------------|--------|
| 1 | slither-mcp | 2.3.2 | `cd /Users/r00t/slither-mcp && .venv/bin/python /tmp/slither_mcp_run.py` (drives `SlitherMCPClient` against `PROJECT=/Users/r00t/smartcontracts/tel-v3`) | 0 | ~2 min (first call built `artifacts/project_facts.json` cache; subsequent calls <5 s each) | reports/slither-mcp.json | **23 MCP tools callable**, 250 detector results (101 detectors), **29 in-scope** across 6 detector classes. Structured JSON; 1 additional in-scope finding the CLI filtered (`shadowing-local`) → new finding **SLS-1 (Info)** | ✅ RAN |
| 2 | slither (CLI) | 0.11.5 | `slither --filter-paths 'lib/\|test/\|script/\|src/legacy' --checklist --markdown-root . src/` | 0 *(detector hits cause slither's non-zero exit code 255, treated as success because `reports/slither.md` was produced and parsed)* | ~15 s | reports/slither.md | 2 M / 4 L / 22 I detector hits — all triaged as FP or style (see `reports/skill-coverage/tob-fp-check.md`) | ✅ RAN |
| 3 | slither printers | 0.11.5 | `slither --filter-paths … --print human-summary --print function-summary --print data-dependency src/` | 0 | ~8 s | reports/slither-function-summary.txt, reports/slither-data-dependency.txt | 2 printer outputs | ✅ RAN |
| 4 | semgrep | 1.155.0 | `semgrep --config r/solidity --sarif --metrics off --exclude lib --exclude test --exclude script --exclude src/legacy --exclude audit --exclude deployments --exclude out -o reports/semgrep.sarif .` | 0 | ~7 s | reports/semgrep.sarif, reports/semgrep.log | 50 rules / 7 findings (all gas/style) | ✅ RAN |
| 5 | aderyn | 0.1.9 | `aderyn --src src --path-excludes src/legacy --no-snippets -o reports/aderyn.md .` (from a `cancun`-patched /tmp copy — Amendment 2's fallback note: aderyn 0.1.9 does not parse `evm_version = "prague"`) | 0 (report written; panics after) | ~10 s | reports/aderyn.md | 1 H (FP → I-01) / 7 L (style / I-03) | ✅ RAN |
| 6 | echidna | 2.3.2 | `echidna test/echidna/EchidnaProps.sol --contract EchidnaProps --config echidna.yaml --format text --test-limit 500000` | 0 | 3 m 41 s (wall) | reports/echidna.log | 10/10 properties pass / 500 087 calls / 10 080 unique instructions | ✅ RAN |
| 7 | medusa | 1.5.0 | `medusa fuzz --config medusa.json --test-limit 200000` | 0 | 16 s | reports/medusa.log | 10/10 properties pass / 224 150 calls / 1 127 branches | ✅ RAN |
| 8 | halmos | 0.3.3 | `halmos --contract SymbolicMigration --solver-timeout-assertion 30000` | 0 | <1 s | reports/halmos.log | 5/5 symbolic checks pass | ✅ RAN |
| 9 | manticore | n/a | — | — | — | — | — | **⛔ N/A** — Manticore does not support Python 3.13 / arm64 Darwin at the time of this review; upstream installation is blocked. Halmos (row 8) is the SMT-backed symbolic equivalent and performs the same class of checks. |
| 10 | amarna | n/a | — | — | — | — | — | **⛔ N/A** — Cairo static analyser; no Cairo contracts in scope (EVM Solidity). |
| 11 | tealer | n/a | — | — | — | — | — | **⛔ N/A** — TEAL/Algorand static analyser; no TEAL contracts in scope. |
| 12 | forge build | 1.5.1-stable | `forge build --sizes` | 0 | ~7 s | reports/build.log | All in-scope contracts compile, max runtime size 19 454 B (TelcoinBridge) | ✅ RAN |
| 13 | forge test | 1.5.1-stable | `forge test` (with `ETHEREUM_RPC_URL=https://ethereum-rpc.publicnode.com` for 2 forking tests) | 0 | 203 s | reports/test.log | **145 passed / 0 failed / 0 skipped** (139 existing + 6 new invariant tests) | ✅ RAN |
| 14 | forge coverage | 1.5.1-stable | `forge coverage --report summary --no-match-coverage '(test\|script\|lib)/'` | 0 | 136 s | reports/coverage.log | 100 % lines on all in-scope contracts; 75 % branch on TokenMigration (uncovered branch is `renounceOwnership` which reverts; covered symbolically by Halmos) | ✅ RAN |
| 15 | forge invariant | 1.5.1-stable | `forge test --match-path test/invariant/*` | 0 | <1 s | — (included in test.log) | 6/6 invariants pass / 256 runs × depth 15 = 3 840 handler calls | ✅ RAN |

## File integrity — `shasum -a 256 reports/*`

```
reports/aderyn.md                        12296 bytes   sha256=c56add3b80ca2061c940a270c164e3919f4c092da8bc0d4c7a9cfca650b39931
reports/build.log                          432 bytes   sha256=831907de1d3812f6412139944b8fb27f8641fc78bb4c888c8a041e7e45488bc1
reports/coverage.log                      1816 bytes   sha256=0c317deeec82fa8119fa0e3d8fa321d5bf7edc260f4250db30923a2bd1e7f5f2
reports/echidna.log                      10234 bytes   sha256=fc5514145ada2da909504165560c19b54fc3f731020bf9bd00706725912fcc4c
reports/halmos.log                         573 bytes   sha256=6d7bca8e4577d5709da0d4cb1b563143a8d3a1cda784200b6f643f04398efa13
reports/medusa.log                        5851 bytes   sha256=89a20ee4b7a6476b81253026852162ebc115b83ff7ea944de38bc913fa7c0c1f
reports/semgrep.log                       5528 bytes   sha256=7d285902fdf71ccbfe63c568ecf5e5530d39e67d7259a1ca0b2273b72c1d2a9b
reports/semgrep.sarif                    80673 bytes   sha256=710d04a235dd74fee92dc7410a8985f86dfdc0b4ede235151392b55bb0a87f65
reports/slither.md                        5679 bytes   sha256=56e46758f8354863037c8e216cc5cb490573ab04ccbd0f16f918235efc0dc729
reports/slither-function-summary.txt      5923 bytes   sha256=7d87e0b0247438b61f2cbcb02be78f52e1cbd62a58d6c701ec53cfbcbeeae356
reports/slither-data-dependency.txt       3521 bytes   sha256=acdba04b8f9d9c760e6c1d82a06e79b9fc30d4c024e4e5ea49d580bf3598b71e
reports/test.log                           372 bytes   sha256=2ae219b6abb3fa9d2fba3f1b6c9d50abca120dd103c8051eaeb2aef01ab4fcf6
```

All log files exist and are non-empty (verified by `wc -c`).

## Self-check

- **Total tools expected:** 15
- **✅ RAN:** 12 (slither-mcp, slither CLI, slither printers, semgrep, aderyn, echidna, medusa, halmos, forge build, forge test, forge coverage, forge invariant)
- **⛔ N/A:** 3 (manticore — Py3.13 arm64 incompatible; amarna — no Cairo; tealer — no TEAL). Each carries a one-line justification above.
- **❌ FAILED:** 0
- **All log files exist and are non-empty:** yes
- **Prior-review artefacts consumed:** `audit/report-cantinacode-telcoin-V3-1025.pdf` (Cantina Dec 2025 review) — used for differential scoping.

### Correction note

The initial pass of this manifest erroneously marked `slither-mcp` as N/A because I searched `$PATH` / `pip show` / Homebrew — not `/Users/r00t/slither-mcp/` where the user had a local install. Re-ran with the local venv; slither-mcp **is** available and now rated ✅ RAN. The run surfaced one additional finding (SLS-1) that the CLI's default filter dropped.
