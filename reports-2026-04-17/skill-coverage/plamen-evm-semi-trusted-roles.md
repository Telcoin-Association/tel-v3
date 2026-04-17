# Plamen evm/semi-trusted-roles — Coverage

**Checked — clean.** Roles enumerated:

**TelcoinV3 roles (AccessControlEnumerable):**

| Role | Expected holder(s) | Can |
|---|---|---|
| DEFAULT_ADMIN_ROLE | Governance multisig | grantRole, revokeRole, rescueBurn, rescueTokens |
| MINTER_ROLE | TokenMigration (chain-dependent), MintBurnWrapper | mint |
| BURNER_ROLE | MintBurnWrapper | burn (with allowance) |
| PAUSER_ROLE | Governance | pause |
| UNPAUSER_ROLE | Governance | unpause |

`renounceRole` permanently disabled (src/TelcoinV3.sol:100) — no accidental role loss. `grantRole`/`revokeRole` gated to admin via OZ. Roles are enumerable so governance tooling can list current holders. See L-01 note: a compromised `authorizeBridge` could route bridge access to a malicious contract, but owner is trusted multisig.

**Ownable2Step roles on TokenMigration, TelcoinBridge, NativeBridge, MintBurnWrapper:**

Two-step transfer (`transferOwnership` → `acceptOwnership`). `renounceOwnership` permanently disabled on all four. No orphan-admin risk.
