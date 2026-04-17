# Plamen niche/semantic-consistency-audit — Coverage

**References finding I-03.**

Semantic mismatches checked:

- `ITelcoinBridge.sol` defines `bridge()`, `quote()`, `rescueTokens(address,uint256)`, events `BridgeSent`/`BridgeReceived` — NONE of which are implemented by `TelcoinBridge`. The actual contract exposes `send()`, `quoteSend()`, `rescueTokens(address,uint256,address)` and emits OFTCore's `OFTSent`/`OFTReceived`. The interface is stale — → I-03.

- README.md vs code — cross-check:

  | README claim | Code reality | Match? |
  |---|---|---|
  | "Minted on demand by the migration contract (no pre-funding required)" | `migrate()` calls `telcoinV3.mint` requiring MINTER_ROLE | ✅ |
  | "Hard supply cap: 100 billion tokens" | `MIGRATION_SUPPLY_CAP = 100_000_000_000 ether` | ✅ |
  | "burn() requires prior approval" | `_spendAllowance(from, msg.sender, amount)` | ✅ |
  | "rescueBurn gated by DEFAULT_ADMIN_ROLE" | `onlyRole(DEFAULT_ADMIN_ROLE)` | ✅ |
  | "renounceRole disabled" | Overridden to revert | ✅ |
  | "sharedDecimals = 6" | Inherited default from OFTCore | ✅ |
  | "Single authorized bridge via `address public bridge`" | Confirmed | ✅ (but overwrite possible → L-01) |
  | "`setPeer` updates — no token governance action required" | Wrapper management decoupled from TelcoinV3 roles | ✅ |
  | "sharedDecimals = 6, matching all satellite" | ✅ both NativeBridge and TelcoinBridge use OFTCore default 6 | ✅ |
  | "receive() for reserve top-ups emits ReserveFunded" | Confirmed | ✅ |
