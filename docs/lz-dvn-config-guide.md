# LayerZero V2 OApp DVN Configuration Guide

## Overview

This document explains how to configure the security stack for a LayerZero V2 OApp (Omnichain Application). Specifically, it covers:

- What DVNs and Executors are and why they matter
- What configuration calls are required and why
- The correct directionality of each config
- How to add new chain pathways

This was originally written in the context of **TelcoinBridge**, but the patterns apply to any LZ V2 OApp.

---

## Background: LayerZero V2 Security Model

When a message is sent cross-chain via LayerZero V2, it goes through the following lifecycle:

```
Sender → Source Endpoint → Message Library → DVN(s) → Executor → Destination Endpoint → OApp
```

| Component | Role |
|-----------|------|
| **Endpoint** | The core LZ V2 contract on each chain. Manages message routing and config. |
| **Message Library (SendUln302 / ReceiveUln302)** | The versioned library used to send/receive messages. Config is scoped per library. |
| **DVN (Decentralized Verifier Network)** | Off-chain nodes that watch source chain events and verify that a packet was sent before the destination chain can execute it. You pay DVNs on the **source** chain. |
| **Executor** | An off-chain relayer that calls `lzReceive` on the destination OApp once DVNs have verified the message. Paid on the **source** chain. |

Because DVNs and the Executor are paid on the **source chain**, their **addresses in the config always refer to source chain deployments**.

---

## Configuration Calls

For each directional pathway **A → B**, you must make the following calls:

### On Chain A (Source)

```solidity
// 1. Lock in the send library for this pathway
EndpointV2.setSendLibrary(OAppAddress, dstEid, sendLib302Address)

// 2. Set DVN + Executor config for messages leaving A toward B
EndpointV2.setConfig(OAppAddress, sendLib302Address, [
    SetConfigParam(dstEid, CONFIG_TYPE_ULN, abi.encode(UlnConfig)),        // DVN settings
    SetConfigParam(dstEid, CONFIG_TYPE_EXECUTOR, abi.encode(ExecutorConfig)) // Executor settings
])
```

### On Chain B (Destination)

```solidity
// 3. Lock in the receive library for this pathway
EndpointV2.setReceiveLibrary(OAppAddress, srcEid, receiveLib302Address, gracePeriod)

// 4. Set DVN config for messages arriving at B from A
EndpointV2.setConfig(OAppAddress, receiveLib302Address, [
    SetConfigParam(srcEid, CONFIG_TYPE_ULN, abi.encode(UlnConfig))  // DVN settings only
])
```

> **Note:** No Executor config is set on the receive side. The Executor only needs to be configured on the send side — it is the entity that initiates delivery to the destination.

---

## Why Configurations Are Set on Specific Chains

This is the most common source of confusion.

### Send Config — always on the source chain

The send config controls what DVNs and Executor are **paid** when a message leaves. These contracts are deployed on the source chain, so the config naturally lives there.

```
setConfig(srcBridge, srcSendLib, params using dstEid)
           ↑                              ↑
        on chain A                 targeting chain B
```

### Receive Config — always on the destination chain

The receive config tells the destination endpoint **which DVN signatures to accept** as valid verification before allowing execution. This verification logic runs on the destination chain.

```
setConfig(dstBridge, dstReceiveLib, params using srcEid)
           ↑                               ↑
        on chain B                  expecting messages from chain A
```

> A common mistake is setting the receive config on the source chain. This silently misconfigures the pathway — it would configure how chain A *receives* from chain B, not how chain B receives from chain A.

---

## Struct Definitions

### UlnConfig

```solidity
// @layerzerolabs/lz-evm-messagelib-v2/contracts/uln/UlnBase.sol

struct UlnConfig {
    uint64 confirmations;
    uint8 requiredDVNCount;
    uint8 optionalDVNCount;
    uint8 optionalDVNThreshold;
    address[] requiredDVNs;    // sorted ascending, no duplicates
    address[] optionalDVNs;    // sorted ascending, no duplicates
}
```

### ExecutorConfig

```solidity
// @layerzerolabs/lz-evm-messagelib-v2/contracts/SendLibBase.sol

struct ExecutorConfig {
    uint32 maxMessageSize; // max payload size in bytes
    address executor;      // executor contract on the source chain
}
```

> Always encode these as `abi.encode(struct)` rather than `abi.encode(field1, field2, ...)`. Tuple encoding can silently mismatch if struct layout changes across LZ versions, making "already configured" checks unreliable.

---

## Configuration Values — Choices and Rationale

### Block Confirmations: `1`

We use `1` confirmation for testnets. On mainnet, increase this to match the finality guarantees of the source chain (e.g., `15` for Ethereum post-merge).

### Required DVNs: `[LZ Labs DVN]`

We use the LayerZero Labs DVN as the sole required DVN on testnets because:

- It is the only DVN reliably deployed and operational across all LZ testnets
- Production deployments should use multiple DVNs (e.g., LZ Labs + Polyhedra) for defense-in-depth

### Optional DVNs: `[]`

None on testnet. On mainnet, optional DVNs provide resilience — messages can be verified by a threshold of optional DVNs even if a required one goes offline.

### Max Message Size: `10000` bytes

Default value. Sufficient for all current TelcoinBridge payloads (`address` + `uint256` = 64 bytes ABI-encoded). Can be tightened on mainnet to reduce attack surface.

### Grace Period: `0`

Passed to `setReceiveLibrary`. A value of `0` means the old receive library is invalidated immediately during a version migration. Acceptable for testnet. On mainnet, a non-zero grace period allows in-flight messages from the old library to be delivered before the switch takes effect.

---

## DVN and Executor Addresses

DVN, Executor, SendLib, and ReceiveLib addresses are **chain-specific**. Find them at:

- Protocol contracts: https://docs.layerzero.network/v2/deployments/deployed-contracts
- DVN addresses: https://docs.layerzero.network/v2/deployments/dvn-addresses

Contract addresses are stored in [`script/utils/Constants.sol`](../script/utils/Constants.sol).

### Current Testnet Addresses

> All testnets share the same Endpoint address: `0x6EDCE65403992e310A62460808c4b910D972f10f`

| Chain | EID | DVN | SendUln302 | ReceiveUln302 | Executor |
|-------|-----|-----|-----------|--------------|----------|
| Eth Sepolia | `40161` | `0x8eebf8b423B73bFCa51a1Db4B7354AA0bFCA9193` | `0xcc1ae8Cf5D3904Cef3360A9532B477529b177cCE` | `0xdAf00F5eE2158dD58E0d3857851c432E34A3A851` | `0x718B92b5CB0a5552039B593faF724D182A881eDA` |
| Base Sepolia | `40245` | `0xe1a12515F9AB2764b887bF60B923Ca494EBbB2d6` | `0xC1868e054425D378095A003EcbA3823a5D0135C9` | `0x12523de19dc41c91F7d2093E0CFbB76b17012C8d` | `0x8A3D588D9f6AC041476b094f97FF94ec30169d3D` |

---

## Adding a New Chain Pathway

To add a new chain to an existing OApp:

**1. Add constants to [`script/utils/Constants.sol`](../script/utils/Constants.sol)**

```solidity
address constant NEW_CHAIN_LZ_ENDPOINT_V2     = 0x...;
uint16  constant NEW_CHAIN_LZ_CHAIN_ID_V2     = 4xxxx;
address constant NEW_CHAIN_LZ_DVN             = 0x...;
address constant NEW_CHAIN_LZ_EXECUTOR        = 0x...;
address constant NEW_CHAIN_LZ_SEND_ULN_302    = 0x...;
address constant NEW_CHAIN_LZ_RECEIVE_ULN_302 = 0x...;
```

**2. Add a chain entry to [`script/testnet/ConfigureAllBridges.s.sol`](../script/testnet/ConfigureAllBridges.s.sol)**

```solidity
allChains.push(ChainConfig({
    chainName:  "new-chain",
    rpcUrl:     vm.envString("NEW_CHAIN_RPC_URL"),
    eid:        NEW_CHAIN_LZ_CHAIN_ID_V2,
    endpoint:   NEW_CHAIN_LZ_ENDPOINT_V2,
    dvn:        NEW_CHAIN_LZ_DVN,
    sendLib:    NEW_CHAIN_LZ_SEND_ULN_302,
    receiveLib: NEW_CHAIN_LZ_RECEIVE_ULN_302,
    executor:   NEW_CHAIN_LZ_EXECUTOR
}));
```

The script automatically configures all `N*(N-1)` directional pathways between every chain pair — no other changes needed.

**3. Add a chain entry to [`script/testnet/DeployAllToTestnet.s.sol`](../script/testnet/DeployAllToTestnet.s.sol)**

```solidity
allChains.push(NetworkData({
    chainName:     "new-chain",
    rpc_url:       vm.envString("NEW_CHAIN_RPC_URL"),
    lz_endpoint:   NEW_CHAIN_LZ_ENDPOINT_V2,
    chainId:       NEW_CHAIN_LZ_CHAIN_ID_V2,
    legacyTel:     address(0),
    initialSupply: 100_000_000 ether,
    mainChain:     false
}));
```

**4. Run the scripts in order**

```bash
# Deploy bridge contracts to the new chain (and set peers on all chains)
forge script script/testnet/DeployAllToTestnet.s.sol --multi --broadcast --verify -vvvv

# Configure DVN pathways between all chain pairs
forge script script/testnet/ConfigureAllBridges.s.sol --multi --broadcast -vvvv
```

**Checklist**

- [ ] Constants added to `Constants.sol`
- [ ] Chain entry added to `ConfigureAllBridges.s.sol`
- [ ] Chain entry added to `DeployAllToTestnet.s.sol`
- [ ] `DeployAllToTestnet` executed (deploys contracts + sets peers)
- [ ] `ConfigureAllBridges` executed (configures DVN pathways)
- [ ] Bridge verified on [LayerZero Scan](https://testnet.layerzeroscan.com/)

---

## Common Mistakes

| Mistake | Symptom | Fix |
|---------|---------|-----|
| Setting receive config on the source chain | Config call succeeds but messages never verify on destination | Set receive config on the **destination** chain using destination's `receiveLib` and source EID |
| Using source chain DVN address in receive config | Config call succeeds but verification fails | Receive config must use the **destination chain's** DVN address |
| Encoding config as a loose tuple instead of a struct | `getConfig` hash never matches, "already set" checks always false | Use `abi.encode(struct)` not `abi.encode(field1, field2, ...)` |
| Only configuring one direction | One-way bridge works, reverse direction silently fails | A→B and B→A are independent — both must be configured |
| Skipping `setSendLibrary` / `setReceiveLibrary` | `setConfig` succeeds but config is applied to the wrong (default) library | Always call `setSendLibrary`/`setReceiveLibrary` before `setConfig` |
| Passing empty options (`0x0003`) to `bridge()` | Quote reverts with DVN price feed error | Options must include at least one executor `lzReceive` gas option (see `BridgeTokens.s.sol`) |
