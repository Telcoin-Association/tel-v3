# Archethect/sc-auditor — approval-abuse — Coverage

**Checked — clean.**

Approval surfaces in scope:

1. User approves `TokenMigration` to spend OldToken → migration pulls `balanceOf(msg.sender)` and burns to 0xdEaD. If user decreases approval or receives more OldToken after approving, `transferFrom` reverts on insufficient allowance. If user approves MAX then receives tokens, subsequent migration migrates the full current balance — by design.
2. User approves `MintBurnWrapper` to spend TelcoinV3 → wrapper burns during `OFTCore._debit`. Uses `_spendAllowance(from, msg.sender, amount)`, so only the wrapper (the `msg.sender` when called from the bridge) can spend. If a third party had been granted an allowance from the user, that third party cannot call `wrapper.burn` because only `onlyBridge` can.
3. TelcoinV3 inherits OZ ERC-20 `approve` (no rate-change-race mitigation beyond OZ defaults — no `increaseAllowance`/`decreaseAllowance` wrappers added, but OZ ERC-20's approve no longer requires zero-first in 5.x).

**Approval abuse vectors:**

- A compromised `MintBurnWrapper` (i.e. governance sets `authorizeBridge` to a malicious bridge that calls `wrapper.burn`) can only burn from users who have approved the wrapper for that amount. So the blast radius is bounded by approved allowances — users who approved MAX are exposed, users who approved amount-only are exposed to that amount.
- `TelcoinV3.rescueBurn` bypasses approval — but it is gated to DEFAULT_ADMIN_ROLE (governance multisig).

No unprotected approval-abuse path.
