# Plamen niche/spec-compliance-audit — Coverage

**References I-07.**

Spec sources: `README.md`, `invariants.md`, `docs/bridge-integration.md`.

Each spec invariant cross-checked against code — match verdicts recorded in `plamen-niche-semantic-consistency.md`. All documented invariants match implementation with three exceptions:

1. **I-07**: CREATE3 deployment script (`script/MigrationDeployment.s.sol`) uses a salt that does not include `msg.sender` / deployer EOA. If the `Create3Utils` factory (test/utils/Create3Utils.sol:21) is publicly callable, a frontrunner can deploy to the same address first.
2. **I-03**: `ITelcoinBridge.sol` interface is stale; README refers to OFT `send()` / `quoteSend()` but the interface file still lists `bridge()` / `quote()`.
3. **L-01**: README documents a two-step rotate (`revokeBridge` + `authorizeBridge`) but the contract permits a one-step rotate that silently overwrites.

Other invariants (supply cap, role decoupling, burn-approval requirement, sharedDecimals=6, Ownable2Step, pausability semantics) all match.
