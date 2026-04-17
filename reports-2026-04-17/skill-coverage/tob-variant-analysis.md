# trailofbits/skills — variant-analysis — Coverage

**Methodology applied** — for each finding, the codebase was searched for similar patterns to confirm the issue is isolated, not systemic.

| Finding | Variant search | Result |
|---|---|---|
| L-01 `authorizeBridge` silent overwrite | `grep -rn 'function authorize' src/` | Only one `authorizeBridge` (MintBurnWrapper.sol:95). No other "authorize*" setter with the same slot-overwrite pattern |
| I-01 NativeBridge no native-withdraw | `grep -rn 'receive(' src/ && grep -rn 'withdraw\|rescueNative' src/` | Only NativeBridge has `receive()`; no payable `withdraw*` anywhere. TelcoinBridge has no `receive()`. Isolated |
| I-02 rescueTokens blocked while paused | `grep -rn 'rescueTokens\|recoverERC20' src/` | TelcoinV3 rescueTokens has the override-update pause guard. TelcoinBridge/NativeBridge rescueTokens do not suffer from this (no pause guard on their transfer paths). Isolated to TelcoinV3 |
| I-03 stale interface | `find src/interfaces -name '*.sol'` | Two interfaces: IERC20Mintable (used), ITelcoinBridge (stale). Isolated |
| I-04 rescueBurn no event | `grep -rn 'emit \|event ' src/TelcoinV3.sol` | No dedicated burn-related events beyond OZ Transfer — consistent with standard ERC-20 design. rescueBurn is the intentional emergency exit; only event gap |
| I-05 per-chain cap | `grep -rn 'MIGRATION_SUPPLY_CAP' src/` | Only TelcoinV3.sol has the cap. Each chain has its own instance. Global aggregation is off-chain |
| I-06 native push failure | `grep -rn 'call{value' lib/.../NativeOFTAdapter.sol` | Single `_credit` location; variant — no |
| I-07 CREATE3 salt collision | `grep -rn 'deploy\|create3' script/` | CREATE3 usage is limited to the deployment scripts — single surface |

No systemic pattern variants found. Each finding is isolated.
