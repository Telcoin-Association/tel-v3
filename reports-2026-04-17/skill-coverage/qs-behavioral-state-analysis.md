# qs_skills/behavioral-state-analysis — Coverage

**Checked — clean.**

State machines:

### TokenMigration
States: {pre-expiry,not-paused} → migrate succeeds. {paused} → revert. {post-expiry} → revert.
Owner can toggle pause and extend (not shrink) expiry.

### TelcoinV3
Paused ⇔ transfers between non-zero addresses revert. Mint/burn always allowed. Role modifications always allowed.

### MintBurnWrapper
bridge ∈ {address(0), bridgeAddress}. Transitions:
- `authorizeBridge(0→b)` emits `BridgeAuthorized`.
- `authorizeBridge(b→b)` reverts BridgeAlreadySet.
- `authorizeBridge(b→b')` ⚠️ silently transitions without BridgeRevoked (L-01).
- `revokeBridge(b→0)` emits BridgeRevoked.
- `revokeBridge(0→*)` reverts BridgeNotSet.
- `revokeBridge(b→b')` where b ≠ b' reverts UnauthorizedBridge.

### Bridges (TelcoinBridge, NativeBridge)
Paused ⇔ send + _lzReceive revert. Admin toggles via pause/unpause.

### Ownership
`owner = O`, `pendingOwner = P`. Transitions:
- `transferOwnership(P')`: sets `pendingOwner = P'`.
- `acceptOwnership()` by P: sets `owner = P`, clears pending.
- `renounceOwnership()` disabled on non-token contracts.

All state transitions guarded by modifiers and emit events (except the L-01 overwrite gap).
