# Archethect/sc-auditor — semantic-drift — Coverage

Semantic-drift look-fors: spec vs implementation mismatches, stale code paths, comments that lie.

Identified:

- **I-03**: `ITelcoinBridge.sol` is semantically drifted — defines `bridge()`/`quote()`, contract exposes `send()`/`quoteSend()`.
- **L-01**: README says "Single Active Bridge; replacing a bridge requires `revokeBridge` + `authorizeBridge`" but code allows one-step overwrite.
- Comments audit: NatSpec generally accurate. One minor: `MintBurnWrapper.mint` returns bool docs say "Always true — reverts on failure"; code confirms this.

See `plamen-niche-semantic-consistency.md` for the full spec-vs-code matrix.
