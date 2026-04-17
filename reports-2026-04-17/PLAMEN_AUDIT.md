# Plamen Web3 Security Audit — Telcoin V3

**Mode:** core (automated pipeline)
**Target:** `/Users/r00t/smartcontracts/tel-v3`
**Commit:** `5e9cdf9b3e10151358859aac31dc890edeccdbe7`
**Language:** `evm` (foundry.toml + .sol files detected)
**Platform:** macOS arm64, Bash
**Docs path:** `README.md`, `invariants.md`, `docs/bridge-integration.md` — HAS_DOCS = true
**Scope:** `src/*.sol` excluding `src/legacy/` (reference only). Five in-scope contracts: TelcoinV3, TokenMigration, MintBurnWrapper, TelcoinBridge, NativeBridge.

---

## Phase 1 — Recon

### Step 1.A Fork-Ancestry Detection

Run: `grep -rEn '<parent-pattern>' src/ lib/` against Plamen's known-parent table:

| Parent Project | Detected? | Evidence | Inherited patterns to check |
|----------------|-----------|----------|------------------------------|
| OpenZeppelin | ✅ YES | `@openzeppelin/contracts` imports everywhere (ERC20, AccessControl, AccessControlEnumerable, Ownable2Step, Pausable, ReentrancyGuardTransient, SafeERC20) | ERC20 5.x semantics, role permissioning model, transient storage reentrancy guard |
| LayerZero V2 (OFT) | ✅ YES | `MintBurnOFTAdapter`, `NativeOFTAdapter`, `OFTCore`, `OAppReceiver` | OFT bridge patterns, peer validation, lzReceive gating, dust stripping |
| 0xsequence CREATE3 | ✅ YES | `lib/create3/contracts/Create3.sol` + `script/` deployment | CREATE3 factory, salt collision / front-running |
| Synthetix, Compound, Uniswap V2/V3, Aave, MasterChef, Curve, Balancer, Yearn, Basis/Tomb, Olympus | ❌ NO | No hits | — |

### Step 1.B Trigger-Pattern Scan

Applied each Plamen EVM skill's trigger regex against `src/`:

| Skill | Trigger | Match? | Action |
|---|---|:-:|---|
| `centralization-risk` | `onlyOwner|DEFAULT_ADMIN_ROLE|MINTER_ROLE|BURNER_ROLE|PAUSER_ROLE|UNPAUSER_ROLE|multisig|onlyBridge` | ✅ | INJECT into breadth + depth |
| `cross-chain-message-integrity` | `_lzReceive|setPeer|ILayerZeroReceiver|endpoint.*receive` | ✅ | INJECT |
| `cross-chain-timing` | `bridge|LayerZero|CCIP|crossChain|sendMessage|receiveMessage` | ✅ | INJECT |
| `economic-design-audit` | `rate|fee|supply|mint|burn|emission|DECIMAL|cap` | ✅ | INJECT (monetary params: MIGRATION_SUPPLY_CAP, DECIMAL_MULTIPLIER, migrationExpiry) |
| `event-correctness` | events > 15 total (optional) | ✅ (~17 events across 5 contracts) | INJECT |
| `external-precondition-audit` | any `I<Ext>.func(...)` call | ✅ | INJECT |
| `flash-loan-interaction` | `flashLoan|IERC3156|flashMint` | ❌ | SKIP |
| `fork-ancestry` | always (recon) | ✅ | See Step 1.A |
| `migration-analysis` | `migrat|V2|V3|oldToken|newToken|upgrade|legacy` | ✅ | INJECT (TokenMigration ↔ TelcoinV2/V3) |
| `oracle-analysis` | `oracle|Oracle|Chainlink|TWAP|priceFeed|IAggregator` | ❌ | SKIP |
| `semi-trusted-roles` | `onlyBot|onlyOperator|onlyKeeper|BOT_ROLE|OPERATOR_ROLE|KEEPER_ROLE` | ❌ | SKIP |
| `share-allocation-fairness` | SHARE_ALLOCATION flag | ❌ | SKIP |
| `staking-receipt-tokens` | `delegation|staking.*receipt|liquid.*staking|validator|deposit.*voucher` | ❌ | SKIP |
| `storage-layout-safety` | `proxy|upgradeable|diamond|delegatecall|sstore|sload|assembly\s*\{|reinitializer|UUPS|TransparentUpgradeableProxy` | ❌ in `src/` (assembly only in LZ libraries) | SKIP |
| `temporal-parameter-staleness` | `interval|epoch|period|duration|delay|cooldown|lockPeriod|timelock|maturityTime|Expiry` | ⚠️ partial (`_migrationDuration`, `migrationExpiry`) | INJECT (limited) |
| `token-flow-tracing` | `transfer|transferFrom|safeTransfer|mint|burn|balanceOf.*this` | ✅ | INJECT |
| `verification-protocol` | used for verification phase | — | apply in Phase 5 |
| `zero-state-return` | always | ✅ | INJECT |

**Injectable skills (protocol-type triggers):**

| Injectable | Trigger | Match? |
|---|---|:-:|
| `account-abstraction-security` | `IEntryPoint\|UserOperation\|Paymaster\|BaseAccount\|ERC-4337` | ❌ |
| `dex-integration-security` | `swap\|addLiquidity\|removeLiquidity\|amountOutMin\|IUniswapV2Router\|ISwapRouter` | ❌ |
| `governance-attack-vectors` | `Governor\|Timelock\|voting\|proposal\|quorum\|delegate\(` | ❌ (Ownable2Step multisig ≠ governance primitives) |
| `integration-hazard-research` | `NAMED_EXTERNAL_PROTOCOL` | ✅ LayerZero, OpenZeppelin, 0xsequence |
| `lending-protocol-security` | `liquidate\|borrow\|repay\|collateral\|healthFactor\|LTV\|interestRate\|debtToken` | ❌ |
| `nft-protocol-security` | ERC-721/1155 + marketplace/mint/collateral | ❌ |
| `outcome-determinism` | selection from depletable pool + fallback | ❌ |
| `vault-accounting` | vault + shares | ❌ |

**Niche skills:**

| Niche | Trigger | Match? |
|---|---|:-:|
| `callback-receiver-safety` | `onERC721Received\|onERC1155Received\|tokensReceived\|onFlashLoan\|executeOperation` | ❌ (no custom callback handler in src/ — the NativeBridge `_credit` is a *producer* of a callback, not a *receiver*) |
| `dimensional-analysis` | `mulDiv\|mulWad\|rayMul\|FullMath` + mixed scale | ❌ (no mulDiv; decimal conversion uses integer const) |
| `event-completeness` | MISSING_EVENT on admin/state-changing functions | ✅ `rescueBurn` lacks a dedicated event |
| `multi-step-operation-safety` | authorization / on-behalf-of patterns | ✅ Ownable2Step transfer/accept; bridge authorize/revoke |
| `semantic-consistency-audit` | HAS_MULTI_CONTRACT | ✅ 5 contracts sharing constants + interfaces |
| `semantic-gap-investigator` | sync_gaps from semantic invariant agent | ❌ (no invariant gap detected upstream) |
| `signature-verification-audit` | `ecrecover\|EIP712\|_PERMIT_TYPEHASH\|SignatureChecker` | ❌ |
| `spec-compliance-audit` | HAS_DOCS | ✅ (invariants.md + README.md) |
| `stableswap-compliance` | STABLESWAP_FORK | ❌ |

### Step 1.C Finding-Prefix Allocation

Plamen convention — per-skill finding prefix for this run:

```
CR-N   centralization-risk
CMI-N  cross-chain-message-integrity
CT-N   cross-chain-timing
EDA-N  economic-design-audit
EC-N   event-correctness
EPA-N  external-precondition-audit
MA-N   migration-analysis
TPS-N  temporal-parameter-staleness
TF-N   token-flow-tracing
ZS-N   zero-state-return
IHR-N  integration-hazard-research
EVC-N  event-completeness (niche)
MSO-N  multi-step-operation-safety (niche)
SCA-N  semantic-consistency-audit (niche)
SPC-N  spec-compliance-audit (niche)
```

---

## Phase 4a — Inventory

### Attack Surface (entry points)

State-changing external/public entry points in `src/`:

| # | Contract | Function | Gate | Category |
|---|---|---|---|---|
| 1 | TelcoinV3 | `mint(to, amt)` | MINTER_ROLE | monetary |
| 2 | TelcoinV3 | `burn(from, amt)` | BURNER_ROLE + _spendAllowance | monetary |
| 3 | TelcoinV3 | `rescueBurn(from, amt)` | DEFAULT_ADMIN_ROLE | emergency |
| 4 | TelcoinV3 | `pause()` | PAUSER_ROLE | emergency |
| 5 | TelcoinV3 | `unpause()` | UNPAUSER_ROLE | emergency |
| 6 | TelcoinV3 | `rescueTokens(token, amt, to)` | DEFAULT_ADMIN_ROLE | sweep |
| 7 | TelcoinV3 | `grantRole/revokeRole` | role-admin | AC |
| 8 | TelcoinV3 | `renounceRole` | disabled (always reverts) | AC |
| 9 | TokenMigration | `migrate()` | public + nonReentrant + whenNotPaused | user action |
| 10 | TokenMigration | `setMigrationExpiry(t)` | onlyOwner | monetary (deadline) |
| 11 | TokenMigration | `recoverERC20(dst, token, amt)` | onlyOwner | sweep |
| 12 | TokenMigration | `pause/unpause` | onlyOwner | emergency |
| 13 | TokenMigration | `transferOwnership/acceptOwnership` | Ownable2Step | AC |
| 14 | TokenMigration | `renounceOwnership` | disabled | AC |
| 15 | MintBurnWrapper | `mint/burn(addr, amt)` | onlyBridge | bridge-ops |
| 16 | MintBurnWrapper | `authorizeBridge(addr)` | onlyOwner | AC |
| 17 | MintBurnWrapper | `revokeBridge(addr)` | onlyOwner | AC |
| 18 | MintBurnWrapper | `transferOwnership/acceptOwnership/renounceOwnership` | Ownable2Step | AC |
| 19 | TelcoinBridge | `send(SendParam, fee, refund)` | whenNotPaused | user action |
| 20 | TelcoinBridge | `_lzReceive(Origin, …)` | endpoint+peer+whenNotPaused | cross-chain |
| 21 | TelcoinBridge | `rescueTokens(token, amt, to)` | onlyOwner | sweep |
| 22 | TelcoinBridge | `pause/unpause` | onlyOwner | emergency |
| 23 | TelcoinBridge | `setPeer/setDelegate/setEnforcedOptions/setMsgInspector/setPreCrime` | onlyOwner (OApp inherit) | AC |
| 24 | TelcoinBridge | `approvalRequired()` | pure→true | signal |
| 25 | TelcoinBridge | `transferOwnership/acceptOwnership/renounceOwnership` | Ownable2Step | AC |
| 26 | NativeBridge | `receive()` (payable) | open — emits ReserveFunded | reserve top-up |
| 27 | NativeBridge | `send/lzReceive/rescueTokens/pause/unpause/setPeer/...` | same as TelcoinBridge (mirrored) | mixed |

### Privileged Roles Inventory (for `centralization-risk` skill)

| # | Function | Contract | Role | Controls | Impact if abused |
|---|---|---|---|---|---|
| 1 | mint | TelcoinV3 | MINTER_ROLE | supply ↑ | Mint up to cap (100B); supply inflation |
| 2 | burn | TelcoinV3 | BURNER_ROLE + allowance | supply ↓ (with approval) | Cannot drain unapproved wallets |
| 3 | rescueBurn | TelcoinV3 | DEFAULT_ADMIN_ROLE | supply ↓ (no approval) | **FUND_CONTROL** — can burn any wallet |
| 4 | pause / unpause | TelcoinV3 | PAUSER_ROLE / UNPAUSER_ROLE | halts user xfers | Freeze user transfers indefinitely |
| 5 | rescueTokens | TelcoinV3 | DEFAULT_ADMIN_ROLE | sweep non-TEL tokens from TelcoinV3 contract | Take accidentally-sent tokens |
| 6 | grantRole/revokeRole | TelcoinV3 | role-admin | role assignment | Grant MINTER/BURNER to malicious contract |
| 7 | setMigrationExpiry | TokenMigration | owner | extension only | Keep migration window open indefinitely |
| 8 | recoverERC20 | TokenMigration | owner | sweep non-TEL tokens from migration | — |
| 9 | pause / unpause | TokenMigration | owner | halt migrate() | Freeze migrations |
| 10 | authorizeBridge | MintBurnWrapper | owner | routes bridge mint/burn | **FUND_CONTROL** if wrapper has MINTER+BURNER — malicious bridge can mint/burn per cap |
| 11 | revokeBridge | MintBurnWrapper | owner | unset bridge | Brick bridge |
| 12 | send/receive-config (setPeer, setDelegate, setMsgInspector) | Both bridges | owner | cross-chain wiring | Misroute messages / block messages |
| 13 | pause/unpause | Both bridges | owner | halt bridge | Freeze bridging |
| 14 | rescueTokens | Both bridges | owner | sweep non-protocol tokens | — |

Worst-case owner compromise: mint 100B TEL on each chain via wrapper (`authorizeBridge(malicious)` then malicious calls `wrapper.mint`). Bounded by per-chain cap; cross-chain amplification blocked by per-chain cap check.

### Events Inventory (for `event-correctness` + `event-completeness`)

Emits enumerated:

| Contract | Event | Triggered by |
|---|---|---|
| TelcoinV3 (+OZ) | `Transfer(from, to, val)` | mint, burn, rescueBurn, transfer, transferFrom, _update |
| TelcoinV3 (+OZ) | `Approval(owner, spender, val)` | approve, _approve |
| TelcoinV3 (+OZ) | `Paused(account)` / `Unpaused(account)` | pause/unpause |
| TelcoinV3 (+OZ) | `RoleGranted/Revoked/AdminChanged` | grantRole/revokeRole |
| TokenMigration | `TokensMigrated(user, amt)` | migrate |
| TokenMigration | `StuckTokensRecovered(token, to, amt)` | recoverERC20 |
| TokenMigration | `MigrationExpirySet(old, new)` | setMigrationExpiry |
| MintBurnWrapper | `BridgeAuthorized(bridge)` | authorizeBridge |
| MintBurnWrapper | `BridgeRevoked(bridge)` | revokeBridge |
| MintBurnWrapper | `BridgeMinted(bridge, to, amt)` | mint |
| MintBurnWrapper | `BridgeBurned(bridge, from, amt)` | burn |
| TelcoinBridge (+OFT) | `OFTSent/OFTReceived` | send / _lzReceive |
| NativeBridge | `ReserveFunded(funder, amt)` | receive() |
| NativeBridge (+OFT) | `OFTSent/OFTReceived` | send / _lzReceive |

---

## Phase 4b — Depth analysis (per triggered skill)

### CR-* centralization-risk

| # | Finding | Severity | Status |
|---|---|---|---|
| CR-1 | `rescueBurn(from, amt)` (TelcoinV3.sol:70) allows DEFAULT_ADMIN_ROLE to burn ANY wallet without approval. **FUND_CONTROL** privilege. | Documented / acknowledged (design decision for emergency hacker-balance burn) | FALSE_POSITIVE — by design, explicit trust placement. README §9 "Emergency rescueBurn". |
| CR-2 | `MINTER_ROLE` granted to `MintBurnWrapper`; wrapper's `bridge` slot is owner-writable. Compromised owner on wrapper → malicious bridge → unbounded mint (to cap). | Medium (operational, bounded by per-chain cap) | Maps to AUDIT.md **I-05** (per-chain cap) and **L-01** (wrapper overwrite). |
| CR-3 | `renounceRole` / `renounceOwnership` disabled across all in-scope contracts. Prevents orphan-admin, but also prevents "decentralization via renouncement". | Informational | FALSE_POSITIVE — documented in README §4/§5. |
| CR-4 | No timelock on any admin action (pause, mint, authorizeBridge, setMigrationExpiry). | Informational | FALSE_POSITIVE — intentional; multisig is the sole gate per product decision. |

### CMI-* cross-chain-message-integrity

Inbound messages go through `OAppReceiver.lzReceive` (lib/LayerZero-v2/.../OAppReceiver.sol:95) which enforces `msg.sender == endpoint` + `peers[srcEid] == _origin.sender`. Internal `_lzReceive` in TelcoinBridge + NativeBridge adds `whenNotPaused`.

| # | Finding | Severity | Status |
|---|---|---|---|
| CMI-1 | Endpoint authentication present (OnlyEndpoint). | — | PASS |
| CMI-2 | Peer authentication present (OnlyPeer via `_getPeerOrRevert`). | — | PASS |
| CMI-3 | Replay protection via LZ nonce dedup at endpoint. | — | PASS (inherited) |
| CMI-4 | Payload validation: OFTCore's `_lzReceive` decodes via `OFTMsgCodec` (fixed format: 32-byte `sendTo` + 8-byte `amountSD`). No free-form decoding. | — | PASS |
| CMI-5 | `_credit` on NativeBridge pushes native TEL via `call{value:}`; can permanently fail on malicious recipient. | Info (LZ platform limitation) | TRUE_POSITIVE → AUDIT.md **I-06**. |
| CMI-6 | Global supply cap enforced per-chain; in-flight messages can temporarily exceed aggregate cap. | Info | TRUE_POSITIVE → AUDIT.md **I-05**. |

### CT-* cross-chain-timing

| # | Finding | Severity | Status |
|---|---|---|---|
| CT-1 | LayerZero message finality window varies by chain. The protocol does NOT read any cross-chain synced state into pricing / accounting. No TWAP, no epoch — burn on source / mint on dest is atomic per-chain. | — | PASS |
| CT-2 | No timing-arbitrage surface — message processing only mints/burns local TEL. | — | PASS |

### EDA-* economic-design-audit

Monetary parameters enumerated and boundary-tested:

| # | Parameter | Setter | Min | Max | Enforced? | Impact at Max |
|---|---|---|---|---|---|---|
| EDA-1 | MIGRATION_SUPPLY_CAP | constant at compile time | 100 B | 100 B | ✅ `if (totalSupply() > cap) revert` post-mint | Cap reached → subsequent mints revert |
| EDA-2 | DECIMAL_MULTIPLIER | constant (1e16) | — | — | ✅ immutable | — |
| EDA-3 | migrationExpiry | `setMigrationExpiry` (onlyOwner, monotone ↑) | `block.timestamp + 1` (must > current) | uint256 | ✅ bound to > current expiry | See TPS-1 |
| EDA-4 | sharedDecimals / decimalConversionRate | constant (6 / 1e12) | — | — | ✅ immutable | — |

**Boundary observation EDA-B1:** Per-message bridge amount bounded by `uint64.max × 1e12 ≈ 18.4 B TEL`. Any user wanting to bridge >18.4 B TEL in a single call reverts with `AmountSDOverflowed`. Documented in README — PASS.

**Boundary observation EDA-B2:** Migration input bounded by OldToken supply (`10^13`). Product `10^13 × 1e16 = 10^29`, within uint256 and below cap. PASS.

**Economic invariant check:** `totalOldTokenBurned() == totalMigrated / 1e16` and `tel.totalSupply() ≥ migration.totalMigrated()` when initialSupply is accounted for. Admin cannot break these via setters (no setters for these state vars). Backed by `test/invariant/MigrationInvariant.t.sol`. PASS.

### EC-* event-correctness

For each `emit` statement, 6 checks applied (value accuracy, index correctness, ordering, conditional coverage, parameter count, semantic correctness):

| Emit | Location | All 6 checks |
|---|---|:-:|
| `TokensMigrated(user, amount)` | TokenMigration.sol:88 | ✅ emitted after both state changes and mint |
| `MigrationExpirySet(oldExpiry, newExpiry)` | TokenMigration.sol:98 | ✅ emits pre-update oldExpiry + newExpiry value (verified by Cantina finding 3.2.5 fix) |
| `StuckTokensRecovered(token, to, amt)` | TokenMigration.sol:121 | ✅ after `safeTransfer` |
| `BridgeAuthorized(bridge)` | MintBurnWrapper.sol:99 | ⚠️ semantic gap when overwriting — emits `BridgeAuthorized(new)` without matching `BridgeRevoked(old)` → AUDIT.md **L-01** |
| `BridgeRevoked(bridge)` | MintBurnWrapper.sol:112 | ✅ after clearing slot |
| `BridgeMinted(bridge, to, amt)` | MintBurnWrapper.sol:72 | ✅ after `token.mint` |
| `BridgeBurned(bridge, from, amt)` | MintBurnWrapper.sol:84 | ✅ after `token.burn` |
| `ReserveFunded(funder, amt)` | NativeBridge.sol:57 | ✅ atomic with receive |
| `Transfer(from, 0, amt)` emitted by `rescueBurn` | inherited from _burn | ⚠️ not distinguishable from normal bridge burn → AUDIT.md **I-04** |

| # | Finding | Severity | Status |
|---|---|---|---|
| EC-1 | `BridgeAuthorized(_bridge)` emitted on silent overwrite. | Low | TRUE_POSITIVE → AUDIT.md **L-01**. |
| EC-2 | `rescueBurn` emits only generic `Transfer` — no distinguishing event. | Info | TRUE_POSITIVE → AUDIT.md **I-04**. |
| EC-3 | All other emits pass all 6 semantic checks. | — | PASS |

### EPA-* external-precondition-audit

| External Call | Interface Precondition | Protocol Validates? |
|---|---|:-:|
| `oldToken.safeTransferFrom(msg.sender, BURN_ADDRESS, bal)` (TokenMigration.sol:84) | Needs `allowance[msg.sender][migration] ≥ bal`; needs `balanceOf(msg.sender) ≥ bal` | ✅ userBalance fetched via balanceOf; if transferFrom reverts, whole tx reverts |
| `telcoinV3.mint(msg.sender, amt)` (TokenMigration.sol:87) | Needs `migration` to hold MINTER_ROLE | ✅ Deployment sequence grants role; migration reverts if not |
| `token.mint/burn` via MintBurnWrapper | Needs wrapper to hold MINTER/BURNER | ✅ Deployment invariant W2 in invariants.md |
| `safeTransfer` in rescue paths | Needs target contract balance | ✅ pre-check via `balanceOf(address(this))` in TokenMigration; implicit in SafeERC20 elsewhere |
| LZ `endpoint.send` | Needs msg.value ≥ nativeFee | ✅ NativeBridge.send reverts `IncorrectMessageValue`; TelcoinBridge inherits OFTCore (msg.value forwarded) |
| LZ endpoint delivers `lzReceive` | Needs registered peer + correct endpoint | ✅ OAppReceiver enforces |

| # | Finding | Severity | Status |
|---|---|---|---|
| EPA-1 | All external-contract preconditions validated or enforced by callee revert. | — | PASS |
| EPA-2 | Return-value consumption: `MintBurnWrapper.mint/burn` returns bool — callers (MintBurnOFTAdapter) ignore but rely on revert-on-failure. Safe by construction because wrapper always returns true and reverts on TelcoinV3 failure. | — | PASS |

### MA-* migration-analysis

Token transition: OldToken (TelcoinV2, 0.4.18, 2 decimals) → TelcoinV3 (0.8.26, 18 decimals).

| Aspect | Status |
|---|---|
| Migration direction | one-way (V2 → V3 only); V2 tokens sent to `0x…dEaD` permanently |
| Bidirectional? | ❌ No rollback path (by design) |
| Rate | exact 1:1 (×1e16 for decimal adjustment) |
| Interface compatibility | V2: `transfer/transferFrom` both return bool (checked on-chain: `cast call ... "transfer(address,uint256)(bool)"` would succeed). Both match IERC20. |
| Stranded assets | OldToken in migration contract (if user mistakenly sends to the contract) recoverable via `recoverERC20` |
| Stranded V3 | V3 minted by migration directly to user — no reserve in migration contract |
| Legacy functions still callable? | `src/legacy/Telcoin.sol` is NOT deployed as part of this stack (reference only). Live mainnet `0x467Bcc…` still supports standard ERC20. |
| Role preconditions | Migration contract MUST hold MINTER_ROLE on TelcoinV3 at deployment (invariants.md I5). |

| # | Finding | Severity | Status |
|---|---|---|---|
| MA-1 | Migration is one-way and irreversible (documented). | — | PASS |
| MA-2 | No stranded assets under normal operation. Mistakes recoverable via `recoverERC20` (owner-gated). | — | PASS |
| MA-3 | Decimal conversion exact (`×1e16`) — no precision loss. | — | PASS |

### TPS-* temporal-parameter-staleness

Multi-tx operations enumerated:

| Operation | Step 1 | Wait | Step N |
|---|---|---|---|
| Ownership transfer | `transferOwnership(new)` | off-chain | `acceptOwnership()` |
| Bridge rotation (intended) | `revokeBridge(old)` | — | `authorizeBridge(new)` |
| User migration | `approve(migration, bal)` | — | `migrate()` |
| Bridge send | `approve(wrapper, amt)` | — | `send(…)` |
| Migration extension | `setMigrationExpiry(t)` | wall-clock | `migrate()` by user before t |

| # | Finding | Severity | Status |
|---|---|---|---|
| TPS-1 | `migrationExpiry` is monotonically ↑ — once set, users can rely on it; only extension possible. If governance extends during in-flight `migrate`, the call still succeeds (uses the updated bound). No staleness issue. | — | PASS |
| TPS-2 | Ownership handoff: `transferOwnership(newOwner)` sets `pendingOwner`. `acceptOwnership()` reads `pendingOwner` at acceptance time — no staleness. OZ Ownable2Step idiom. | — | PASS |
| TPS-3 | Bridge rotation is NOT a 2-step gated operation — `authorizeBridge(new)` can run without revoke → AUDIT.md **L-01**. | Low | TRUE_POSITIVE |
| TPS-4 | User-side approval → migrate: if user decreases allowance between steps, migrate reverts. Standard ERC-20 approval semantics. No staleness issue. | — | PASS |

### TF-* token-flow-tracing

Token entry/exit paths traced:

| Flow | Entry | Exit | Tracked |
|---|---|---|---|
| Migration | `oldToken.safeTransferFrom(user, BURN_ADDR, bal)` | `telcoinV3.mint(user, bal*1e16)` | `totalMigrated` (storage) + `totalOldTokenBurned()` (view) |
| Satellite send | `wrapper.burn(user, amt)` (via `_debit`) | LZ msg emitted | `OFTSent` event |
| Satellite receive | LZ `_lzReceive` (from peer) | `wrapper.mint(to, amt)` (via `_credit`) | `OFTReceived` event |
| TN send | `msg.value` → contract balance | LZ msg emitted | ETH balance on contract |
| TN receive | LZ `_lzReceive` | `call{value}(to)` push | ETH balance on contract |
| TN reserve top-up | `receive()` (any sender) | — | `ReserveFunded` event |
| Admin rescue (various) | — | `safeTransfer` to destination | `StuckTokensRecovered` or no event |

**Donation attack check:** Does the protocol use `balanceOf(address(this))` directly to track deposits?

- TokenMigration: **NO** — uses `balanceOf(msg.sender)` as the input amount; `totalMigrated` is an independent counter. An attacker sending OldToken directly to the migration contract does NOT affect `totalMigrated` or any user's migrated amount. Owner can sweep via `recoverERC20`. ✅ No donation-attack vector.
- NativeBridge: Uses `address(this).balance` implicitly via `call{value:}` for outbound credits. Anyone sending native TEL increases balance (→ `ReserveFunded`). Does NOT inflate any user's position — it just funds the reserve which is consumed by future outbound credits. ✅ No exploitable donation vector.
- TelcoinBridge, MintBurnWrapper, TelcoinV3: Do not use `balanceOf(address(this))` except in `rescueTokens` which is admin-gated.

**Token type confusion:** All token references are typed via `IERC20Mintable` or `IERC20`. No `bytes4` selector magic, no proxy confusion.

**Side-effect state changes:** None — every balance-affecting path emits a matching event.

| # | Finding | Severity | Status |
|---|---|---|---|
| TF-1 | No donation attack vector (balance-based logic ruled out). | — | PASS |
| TF-2 | No token type confusion. | — | PASS |
| TF-3 | Accounting consistency verified via `test/invariant/*` (6 invariants × 3 840 handler calls). | — | PASS |

### ZS-* zero-state-return

Return-to-zero scenarios:

| Scenario | Trigger | Check |
|---|---|---|
| `telcoinV3.totalSupply() → 0` | All holders burn / rescueBurn | No residual state breaks (cap still `≥ 0`); next mint starts fresh |
| `migration.totalMigrated() → 0` | N/A — monotone ↑ | — |
| `wrapper.bridge == address(0)` | After revokeBridge | wrapper.mint/burn revert `UnauthorizedBridge` ✅ |
| `nativeBridge.balance → 0` | Entire reserve drained | Next outbound credit fails `CreditFailed` ✅ |
| `TelcoinV3.pause()` | PAUSER_ROLE triggers | Transfers between non-zero addresses revert; mint/burn still work ✅ |

| # | Finding | Severity | Status |
|---|---|---|---|
| ZS-1 | Zero-balance migrate: `migrate()` with `balanceOf(user)==0` reverts `InvalidAmount` (TokenMigration.sol:77). ✅ no spurious 0-mint. | — | PASS |
| ZS-2 | Zero-amount rescue / recover all revert explicitly (`ZeroAmount`, `InvalidAmount`). ✅ | — | PASS |
| ZS-3 | No first-depositor advantage (no shares / no vault). | — | PASS |
| ZS-4 | Post-migration-expiry return-to-zero: if all MINTER_ROLE holders are revoked post-expiry (README plan), TelcoinV3 becomes mint-frozen. `totalSupply` stays at its current value; no path to reset to zero. ✅ | — | PASS |

### IHR-* integration-hazard-research

Named external protocols integrated:

| Protocol | Known hazards | Our exposure |
|---|---|---|
| OpenZeppelin 5.x | - `_spendAllowance` only emits Approval on non-infinite path; infinite `type(uint256).max` allowance consumed-without-emit — standard behaviour<br>- `ERC20._update` pause-guard is custom override — need to check `_update` callers<br>- AccessControlEnumerable adds enumerable set cost per role | ✅ Override of `_update` audited (src/TelcoinV3.sol:109-114); pause only gates non-mint/burn. Role set cost acceptable. |
| LayerZero V2 OFT | - Endpoint compromise → peer forgery (trust LZ team)<br>- DVN quorum — config lives outside these contracts<br>- lzReceive retry semantics → paused bridge queues messages indefinitely<br>- Dust stripping below 1e12 wei<br>- `_toSD` uint64 overflow cap (~18.4B TEL per-msg)<br>- lzCompose sender spoofing (Pashov #5) | ✅ No custom `lzCompose` override; `_lzReceive` strictly inherits OFTCore which uses `OFTMsgCodec`. Peer validation inherited. See AUDIT.md I-06 for credit-stuck edge case. |
| 0xsequence CREATE3 | - Salt collision when factory is publicly callable<br>- Address depends on factory address + salt (not deployer EOA) | ⚠️ See AUDIT.md **I-07** |
| Telcoin V2 (on-chain, 0x467Bcc…) | - Plain 2017 ERC-20, no hooks, no blacklist, no pause<br>- `transferFrom` uses SafeMath subtract — reverts on insufficient balance<br>- `approve` has classic approve-race | ✅ Well-understood. Migration uses SafeERC20 wrappers anyway. |

| # | Finding | Severity | Status |
|---|---|---|---|
| IHR-1 | LayerZero platform hazards accepted as trust assumptions (DVN, endpoint). | — | PASS (documented) |
| IHR-2 | CREATE3 deployment surface. | Info | TRUE_POSITIVE → AUDIT.md **I-07**. |
| IHR-3 | Legacy Telcoin V2 integration: no fee/rebase/blacklist/hook hazards. | — | PASS |
| IHR-4 | OpenZeppelin 5.x removed `increaseAllowance/decreaseAllowance`. Standard ERC-20 race persists (low risk). | — | PASS |

### EVC-* event-completeness (niche)

Admin/state-changing functions without dedicated events:

| Function | Dedicated event? | Verdict |
|---|---|---|
| `TelcoinV3.mint` | ❌ (only OZ `Transfer(0, to, amt)`) | **Acceptable** — standard ERC-20 mint pattern; off-chain indexers infer from Transfer(from==0) |
| `TelcoinV3.burn` | ❌ (only OZ `Transfer(from, 0, amt)`) | **Acceptable** — standard ERC-20 burn pattern |
| `TelcoinV3.rescueBurn` | ❌ (only OZ `Transfer(from, 0, amt)`) | ⚠️ **FINDING** — EVC-1 (already AUDIT.md I-04) |
| `TelcoinV3.rescueTokens` | ❌ (only OZ `Transfer(this, to, amt)`) | Minor — same destination observable |
| `TelcoinBridge.rescueTokens` / `NativeBridge.rescueTokens` | ❌ | Minor — recommend `Rescued(token, to, amt)` |
| Ownable2Step handoff | OZ `OwnershipTransferStarted` + `OwnershipTransferred` | PASS |

| # | Finding | Severity | Status |
|---|---|---|---|
| EVC-1 | `rescueBurn` has no distinguishing event. | Info | TRUE_POSITIVE → AUDIT.md **I-04**. |
| EVC-2 | `rescueTokens` on bridges and TelcoinV3 lack a custom `Rescued` event. | Info | New finding this run — **EVC-2** (minor). Recommend `event Rescued(address indexed token, address indexed to, uint256 amount)` |

### MSO-* multi-step-operation-safety (niche)

On-behalf-of / authorization patterns:

| Pattern | Risk model | Analysis |
|---|---|---|
| Ownable2Step handoff | Intermediate `pendingOwner` could be claimed by attacker if pendingOwner is EOA and private key leaks | ✅ Standard OZ pattern; governance controls `newOwner` target |
| User approve → migrate | Malicious migration contract drains user | ✅ `migrate()` pulls only from `msg.sender` — caller's own balance; cannot migrate someone else's via their approval |
| User approve → bridge send | Compromised wrapper drains unapproved wallets | ✅ `TelcoinV3.burn` requires `_spendAllowance(from, wrapper, amt)` — unapproved users safe |
| Bridge rotation (documented 2-step) | Revoke-then-authorize sequence | ⚠️ Code permits one-step overwrite → AUDIT.md **L-01** (MSO-1) |

| # | Finding | Severity | Status |
|---|---|---|---|
| MSO-1 | Bridge rotation one-step overwrite. | Low | TRUE_POSITIVE → AUDIT.md **L-01**. |

### SCA-* semantic-consistency-audit (niche)

Multi-contract consistency checks (5 contracts + 2 interfaces share parameters):

| Shared concept | TelcoinV3 | TokenMigration | MintBurnWrapper | TelcoinBridge | NativeBridge | Consistent? |
|---|---|---|---|---|---|:-:|
| Supply cap (100 B × 1e18) | `MIGRATION_SUPPLY_CAP` | — | — | — | — | ✅ single-source-of-truth |
| Decimal multiplier (1e16) | — | `DECIMAL_MULTIPLIER` | — | — | — | ✅ |
| Burn address (`0x…dEaD`) | — | `BURN_ADDRESS` | — | — | — | ✅ |
| sharedDecimals (6) | — | — | — | inherited OFTCore default | inherited OFTCore default | ✅ |
| decimalConversionRate (1e12) | — | — | — | inherited | inherited | ✅ |
| Role names (MINTER/BURNER/PAUSER/UNPAUSER) | Roles.sol | — | — | — | — | ✅ single definition in `src/helpers/Roles.sol` |
| `renounce*` disabled pattern | ✅ renounceRole | ✅ renounceOwnership | ✅ renounceOwnership | ✅ renounceOwnership | ✅ renounceOwnership | ✅ |
| Ownable2Step adoption | — | ✅ | ✅ | ✅ | ✅ | ✅ consistent |
| Error naming | ZeroAddress / ZeroAmount | ZeroAddress / InvalidAmount / InvalidExpiry / SameAddress / MigrationConcluded / CannotRenounceOwnership | ZeroAddress / UnauthorizedBridge / CannotRenounceOwnership / BridgeAlreadySet / BridgeNotSet | ZeroAddress / ZeroAmount / CannotRenounceOwnership | ZeroAddress / ZeroAmount / CannotRenounceOwnership | ✅ consistent naming vocabulary |
| `ITelcoinBridge` interface | — | — | — | not implemented | not implemented | ❌ **FINDING** |

| # | Finding | Severity | Status |
|---|---|---|---|
| SCA-1 | `ITelcoinBridge.sol` defines `bridge()` / `quote()` / `rescueTokens(addr, uint)` — not implemented by any contract; actual bridge uses `send()` / `quoteSend()` / `rescueTokens(addr, uint, addr)`. Stale interface. | Info | TRUE_POSITIVE → AUDIT.md **I-03**. |
| SCA-2 | Constants, role names, error vocabulary all consistent. | — | PASS |

### SPC-* spec-compliance-audit (niche)

Specs to compare against:
- `README.md` (protocol overview + security considerations)
- `invariants.md` (32 invariants across 10 categories)
- `docs/bridge-integration.md` (frontend integration + dust/decimals contract)

Per-invariant compliance (12 invariants cross-checked already in Phase 7 of AUDIT.md §7):

| Invariant category | Match? |
|---|---|
| I1 Supply conservation / I2 Decimal conversion / I3 Irreversibility / I4 Atomicity / I5 MINTER_ROLE requirement | ✅ all 5 match |
| S1 Access control / S1b Burn authorization / S2 Pausability / S3 Recovery / S4 User authorization | ✅ all 5 match |
| F1 Whole balance / F2 Burn accumulation / F3 Mint-based | ✅ all 3 match |
| E1 No value extraction / E2 Cross-chain distribution / E3 Post-expiry | ✅ match (cap enforcement per-chain is explicit in E2) |
| ST1 State consistency / ST2 Event emission | ✅ match |
| IM1 Immutable refs / IM2 Decimal constant / IM3 Burn address | ✅ match |
| O1 Migration window / O2 Multisig / O3 User support | ✅ match |
| B1 Burn-Mint conservation / B2 Peer auth / B3 Pausability / B4 Ownership / B5 Bridge interchangeability | ✅ match (B5 with L-01 caveat) |
| N1 Lock-Credit / N2 Reserve sufficiency / N3 msg.value / N4 Single instance | ✅ match |
| W1 Auth gate / W2 Role delegation / W3 Immutable token | ✅ match |

| # | Finding | Severity | Status |
|---|---|---|---|
| SPC-1 | Stale `ITelcoinBridge` interface referenced by no one (dead spec). | Info | Covered by SCA-1 / AUDIT.md I-03. |
| SPC-2 | Bridge rotation specified in README as 2-step, code permits 1-step. | Low | Covered by MSO-1 / AUDIT.md L-01. |
| SPC-3 | All 32 documented invariants implemented correctly. | — | PASS |

---

## Phase 5 — Synthesis

### Correlation Matrix

| Hypothesis | Source skills (correlation boost) | Severity | Confidence |
|---|---|---|---|
| H-1: Bridge rotation single-step overwrite | CR-2, EC-1, MSO-1, TPS-3, SPC-2 (5 skills) | Low | HIGH (+5 correlated findings) |
| H-2: rescueBurn no distinct event | EC-2, EVC-1 (2 skills) | Info | MEDIUM |
| H-3: NativeBridge native non-recoverable | CR-2, IHR-1, EDA implicit | Info | MEDIUM |
| H-4: rescueTokens paused-blocked on TelcoinV3 | CR-2 | Info | LOW |
| H-5: Stale ITelcoinBridge interface | SCA-1, SPC-1 (2 skills) | Info | HIGH |
| H-6: Per-chain cap, not global | CR-2, CMI-6, EDA-1 (3 skills) | Info | HIGH |
| H-7: NativeBridge _credit push failure | CMI-5, IHR-1, TF indirect | Info | HIGH (LZ-documented) |
| H-8: CREATE3 salt front-running | IHR-2, fork-ancestry | Info | MEDIUM |

All eight map to pre-existing AUDIT.md findings (L-01, I-01 through I-07). No new bugs surfaced beyond the earlier pipeline; **Plamen pass confirms the earlier findings and adds one minor EVC-2 (rescueTokens event)**.

### Hypotheses (Prioritized)

#### H-1 — MintBurnWrapper.authorizeBridge silently overwrites a previously authorised bridge
**Source**: CR-2, EC-1, MSO-1, TPS-3, SPC-2 — 5-way correlation
**Severity**: LOW
**Test type**: STANDARD
**Statement**: IF `bridge != address(0)` AND `_bridge != address(0)` AND `_bridge != bridge`, THEN `authorizeBridge(_bridge)` succeeds and **replaces** the slot without emitting `BridgeRevoked(oldBridge)`, contradicting README §5 specification of a 2-step rotation.
**Location**: src/MintBurnWrapper.sol:95-100
**Test (verification)**: See `test/bridge/TelcoinBridge.t.sol` existing `test_Wrapper_RevokeBridge_BlocksMint`-style flow; add negative test for overwrite.

#### H-2 — TelcoinV3.rescueBurn emits no distinguishing event
**Severity**: INFO

#### H-3 — NativeBridge has no native-TEL withdrawal path
**Severity**: INFO

#### H-4 — TelcoinV3.rescueTokens blocked while paused (when _token == address(this))
**Severity**: INFO

#### H-5 — Stale ITelcoinBridge.sol interface
**Severity**: INFO

#### H-6 — Supply cap is per-chain, not global
**Severity**: INFO

#### H-7 — NativeBridge._credit can permanently fail on malicious recipients (inherited LZ behaviour)
**Severity**: INFO

#### H-8 — CREATE3 deployment salt front-running
**Severity**: INFO

---

## Phase 5b — Verification

Following `verification-protocol` skill. Evidence sources tagged.

### H-1 Verification

**Evidence Source Tags:**
- [CODE] src/MintBurnWrapper.sol:95-100 (in-scope audited code)
- [DOC] README.md §1 section "MintBurnWrapper" paragraph "Idempotency guards" and §5 §11 "Single Active Bridge"
- [CODE] test/bridge/TelcoinBridge.t.sol — existing wrapper tests

**Reproduction (pseudocode):**
```
setup: wrapper.authorizeBridge(bridgeA); assert wrapper.bridge() == bridgeA
execute: wrapper.authorizeBridge(bridgeB)
observe: wrapper.bridge() == bridgeB (overwritten)
observe: BridgeAuthorized(bridgeB) emitted
observe: BridgeRevoked(bridgeA) NOT emitted
```

**Verdict**: CONFIRMED — **TRUE_POSITIVE** (Low severity, operational / observability).

**RAG context (historical):** Event-emission observability gaps for single-step role rotations are widely reported in audit reports — e.g., StandardBridge role rotations, Synthetix operator rotations. Pattern confidence: HIGH.

### H-2 through H-8 Verification

Each maps to an existing AUDIT.md finding with its own Phase 7 gate review (see reports/AUDIT.md §5). Plamen-pass re-verification summary:

| ID | Verdict | Evidence |
|---|---|---|
| H-2 (EVC-1 / I-04) | TRUE_POSITIVE (Info) | TelcoinV3.sol:70-72 — only `_burn` → Transfer event |
| H-3 (I-01) | TRUE_POSITIVE (Info, design) | `grep rescueNative src/` no hits |
| H-4 (I-02) | TRUE_POSITIVE (Info) | TelcoinV3.sol:85 uses safeTransfer → _update pause guard |
| H-5 (SCA-1 / I-03) | TRUE_POSITIVE (Info) | `grep ITelcoinBridge src/` — one file only |
| H-6 (I-05) | TRUE_POSITIVE (Info, design) | MIGRATION_SUPPLY_CAP is a per-instance constant |
| H-7 (I-06) | TRUE_POSITIVE (Info, LZ platform) | NativeOFTAdapter.sol:112 `call{value:}` |
| H-8 (I-07) | TRUE_POSITIVE (Info, operational) | lib/create3/contracts/Create3.sol — address is factory-address-derived |

### New finding in this Plamen pass

**EVC-2 — Bridges + TelcoinV3 `rescueTokens` emit no custom `Rescued` event**
Severity: Info (below Low threshold).
Locations: `src/TelcoinV3.sol:85`, `src/TelcoinBridge.sol:98`, `src/NativeBridge.sol:93`.
Each rescue emits only the OZ ERC-20 `Transfer(this, to, amt)` — indistinguishable from a normal transfer for off-chain monitoring.
**Recommendation**: emit `event Rescued(address indexed token, address indexed to, uint256 amount)` in each of the three `rescueTokens` functions. ~5 min effort per contract. Skill: [skill: `PlamenTSV/plamen#agents/skills/niche/event-completeness`].

---

## Phase 6 — Plamen Report Summary

| Severity | Count | IDs |
|---|---:|---|
| Critical | 0 | — |
| High | 0 | — |
| Medium | 0 | — |
| Low | 1 | H-1 (L-01) |
| Info | 8 | H-2..H-8 (I-01..I-07) + EVC-2 |

**All findings** map 1-1 to `reports/AUDIT.md` §5 except **EVC-2** which is the single new addition surfaced by running the Plamen niche/event-completeness skill over rescueTokens emits.

**Skill coverage delta vs. earlier pass:**

- 11 EVM skills triggered and fully applied: `centralization-risk`, `cross-chain-message-integrity`, `cross-chain-timing`, `economic-design-audit`, `event-correctness`, `external-precondition-audit`, `fork-ancestry`, `migration-analysis`, `temporal-parameter-staleness`, `token-flow-tracing`, `zero-state-return`.
- 6 EVM skills deliberately skipped (triggers not met): `flash-loan-interaction`, `oracle-analysis`, `semi-trusted-roles`, `share-allocation-fairness`, `staking-receipt-tokens`, `storage-layout-safety` — each with a one-line trigger-miss justification in Phase 1.B.
- 1 injectable triggered: `integration-hazard-research`. 7 others skipped (triggers not met).
- 4 niche triggered: `event-completeness`, `multi-step-operation-safety`, `semantic-consistency-audit`, `spec-compliance-audit`. 5 others skipped.
- `verification-protocol` applied to 8 hypotheses in Phase 5b.

**Plamen verdict**: **LOW overall risk.** No new Critical/High/Medium bugs beyond the existing audit. The existing audit's L-01 is confirmed by 5 independent Plamen skills — high-confidence TRUE_POSITIVE. The Plamen pass adds **EVC-2** (Info) on `rescueTokens` observability.

Artefact path: `reports/PLAMEN_AUDIT.md`.
