# kadenzipfel/scv-scan#unchecked-return-values — Coverage

**Checked — not vulnerable because:**

- All ERC-20 interactions use `SafeERC20`'s `safeTransfer` / `safeTransferFrom` (src/TokenMigration.sol:84, 120; src/TelcoinV3.sol:88; src/TelcoinBridge.sol:101; src/NativeBridge.sol:96).
- `MintBurnWrapper.mint/burn` returns `(bool)` — callers (`MintBurnOFTAdapter._debit/_credit`) ignore the return and rely on revert-on-failure, which is the `IMintableBurnable` convention. The wrapper **always returns true and reverts on failure**, so this is safe by construction.
- `NativeBridge._credit` checks `(bool success, bytes memory data) = payable(_to).call{value:}("")` and reverts with `CreditFailed` — handled correctly.
