# Plamen evm/centralization-risk — Coverage

**Checked — documented trust assumption.**

Single trust root: governance multisig owns all four non-token contracts and holds `DEFAULT_ADMIN_ROLE` on TelcoinV3. The multisig can:

- Mint up to 100 B TEL per chain via `grantRole(MINTER_ROLE)` to any address (or by pointing `MintBurnWrapper` at a malicious bridge — L-01).
- Pause / unpause any contract indefinitely.
- `rescueBurn` any wallet (TelcoinV3 DEFAULT_ADMIN_ROLE).
- Rescue any non-protocol ERC-20 (`rescueTokens`).

Mitigations present:

- Ownable2Step on all four non-token contracts (no single-step owner transfer, `renounceOwnership` disabled).
- `renounceRole` permanently disabled on TelcoinV3.
- Wrapper is the ONLY BURNER_ROLE holder → removes bypass paths.
- AccessControlEnumerable → governance tooling can enumerate current role holders.

Residual risk: standard multisig-compromise catastrophic outcome. Mentioned in report as I-05 (per-chain cap, not global).
