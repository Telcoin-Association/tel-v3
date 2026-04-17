# qs_skills/reentrancy-pattern-analysis — Coverage

**Checked — clean.**

Reentrancy patterns surveyed:

| Variant | In-scope surface | Mitigation |
|---|---|---|
| Classic same-function reentry | `TokenMigration.migrate` | `ReentrancyGuardTransient` + trusted external targets |
| Cross-function reentry | Migration ↔ rescueERC20 / pause | No shared state with `migrate` that a reentrant call could manipulate mid-transaction |
| Read-only reentry | `TokenMigration.totalOldTokenBurned()` / `totalMigrated` | View only, no effect on reentry attacker |
| ERC-777 `tokensReceived` hook | N/A | TelcoinV3 is OZ ERC-20 (no hooks) |
| ERC-721 `onERC721Received` | N/A | No NFTs |
| Reentry via native push | `NativeBridge._credit` `payable(_to).call{value:…}("")` | `_lzReceive` cannot be reentered — gated by `onlyEndpoint`. Attacker's fallback cannot recursively invoke `_lzReceive` |
| Reentry via native receive | `NativeBridge.receive()` only accepts ETH & emits event; no state-change beyond balance | Cannot reenter bridge logic |
| ERC-20 transferFrom reentry | `SafeERC20` + reentrancy guard | OldToken is v2 no-hook ERC-20 |

No reentrancy exploit path.
