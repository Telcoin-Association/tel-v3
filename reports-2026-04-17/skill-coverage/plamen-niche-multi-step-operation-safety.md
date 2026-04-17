# Plamen niche/multi-step-operation-safety — Coverage

**Checked — mostly clean; L-01 arises here.**

Multi-step operations in scope:

| Flow | Step 1 | Step 2 | Safety |
|---|---|---|---|
| Ownership transfer | `transferOwnership(new)` sets pendingOwner | `acceptOwnership()` by new owner | ✅ Ownable2Step, no no-owner window |
| Bridge rotation | `revokeBridge(old)` → bridge = 0 | `authorizeBridge(new)` → bridge = new | ⚠️ **L-01**: `authorizeBridge(new)` when bridge != 0 silently overwrites, skipping step 1 |
| Migration | `approve(migration, bal)` | `migrate()` | ✅ front-runnable? No — migrate only operates on msg.sender's balance |
| Bridging | `approve(wrapper, amt)` | `send(…)` | ✅ allowance consumed exactly |
| Expiry extension | `setMigrationExpiry(newExpiry)` only accepts greater-than-current | — | ✅ monotonic |

See L-01 for the bridge-rotation concern.
