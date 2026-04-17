# === TOKEN INTEGRATION ANALYSIS REPORT ===

**Project:** Telcoin V3 + LayerZero OFT bridge mesh
**Tokens analyzed:**
- **Implementation:** `TelcoinV3` (new ERC-20, 18 decimals) at `src/TelcoinV3.sol`
- **Integration A:** `TokenMigration` integrates legacy `TelcoinV2` (2-decimal ERC-20 on Ethereum mainnet: `0x467Bccd9d29f223BcE8043b84E8C8B282827790F`)
- **Integration B:** `TelcoinBridge` + `NativeBridge` bridge TEL across chains via LayerZero V2 OFT, routing mint/burn through `MintBurnWrapper`
**Platform:** Solidity 0.8.26 / 0.8.30, EVM (prague). Targets: Ethereum, Polygon, Base, TelcoinNetwork
**Commit:** `5e9cdf9b3e10151358859aac31dc890edeccdbe7`
**Analysis date:** 2026-04-17

---

## EXECUTIVE SUMMARY

**Token type:** ERC-20 implementation (TelcoinV3) + protocol integrating an existing ERC-20 (legacy TelcoinV2) + cross-chain bridge integration via LayerZero OFT.

**Overall risk level:** **LOW**
**Critical issues:** 0
**High issues:** 0
**Medium issues:** 0
**Low issues:** 1 (L-01 carried from earlier bridge audit)
**Informational:** 7 (I-01 … I-07 from earlier bridge audit) + 2 integration-analyzer observations (TIA-01, TIA-02) below

**Top observations:**

- ✅ `TelcoinV3` is **fully ERC-20 compliant** per `slither-check-erc` (all functions, return types, events, indexing correct). No missing-return bug, no revert-on-zero quirks.
- ✅ `TokenMigration` already uses **OpenZeppelin `SafeERC20`** (`safeTransferFrom`, `safeTransfer`) for every OldToken interaction → USDT-style missing-return tokens would still work correctly. Legacy `TelcoinV2` actually **does** return bool, so no issue in this integration.
- ✅ The **legacy `TelcoinV2`** integration target is a well-understood, plain-vanilla ERC-20: no fee-on-transfer, no rebasing, no blacklist, no hooks. Verified on-chain (`10^13` raw total supply, 2 decimals, "Telcoin" / "TEL").
- ✅ Migration math is **exact** (`x * 1e16`), no rounding drift.
- ℹ️ `TelcoinV3` has **unbounded minting by MINTER_ROLE**, mitigated by a hard per-chain cap of 100 B (reverts on mint that would exceed).
- ℹ️ Supply cap is **per-chain not global** — see finding I-05 in `reports/AUDIT.md`.
- ℹ️ **LayerZero `_removeDust` strips sub-1e12 wei** from bridged amounts — bridging is lossy below the 1e12 threshold (documented; dust stays with sender).
- ℹ️ No `permit` (EIP-2612) — users need two transactions (approve + send) when bridging. Not a bug, a UX note.

**Recommendation:** No blocking changes for token security. Apply the two new observations below (TIA-01, TIA-02) at the author's convenience; address `reports/AUDIT.md`'s L-01 / I-03 / I-04 before mainnet.

---

## 1. GENERAL CONSIDERATIONS

| Check | Status | Evidence |
|---|---|---|
| Security reviews completed | ✅ | Cantina managed review (Dec 2025, `audit/report-cantinacode-telcoin-V3-1025.pdf`) — 0 Critical/High/Medium/Low, 1 Gas, 12 Info. 11/12 fixed, 1 acknowledged. **Bridge contracts were NOT in Cantina scope**; covered by this audit (`reports/AUDIT.md`). |
| Team contactable | ✅ | Telcoin Association public; GitHub org `Telcoin-Association`; deployment docs list admin multisig ownership. |
| Security contact | ⚠️ | No `SECURITY.md` in the repo. Recommend adding `security@telco.in` or similar. |
| Responsible disclosure process | ⚠️ | Not documented in-repo. |

**Status:** ACCEPTABLE — prior audit trail is solid; one housekeeping item.

---

## 2. CONTRACT COMPOSITION

**Slither human-summary output (commit 5e9cdf9):**

```
Total number of contracts in source files: 10
Source lines of code (SLOC) in source files: 402
Number of assembly lines: 0
Number of optimization issues: 0
Number of informational issues: 22
Number of low issues: 4
Number of medium issues: 2
Number of high issues: 0
```

Per-contract function counts and complexity:

| Contract | Functions | Complex code? | Features |
|---|---:|---|---|
| TelcoinV3 | 72 (incl. inherited) | No | ERC20, ERC165, Pausable, ∞ Minting, Approve Race Cond. |
| TokenMigration | 31 | No | Tokens interaction |
| MintBurnWrapper | 21 | No | Tokens interaction |
| TelcoinBridge | 103 | No | Receive ETH, Send ETH, Tokens, Assembly (LZ-library) |
| NativeBridge | 106 | No | Receive ETH, Send ETH, Tokens, Assembly (LZ-library) |
| TelcoinV2 (legacy) | 9 | No | ERC20, No Minting (frozen supply) |

- ✅ No contract flagged `Complex code: Yes`.
- ✅ Zero user-authored assembly lines; all assembly is inside LayerZero / forge-std libraries.
- ✅ Solidity **0.8.26+** / **0.8.30+** → built-in overflow protection; no `unchecked` blocks in `src/` (verified).
- ⚠️ Bridge contracts are large (106 fns in NativeBridge, 103 in TelcoinBridge) because of deep LayerZero inheritance — these are well-tested library code.

**Non-token functions (beyond ERC-20) in TelcoinV3:**

| Function | Purpose | Access |
|---|---|---|
| `mint(address,uint256)` | Grant new TEL to `to`, respects 100 B cap | `MINTER_ROLE` |
| `burn(address,uint256)` | Burn from `from` **with** allowance check | `BURNER_ROLE` |
| `rescueBurn(address,uint256)` | Emergency burn without allowance | `DEFAULT_ADMIN_ROLE` |
| `pause()` / `unpause()` | Halt non-mint/burn transfers | `PAUSER_ROLE` / `UNPAUSER_ROLE` |
| `rescueTokens(address,uint256,address)` | Sweep accidentally-sent tokens | `DEFAULT_ADMIN_ROLE` |
| `renounceRole(bytes32,address)` | **Overridden to always revert** | — |

Admin entry points are minimal and each has a purpose. No hidden sweeps, no arbitrary-call helpers, no `delegatecall` in scope.

**Status:** PASS.

---

## 3. OWNER PRIVILEGES

### Upgradeability
- ❌ **Not upgradeable.** No proxy / no `initialize()` / no `__gap`. `grep -rn 'upgradeable\|UUPS\|TransparentProxy\|initialize' src/` returns no hits.
- **Risk level:** LOW — this eliminates an entire class of upgrade-safety concerns (storage collision, uninitialized proxy, logic swap).

### Minting Capabilities
- ⚠️ **Unbounded minting by `MINTER_ROLE` up to 100 B cap.** `TelcoinV3.mint` (src/TelcoinV3.sol:46-49):

  ```solidity
  function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) {
      _mint(to, amount);
      if (totalSupply() > MIGRATION_SUPPLY_CAP) revert SupplyCapExceeded();
  }
  ```
- ✅ **Hard cap enforced post-mint** — any mint that would exceed 100 B reverts.
- ⚠️ Cap is per-chain, not global (see `reports/AUDIT.md` I-05). Cross-chain in-flight messages can temporarily push aggregate supply above 100 B.
- ✅ MINTER_ROLE is only granted to:
  - `TokenMigration` (for migration minting, expected to be revoked post-expiry)
  - `MintBurnWrapper` (for bridge-triggered mints)
- **Team plan (per README):** post-expiry governance revokes migration's MINTER_ROLE, leaving only the wrapper with mint capability.

### Pausability
- ✅ **Scoped pause** — `_update` override (src/TelcoinV3.sol:109-114):

  ```solidity
  if (paused() && from != address(0) && to != address(0)) revert EnforcedPause();
  ```

  Mints (`from == 0`) and burns (`to == 0`) remain active while paused. Migration continues to function (migrate calls TelcoinV3.mint), and bridge-triggered mints/burns continue. Only **transfers between holders** are blocked.
- ✅ Separate `PAUSER_ROLE` and `UNPAUSER_ROLE` — good separation of duties.
- ⚠️ Minor: `TelcoinV3.rescueTokens` with `_token == address(this)` cannot execute while paused (→ AUDIT.md I-02).

### Blacklisting
- ✅ **No blacklist function.** No centralized censorship risk at the token layer. Governance can only burn balances via `rescueBurn` (reserved for emergency, not blacklist enforcement).

### Team Transparency & Multisig
- Ownable2Step on TokenMigration, TelcoinBridge, NativeBridge, MintBurnWrapper — two-step transfers, `renounceOwnership` permanently disabled on the last three.
- `renounceRole` permanently disabled on TelcoinV3 for all roles — prevents accidental orphan-admin.
- Trust root: a single governance multisig on each chain holds `DEFAULT_ADMIN_ROLE` on TelcoinV3 and owns the three Ownable2Step contracts.

**Status:** ACCEPTABLE with the noted cap-is-per-chain caveat (already in AUDIT.md I-05).

---

## 4. ERC-20 CONFORMITY (TelcoinV3)

**slither-check-erc result (src/TelcoinV3.sol, --erc ERC20):**

```
[✓] totalSupply() present / returns uint256 / is view
[✓] balanceOf(address) present / returns uint256 / is view
[✓] transfer(address,uint256) present / returns bool / emits Transfer
[✓] transferFrom(address,address,uint256) present / returns bool / emits Transfer
[✓] approve(address,uint256) present / returns bool / emits Approval
[✓] allowance(address,address) present / returns uint256 / is view
[✓] name() / symbol() / decimals() present & view
[✓] decimals() returns uint8 (value: 18)
[✓] Transfer event with 2 indexed params
[✓] Approval event with 2 indexed params
[ ] TelcoinV3 is not protected for the ERC20 approval race condition
```

**The one unchecked box** is that OZ 5.x ERC-20 **removed `increaseAllowance`/`decreaseAllowance`** — intentional upstream decision, not a TelcoinV3 regression. Users relying on sequential approvals should set the allowance to 0 before setting to a new non-zero value (standard ERC-20 idiom). OZ's reasoning: the race was never a real attack primitive, and the extra functions encouraged non-standard integrations.

**Status:** **FULLY COMPLIANT.**

**Integrations use `SafeERC20`** — I verified every `IERC20` call-site:

| Site | Method | Safe? |
|---|---|---|
| `TokenMigration.migrate` L84 | `oldToken.safeTransferFrom` | ✅ SafeERC20 |
| `TokenMigration.recoverERC20` L120 | `tokenContract.safeTransfer` | ✅ SafeERC20 |
| `TelcoinV3.rescueTokens` L88 | `IERC20(_token).safeTransfer` | ✅ SafeERC20 |
| `TelcoinBridge.rescueTokens` L101 | `IERC20(_token).safeTransfer` | ✅ SafeERC20 |
| `NativeBridge.rescueTokens` L96 | `IERC20(_token).safeTransfer` | ✅ SafeERC20 |

---

## 5. ERC-20 EXTENSION RISKS

| Check | Status |
|---|---|
| External calls / hooks on transfer (ERC-777, ERC-1363) | ✅ No callbacks — OZ ERC-20 base only. `_update` override adds only the pause guard. |
| Fee on transfer | ✅ Not present. `_update` is a direct balance swap; no fee collector logic. |
| Rebasing / yield-bearing | ✅ Not present. Balances change only via mint/burn/transfer. |
| Token hooks on balanceOf (e.g. Ampleforth) | ✅ `balanceOf` is inherited OZ — pure storage read. |
| Flash-mintable | ✅ No flash-mint entry point (no DAI-style `flashMint`). |

**Status:** None of the "weird extension" risks apply. TelcoinV3 behaves as a standard mint/burn ERC-20 with scoped pause.

---

## 6. TOKEN SCARCITY ANALYSIS

### Legacy OldToken (on-chain query results)

```
$ cast call 0x467Bccd9d29f223BcE8043b84E8C8B282827790F "totalSupply()(uint256)" --rpc-url https://ethereum-rpc.publicnode.com
10_000_000_000_000  (= 100 B × 10^2, matches 100B whole tokens at 2 decimals)

$ cast call …"decimals()(uint8)"
2

$ cast call …"name()(string)"
"Telcoin"

$ cast call …"symbol()(string)"
"TEL"

$ cast code … | wc -c       # hex bytes of deployed code
9133
```

- ✅ Matches expected legacy contract deployed by Telcoin in the 2017–2018 era. Source in `src/legacy/Telcoin.sol` (Solidity 0.4.18) — slither-check-erc confirms ERC-20 conformance.
- ✅ Supply is **fixed** (no minting path on TelcoinV2); migration simply moves tokens to `0x…dEaD`.

### TelcoinV3 (new token)

- **Supply cap:** `MIGRATION_SUPPLY_CAP = 100_000_000_000 ether` (100 B × 10^18) per chain.
- **Initial distribution (from docs/bridge-integration.md & invariants.md):** Ethereum ~65 B, Polygon ~30 B, Base ~5 B — minted to admin at deployment.
- **Additional supply expansion:** via `TokenMigration.migrate` (one-time, 1:1 from V2 burn) or via bridge-in from another chain.

### Holder Concentration Risk
- At launch, **most of the supply will be in the admin multisig** (genesis mint). This is expected for a migration token; migration contracts unwind the concentration as users migrate.
- Post-migration, distribution should track legacy `TelcoinV2`'s holder set. If V2 was concentrated, V3 will inherit that concentration — orthogonal to contract security.

### Flash Mint / Flash Loan Risk
- ✅ **No flash mint.** MINTER_ROLE is gated to known addresses (migration, wrapper). Bridge mint requires an LZ inbound message from a registered peer, paid for with burned supply on the source chain — no flash-mint vector.

**Status:** No scarcity issue at the contract level. On-chain distribution is a governance/operations concern.

---

## 7. WEIRD ERC-20 PATTERNS — Applicability to TelcoinV3 (implementation) and TelcoinV2 (integration target)

Trail of Bits / weird-erc20 database — 24 patterns scored for both contracts:

| # | Pattern | TelcoinV3 (new) | TelcoinV2 (integration target) | Risk |
|---|---|---|---|---|
| 7.1 | Reentrant calls via ERC-777 / ERC-1363 hooks | ❌ Not present (OZ ERC-20 only, no hooks) | ❌ Not present (standard 2017 ERC-20) | ✅ SAFE |
| 7.2 | Missing return values on transfer/approve (USDT/BNB/OMG style) | ❌ All methods return bool (OZ default) | ❌ All methods return bool (checked in slither-check-erc) | ✅ SAFE — and integrations use SafeERC20 anyway |
| 7.3 | Fee on transfer (STA, PAXG) | ❌ No fee logic | ❌ No fee logic | ✅ SAFE |
| 7.4 | Balance modifications outside transfers (Ampleforth-style rebase, Compound cToken exchange-rate) | ❌ balances only change via _update | ❌ balances only change via transfer/transferFrom | ✅ SAFE |
| 7.5 | Upgradable token | ❌ Not upgradeable | ❌ Not upgradeable (2017 contract, no proxy) | ✅ SAFE |
| 7.6 | Flash mintable | ❌ No flash mint | ❌ No flash mint | ✅ SAFE |
| 7.7 | Blocklist / freezing (USDC/USDT style) | ❌ No blocklist. (Note: `rescueBurn` can burn any wallet, but gated to DEFAULT_ADMIN_ROLE — see AUDIT.md §5) | ❌ No blocklist | ✅ SAFE at user level |
| 7.8 | Pausable token | ✅ **Present** (only blocks non-mint/burn transfers); intentional emergency knob | ❌ Not pausable | ⚠️ Documented — integrations should surface "bridge paused" state |
| 7.9 | Approval race protection (requires allowance=0 before new approve) | ❌ No — users can overwrite directly (OZ default) | ❌ No — but provides `increaseApproval`/`decreaseApproval` helpers | ℹ️ Standard ERC-20 race; not an exploitable bug |
| 7.10 | Revert on approve/transfer to zero address | ✅ Reverts on `approve(0)` and `transfer(0)` (OZ 5.x defaults: `ERC20InvalidReceiver`) | ✅ Reverts on `transfer(0)` (`require(_to != address(0))`); `approve(0)` does NOT revert | ⚠️ Minor behaviour difference between old and new token — integrations receiving V2 approvals to address(0) need to handle both. Not exploitable here |
| 7.11 | Revert on zero-value approval / transfer | ❌ Does not revert on zero-value transfer or approve | ❌ Does not revert on zero-value | ✅ SAFE |
| 7.12 | Multiple token addresses for same token (TUSD-style) | ❌ Single address per chain | ❌ Single address | ✅ SAFE |
| 7.13 | Low decimals (USDC: 6, Gemini: 2) | ❌ 18 decimals (standard) | ⚠️ **2 decimals** — this is the whole point of the migration | ✅ Handled by `DECIMAL_MULTIPLIER = 1e16` in TokenMigration (exact) |
| 7.14 | High decimals (YAM-V2: 24) | ❌ 18 decimals | ❌ 2 decimals | ✅ SAFE |
| 7.15 | `transferFrom` with `src == msg.sender` behavior | OZ default: still consumes allowance (i.e. `_spendAllowance` even if spender == owner). OZ 5.x uses `_spendAllowance` which returns early for infinite allowance but otherwise always spends | TelcoinV2 uses `SafeMath.sub(allowed[_from][msg.sender], _value)` regardless of whether `msg.sender == _from` — so it **would revert** if user transferFroms themselves without an allowance. TelcoinV3's burn() also enforces allowance. | ℹ️ Documented — not an exploit, but worth noting that `TelcoinV2.transferFrom(user, dst, amt)` called by user reverts with SafeMath if they haven't self-approved. `TokenMigration.migrate` uses `safeTransferFrom(msg.sender, BURN_ADDRESS, bal)` → OK, user must approve the migration contract (not self) |
| 7.16 | Non-string metadata (MKR-style bytes32 symbol) | ❌ Standard string metadata | ❌ Standard string metadata | ✅ SAFE |
| 7.17 | No revert on transfer failure (ZRX, EURS) | ❌ OZ reverts on failure | ❌ TelcoinV2 reverts on failure (`require(_value <= balances[...])` + SafeMath) | ✅ SAFE |
| 7.18 | Revert on large approvals (UNI: `uint96` overflow) | ❌ Supports full `uint256` approval | ❌ Supports full `uint256` approval (TelcoinV2 uses `uint256` allowance) | ✅ SAFE |
| 7.19 | Code injection via token name (HTML/string injection in UI) | String name is user-set at construction (`"Telcoin"` constant). No injection path. | String name `"Telcoin"` constant | ✅ SAFE |
| 7.20 | Unusual permit function (DAI, RAI, GLM) | ❌ **No `permit` at all** | ❌ No `permit` | ⚠️ Minor UX — see TIA-02 below |
| 7.21 | Transfer less than amount (cUSDCv3) | ❌ Transfers full amount | ❌ Transfers full amount | ✅ SAFE |
| 7.22 | ERC-20 native currency (Celo, Polygon, zkSync style) | ❌ TelcoinV3 is ERC-20 on satellite chains. On TelcoinNetwork, TEL is the **native gas token** and `NativeBridge` handles the lock/credit — **this IS a native-currency token** in one dimension | N/A | ⚠️ Architectural: the mesh is designed around this duality and handles it via separate adapters (MintBurnOFTAdapter on satellites, NativeOFTAdapter on TN). See §8. |
| 7.23 | `transferFrom` with self-approval quirks | Standard | Standard | ✅ SAFE |
| 7.24 | Sub-integer share accounting (token "shares" drifting from balances) | ❌ No share accounting | ❌ No share accounting | ✅ SAFE |

**Summary:** Only patterns **7.8 (pausability), 7.13 (low-decimal integration partner), and 7.22 (native-currency dual representation)** are materially present — all are **explicit design decisions**, properly handled by the migration contract (exact decimal conversion) and the two bridge adapters (separate MintBurnOFTAdapter + NativeOFTAdapter). No exploitable weird-token bugs surfaced.

---

## 8. TOKEN INTEGRATION SAFETY

Three integrations in scope:

### 8.a `TokenMigration` ↔ legacy `TelcoinV2` (OldToken)

- ✅ **Uses `SafeERC20.safeTransferFrom`** (src/TokenMigration.sol:84) for pulling OldToken from the user.
- ✅ **Uses `SafeERC20.safeTransfer`** (src/TokenMigration.sol:120) for `recoverERC20`.
- ✅ **Reentrancy-guarded** (`ReentrancyGuardTransient`) — and OldToken is a 2017 no-hook ERC-20, so there's no live reentry path anyway.
- ✅ **Balance-based** (`oldToken.balanceOf(msg.sender)`) — but OldToken is non-fee-on-transfer, non-rebasing, so `balanceBefore/balanceAfter` pattern is not needed. Migration math is `bal * 1e16`, exact.
- ✅ **Reverts if user has zero balance** (`InvalidAmount`), avoiding silent success on no-op.
- ✅ **OldToken sent to `0x…dEaD`** (burn address). Does not accumulate in the migration contract.
- ℹ️ `migrate()` is `public` by design — anyone can migrate their own balance. Cannot migrate someone else's because `msg.sender` is the `from` in `safeTransferFrom` and the mint recipient. **Not front-runnable** in a harmful way.

**Status:** SAFE.

### 8.b `TelcoinBridge` (satellite) ↔ TelcoinV3 via `MintBurnWrapper`

- ✅ **Approval flow:** user approves `MintBurnWrapper` (not the bridge) for their TEL. `MintBurnWrapper` has `BURNER_ROLE` on TelcoinV3; `TelcoinV3.burn` enforces `_spendAllowance(from, msg.sender, amount)`. **A compromised wrapper cannot drain wallets that haven't approved it.**
- ✅ `TelcoinBridge.approvalRequired()` is `pure override returns (true)` (src/TelcoinBridge.sol:64) — **explicit signal** to frontends that approval is needed (overrides MintBurnOFTAdapter's default of `false`).
- ✅ `_lzReceive` gated by `whenNotPaused` + LayerZero endpoint+peer validation (OAppReceiver.lzReceive → OnlyEndpoint + OnlyPeer).
- ✅ Dust stripping (`_removeDust`) is symmetric — dust stays with the sender on source.
- ✅ Max per-message amount bounded by `uint64.max × 1e12 ≈ 18.4 B TEL` (OFTCore `_toSD` overflow check).

### 8.c `NativeBridge` (TelcoinNetwork) — native TEL lock/credit

- ✅ `send()` validates `msg.value == nativeFee + removeDust(amount)` — inherited from `NativeOFTAdapter.send` (lib/…/NativeOFTAdapter.sol:65-78). Reverts `IncorrectMessageValue(provided, required)` otherwise.
- ✅ `_credit` uses `call{value:}("")` with explicit success check → reverts `CreditFailed(to, amount, data)` on failure.
- ⚠️ **Native credit may fail permanently** if recipient contract rejects ETH (see AUDIT.md I-06). LayerZero retries indefinitely; no in-protocol skip.
- ℹ️ **Reserve top-ups** via `receive() payable` — anyone can fund the reserve (emits `ReserveFunded`). Cannot under-fund accounting because inbound LZ messages burn on source.
- ⚠️ **Reserve non-recoverable** (AUDIT.md I-01). No `rescueNative` function.

**Status:** SAFE with two documented informational observations (I-01, I-06) already in the main AUDIT.md.

### New observations from this token-integration analyzer pass

#### TIA-01 — TelcoinV3 has no `permit` (EIP-2612) → 2-transaction bridging UX

**Severity:** Informational (UX / ergonomics)
**Location:** `src/TelcoinV3.sol`

`TelcoinV3` inherits only OZ's base `ERC20` + `AccessControlEnumerable`, not `ERC20Permit`. Bridging TEL to another chain therefore requires two transactions:
1. `TelcoinV3.approve(MintBurnWrapper, amount)` (L1 gas, user pays)
2. `TelcoinBridge.send(sendParam, fee, refund, {value: fee})` (L1 gas + LZ fee)

No security impact. Adding `ERC20Permit` would let frontends collapse this to a single-call flow (off-chain signature + on-chain `permit + send`). Two-step is also perfectly acceptable; many production tokens (USDC long resisted permit) work this way.

**Recommendation:** Optional — adopt `ERC20Permit` and expose a `sendWithPermit` wrapper if single-click UX becomes a goal. Low priority.

---

#### TIA-02 — `NativeBridge.receive()` accepts ETH from anyone without a rate-limit or size cap

**Severity:** Informational
**Location:** `src/NativeBridge.sol:56-58`

```solidity
receive() external payable {
    emit ReserveFunded(msg.sender, msg.value);
}
```

Anyone can send arbitrary native TEL to NativeBridge, and the reserve cannot be withdrawn by the owner (see AUDIT.md I-01). While there's no accounting bug (inbound LZ credits burn source-side TEL), this means:

- A well-meaning user can **over-fund** the reserve indefinitely with no easy recovery; their funds are trapped (only consumed by future outbound LZ credits).
- Griefer-style: an adversary can push arbitrary ETH to the contract, inflating the reserve beyond any reasonable need. Since no withdrawal exists, the excess sits forever.

No security impact to users — their own sends are received correctly. Just an observation.

**Recommendation:** Consider a `receive()` that emits an "operator-only" hint, OR document prominently that non-operator top-ups are permitted but non-recoverable. Optionally, an `onlyOwner rescueNativeToReserveWallet` escape hatch (gated to a specific treasury/reserve-keeper).

---

## 9. ERC-721 CONFORMITY

**N/A** — no ERC-721 contracts in scope. All tokens are fungible ERC-20.

---

## 10. ERC-721 COMMON RISKS

**N/A** — no NFTs.

---

## Compliance Checklist

- [x] **ERC-20 conformance verified** via slither-check-erc on TelcoinV3 ✅ and TelcoinV2 ✅
- [x] **All 24 weird-erc20 patterns triaged** (0 critical, 0 high; 7.8, 7.13, 7.22 are design-intended, handled)
- [x] **SafeERC20 used for every external token interaction** (TokenMigration, TelcoinV3.rescueTokens, bridges.rescueTokens)
- [x] **Reentrancy guard present on migrate()**
- [x] **Approval flow documented** (users approve MintBurnWrapper, bridge signals `approvalRequired() == true`)
- [x] **Pause semantics verified** (mints/burns still work under pause; only peer-to-peer transfers blocked)
- [x] **Supply cap enforced per-chain** (verified by Halmos + Echidna)
- [x] **On-chain query of legacy OldToken** confirms decimals/name/symbol/supply match expected
- [x] **Admin privileges enumerated** (minter, burner, pauser, admin + Ownable2Step owners on each contract)
- [x] **No upgradeable / proxy / delegatecall paths**
- [x] **No hooks, no fee-on-transfer, no rebasing, no flash-mint**

---

## Prioritized Recommendations

| # | Severity | Recommendation | Effort |
|---|---|---|---|
| — | LOW | **L-01** (`MintBurnWrapper.authorizeBridge` overwrite): require `bridge == address(0)` before re-auth. See AUDIT.md §5. | ~10 min |
| — | INFO | **TIA-01** Add ERC20Permit (optional UX polish) | ~1 h |
| — | INFO | **TIA-02** Document or gate NativeBridge `receive()` | ~10 min |
| — | INFO | **I-03** Delete or update stale `ITelcoinBridge.sol` interface | ~5 min |
| — | INFO | **I-04** Emit `RescueBurned` event from `TelcoinV3.rescueBurn` | ~5 min |
| — | INFO | **I-05** Document per-chain cap semantics in invariants.md | ~15 min |
| — | INFO | Add `SECURITY.md` with disclosure process | ~15 min |

No CRITICAL / HIGH / MEDIUM issues; the token implementation and both token integrations are secure at the contract level.
