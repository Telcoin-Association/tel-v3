# Plamen evm/token-flow-tracing — Coverage

**Checked — clean.**

Token flows traced:

1. **Migration (TokenMigration.migrate)**: user → [OldToken transferFrom] → BURN_ADDRESS (0xdEaD). User → [TelcoinV3.mint by migration as MINTER] → user. Net: oldToken decreases by `bal`, TelcoinV3 increases by `bal * 1e16`.
2. **Satellite send (TelcoinBridge.send)**: user → [TelcoinV3 approve(MintBurnWrapper, amt)] → [wrapper.burn(user, amt) triggered by OFTCore._debit] → supply on this chain drops by `amt`. LZ message emitted.
3. **Satellite receive (TelcoinBridge._lzReceive)**: [wrapper.mint(to, amt) triggered by OFTCore._credit] → supply on this chain rises by `amt`.
4. **TN send (NativeBridge.send)**: user → locks `amt` wei in `address(this).balance` (msg.value). LZ message emitted.
5. **TN receive (NativeBridge._lzReceive)**: bridge → [payable(to).call{value:amt}] → recipient. Reserve drops by `amt`.
6. **rescueBurn (TelcoinV3.rescueBurn)**: admin → [_burn(from, amt)] → supply drops.
7. **rescueTokens / recoverERC20**: admin → [safeTransfer] → destination.

No hidden token flows (e.g. no airdrop/mint paths, no sweep paths with dual accounting). Symmetric burn↔mint on bridges; lock↔credit on NativeBridge. Decimal exactness preserved via `_removeDust` dust-stripping and integer multiplier.
