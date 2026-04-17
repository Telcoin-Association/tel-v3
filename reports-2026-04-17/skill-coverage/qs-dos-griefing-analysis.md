# qs_skills/dos-griefing-analysis — Coverage

**Checked — one LayerZero-platform issue noted (I-06).**

| Vector | Status |
|---|---|
| Unbounded loop in state-changing function | None in scope |
| Loop over user-controllable data | None |
| Push transfer to contract whose fallback reverts | I-06 on `NativeBridge._credit` |
| Gas-stipend starvation | N/A — no `.transfer`/`send` with 2300 gas stipend |
| Memory expansion bomb | N/A — all calldata is fixed-format SendParam / LZ Origin |
| Storage slot exhaustion | N/A — AccessControlEnumerable role set growth is bounded by governance grants |
| Out-of-gas on deep inheritance | Verified OK — `forge build --sizes` shows all contracts under 24 576 B runtime |
| Pause-based griefing by admin | Documented trust — admin multisig can pause forever (expected) |

Only I-06 (native push may revert on contract recipients) is a non-trivial DoS vector, and it's inherited from LayerZero's platform.
