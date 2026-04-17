# variant-analysis — L-01 and cohort

Applying `trailofbits/skills#variant-analysis` 5-step process: understand original → exact match → abstract → generalise → triage.

## Original issue: L-01

```solidity
// src/MintBurnWrapper.sol:95-100
function authorizeBridge(address _bridge) external onlyOwner {
    if (_bridge == address(0)) revert ZeroAddress();
    if (bridge == _bridge) revert BridgeAlreadySet();
    bridge = _bridge;                 // silently overwrites non-zero slot
    emit BridgeAuthorized(_bridge);   // no BridgeRevoked(old) emitted
}
```

**Root cause:** A state-slot setter whose idempotency guard only prevents the *no-op* case (`new == old`) but not the *overwrite* case (`old != 0 && new != 0 && new != old`), combined with emitting a "set" event without a matching "unset" event.

## Step 2: Exact Match

```
grep -n "bridge == _bridge\|bridge = address(0)\|bridge = _bridge" src/MintBurnWrapper.sol
```

Only one match (the original). OK.

## Step 3: Abstraction Points

Generalise the pattern to *"storage address slot setter with idempotency-only guard"*:

```
regex: \bif \(\s*[a-zA-Z_][a-zA-Z0-9_]* == [a-zA-Z_][a-zA-Z0-9_]*\s*\) revert [A-Z]
```

Applied.

## Step 4: Generalise Iteratively

Variant searches:

| Abstraction | Command | Hits |
|---|---|---|
| Any setter with `X = _new` preceded only by `if (X == _new) revert` | `grep -rn "revert BridgeAlreadySet\|AlreadySet" src/` | 1 (original) + 1 in MintBurnWrapper.sol:42 (error decl) |
| State-variable setters with `onlyOwner` that lack a companion clear-first check | manual enumeration below | see table |
| Single-step role rotation pattern | | |

**All `onlyOwner` / admin setters in scope — generalisation table:**

| Setter | Pre-existing value check | Emits a "cleared"/"revoked" event on overwrite? |
|---|---|---|
| `MintBurnWrapper.authorizeBridge` (src/MintBurnWrapper.sol:95) | Idempotency only | ❌ — **the L-01 case** |
| `MintBurnWrapper.revokeBridge` (src/MintBurnWrapper.sol:108) | Requires `bridge != 0` + `bridge == _bridge` | ✅ correct |
| `TokenMigration.setMigrationExpiry` (src/TokenMigration.sol:96) | `>` comparison (monotonic) | ✅ emits `MigrationExpirySet(old, new)` — consistent |
| `TelcoinV3.grantRole/revokeRole` | inherited OZ — emits `RoleGranted`/`RoleRevoked` | ✅ standard pattern |
| `OApp.setPeer(eid, peer)` (inherited) | overwrites silently; emits `PeerSet(eid, peer)` | ⚠️ same pattern as L-01 but accepted LayerZero convention |
| `OApp.setDelegate(addr)` (inherited) | overwrites silently; emits `DelegateSet(addr)` | ⚠️ same pattern as L-01 but accepted LayerZero convention |
| `TelcoinBridge.transferOwnership` / `Ownable2Step._transferOwnership` | two-step pending→accept; emits `OwnershipTransferStarted` + `OwnershipTransferred` | ✅ correct |

### Variants confirmed

**V-1 (L-01 original):** `MintBurnWrapper.authorizeBridge` overwrite. Classified **Low** (observability).

**V-2 (NEW candidate):** `OApp.setPeer(eid, peer)` inherited by both bridges, emits only `PeerSet(eid, peer)` on overwrite — no `PeerRevoked(eid, oldPeer)`. This is the same pattern.

Verification: `grep -rn "emit PeerSet" lib/LayerZero-v2/packages/layerzero-v2/evm/oapp/`:

```
lib/LayerZero-v2/packages/layerzero-v2/evm/oapp/contracts/oapp/OAppCore.sol
```

Reading the source:

```solidity
// lib/.../OAppCore.sol (OApp)
function setPeer(uint32 _eid, bytes32 _peer) public virtual onlyOwner {
    _setPeer(_eid, _peer);
}
function _setPeer(uint32 _eid, bytes32 _peer) internal virtual {
    peers[_eid] = _peer;
    emit PeerSet(_eid, _peer);
}
```

Confirmed: same pattern — overwrite silently, emit only `PeerSet`. This is LayerZero platform behaviour inherited by TelcoinBridge + NativeBridge.

**Assessment of V-2:** Because this is inherited LZ library behaviour (not custom Telcoin code), the fix would have to be either:
- (a) wrap `setPeer` in a Telcoin override that requires `peers[eid] == 0` (breaks LZ operational upgrade paths)
- (b) accept the LZ convention and document it externally

Severity: **Info** (same class as L-01). Designation: **VA-1 (new, minor)**.

**V-3 (NEW candidate):** `OApp.setDelegate(addr)` — overwrite silently. Same class; same LZ-inherited. **Info**. Designation: **VA-2**.

### Variants ruled out

Ownable2Step transfer: ruled out — two-step pattern already enforced.
grantRole/revokeRole: ruled out — OZ emits paired events.
setMigrationExpiry: ruled out — emits both old and new in `MigrationExpirySet(old, new)`, making the transition unambiguous even though it's a single-event emit.

## Step 5: Results

| # | Variant | Severity | Status |
|---|---|---|---|
| V-1 | `authorizeBridge` overwrite | Low | Existing L-01 — confirmed |
| V-2 | `setPeer` overwrite (inherited) | Info | **VA-1 (new)** — LZ platform convention; recommend documentation |
| V-3 | `setDelegate` overwrite (inherited) | Info | **VA-2 (new)** — LZ platform convention; recommend documentation |

## Stop criterion

Generalising further (to any `X = _new; emit XSet(_new)` pattern) would match most OZ setter-emits (which are conventionally accepted), producing an FP rate > 50%. Stop here per variant-analysis skill Step 4 guidance.
