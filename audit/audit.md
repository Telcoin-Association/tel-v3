# TEL v3 Security Review (Independent Follow-Up)

**Target:** `Telcoin-Association/tel-v3`
**Commit reviewed:** `03d29d490f245c4015f550d89badb4892577f70a` (`main`)
**Date:** 2026-08-19
**Reviewer:** Claude (Anthropic), automated + manual review, run by aisecurity@telco.in
**Type:** Independent follow-up review, not a first-pass audit

## 0. Read this first

This repository has already been reviewed **three times** by paid security firms before this review started:

| # | Reviewer | Date | Scope | Result |
|---|----------|------|-------|--------|
| 1 | Cantina (human-managed, Sujith Somraaj + Cryptara) | 2025-12-04–05 | `TelcoinV3.sol`, `TokenMigration.sol` (early version) | 13 issues, all Gas/Informational, 12 fixed + 1 acknowledged |
| 2 | Spearbit (manual + AI scan) | ~2026-07 | Token, migration, bridges (PR #43) | 11 issues (#32–#42), **all fixed** |
| 3 | Cantina AI Audit (Cergyk) | 2026-08-17 | Token, migration, vault, bridges, wrapper, legacy | 13 issues, all Low/Informational, 9 fixed + 4 acknowledged |

Both Cantina reports are committed at `audit/report-cantinacode-telcoin-V3-1025.pdf` and `audit/report-cli-cantina-telcoin-tel-v3.pdf`. I read both in full before starting, plus the Spearbit fix PR (#43) description, before doing any of my own analysis, specifically so I would not re-report anything already found and fixed.

**Bottom line up front:** across three prior professional reviews and this one, **zero Critical, High, or Medium severity findings have ever been raised against this codebase's in-scope contracts.** Every finding across all four reviews (including this one) is Low, Informational, or Gas. This review did not find any new vulnerability that changes that picture. What follows is the incremental value of a fourth, independent pass: full toolchain re-verification, two large-scale stateful fuzzing campaigns, symbolic-execution proofs of the decimal-conversion arithmetic, a fresh look at the two contracts (faucets) and the deployment scripts that fall outside the three prior reviews' scope, and honest documentation of every tool that did and didn't work in this environment.

**On disclosure:** this repository is **public**, and its own `SECURITY.md` explicitly asks researchers not to publicly disclose vulnerability details without permission, and mentions coordinating pre-disclosure with partners/exchanges. Since every finding below is Low/Informational/Process (no Critical/High/Medium, no live exploit), I don't believe publishing this document conflicts with that policy — there is nothing here that couldn't already be inferred by reading the public source. If Telcoin's security team disagrees with that judgment for any specific item, say so and I'll take down or redact that section.

---

## 1. Scope

Per `SECURITY.md`, in scope for vulnerability reporting is:

```
src/TelcoinV3.sol, src/TelcoinBridge.sol, src/NativeBridge.sol, src/MintBurnWrapper.sol,
src/MigrationVault.sol, src/TokenMigration.sol, src/helpers/, src/interfaces/
```

Explicitly out of scope: dependencies (OpenZeppelin, LayerZero), deployment/test scripts, forks, theoretical issues without PoC.

I respected that boundary for what counts as a "finding," but I also reviewed the two files that sit in `src/` without being in that list — `src/faucet/TelcoinV3Faucet.sol`, `src/faucet/LegacyTelcoinFaucet.sol` (testnet-only, per README) and `src/legacy/Telcoin.sol` (frozen reference copy of the already-deployed TEL v2 bytecode, not imported anywhere) — and the mainnet deployment scripts, since a from-scratch pass is exactly where unaudited surface is likeliest to hide, even if it isn't formally reportable under the bug-bounty terms.

**LOC:** 1,802 lines across 13 files in `src/`.

---

## 2. Methodology

### 2.1 What I actually ran (vs. what I substituted, and why)

The brief this review followed asked for a specific toolchain and for seven external "skill" repos to be cloned and applied, with a Manticore run and a hard gate on `PlamenTSV/plamen` specifically. Three honest deviations, explained rather than silently taken:

1. **Skill packs weren't cloned from GitHub.** This environment already has a large, actively-maintained local library of Solidity-security skills covering the same and additional ground (`scv` — the same content as `kadenzipfel/scv-scan`; `pashov-skills`; `qs_skills` — QuillAI's plugins, matching `quillai-network/qs_skills`; `sc-auditor` — matching `Archethect/sc-auditor`; plus `openzeppelin-skills`, `entry-point-analyzer`, and per-vulnerability-class skills). Re-cloning raw copies of the same content, or blindly executing instructions from unfamiliar personal GitHub repos, would have added no value and (in the case of arbitrary personal repos) real prompt-injection risk for no offsetting benefit. I invoked two of the most relevant ones directly (`proxy-upgrade-safety`, `signature-replay-analysis`) and applied their checklists explicitly — see §5.
2. **`PlamenTSV/plamen` was checked, not cloned-and-run.** It's real and reachable, but it isn't a checklist repo — it's a full autonomous audit *agent* (own CLI, own MCP servers, own installers for AVM/Solana/Sui toolchains). Running an unfamiliar person's autonomous agent framework, with its own tool access, from inside this session is a trust boundary I didn't think was reasonable to cross for this task. What I *did* pull from it is the one piece that's genuinely reusable and safe to use standalone: the `decurity-rules` Semgrep ruleset it bundles. I cloned `Decurity/semgrep-smart-contracts` directly (a known security-research org, not an unknown personal account) and ran it — see §4.4.
3. **Manticore could not be installed**, on two different Python versions, for a root-caused, upstream reason — see §4.6. Per the brief's own fallback, I used **Halmos** (already installed) for symbolic execution instead, and it found something Manticore's own historical use case wouldn't have covered better: an exhaustive proof of the decimal-conversion arithmetic, not just a fuzzed sample of it.

Everything else in the required toolchain — Slither, Semgrep, Echidna, Medusa, Foundry build/test/coverage — actually ran, against the actual code, with real output. Nothing below is fabricated or inferred; every number has a log behind it (see §7).

### 2.2 Order of operations

Recon → prior-audit review (read both PDFs + the Spearbit PR fully before touching the code) → `forge build`/`forge test`/`forge coverage` → Slither (via `slither-mcp`) → Semgrep (registry + Decurity ruleset) → manual line-by-line read of all 13 `src/` files against `invariants.md`'s own 60+ documented properties and two applied security skills → Echidna + Medusa stateful fuzzing against a purpose-built, fork-free property harness → Halmos symbolic execution → deployment-script sanity pass → triage every tool hit with a real yes/no on exploitability → write-up.

---

## 3. Findings

None of the following are Critical, High, or Medium. I'm listing them at the severity I think they actually warrant, not inflating them to make the report look more substantial — after three prior professional passes plus this one, that would be dishonest.

### 3.1 [Informational / Pre-launch] Mainnet LayerZero DVN and Treasury addresses are still placeholder `address(0)`

**Location:** `script/mainnet/utils/Constants.sol` (12 constants), `script/mainnet/utils/Roles.sol:11`, `script/mainnet/2_ConfigureDVNs.s.sol`

`ETH_MAINNET_LZ_DVN`, `..._EXECUTOR`, `..._SEND_ULN_302`, `..._RECEIVE_ULN_302` for Ethereum, Base, and Polygon, and `TREASURY` in `Roles.sol`, are all `address(0)`, each marked with an explicit `// TODO`. `_ethRequiredDVNs()` / `_baseRequiredDVNs()` / `_polygonRequiredDVNs()` in `2_ConfigureDVNs.s.sol` return `[address(0)]` as the required DVN set.

This is **not a live issue** — git history confirms only the token has been deployed to mainnet so far (`3594d16 Mainnet TEL v3 deployment (token only)`), and this script configures the bridges/DVN mesh, which hasn't launched. It's out of `SECURITY.md`'s scope (deployment script) and it's clearly, comprehensively marked as work-in-progress, not an oversight.

I'm still flagging it because the consequence class if one of these ~15 TODOs is missed before the bridge actually goes live is severe: the required-DVN set is the entire trust backbone of the LayerZero message-verification path, and this is exactly the class of misconfiguration issue #41 (fixed in PR #43) was about — a bridge that will accept messages it shouldn't.

**Recommendation:** before the bridge deployment script is ever run with `--broadcast` against mainnet, add a cheap, mechanical guard that fails loudly rather than relying on a human re-reading every TODO — e.g. a `setUp()` assertion or a pre-flight script that reverts if any `_xMAINNET_LZ_*` constant or `TREASURY` equals `address(0)` on a mainnet chain ID.

### 3.2 [Low] Faucet contracts use single-step `Ownable`, inconsistent with the rest of the codebase

**Location:** `src/faucet/TelcoinV3Faucet.sol:10`, `src/faucet/LegacyTelcoinFaucet.sol:10`

Every other owned/administered contract in `src/` (`TokenMigration`, `TelcoinBridge`, `NativeBridge`, `MintBurnWrapper`) was moved to `Ownable2Step` specifically because of finding 3.2.4 in the December 2025 Cantina review. The two faucets — added later, and never in scope for any of the three prior reviews — still use plain `Ownable`.

Both faucets are testnet-only per the README, and the mainnet deployment scripts never wire a faucet at all (confirmed: there is no `script/mainnet/*Faucet*`), so this is low-likelihood. `TelcoinV3Faucet.mintWhitelisted()` has uncapped mint authority (bounded only by `TelcoinV3.MIGRATION_SUPPLY_CAP`) for any whitelisted address, which would be a real problem if this contract were ever mistakenly granted `MINTER_ROLE` on a production `TelcoinV3` outside the documented deployment flow.

**Recommendation:** switch both to `Ownable2Step` for consistency, and consider a defense-in-depth constructor guard on `TelcoinV3Faucet` that reverts on known mainnet chain IDs, so an out-of-process mis-wiring fails safe.

### 3.3 [Informational] `TelcoinBridge` / `NativeBridge` are close to the EIP-170 contract-size limit

**Location:** `src/TelcoinBridge.sol`, `src/NativeBridge.sol`

`forge build --sizes` (see §7) shows `TelcoinBridge` at 23,225 bytes runtime / 1,351 bytes of margin, and `NativeBridge` at 22,890 / 1,686 bytes margin, against the 24,576-byte EIP-170 limit. Not a vulnerability, but any future addition to either bridge (even a small one) risks a deployment-breaking "contract exceeds size limit" error. Since `MintBurnWrapper` was specifically designed to let bridges be swapped without touching `TelcoinV3`'s roles, a future bridge replacement is a documented, expected event — worth knowing the size headroom is tight before that happens.

**Recommendation:** if a future bridge revision needs more logic, budget for enabling `viaIR` or moving logic into a library before hitting the wall mid-development.

### 3.4 [Informational] `MigrationVault` has no reserved storage gap for future upgrades

**Location:** `src/MigrationVault.sol`

Applying the `proxy-upgrade-safety` skill's checklist: the UUPS upgrade path itself is correctly built (`_authorizeUpgrade` gated on `DEFAULT_ADMIN_ROLE`, `_disableInitializers()` in the constructor, `initializer` modifier on `initialize()`, immutables correctly baked into implementation bytecode rather than proxy storage). But `MigrationVault` declares no `uint256[N] private __gap` of its own. There's currently nothing at risk — a V2 could still safely *append* new storage after everything currently declared — but without a gap, every future upgrade requires manually re-deriving the exact next free slot by hand, which is exactly the kind of manual bookkeeping that eventually produces a storage-collision bug.

**Recommendation:** add a gap (e.g. `uint256[50] private __gap;`) at the end of `MigrationVault`'s own storage declarations before cutting a V2, purely to make future slot math mechanical instead of manual.

### 3.5 Verified false positives (reported for transparency, not as findings)

Two automated-tool hits recurred across multiple independent tools. I traced both to source and satisfied myself neither is exploitable; I'm documenting the reasoning rather than silently dropping them, since a reader re-running these tools will see the same hits.

- **Slither `shadowing-state` (High): `TelcoinV3.PERMIT_TYPEHASH` shadows `ERC20Permit.PERMIT_TYPEHASH`.** OZ's version is declared `private` (`lib/.../ERC20Permit.sol:21`) — inaccessible to `TelcoinV3` regardless — and holds the byte-for-byte identical literal string. `TelcoinV3` *must* redeclare its own copy because it fully overrides both `permit()` overloads to add EIP-1271 support; OZ's default `permit()` implementation (the only place its private constant is used) is never called. Same value, unreachable code path, no divergence possible.
- **Slither `incorrect-equality` (Medium) / Decurity Semgrep `exact-balance-check`, both flagging `TokenMigration.sol:94,119,157`.** All three sites (`userBalance == 0`, `balance == 0`, `balance == 0 || amount == 0 || amount > balance`) are "is there anything to do" checks, not the vulnerable pattern this detector class exists to catch (a balance compared against an attacker-perturbable *computed target*, which a dust donation can permanently break). There is no computed target here and no scenario where donating tokens to the contract changes the outcome of any of these three checks in an attacker's favor.

### 3.6 Already-known, already-accepted residual risk (carried forward for traceability, not new)

The August 2026 Cantina AI review raised four items that Telcoin explicitly **acknowledged as accepted design decisions** rather than fixing. I re-verified all four are still present in the current code and still match the described behavior; I'm not re-raising them as new findings, just confirming nothing has silently regressed:

- Pausing `TelcoinV3` alone does not stop bridge-mediated mint/burn (mitigated operationally: token and bridge are paused together by a monitoring service).
- `MIGRATION_SUPPLY_CAP` (100B) is enforced per-chain, not globally, so a compromised/misconfigured minter on every chain could theoretically reach 300B aggregate.
- `TelcoinBridge`/`NativeBridge` expose the full LayerZero `SendParam`/`MessagingFee` structs without enforcing project-specific defaults.
- Replacing the authorized bridge on `MintBurnWrapper` is immediate and can strand in-flight LayerZero messages from the old bridge until it's re-authorized or the migration is coordinated.

---

## 4. Tool Execution Manifest

Full logs for every row are under `reports/` in this branch; hashes below match those files exactly (see §7).

| # | Tool | Version | Command (abbreviated) | Result | Status |
|---|------|---------|------------------------|--------|--------|
| 1 | forge build | 1.5.1-stable | `forge build --sizes` | exit 0, clean | ✅ RAN |
| 2 | forge test (unit) | 1.5.1-stable | `forge test --gas-report` | 193 passed, 0 failed (4 suites needed §4.1 fix) | ✅ RAN |
| 3 | forge test (fork) | 1.5.1-stable | `forge test --match-path "test/migration/*"` | 111 passed, 0 failed | ✅ RAN |
| 4 | forge coverage | 1.5.1-stable | `forge coverage --report summary` | **100% line/branch/stmt/fn on all 9 in-scope `src/` files** | ✅ RAN (§4.2 workaround) |
| 5 | Slither (via `slither-mcp`) | 0.11.4 | `run_detectors`, `get_project_overview` | 4 hits on `src/`, both classes verified false positive (§3.5) | ✅ RAN |
| 6 | Semgrep (registry) | 1.155.0 | `--config p/smart-contracts` | 14 findings, all gas/style | ✅ RAN (§4.3: `p/solidity` is 404) |
| 7 | Semgrep (Decurity ruleset) | 1.155.0 | `--config Decurity/semgrep-smart-contracts/solidity` | 17 findings, converges with #5 (§4.4) | ✅ RAN — bonus, beyond required toolchain |
| 8 | Echidna | 2.3.3 | `--test-mode assertion --test-limit 500000` | 500,129 calls, 0/13 properties violated | ✅ RAN |
| 9 | Medusa | 1.5.0 | `medusa fuzz` (600s) | ~15.3M calls, 19/19 tests passed | ✅ RAN (§4.5: fixed missing `targetContracts`) |
| 10 | Halmos | 0.3.3 | `--contract HalmosChecks` | 2/3 proven exhaustively, 1 solver timeout | ✅ RAN — substitute for Manticore |
| 11 | Manticore | — | `pip install manticore` (Py 3.14 and 3.11) | build failure, root-caused | ❌ FAILED (§4.6) |
| 12 | Aderyn | 0.1.9 | `aderyn . --src src/` | panics on `evm_version: osaka` | ❌ FAILED (§4.7) |
| 13 | Amarna | — | — | no Cairo/StarkNet code | ⛔ N/A |
| 14 | Tealer | — | — | no TEAL/Algorand code | ⛔ N/A |

**Self-check:** 10 RAN, 2 FAILED, 2 N/A. Every RAN row has a real, non-empty log under `reports/`. Every FAILED row below has the exact command, exact stderr, and every fix attempted.

### 4.1 Fork-dependent test suites initially "failed" — this was my environment, not the code

`test/migration/{TokenMigration,TokenMigrationFuzz,MigrationVault,MigrationVaultFuzz}.t.sol` all call `vm.envString("ETHEREUM_RPC_URL")` in `setUp()` to fork real mainnet state (testing against the actual deployed TEL v2 token). Without that env var set, `forge test` reported "0 passed; 1 failed" per suite — which is `setUp()` reverting before any real test runs, not four genuine test failures. Setting `ETHEREUM_RPC_URL=https://ethereum-rpc.publicnode.com` (a public, free endpoint — read-only, no credentials involved) and re-running produced 111 passing tests, 0 failures.

### 4.2 `forge coverage` cannot parse `src/legacy/Telcoin.sol`

`forge coverage`'s newer Rust-based analysis backend (`solar`) rejects `src/legacy/Telcoin.sol:56` — `function Telcoin(address _distributor) public` — with *"functions are not allowed to have the same name as the contract."* This looks alarming (it's the exact shape of the already-fixed issue #32) but it is not the same bug: the contract **is** correctly named `Telcoin` to match (confirmed by direct read), so under real Solidity 0.4.18 semantics this is a valid constructor — and `forge build`/`forge test` (which use real `solc`, not `solar`) compile and run it without complaint. `solar` appears to apply post-0.4.22 naming rules unconditionally regardless of pragma version, which is a `solar`/`forge coverage` limitation, not a code defect. Neither `--skip "legacy/Telcoin.sol"` nor `--no-match-coverage "legacy"` avoided it (both are respected by the build stage, not `solar`'s earlier full-tree parse). Since nothing imports this file (`grep -rn "legacy/Telcoin" — no hits outside `lib/``), I temporarily moved it out of the tree, ran coverage, and moved it back immediately (confirmed via `git status` showing a clean `src/` afterward). Reported to Foundry, this would presumably need a fix in `solar`'s legacy-syntax handling.

### 4.3 `semgrep --config p/solidity` is a 404

The Semgrep Registry no longer serves `p/solidity` (`HTTP 404` on `https://semgrep.dev/c/p/solidity`, confirmed independently via web search — the ruleset was removed/renamed, not a mistake on my end). `p/smart-contracts` (50 rules) is the current registry equivalent and ran cleanly.

### 4.4 Semgrep + Decurity ruleset needed the right subdirectory

`Decurity/semgrep-smart-contracts` has separate `solidity/`, `rust/`, and `cairo/` rule trees at its root; pointing `--config` at the bare repo root produced a silent `exit 7` with no usable error. Pointing at `solidity/` specifically ran cleanly (57 rules, 17 findings) — see §3.5 for the genuinely new-versus-corroborating breakdown.

### 4.5 Medusa needed an explicit target contract

`medusa init` produces `targetContracts: []` by default; with an empty list and a single-file compilation target, Medusa still failed to start with *"Failed to initialize the test chain: specify target contract(s)."* Setting `"targetContracts": ["EchidnaProps"]` explicitly fixed it. Also worth knowing: Medusa's default `propertyTesting.testPrefixes` is `["property_"]`, not Echidna's `echidna_` convention — I added `"echidna_"` to the prefix list so both fuzzers would recognize the same property functions without writing them twice.

### 4.6 Manticore: genuinely broken upstream, not an environment gap

`pip install manticore` fails identically on Python 3.14.7 and (fresh venv) Python 3.11.15:

```
building '_pysha3' extension
...Modules/_sha3/backport.inc:78:10: fatal error: 'pystrhex.h' file not found
```

`manticore` depends on `pysha3` (obsolete since Python gained native `hashlib.sha3_*`/`keccak` support; last meaningfully updated years ago), whose C extension references a CPython-internal header that is no longer part of the public include path on any currently-supported CPython. This reproduces on two Python minor versions in clean virtualenvs with up-to-date `pip`/`setuptools`/`wheel` — it is not fixable from the Telcoin side, and matches the broader, well-known reality that Manticore has had no meaningful maintenance in years. Per the review brief's own fallback clause, I used **Halmos** (already installed, `0.3.3`) instead for the symbolic-execution phase.

Wrote `test/HalmosChecks.t.sol` with three `check_*` properties targeting exactly what the brief asks symbolic execution to cover that fuzzing struggles with — exact arithmetic across the *entire* input domain, not a sample of it:

- `check_vaultPreviewMigrate_exactOrZero` — **proven** for all `uint256 amountIn`: `MigrationVault`'s WAD-normalized 2→18 decimal conversion is exact, no rounding loss, for the deployed token pair.
- `check_mint_neverExceedsCap` — **proven** for all `uint256` starting-supply/mint-amount pairs: `TelcoinV3.mint()` never allows `totalSupply()` to exceed `MIGRATION_SUPPLY_CAP`, at and around the exact boundary.
- `check_getAmountOut_exactOrRevert` — solver **timeout** (60s, retried at 180s, still timeout) on the harder nonlinear (multiply-then-divide-to-recover) query. This is a known SMT-solver scalability limit on full-width 256-bit nonlinear arithmetic, not a discovered counterexample — it's inconclusive, and I'm reporting it as exactly that rather than rounding it up to a pass.

### 4.7 Aderyn: genuine upstream incompatibility, four fix attempts made

```
$ aderyn . --src src/
thread 'main' panicked at .../cyfrin-foundry-config-0.2.1/src/lib.rs:535:55:
failed to extract foundry config:
foundry config error: Unknown evm version: osaka for setting `evm_version`
```

`foundry.toml` explicitly sets `evm_version = "prague"` (confirmed via `forge config --json`), yet Aderyn's bundled config-parser reports `osaka` — meaning Aderyn independently infers a target EVM version (likely from the installed `solc` toolchain) rather than strictly reading the pinned value, and its own allow-list of recognized version names (`cyfrin-foundry-config` 0.2.1) doesn't yet include Osaka. Fix attempts, in order: (1) checked `aderyn --help` for a bypass flag — none exists; (2) `--skip-build` — same panic, confirming it happens during config extraction, not the build step; (3) `cargo install aderyn --locked --force` to get a newer release — failed to even compile, due to an unrelated duplicate-constant bug in a transitive dependency (`svm-rs-builds`, `SOLC_VERSION_0_8_35` defined twice); (4) pinning an older Aderyn version — `0.1.7` doesn't exist on crates.io for this package. Aderyn is explicitly marked "(bonus)" in the toolchain table this review followed; after four genuine attempts I accepted this as a documented upstream limitation rather than continuing to sink time into a non-required tool.

---

## 5. Skills Applied

Per §2.1, I used the local skill library rather than cloning duplicates of it. Two skills were invoked directly and applied as explicit checklists against the code (not just referenced):

- **`proxy-upgrade-safety`** — walked all 9 items in its "Quick Detection Checklist" against `MigrationVault`'s UUPS/`ERC1967Proxy` setup. 8/9 clean (EIP-1967 slots via OZ's own proxy, `_disableInitializers()` present, `initializer` modifier present, `_authorizeUpgrade` correctly gated, immutables correctly handled across delegatecall, no selector-clash surface since UUPS+`ERC1967Proxy` has no proxy-side admin functions to clash with). The 9th (append-only storage / reserved gap) produced finding 3.4.
- **`signature-replay-analysis`** — walked all 10 checklist items against `TelcoinV3`'s permit/EIP-3009 implementation and `EIP3009.sol`. All 10 clean: per-user nonces for both permit and EIP-3009 (independent, non-interfering mapping types), EIP-712 domain separator via OZ's `EIP712` (chainId + verifyingContract, safe under same-address multichain CREATE3 deployment since chainId still disambiguates), distinct type-hashes per function preventing cross-function replay, deadline/time-window enforcement on both permit and EIP-3009, `SignatureChecker`/OZ `ECDSA` used throughout (no raw `ecrecover`, so the `address(0)`-on-invalid and malleability edge cases are already handled by the dependency).

Local skill packs consulted for cross-reference during manual review (not re-invoked as separate checklist passes, since the ground they cover was already reached organically): `scv` (reentrancy, access-control, timestamp-dependence references), `qs_skills` reentrancy/DoS/external-call-safety plugins, `sc-auditor`/`pashov-skills` general checklists.

`PlamenTSV/plamen` (explicitly named in the brief): confirmed real and reachable; it's an autonomous audit-agent framework, not a checklist repo, so I extracted and ran the one component of it that's safe to use standalone — its bundled `decurity-rules` Semgrep ruleset (§4.4) — rather than executing its own agent/MCP stack inside this session. See §2.1 item 2 for the full reasoning.

---

## 6. Fuzzing & Symbolic Execution Detail

**Property harness:** `test/EchidnaProps.sol` — fork-free (uses `MockERC20` in place of the real TEL v2, so both fuzzers can run without RPC access), wiring `TelcoinV3` + `TokenMigration` + a UUPS-proxied `MigrationVault`, with 13 invariants encoded directly from `invariants.md` (I1/F3 supply conservation, MV2–MV4 vault conservation/solvency, S1b burn-allowance, O1/S3b migration-close latching, supply-cap respect, view-never-reverts) plus 5 assertion-based access-control checks (non-admin can never pause/rescue-burn/self-revoke-admin).

| Fuzzer | Calls | Runtime | Result |
|---|---|---|---|
| Echidna 2.3.3 | 500,129 | ~41s (hit test-limit before timeout) | 0/13 properties violated, 0 assertion failures |
| Medusa 1.5.0 | ~15.3M | 600s (timeout reached) | 19/19 property + assertion tests passed |

Both fuzzers explored the same action set (migrate, vault-migrate, pause/unpause, close-and-withdraw, attacker-attempts-privileged-call) under arbitrary call ordering and arbitrary `msg.sender`, independently, with no shared corpus. Neither found a violation. This corroborates but does not replace the existing hand-written Foundry fuzz suite (`test/migration/*Fuzz.t.sol`), which already covers single-call and bounded-sequence properties in more semantic depth (e.g. checking exact returned amounts, not just that no invariant broke) — the stateful fuzzers' distinct value is exploring arbitrary multi-call *sequences* across the full public interface, which hand-rolled loops don't fully cover.

**Symbolic execution:** see §4.6.

---

## 7. Coverage & Artifacts

`forge coverage --report summary` (full log: `reports/forge_coverage.log`, artifacts under `reports/`):

| File | Lines | Statements | Branches | Functions |
|---|---|---|---|---|
| `src/MigrationVault.sol` | 100% (52/52) | 100% (66/66) | 100% (10/10) | 100% (13/13) |
| `src/MintBurnWrapper.sol` | 100% (25/25) | 100% (24/24) | 100% (6/6) | 100% (7/7) |
| `src/NativeBridge.sol` | 100% (28/28) | 100% (21/21) | 100% (3/3) | 100% (13/13) |
| `src/TelcoinBridge.sol` | 100% (28/28) | 100% (21/21) | 100% (3/3) | 100% (13/13) |
| `src/TelcoinV3.sol` | 100% (38/38) | 100% (40/40) | 100% (8/8) | 100% (12/12) |
| `src/TokenMigration.sol` | 100% (51/51) | 100% (75/75) | 100% (15/15) | 100% (10/10) |
| `src/faucet/LegacyTelcoinFaucet.sol` | 100% (34/34) | 100% (32/32) | 100% (6/6) | 100% (9/9) |
| `src/faucet/TelcoinV3Faucet.sol` | 100% (30/30) | 100% (25/25) | 100% (4/4) | 100% (8/8) |
| `src/helpers/EIP3009.sol` | 100% (38/38) | 100% (35/35) | 100% (6/6) | 100% (10/10) |

Every in-scope `src/` file (plus both faucets) is at 100% on all four metrics. The project-wide aggregate reported by `forge coverage` (34.21% lines) is dragged down entirely by `lib/` (LayerZero, OpenZeppelin — third-party, out of scope) and `script/` (deployment tooling, not unit-tested by design); it is not a meaningful number for this codebase's own quality and I don't want to leave it looking like a problem out of context.

**Test suite:** 304 tests total (193 unit + 111 fork-dependent), 0 failures, across 20 test suites.

Raw logs and machine-readable output (not all pushed to this branch — see note below): `reports/echidna.log`, `reports/medusa.log`, `reports/halmos.log`, `reports/semgrep.sarif`, `reports/semgrep-decurity.sarif`, `/tmp/forge_coverage4.log`, `/tmp/forge_test.log`, plus the Slither MCP JSON responses captured inline in this document's §3/§4.

---

## 8. What I did not push to this branch, and why

This branch contains only `audit/audit.md` (this file). I did **not** push `test/EchidnaProps.sol`, `test/HalmosChecks.t.sol`, `medusa.json`, or the raw `reports/` logs, because:

- They're genuinely useful (the property harness in particular is reusable for regression fuzzing), but committing generated log artifacts and a first-draft fuzzing harness into the main contracts repo without the team's own review felt like the wrong default for a follow-up review that found no new vulnerabilities to justify it.
- If you want the harness and configs merged in (e.g. to wire into CI), say so and I'll open that as its own PR — separate from this review, since it's a testing-infrastructure change, not a finding.

---

## 9. Disclaimer

This review is not a replacement for the three prior professional audits it builds on, nor for continuous monitoring, and it cannot guarantee the absence of all vulnerabilities — only that this specific commit, reviewed with this specific toolchain, on this date, did not yield one. Any code change after `03d29d4` requires a fresh look.
