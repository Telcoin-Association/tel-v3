# Archethect/sc-auditor — callback-grief — Coverage

**Referenced by finding: I-06.**

`NativeBridge._credit` (inherited from `lib/…/NativeOFTAdapter.sol:106-119`) uses `payable(_to).call{value: _amountLD}("")`. If `_to` is a contract whose `receive`/`fallback` reverts or consumes too much gas, the `lzReceive` tx reverts — LayerZero will retry indefinitely, the bridged amount is stuck in-flight on LZ's side. The sender has already burned the source-chain TEL.

No in-scope fix — this is inherited LayerZero platform behaviour. Surfaced as I-06 and recommended frontend documentation.

No other callback surfaces in scope (no ERC-777 hooks, no ERC-721 receiver, no custom callback interfaces).
