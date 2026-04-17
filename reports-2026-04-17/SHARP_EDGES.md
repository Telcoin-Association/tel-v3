# sharp-edges Application — Telcoin V3

Applying `trailofbits/skills#sharp-edges` ("pit of success" analysis) to Telcoin V3's security-relevant APIs. For each exposed knob, ask: does the easy path lead to a secure outcome?

## Security-relevant APIs exposed by Telcoin V3

### 1. `TelcoinV3.mint(address to, uint256 amount)` — MINTER_ROLE

**Pit-of-success check:**
- Easy path: call `mint(to, amount)`. Secure outcome: supply increases up to 100 B cap; revert if exceeded.
- Footgun potential: ❌ none — the post-mint cap check (`totalSupply() > cap → revert`) is non-bypassable from within the function. A MINTER holder cannot accidentally mint past the cap.
- Recommendation: none.

### 2. `TelcoinV3.burn(address from, uint256 amount)` — BURNER_ROLE

**Pit-of-success check:**
- Easy path: `burn(from, amount)` — requires `_spendAllowance(from, msg.sender, amount)`. If unapproved → revert.
- Footgun: ❌ none. The allowance gate is the opposite of a footgun — a compromised BURNER_ROLE holder cannot drain unapproved wallets.
- **Sharp edge avoided**: without the allowance check, BURNER_ROLE would be a drain-anyone key. Correct design.

### 3. `TelcoinV3.rescueBurn(address from, uint256 amount)` — DEFAULT_ADMIN_ROLE

**Pit-of-success check:**
- Easy path: `rescueBurn(hacker, amount)` — burns without approval.
- Footgun: ⚠️ **rescueBurn is a high-power tool masquerading as a small utility.** An admin who intended `burn` (allowance-required) but accidentally called `rescueBurn` can burn any wallet.
- Mitigation in code: role separation — **BURNER_ROLE cannot call rescueBurn; only DEFAULT_ADMIN_ROLE can**. The admin role is held by the multisig, not the wrapper. So the "easy path" for routine bridge burning is `burn()` which requires approval; `rescueBurn` is reserved for deliberate governance.
- Recommendation (minor): ensure multisig signer UIs show a highlighted "EMERGENCY BURN — no approval check" warning when simulating rescueBurn, so signers don't approve it by pattern-matching on "burn". This is operational, not contract.

### 4. `MintBurnWrapper.authorizeBridge(address _bridge)` — onlyOwner

**Pit-of-success check:**
- Easy path: `authorizeBridge(newBridge)`.
- Footgun: ✅ **YES — this is L-01.** If a bridge is already set, the easy path silently overwrites without a revoke event. The secure path (two-step: revoke → authorize) is longer and not enforced by the contract. Pit of failure.
- Recommendation: per L-01, add `if (bridge != address(0)) revert BridgeAlreadySet();` to force the caller into the secure revoke-first path.

### 5. `TelcoinV3.rescueTokens(address _token, uint256 _amount, address _to)` — DEFAULT_ADMIN_ROLE

**Pit-of-success check:**
- Easy path: rescue accidentally-sent ERC-20 tokens to any destination.
- Footgun: ⚠️ **minor** — if `_token == address(this)` (TelcoinV3 itself), transfer goes through `_update` which enforces the pause guard. Admin expecting rescue to work during pause will hit `EnforcedPause`. This is the AUDIT.md I-02 observation.
- Recommendation: either document or allow admin-initiated sweep-of-self during pause.

### 6. `TokenMigration.migrate()` — public, no args

**Pit-of-success check:**
- Easy path: approve + migrate → whole-balance conversion at 1:1.
- Footgun: none. No per-amount argument to get wrong. No slippage parameter to forget.
- **Sharp-edge avoided**: by taking no arguments and always converting the full balance, the API eliminates the class of "bad amount" mistakes.
- One quirk: users who want to migrate partially must split via transfer first. Documented.

### 7. `TokenMigration.setMigrationExpiry(uint256 newMigrationExpiry)` — onlyOwner

**Pit-of-success check:**
- Easy path: set new expiry — must be greater than current, or revert `InvalidExpiry`.
- Footgun: the Cantina audit previously raised a concern about accidentally setting `newMigrationExpiry` to a huge absolute timestamp (e.g., year 2100), which then locks funds because expiry can only increase. Fixed in commit `7571fd8b` by adding a `MAX_EXTENSION_PERIOD = 365 days` upper bound.
- Current code verification: `grep -n MAX_EXTENSION_PERIOD src/TokenMigration.sol` → **NOT found** in current code at commit 5e9cdf9.

Let me verify that.

### 8. LayerZero bridge `send(SendParam, MessagingFee, address)` — pausable

**Pit-of-success check:**
- Easy path: `send(params, fee, refund, { value: fee })` — must match `quoteSend` result.
- Footgun: users picking a too-low `extraOptions` gas (e.g., < 200k for a standard bridge) cause the destination `lzReceive` to run out of gas → message stuck in LZ retry queue.
- The frontend docs (`docs/bridge-integration.md`) say "200_000 gas is sufficient for a standard TEL bridge. If the destination runs out of gas, the message will need to be retried".
- Contract-level mitigation: **enforcedOptions** (OAppOptionsType3) — owner can pre-set a minimum gas. Currently not configured in the deployed contracts per `docs/lz-dvn-config.md`.
- Recommendation: **document or enforce a min gas via setEnforcedOptions** so that a user picking `extraOptions = 0` gets a sane default. This is operational-to-contract, medium-effort.

### 9. `NativeBridge.send` — msg.value must equal fee + amount

**Pit-of-success check:**
- Easy path: `send` with `msg.value = fee + amount`.
- Footgun: footgun handled correctly — `NativeOFTAdapter.send` reverts `IncorrectMessageValue(provided, required)` if the sum is wrong. Good error message with both values helps UI recovery.

### 10. `NativeBridge.receive()` — open-to-anyone ETH reception

**Pit-of-success check:**
- Easy path: anyone can send TEL → reserve increases.
- Footgun: ⚠️ **no way to withdraw** (AUDIT.md I-01). A well-meaning user over-funding has no recovery. The TIA-02 observation.
- Recommendation: surface this prominently in frontend docs.

## Summary: Sharp-Edges finds

| Sharp edge | Severity | Status in audit |
|---|---|---|
| `authorizeBridge` overwrite (L-01) | Low | **already reported** |
| `NativeBridge.receive()` over-funding trap (TIA-02) | Info | already reported |
| `rescueTokens` paused-blocked (I-02) | Info | already reported |
| No enforced-options gas floor on bridges | **NEW** | surface below |
| TokenMigration no max extension period in current code | **NEW — verify vs commit** | see below |

## Verification against HEAD 5e9cdf9

### NE-1 (new) — `TokenMigration.setMigrationExpiry` has no upper bound

**Finding:** Cantina §3.2.7 recommended `MAX_EXTENSION_PERIOD = 365 days` upper bound on expiry extensions to prevent fat-finger lock (e.g., owner accidentally setting timestamp to year 2100 instead of `now + 365d`). Cantina's report lists the fix as applied in commit `7571fd8b`.

**Verification at HEAD `5e9cdf9`:**

```solidity
function setMigrationExpiry(uint256 newMigrationExpiry) external onlyOwner {
    if (newMigrationExpiry == 0 || migrationExpiry > newMigrationExpiry) revert InvalidExpiry();
    emit MigrationExpirySet(migrationExpiry, newMigrationExpiry);
    migrationExpiry = newMigrationExpiry;
}
```

There is **no `MAX_EXTENSION_PERIOD`** check. `grep -n MAX_EXTENSION_PERIOD src/TokenMigration.sol` → no hits. Cantina's fix was **not preserved** through the subsequent mint-based refactor (PR #8 `1067e81`).

**Re-assessment under current architecture:**
The original concern was about locking TelcoinV3 in a pre-funded reserve until expiry. After PR #8, migration is **mint-based** (`telcoinV3.mint(msg.sender, amountNewToken)`), so there is no locked reserve to strand. The only residual concern is:
- A fat-fingered huge expiry keeps `MINTER_ROLE` granted to the migration longer than intended; late migrations could exceed the 100 B cap.
- Purely operational/observability — mitigated because governance can revoke MINTER_ROLE at any time.

**Severity:** Informational / operational — re-audit the Cantina fix under the new mint-based design, and either re-instate MAX_EXTENSION or document why it's no longer needed.

**Designation:** **SE-1 (new finding this pass)**.

---

### NE-2 (new) — Bridge `extraOptions` gas floor not enforced

**Finding:** `TelcoinBridge.send` / `NativeBridge.send` accept user-supplied `extraOptions` bytes that encode the destination-side `lzReceive` gas limit. If a user / frontend passes insufficient gas (< 200k), the destination `lzReceive` runs out of gas and the message enters LZ's retry queue indefinitely. User's source-chain TEL is already burned.

**Verification:**

```
$ grep -rn "setEnforcedOptions\|EnforcedOptionParam\|enforcedOptions" src/ script/
```

Returns no hits — enforced-options are not configured by either bridge contract or the deployment scripts.

**Inherited from OFTCore:** `setEnforcedOptions(EnforcedOptionParam[])` is available via `OAppOptionsType3`, which `OFTCore` inherits. Owner-callable. Not set in deployment.

**Severity:** Informational (UX / operational). A user choosing a sane gas value (≥200k per docs) avoids this. But the frontend-vs-contract trust boundary is thin; a misconfigured frontend or direct contract call with garbage options can brick a bridge message.

**Recommendation:** During deployment, set enforced options via `bridge.setEnforcedOptions(...)` with a sensible minimum (e.g., 200,000 gas for `SEND` msgType). Example:

```solidity
EnforcedOptionParam[] memory params = new EnforcedOptionParam[](1);
params[0] = EnforcedOptionParam({ eid: peerEid, msgType: SEND, options: Options.newOptions().addExecutorLzReceiveOption(200_000, 0).toBytes() });
bridge.setEnforcedOptions(params);
```

**Designation:** **SE-2 (new finding this pass)**.

---

## Final sharp-edges summary

| Finding | Severity | New/existing |
|---|---|---|
| authorizeBridge overwrite | Low → per fp-check strict: Info | **L-01** (existing) |
| rescueTokens paused-blocked | Info | **I-02** (existing) |
| NativeBridge over-funding trap | Info | **TIA-02** (existing) |
| setMigrationExpiry MAX_EXTENSION regression from Cantina fix | Info | **SE-1 (NEW)** |
| No enforced-options gas floor on bridges | Info | **SE-2 (NEW)** |

Both new findings are **Informational** / operational, not security-critical. They materialise only on governance misconfiguration or user frontend errors.
