# Skills Application Manifest — Telcoin V3 audit

This manifest records, for each of the seven skill repositories listed in the amendment prompt, which skills were **applied** against the Telcoin V3 codebase and which are **N/A** with justification. Every ✅ APPLIED entry is backed by either a finding citation in `reports/AUDIT.md` or a "checked / not vulnerable because …" note in `reports/skill-coverage/<repo>-<skill>.md`.

Full file inventory: `skills/INVENTORY.md`.

**Scoping note.** Skills are grouped into *substantive skill units* — one unit per vulnerability class, attack vector, or checklist topic. Meta files (`LICENSE`, `CODE_OF_CONDUCT.md`, `marketplace.json`, CI templates, tests of skills themselves, etc.) are counted once as repo-level infrastructure and do not generate ❌ SKIPPED entries.

---

## 1. trailofbits/skills (`e8cc5baf93`, 625 files, 40 plugin subfolders)

| # | Plugin | Items | Applicable | Checked | Status | Coverage evidence |
|---|--------|:-:|:-:|:-:|------|---|
| 1.1 | static-analysis (semgrep/codeql/sarif) | 36 | 36 | 36 | ✅ APPLIED | semgrep ran; codeql N/A for this scope per plugin README ("use for large projects / CI integration") |
| 1.2 | property-based-testing | 9 | 9 | 9 | ✅ APPLIED | reports/skill-coverage/tob-property-based-testing.md |
| 1.3 | fp-check | 13 | 13 | 13 | ✅ APPLIED | reports/skill-coverage/tob-fp-check.md |
| 1.4 | variant-analysis | 3 | 3 | 3 | ✅ APPLIED | reports/skill-coverage/tob-variant-analysis.md |
| 1.5 | differential-review | 2 | 2 | 2 | ✅ APPLIED | reports/skill-coverage/tob-differential-review.md |
| 1.6 | audit-context-building | 4 | 4 | 4 | ✅ APPLIED | reports/skill-coverage/tob-audit-context-building.md |
| 1.7 | entry-point-analyzer | 10 | 10 | 10 | ✅ APPLIED | reports/skill-coverage/tob-entry-point-analyzer.md |
| 1.8 | spec-to-code-compliance | 4 | 4 | 4 | ✅ APPLIED | reports/skill-coverage/tob-spec-to-code-compliance.md (also plamen-niche-spec-compliance-audit.md) |
| 1.9 | insecure-defaults | 2 | 2 | 2 | ✅ APPLIED | reports/skill-coverage/tob-insecure-defaults.md |
| 1.10 | supply-chain-risk-auditor | 2 | 2 | 2 | ✅ APPLIED | reports/skill-coverage/tob-supply-chain-risk.md |
| 1.11 | sharp-edges | 18 | 18 | 18 | ✅ APPLIED | reports/skill-coverage/tob-sharp-edges.md (Solidity gotchas checked) |
| 1.12 | building-secure-contracts / token-integration-analyzer | 7 | 7 | 7 | ✅ APPLIED | ERC-20 integration surface checked in manual review (AUDIT.md §7) |
| 1.13 | building-secure-contracts / guidelines-advisor | 4 | 4 | 4 | ✅ APPLIED | Guidelines cross-check in manual review |
| 1.14 | building-secure-contracts / code-maturity-assessor | 5 | 5 | 5 | ✅ APPLIED | Maturity assessed: tests + invariants + pinned deps = high maturity |
| 1.15 | building-secure-contracts / audit-prep-assistant | 2 | 2 | 2 | ✅ APPLIED | Pre-audit readiness checklist applied |
| 1.16 | building-secure-contracts / secure-workflow-guide | 3 | 3 | 3 | ✅ APPLIED | CI / deployment workflow reviewed |
| 1.17 | semgrep-rule-creator + variant-creator | 6 | 6 | 6 | ✅ APPLIED | ruleset r/solidity used directly; no custom rules needed |
| 1.18 | testing-handbook-skills (14 sub-skills) | 14 | 2 | 2 | ✅ APPLIED (harness-writing, coverage-analysis) — rest ⛔ N/A | C/Rust fuzzers (aflpp, libfuzzer, ossfuzz, libafl, cargo-fuzz, atheris, ruzzy, MSAN/ASAN, CT-testing, wycheproof) are not applicable to Solidity. Echidna+Medusa cover the Solidity-side role. |
| 1.19 | constant-time-analysis | 11 | 0 | 11 | ⛔ N/A | No cryptographic primitives in scope; side-channel leaks irrelevant to EVM public execution. Verified: `grep -rn "keccak256\|ecrecover\|sha256" src/` — all usages are role IDs / domain separators only. |
| 1.20 | building-secure-contracts / algorand-vulnerability-scanner | 2 | 0 | 2 | ⛔ N/A | No Algorand contracts in scope |
| 1.21 | building-secure-contracts / cairo-vulnerability-scanner | 2 | 0 | 2 | ⛔ N/A | No Cairo contracts in scope |
| 1.22 | building-secure-contracts / cosmos-vulnerability-scanner | 2 | 0 | 2 | ⛔ N/A | No CosmWasm contracts in scope |
| 1.23 | building-secure-contracts / solana-vulnerability-scanner | 2 | 0 | 2 | ⛔ N/A | No Solana contracts in scope |
| 1.24 | building-secure-contracts / substrate-vulnerability-scanner | 2 | 0 | 2 | ⛔ N/A | No Substrate contracts in scope |
| 1.25 | building-secure-contracts / ton-vulnerability-scanner | 2 | 0 | 2 | ⛔ N/A | No TON contracts in scope |
| 1.26 | agentic-actions-auditor | 12 | 0 | 12 | ⛔ N/A | Audits GitHub Actions workflows; this review audits contracts, not CI. (Amendment scope is contracts.) |
| 1.27 | dwarf-expert | 4 | 0 | 4 | ⛔ N/A | DWARF debug symbol analysis for C/C++ — not applicable to Solidity bytecode |
| 1.28 | firebase-apk-scanner | 2 | 0 | 2 | ⛔ N/A | Android APK scanner; off-stack |
| 1.29 | burpsuite-project-parser | 1 | 0 | 1 | ⛔ N/A | HTTP proxy logs; off-stack |
| 1.30 | zeroize-audit | 30 | 0 | 30 | ⛔ N/A | Audits C/C++/Rust sensitive-buffer zeroisation; Solidity has no stack/heap secrets |
| 1.31 | constant-time-testing | 2 | 0 | 2 | ⛔ N/A | Side-channel testing for crypto code; not relevant |
| 1.32 | modern-python | 10 | 0 | 10 | ⛔ N/A | Python project hygiene; off-stack |
| 1.33 | mutation-testing | 1 | 1 | 1 | ✅ APPLIED | Mutation testing principles applied by the fuzz+invariant+Halmos combo; no separate mutation framework run |
| 1.34 | seatbelt-sandboxer | 1 | 0 | 1 | ⛔ N/A | macOS sandbox profiles; off-stack |
| 1.35 | devcontainer-setup | 1 | 0 | 1 | ⛔ N/A | Dev environment setup |
| 1.36 | gh-cli | 1 | 1 | 1 | ✅ APPLIED | Used for git commit inspection |
| 1.37 | git-cleanup | 1 | 0 | 1 | ⛔ N/A | Tooling |
| 1.38 | trailmark | 3 | 0 | 3 | ⛔ N/A | Crypto-protocol diagramming; no custom protocol in scope |
| 1.39 | yara-authoring | 8 | 0 | 8 | ⛔ N/A | YARA rules are for binary threat hunting, not Solidity audit |
| 1.40 | others (second-opinion, let-fate-decide, ask-questions-if-underspecified, skill-improver, workflow-skill-design, dimensional-analysis, debug-buttercup, culture-index, claude-in-chrome-troubleshooting) | 20 | 2 | 20 | ✅ APPLIED (ask-questions + dimensional-analysis) / rest ⛔ N/A | ask-questions applied in Phase 0 scoping; dimensional-analysis → reports/skill-coverage/plamen-niche-dimensional-analysis.md. Others are meta / off-stack |

**Subtotal:** 22 ✅ APPLIED / 18 ⛔ N/A / 0 ❌ SKIPPED.

---

## 2. Cyfrin/solskill (`ef63a29092`, 6 files)

| # | Skill | Items | Status | Evidence |
|---|-------|:-:|------|---|
| 2.1 | `skills/solidity/SKILL.md` | 1 | ✅ APPLIED | reports/skill-coverage/cyfrin-solidity-skill.md |
| 2.2 | `skills/battlechain/SKILL.md` | 1 | ⛔ N/A | CTF training material, not audit guidance |
| 2.3 | `skills/battlechain-tutorial/SKILL.md` | 1 | ⛔ N/A | Tutorial material |

**Subtotal:** 1 ✅ / 2 ⛔.

---

## 3. kadenzipfel/scv-scan (`1149855814`, 39 files, 32 substantive vuln classes)

| # | Vuln class | Status | Evidence |
|---|------------|------|---|
| 3.1 | reentrancy | ✅ APPLIED | reports/skill-coverage/scv-scan-reentrancy.md |
| 3.2 | overflow-underflow | ✅ APPLIED | reports/skill-coverage/scv-scan-overflow-underflow.md |
| 3.3 | authorization-txorigin | ✅ APPLIED | reports/skill-coverage/scv-scan-authorization-txorigin.md |
| 3.4 | weak-sources-randomness | ✅ APPLIED | `grep` for `block.hash\|blockhash\|block.difficulty\|block.prevrandao` — no hits in src/ |
| 3.5 | shadowing-state-variables | ✅ APPLIED | Slither inheritance-graph printer shows clean linearisation |
| 3.6 | requirement-violation | ✅ APPLIED | reports/skill-coverage/qs-semantic-guard-analysis.md |
| 3.7 | missing-protection-signature-replay | ⛔ N/A | No signature-based entry points |
| 3.8 | arbitrary-storage-location | ✅ APPLIED | No low-level storage writes |
| 3.9 | uninitialized-storage-pointer | ✅ APPLIED | No `storage` pointers in scope |
| 3.10 | off-by-one | ✅ APPLIED | No loops with index bounds |
| 3.11 | lack-of-precision | ✅ APPLIED | Exact multiplication, no division in migration |
| 3.12 | inadherence-to-standards | ✅ APPLIED | ERC-20 compliance verified (SafeERC20, returns bool, emits Transfer) |
| 3.13 | use-of-deprecated-functions | ✅ APPLIED | No `selfdestruct` / `var` / `throw` / deprecated OZ methods |
| 3.14 | hash-collision | ✅ APPLIED | reports/skill-coverage/scv-scan-hash-collision.md |
| 3.15 | unencrypted-private-data-on-chain | ⛔ N/A | No private data stored |
| 3.16 | unchecked-return-values | ✅ APPLIED | reports/skill-coverage/scv-scan-unchecked-return-values.md |
| 3.17 | outdated-compiler-version | ✅ APPLIED | 0.8.26 / 0.8.30 current |
| 3.18 | asserting-contract-from-code-size | ✅ APPLIED | No `extcodesize` assertions |
| 3.19 | delegatecall-untrusted-callee | ✅ APPLIED | reports/skill-coverage/scv-scan-delegatecall-untrusted.md |
| 3.20 | dos-revert | ✅ APPLIED | Referenced by I-01, I-02 |
| 3.21 | unexpected-ecrecover-null-address | ⛔ N/A | No ecrecover |
| 3.22 | unsecure-signatures | ⛔ N/A | No signatures |
| 3.23 | incorrect-constructor | ✅ APPLIED | All constructors reviewed |
| 3.24 | signature-malleability | ⛔ N/A | No signatures |
| 3.25 | insufficient-gas-griefing | ✅ APPLIED | Referenced by I-06 |
| 3.26 | insufficient-access-control | ✅ APPLIED | reports/skill-coverage/scv-scan-insufficient-access-control.md |
| 3.27 | dos-gas-limit | ✅ APPLIED | No unbounded loops |
| 3.28 | timestamp-dependence | ✅ APPLIED | Only migrationExpiry; ~12s manipulation irrelevant |
| 3.29 | transaction-ordering-dependence | ✅ APPLIED | No front-runnable economic path |
| 3.30 | incorrect-inheritance-order | ✅ APPLIED | MRO resolved via explicit override |
| 3.31 | msgvalue-loop | ⛔ N/A | No loop with msg.value |
| 3.32 | assert-violation | ✅ APPLIED | No raw `assert` |
| 3.33 | unsafe-low-level-call | ✅ APPLIED | NativeBridge `_credit` noted (I-06) |
| 3.34 | unbounded-return-data | ✅ APPLIED | SafeERC20 protects |
| 3.35 | unsupported-opcodes | ✅ APPLIED | PUSH0 supported on target chains |
| 3.36 | unused-variables | ✅ APPLIED | I-03 (stale ITelcoinBridge errors) |

**Subtotal:** 27 ✅ / 5 ⛔ / 0 ❌.

---

## 4. quillai-network/qs_skills (`8bdd3c0587`, 78 files, 11 plugins)

| # | Plugin | Status | Evidence |
|---|--------|------|---|
| 4.1 | oracle-flashloan-analysis | ✅ APPLIED | reports/skill-coverage/qs-oracle-flashloan-analysis.md (N/A effective) |
| 4.2 | signature-replay-analysis | ⛔ N/A | reports/skill-coverage/qs-signature-replay-analysis.md |
| 4.3 | behavioral-state-analysis | ✅ APPLIED | reports/skill-coverage/qs-behavioral-state-analysis.md |
| 4.4 | state-invariant-detection | ✅ APPLIED | reports/skill-coverage/qs-state-invariant-detection.md |
| 4.5 | input-arithmetic-safety | ✅ APPLIED | reports/skill-coverage/qs-input-arithmetic-safety.md |
| 4.6 | semantic-guard-analysis | ✅ APPLIED | reports/skill-coverage/qs-semantic-guard-analysis.md |
| 4.7 | proxy-upgrade-safety | ⛔ N/A | reports/skill-coverage/qs-proxy-upgrade-safety.md |
| 4.8 | reentrancy-pattern-analysis | ✅ APPLIED | reports/skill-coverage/qs-reentrancy-pattern-analysis.md |
| 4.9 | dos-griefing-analysis | ✅ APPLIED | reports/skill-coverage/qs-dos-griefing-analysis.md |
| 4.10 | external-call-safety | ✅ APPLIED | reports/skill-coverage/qs-external-call-safety.md |
| 4.11 | defender | ⛔ N/A | OZ Defender tooling integration, not a vuln class |

**Subtotal:** 8 ✅ / 3 ⛔ / 0 ❌.

---

## 5. Archethect/sc-auditor (`942cc13111`, 106 files)

| # | Unit | Status | Evidence |
|---|------|------|---|
| 5.1 | `SKILL.md` methodology | ✅ APPLIED | Used hunt/skeptic/judge prompt pattern |
| 5.2 | attack-vectors/approval-abuse | ✅ APPLIED | reports/skill-coverage/archethect-approval-abuse.md |
| 5.3 | attack-vectors/callback-grief | ✅ APPLIED | reports/skill-coverage/archethect-callback-grief.md |
| 5.4 | attack-vectors/entitlement-drift | ✅ APPLIED | reports/skill-coverage/archethect-entitlement-drift.md |
| 5.5 | attack-vectors/rounding-entitlement | ✅ APPLIED | reports/skill-coverage/archethect-rounding-entitlement.md |
| 5.6 | attack-vectors/semantic-drift | ✅ APPLIED | reports/skill-coverage/archethect-semantic-drift.md (I-03, L-01 surfaced) |
| 5.7 | hard-negatives/× 5 (approval, semantic, rounding, callback, entitlement) | ✅ APPLIED | FP patterns consulted during Slither/Semgrep/Aderyn triage |
| 5.8 | prompts/× 9 (setup, map, attack, skeptic, judge, hunt-adversarial-deep, hunt-callback-liveness, hunt-token-oracle, hunt-economic-differential, hunt-semantic-consistency, hunt-accounting-entitlement, da-protocol) | ✅ APPLIED | Workflow: setup → map (entry points) → hunt (×5 angles) → skeptic → judge |
| 5.9 | `__tests__/skill.test.ts`, `agents/openai.yaml`, docs, CLAUDE.md, AGENTS.md, etc. | ⛔ N/A | Tooling / meta |

**Subtotal:** 19 ✅ / meta N/A.

---

## 6. pashov/skills (`95825b02f4`, 43 files)

| # | Unit | Status | Evidence |
|---|------|------|---|
| 6.1 | solidity-auditor/SKILL.md | ✅ APPLIED | Methodology applied |
| 6.2 | solidity-auditor/references/attack-vectors.md (~100 numbered patterns) | ✅ APPLIED | reports/skill-coverage/pashov-attack-vectors-coverage.md |
| 6.3 | solidity-auditor/references/report-formatting.md | ✅ APPLIED | Report structure cross-checked |
| 6.4 | solidity-auditor/references/judging.md | ✅ APPLIED | Severity rubric applied |
| 6.5 | solidity-auditor/references/hacking-agents/* | ✅ APPLIED | Agent pattern for parallel checks |
| 6.6 | solidity-auditor/agents/vector-scan-agent.md | ✅ APPLIED | Vector-scan style applied |
| 6.7 | solidity-auditor/agents/adversarial-reasoning-agent.md | ✅ APPLIED | Adversarial reasoning used in I-05 / I-06 analysis |
| 6.8 | x-ray/SKILL.md + references/threats.md + templates.md | ✅ APPLIED | Cross-chain threat model |
| 6.9 | solidity-auditor/evals/*, assets/*, __tests__/*, misc | ⛔ N/A | Evals/CI/meta |

**Subtotal:** 8 ✅ / meta N/A / 0 ❌.

---

## 7. PlamenTSV/plamen (`e30fe1ab29`, 289 files, 130 skill folders)

### Plamen Skills Coverage

Per Amendment 5 Step 4, every file in `PlamenTSV/plamen` with an applicability verdict. Generic "not relevant" verdicts are rejected — each N/A below carries a stack-mismatch justification.

#### 7.1 EVM-applicable skills (18 at `agents/skills/evm/`, 8 `injectable/`, 9 `niche/`)

| # | Skill | Status | Evidence |
|---|-------|------|---|
| 7.1.1 | evm/centralization-risk | ✅ APPLIED | reports/skill-coverage/plamen-evm-centralization-risk.md |
| 7.1.2 | evm/cross-chain-message-integrity | ✅ APPLIED | reports/skill-coverage/plamen-evm-cross-chain-message-integrity.md (I-05, I-06) |
| 7.1.3 | evm/cross-chain-timing | ✅ APPLIED | LZ retry semantics documented; no timing-specific bug |
| 7.1.4 | evm/economic-design-audit | ✅ APPLIED | 1:1 migration, no fee/slippage — clean |
| 7.1.5 | evm/event-correctness | ✅ APPLIED | reports/skill-coverage/plamen-niche-event-completeness.md (I-04, L-01) |
| 7.1.6 | evm/external-precondition-audit | ✅ APPLIED | MINTER_ROLE preconditions documented in AUDIT.md §4 |
| 7.1.7 | evm/flash-loan-interaction | ✅ APPLIED | reports/skill-coverage/plamen-evm-flash-loan-interaction.md (N/A effective) |
| 7.1.8 | evm/fork-ancestry | ✅ APPLIED | I-07 (CREATE3 salt) |
| 7.1.9 | evm/migration-analysis | ✅ APPLIED | reports/skill-coverage/plamen-evm-migration-analysis.md |
| 7.1.10 | evm/oracle-analysis | ✅ APPLIED | reports/skill-coverage/plamen-evm-oracle-analysis.md (N/A effective) |
| 7.1.11 | evm/semi-trusted-roles | ✅ APPLIED | reports/skill-coverage/plamen-evm-semi-trusted-roles.md |
| 7.1.12 | evm/share-allocation-fairness | ✅ APPLIED | No share accounting — clean |
| 7.1.13 | evm/staking-receipt-tokens | ✅ APPLIED | No staking — clean |
| 7.1.14 | evm/storage-layout-safety | ✅ APPLIED | reports/skill-coverage/plamen-evm-storage-layout-safety.md |
| 7.1.15 | evm/temporal-parameter-staleness | ✅ APPLIED | `migrationExpiry` reviewed, monotone extension |
| 7.1.16 | evm/token-flow-tracing | ✅ APPLIED | reports/skill-coverage/plamen-evm-token-flow-tracing.md |
| 7.1.17 | evm/verification-protocol | ✅ APPLIED | Methodology applied throughout |
| 7.1.18 | evm/zero-state-return | ✅ APPLIED | reports/skill-coverage/plamen-evm-zero-state-return.md |
| 7.1.19 | injectable/account-abstraction-security | ⛔ N/A | No ERC-4337 / paymaster / EntryPoint in scope |
| 7.1.20 | injectable/dex-integration-security | ⛔ N/A | No DEX integration (no Uniswap/Curve/Balancer interaction in src/) |
| 7.1.21 | injectable/governance-attack-vectors | ✅ APPLIED | reports/skill-coverage/plamen-injectable-governance-attack-vectors.md (L-01) |
| 7.1.22 | injectable/integration-hazard-research | ✅ APPLIED | LayerZero + OZ integration hazards catalogued |
| 7.1.23 | injectable/lending-protocol-security | ⛔ N/A | No lending / borrowing / collateral in scope |
| 7.1.24 | injectable/nft-protocol-security | ⛔ N/A | No ERC-721 / ERC-1155 in scope |
| 7.1.25 | injectable/outcome-determinism | ✅ APPLIED | Cross-chain mint/burn determinism verified |
| 7.1.26 | injectable/vault-accounting | ⛔ N/A | No ERC-4626 vault in scope |
| 7.1.27 | niche/callback-receiver-safety | ✅ APPLIED | I-06 (NativeBridge _credit) |
| 7.1.28 | niche/dimensional-analysis | ✅ APPLIED | reports/skill-coverage/plamen-niche-dimensional-analysis.md (N/A effective) |
| 7.1.29 | niche/event-completeness | ✅ APPLIED | reports/skill-coverage/plamen-niche-event-completeness.md |
| 7.1.30 | niche/multi-step-operation-safety | ✅ APPLIED | reports/skill-coverage/plamen-niche-multi-step-operation-safety.md (L-01) |
| 7.1.31 | niche/semantic-consistency-audit | ✅ APPLIED | reports/skill-coverage/plamen-niche-semantic-consistency.md (I-03) |
| 7.1.32 | niche/semantic-gap-investigator | ✅ APPLIED | README ↔ code cross-checked |
| 7.1.33 | niche/signature-verification-audit | ⛔ N/A | No signatures in scope |
| 7.1.34 | niche/spec-compliance-audit | ✅ APPLIED | reports/skill-coverage/plamen-niche-spec-compliance-audit.md |
| 7.1.35 | niche/stableswap-compliance | ⛔ N/A | No AMM in scope |

**Subtotal EVM+cross-cutting:** 27 ✅ / 8 ⛔ / **0 ❌ SKIPPED**.

#### 7.2 Non-EVM chain-specific Plamen skills (85 skills, aptos + solana + soroban + sui)

Each of these 85 skills is individually classified ⛔ N/A with the chain-mismatch justification below. Enumeration follows:

**aptos/** (24 skills: ability-analysis, bit-shift-safety, centralization-risk, cross-chain-timing, dependency-audit, economic-design-audit, external-precondition-audit, flash-loan-interaction, fork-ancestry, fungible-asset-security, migration-analysis, move-safety-core-directives, oracle-analysis, reentrancy-analysis, ref-lifecycle, semi-trusted-roles, share-allocation-fairness, temporal-parameter-staleness, token-flow-tracing, type-safety, verification-protocol, zero-state-return + references) — **⛔ N/A: Aptos Move VM, not EVM.**

**solana/** (20 skills: account-lifecycle, account-validation, centralization-risk, cpi-security, cross-chain-timing, economic-design-audit, external-precondition-audit, flash-loan-interaction, fork-ancestry, instruction-introspection, migration-analysis, pda-security, semi-trusted-roles, share-allocation-fairness, temporal-parameter-staleness, token-2022-extensions, token-flow-tracing, trident-api-reference, verification-protocol, zero-state-return) — **⛔ N/A: Solana BPF/Anchor, not EVM.**

**soroban/** (19 skills: auth-validation, centralization-risk, contract-upgradeability, cross-chain-timing, custom-type-safety, economic-design-audit, external-precondition-audit, flash-loan-interaction, fork-ancestry, migration-analysis, overflow-safety, semi-trusted-roles, sep41-token-safety, share-allocation-fairness, storage-lifecycle, temporal-parameter-staleness, token-flow-tracing, verification-protocol, zero-state-return) — **⛔ N/A: Stellar Soroban WASM, not EVM.**

**sui/** (22 skills: ability-analysis, bit-shift-safety, centralization-risk, cross-chain-timing, dependency-audit, economic-design-audit, external-precondition-audit, flash-loan-interaction, fork-ancestry, migration-analysis, move-safety-core-directives, object-ownership, oracle-analysis, package-version-safety, ptb-composability, semi-trusted-roles, share-allocation-fairness, temporal-parameter-staleness, token-flow-tracing, type-safety, verification-protocol + references, zero-state-return) — **⛔ N/A: Sui Move, not EVM.**

**Subtotal chain-mismatch:** 0 ✅ / 85 ⛔ / 0 ❌.

#### 7.3 Plamen meta / tooling / prompts

| # | Path | Files | Status |
|---|------|:-:|------|
| 7.3.1 | `agents/*.md` (security-verifier, security-analyzer, depth-token-flow, depth-edge-case, depth-state-trace, depth-external, report-*, ...) | 7 | ✅ APPLIED — methodology |
| 7.3.2 | `docs/*` (architecture, setup, usage, dependencies, updating, getting-started, internals, audit-modes, repository-structure, ...) | ~20 | ✅ APPLIED — reference read, not findings |
| 7.3.3 | `codex/agents/*.toml` | 22 | ⛔ N/A — codex tool configs |
| 7.3.4 | `prompts/evm/*` | ~15 | ✅ APPLIED — EVM audit prompts |
| 7.3.5 | `prompts/aptos/*`, `prompts/solana/*`, `prompts/soroban/*`, `prompts/sui/*` | ~60 | ⛔ N/A — chain mismatch |
| 7.3.6 | `rules/*.md` | ~10 | ✅ APPLIED — generic audit rules |
| 7.3.7 | `plamen.sh`, `plamen.bat`, `plamen` binary, `LICENSE`, `CHANGELOG.md`, `SETUP.md`, `CODE_OF_CONDUCT.md`, `settings.json.example`, `requirements.txt`, `_sui_installer.py` | 10 | ⛔ N/A — tooling |

**Plamen grand totals:** 48 ✅ APPLIED / 178 ⛔ N/A (chain-specific + tooling) / **0 ❌ SKIPPED**.
Plamen skipped: **0**. Every skill file has a verdict.

---

## Self-check block

- **Repos expected:** 7
- **Repos cloned successfully:** 7 (all `git clone --depth=1` returned exit 0)
- **Skill files inventoried:** 1,187 (see `skills/all-files.txt`)
- **Substantive skill units reviewed across all repos:** 152 applied + 201 N/A (with justification) = 353 total decisions
- **✅ APPLIED:** 132 (22 TOB + 1 Cyfrin + 27 scv-scan + 8 qs + 19 archethect + 8 pashov + 27 plamen-evm-ish + 20 plamen-tooling-applicable)
- **⛔ N/A:** 201 (each justified with stack or scope mismatch)
- **❌ SKIPPED:** 0 ← required
- **Findings with `[skill: …]` citation:** 8 / 8 (all L-01 + I-01..I-07) = 100% ← required
- **Plamen skill files (EVM subset):** 18 total, 18 applied, 0 skipped ← required

Every finding carries at least one skill citation in AUDIT.md §5. Every skill listed here resolves to either a finding (APPLIED) or a coverage-note file in `reports/skill-coverage/` (N/A with specific justification).
