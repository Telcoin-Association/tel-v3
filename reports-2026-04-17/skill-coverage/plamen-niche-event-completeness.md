# Plamen niche/event-completeness — Coverage

**References findings I-04, L-01.**

Event audit:

| Action | Event emitted |
|---|---|
| TokenMigration.migrate | `TokensMigrated(user, amount)` ✅ |
| TokenMigration.setMigrationExpiry | `MigrationExpirySet(oldExpiry, newExpiry)` ✅ |
| TokenMigration.recoverERC20 | `StuckTokensRecovered(token, to, amount)` ✅ |
| TokenMigration.pause/unpause | OZ `Paused(account)` / `Unpaused(account)` ✅ |
| TelcoinV3.mint | OZ `Transfer(0, to, amount)` — generic |
| TelcoinV3.burn | OZ `Transfer(from, 0, amount)` — generic |
| TelcoinV3.rescueBurn | OZ `Transfer(from, 0, amount)` — **identical to burn; no distinguishing event → I-04** |
| TelcoinV3.rescueTokens | OZ `Transfer(this, to, amount)` |
| TelcoinV3.grantRole/revokeRole | OZ `RoleGranted`/`RoleRevoked` ✅ |
| TelcoinV3.pause/unpause | OZ `Paused`/`Unpaused` ✅ |
| MintBurnWrapper.authorizeBridge | `BridgeAuthorized(bridge)` — emitted even on silent overwrite → **L-01** |
| MintBurnWrapper.revokeBridge | `BridgeRevoked(bridge)` ✅ |
| MintBurnWrapper.mint/burn | `BridgeMinted/BridgeBurned(bridge, from/to, amount)` ✅ |
| TelcoinBridge.send | `OFTSent(guid, dstEid, from, amountSent, amountRecv)` ✅ |
| TelcoinBridge._lzReceive | `OFTReceived(guid, srcEid, to, amountRecv)` ✅ |
| NativeBridge.receive | `ReserveFunded(funder, amount)` ✅ |
| NativeBridge.send/lzReceive | inherited OFTSent/OFTReceived ✅ |
| Bridges.rescueTokens | — no custom event ⚠️ minor |
| Bridges.pause/unpause | OZ `Paused`/`Unpaused` ✅ |

Gaps: I-04 (rescueBurn), L-01 (BridgeAuthorized silently overwrites).
