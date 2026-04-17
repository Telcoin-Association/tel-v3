# kadenzipfel/scv-scan#reentrancy — Coverage

**Checked — not vulnerable because:**

- `TokenMigration.migrate` uses `ReentrancyGuardTransient` (src/TokenMigration.sol:73).
- External calls in `migrate` are to:
  - `oldToken.safeTransferFrom` (src/TokenMigration.sol:84) — target is legacy Telcoin V2 (src/legacy/Telcoin.sol), standard ERC-20, no hooks.
  - `telcoinV3.mint` (src/TokenMigration.sol:87) — target is TelcoinV3 (src/TelcoinV3.sol:46), no hooks.
- `MintBurnWrapper.mint/burn` (src/MintBurnWrapper.sol:70,82) — gated by `onlyBridge` and calls only `TelcoinV3.mint`/`burn`. No hooks.
- `TelcoinBridge` / `NativeBridge` inherit OFTCore which calls the LayerZero endpoint (`_lzSend`) — the endpoint is trusted and does not call back into the bridge during `send`.
- `NativeBridge._credit` (inherited from NativeOFTAdapter.sol:112) uses `call{value:}("")` to recipient — this is a **push** of native TEL; a malicious recipient could reenter `lzReceive`, but `lzReceive` is only callable by the endpoint (`OAppReceiver.lzReceive` reverts if `msg.sender != endpoint`). Reentrancy into `_credit` itself would require the recipient to be the endpoint, which is absurd.

No classic, read-only, cross-function, or cross-contract reentrancy path found.
