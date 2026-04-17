# trailofbits/skills — entry-point-analyzer — Coverage

**Methodology applied** — enumerated every external/public entry point.

### TelcoinV3

| Selector | Function | Auth | Pausable? |
|---|---|---|---|
| `mint(address,uint256)` | mint | MINTER_ROLE | no (by design) |
| `burn(address,uint256)` | burn | BURNER_ROLE + allowance | no |
| `rescueBurn(address,uint256)` | rescueBurn | DEFAULT_ADMIN_ROLE | no |
| `pause()` | pause | PAUSER_ROLE | — |
| `unpause()` | unpause | UNPAUSER_ROLE | — |
| `rescueTokens(address,uint256,address)` | rescueTokens | DEFAULT_ADMIN_ROLE | blocked while paused (I-02) |
| `renounceRole(bytes32,address)` | disabled | always reverts | — |
| All OZ ERC-20 / AccessControlEnumerable reads/writes | inherited | per OZ defaults | — |

### TokenMigration

| Selector | Auth |
|---|---|
| `migrate()` | public, whenNotPaused, reentrancy-guarded |
| `setMigrationExpiry(uint256)` | onlyOwner |
| `recoverERC20(address,address,uint256)` | onlyOwner |
| `pause()` / `unpause()` | onlyOwner |
| `transferOwnership(address)` / `acceptOwnership()` | Ownable2Step |
| `renounceOwnership()` | disabled |
| reads: `oldToken`, `telcoinV3`, `totalMigrated`, `totalOldTokenBurned`, `migrationExpiry`, `getAmountOut`, `paused`, `owner`, `pendingOwner` | public |

### MintBurnWrapper

| Selector | Auth |
|---|---|
| `mint(address,uint256)` / `burn(address,uint256)` | onlyBridge |
| `authorizeBridge(address)` / `revokeBridge(address)` | onlyOwner |
| Ownable2Step | standard |
| `renounceOwnership()` | disabled |

### TelcoinBridge

| Selector | Auth |
|---|---|
| `send(SendParam,MessagingFee,address)` | whenNotPaused |
| `lzReceive(Origin,bytes32,bytes,address,bytes)` | onlyEndpoint + onlyPeer (inherited) + whenNotPaused |
| `rescueTokens(address,uint256,address)` | onlyOwner |
| `pause()` / `unpause()` | onlyOwner |
| `setDelegate(address)` | onlyOwner (inherited from OApp) |
| `setPeer(uint32,bytes32)` | onlyOwner (inherited) |
| `setEnforcedOptions(EnforcedOptionParam[])` | onlyOwner |
| `setMsgInspector(address)` | onlyOwner |
| `setPreCrime(address)` | onlyOwner |
| `approvalRequired()` | pure → true |
| `transferOwnership` / `acceptOwnership` | Ownable2Step |
| `renounceOwnership` | disabled |

### NativeBridge

Same as TelcoinBridge **minus** `approvalRequired` (returns false by default — native), **plus** `receive() external payable` emitting `ReserveFunded`.

### Review

- No unauthenticated state-changing entry points outside `migrate()` (public by intent).
- `receive()` on NativeBridge is intentionally open.
- No `fallback()` anywhere.
- All state-changing entry points that shouldn't run during emergency are gated by `whenNotPaused` (migrate, send, _lzReceive).
- LZ admin config (`setPeer`, `setDelegate`, etc.) are all `onlyOwner`.
