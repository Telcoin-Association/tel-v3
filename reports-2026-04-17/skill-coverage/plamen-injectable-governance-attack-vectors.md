# Plamen injectable/governance-attack-vectors — Coverage

**References finding L-01.**

Governance attack-vector inventory:

| Vector | Status |
|---|---|
| Admin key compromise → full protocol drain | Standard trust assumption; multisig + Ownable2Step mitigations |
| Backdoor role grant | DEFAULT_ADMIN_ROLE can grant MINTER/BURNER to any address — expected governance capability |
| Silent role rotation without event | ⚠️ L-01: `authorizeBridge` overwrites without `BridgeRevoked` for the old bridge |
| Timelock bypass | N/A — no timelock in scope (multisig is the sole gate) |
| Governance-initiated rug | `rescueBurn` can burn any wallet → governance must be fully trusted |
| Proposal censorship / vote buying | N/A — no on-chain voting |
| Emergency-pause griefing by admin | Documented — admin can pause indefinitely, but bridge is key infrastructure; pause is the intended emergency knob |

Main recommendation tied to L-01: force the two-step revoke-then-authorize flow, or emit a `BridgeRevoked(oldBridge)` when overwriting.
