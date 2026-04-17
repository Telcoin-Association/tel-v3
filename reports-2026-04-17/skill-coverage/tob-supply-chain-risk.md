# trailofbits/skills — supply-chain-risk-auditor — Coverage

**Checked.**

Dependencies (submodules):

| Module | Version / Ref |
|---|---|
| `lib/openzeppelin-contracts` | Submodule-pinned commit |
| `lib/LayerZero-v2` | Submodule-pinned commit |
| `lib/layerzero-devtools` | Submodule-pinned commit |
| `lib/create3` | Submodule-pinned commit |
| `lib/forge-std` | Submodule-pinned commit |

Reproducibility: deterministic via `foundry.lock`. No npm / pip dependencies. No dependency injection at runtime.

Risk surface:
- OpenZeppelin 5.x — well-audited.
- LayerZero V2 — audited; their endpoint/DVN security is a platform trust root.
- 0xsequence CREATE3 — small library, reviewed in `lib/create3/contracts/Create3.sol`. See I-07.

No unpinned dependencies, no `*` semver, no postinstall scripts. Supply-chain risk is bounded to the pinned commits.
