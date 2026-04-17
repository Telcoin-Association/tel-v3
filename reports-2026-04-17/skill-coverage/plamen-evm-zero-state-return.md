# Plamen evm/zero-state-return — Coverage

**Checked — clean.**

Zero-state paths verified:

- `TokenMigration.migrate` with `oldToken.balanceOf(msg.sender) == 0` reverts `InvalidAmount` (src/TokenMigration.sol:77). Does not spuriously mint 0.
- `TokenMigration.recoverERC20` with `balance == 0 || amount == 0 || amount > balance` reverts `InvalidAmount` (src/TokenMigration.sol:117). No-op protection.
- `TelcoinV3.rescueTokens` with `_amount == 0` reverts `ZeroAmount` (src/TelcoinV3.sol:87).
- `TelcoinBridge/NativeBridge.rescueTokens` with `_amount == 0` revert `ZeroAmount`.
- OFTCore `send` with `_sendParam.amountLD = 0` does not revert but emits OFTSent(amountSent=0, amountReceived=0); burns/locks 0. Pays LZ fee but performs no token-flow change — acceptable (user error, no accounting risk).

No path returns silently with zero-state — all zero-value operations either revert or are provably no-ops.
