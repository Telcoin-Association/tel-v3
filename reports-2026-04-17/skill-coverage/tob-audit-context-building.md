# trailofbits/skills — audit-context-building — Coverage

**Methodology applied** — ultra-granular function review of the three new bridge-triad contracts:

### MintBurnWrapper (src/MintBurnWrapper.sol)

- **constructor(address _token, address _owner)**: sets `Ownable(_owner)` and stores `token = IERC20Mintable(_token)`. Reverts `ZeroAddress` on `_token == 0`. **Missing**: no explicit zero-check on `_owner` (OZ `Ownable` reverts internally on zero — OK).
- **mint(address _to, uint256 _amount)**: `onlyBridge`, calls `token.mint`, emits `BridgeMinted`. Event emits AFTER external call — reentrancy-events FP (see fp-check).
- **burn(address _from, uint256 _amount)**: `onlyBridge`, calls `token.burn`, emits `BridgeBurned`. Same FP reasoning.
- **authorizeBridge(address _bridge)**: `onlyOwner`. Zero-check + idempotency check. **Does not force revoke-first** (L-01).
- **revokeBridge(address _bridge)**: `onlyOwner`. Zero-bridge check + address-match check. Correct.
- **renounceOwnership**: disabled.

### TelcoinBridge (src/TelcoinBridge.sol)

- **constructor**: wires MintBurnOFTAdapter (token, minterBurner, endpoint, delegate). Sets `Ownable(_delegate)`.
- **approvalRequired**: returns `true` — hardcoded signal to users.
- **send(...)**: whenNotPaused, delegates to `_send`. Does not validate msg.value (OFTCore's `_lzSend` consumes it via endpoint; excess refunded to `_refundAddress`).
- **_lzReceive(...)**: whenNotPaused override of OFTCore's `_lzReceive`. Inherited peer+endpoint check via OAppReceiver.lzReceive.
- **rescueTokens**: onlyOwner, zero-checks, SafeERC20.
- **pause/unpause**: onlyOwner.
- **transferOwnership**: override disambiguates Ownable ↔ Ownable2Step inheritance. Uses Ownable2Step's two-step flow.
- **renounceOwnership**: disabled.

### NativeBridge (src/NativeBridge.sol)

- **constructor(_endpoint, _delegate)**: `NativeOFTAdapter(18, _endpoint, _delegate), Ownable(_delegate)`.
- **receive()**: open to all senders; emits `ReserveFunded(msg.sender, msg.value)`. No state beyond balance.
- **send(...)**: `public payable override whenNotPaused`, delegates to `super.send(...)` which validates `msg.value == nativeFee + removeDust(amount)` and calls `_send`.
- **_lzReceive(...)**: whenNotPaused override of NativeOFTAdapter's `_lzReceive`.
- **rescueTokens**: onlyOwner, zero-checks — ERC-20 only (not native — → I-01).
- **pause/unpause**: onlyOwner.
- **transferOwnership / renounceOwnership**: like TelcoinBridge.

Full coverage.
