# Plamen evm/cross-chain-message-integrity — Coverage

**Checked — references findings I-05, I-06; no new issues.**

Inbound-message integrity gate:

1. `OAppReceiver.lzReceive` (lib/LayerZero-v2/.../OAppReceiver.sol:95-110) verifies `msg.sender == endpoint` AND `peers[srcEid] == _origin.sender`. Both gates must pass or revert `OnlyEndpoint` / `OnlyPeer`.
2. Internal `_lzReceive` in TelcoinBridge + NativeBridge adds `whenNotPaused` wrapper.
3. `OFTCore._lzReceive` decodes the message via `OFTMsgCodec`, extracts `toAddress` from the first 32 bytes (`_message.sendTo().bytes32ToAddress()`) and `amountSD` from the next 8 bytes. No free-form payload decoding — fixed format.
4. `_credit` then mints / pays to `toAddress`.

Peer configuration is `onlyOwner`-gated via `setPeer`. No peer-spoofing vector in-scope.

**Composition message (`_message.isComposed()`):** routes to `endpoint.sendCompose` with the same `toAddress`. No custom compose handler in TelcoinBridge / NativeBridge, so lzCompose spoofing (Pashov #5) is not applicable.

Finding I-05 notes that the 100 B cap is enforced per-chain; cross-chain aggregate can temporarily exceed 100 B while messages are in-flight. Discussed as trust-assumption.
