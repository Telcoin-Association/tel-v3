# trailofbits/skills — sharp-edges/lang-solidity — Coverage

**Checked — clean on Solidity-specific gotchas.**

- PUSH0 opcode usage: TelcoinV3/TokenMigration use Solidity 0.8.26 → emits PUSH0. Target chains (Ethereum, Polygon, Base, TelcoinNetwork) all support Shanghai+. Aderyn flagged this (L-5) — informational, not an issue on target chains.
- `abi.encodePacked` with dynamic types → `keccak256`: not used in hash contexts (only `keccak256("MINTER_ROLE")` etc. with single string literals).
- `delegatecall` into untrusted: not used.
- Assembly blocks in scope: `grep -rn 'assembly' src/` returns no hits.
- `tx.origin` in access control: not used.
- Arithmetic in `unchecked`: not used in scope.
- Re-initialisation via upgrade: not upgradeable.
- Fallback/receive asymmetry: NativeBridge has payable `receive()`; TelcoinBridge has neither `receive()` nor `fallback()` (so direct ETH transfers revert — correct for an OFT adapter whose only ETH path is `send(…)` with msg.value).
- Inheritance diamond: `TelcoinBridge` inherits `MintBurnOFTAdapter, Ownable2Step, Pausable`; `Ownable2Step` extends `Ownable`; both `transferOwnership`/`_transferOwnership` are explicitly overridden with multi-parent resolution (TelcoinBridge.sol:110-116, NativeBridge.sol:105-111). ✅ correctly disambiguated.
- `renounceOwnership` / `renounceRole`: explicitly disabled — addresses the "lose-admin-by-accident" trap.
- Integer division truncation: not used (migration is multiplication only; `totalOldTokenBurned()` is `totalMigrated / 1e16` which is always exact because `totalMigrated` is always a multiple of `1e16`).
