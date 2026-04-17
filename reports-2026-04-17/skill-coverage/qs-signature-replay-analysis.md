# qs_skills/signature-replay-analysis — Coverage

**Checked — N/A.**

No signature-verified entry points in scope. No `ecrecover`, no EIP-712, no ERC-2612 `permit`, no meta-transactions. `grep -rn "ecrecover\|EIP712\|permit\|_PERMIT_TYPEHASH\|domainSeparator" src/` returns no hits.

(Note: LayerZero V2 DVN signatures are validated inside the LZ endpoint, not inside in-scope contracts.)
