# qs_skills/external-call-safety — Coverage

**Checked — clean.**

External calls enumerated:

| Site | Target | Safety |
|---|---|---|
| `TokenMigration.migrate` L84 | `oldToken.safeTransferFrom` | SafeERC20, CEI-compliant (state update before call) |
| `TokenMigration.migrate` L87 | `telcoinV3.mint` (ours) | Own contract, reentrancy-guarded caller |
| `TokenMigration.recoverERC20` L120 | `tokenContract.safeTransfer` | SafeERC20, onlyOwner |
| `TelcoinV3.rescueTokens` L88 | `IERC20.safeTransfer` | SafeERC20 |
| `MintBurnWrapper.mint/burn` | `token.mint/burn` (TelcoinV3) | Trusted own contract |
| `TelcoinBridge.rescueTokens` | `IERC20.safeTransfer` | SafeERC20 |
| `NativeBridge.rescueTokens` | same | SafeERC20 |
| `NativeBridge._credit` (inherited) | `payable(_to).call{value:}("")` | Failure → revert CreditFailed (→ I-06 for grief note) |
| OFTCore inbound through `endpoint.send(...)` | LZ endpoint | Trusted platform |

No unchecked low-level call return values. All fungible transfers use SafeERC20 or have explicit success checks.
