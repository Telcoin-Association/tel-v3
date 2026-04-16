# TelcoinBridge Frontend Integration Guide

This document covers testnet integration for bridging TEL across chains. The mesh currently consists of two satellite chains (Ethereum Sepolia and Base Sepolia) using `TelcoinBridge`. Support for `NativeBridge` on the Adiri testnet (TelcoinNetwork) will be added once that network launches.

## Bridge Architecture

There are two bridge contracts in the mesh:

| Contract | Chain | Role |
|---|---|---|
| `TelcoinBridge` | Satellite chains (Ethereum, Base, etc.) | Burns TEL on send, mints TEL on receive |
| `NativeBridge` | TelcoinNetwork (Adiri testnet — TBD) | Locks native TEL on send, unlocks on receive |

Both implement the same OFT interface (`send`, `quoteSend`, `quoteOFT`) and use the same message encoding — only the `msg.value` requirement and approval flow differ between them, as described below.

## Contract Addresses

> Full deployment files are also available at `deployments/<chain-name>.json` in the repo root.

### Ethereum Sepolia

| Contract | Address |
|---|---|
| `TelcoinV3` | `0x5666F1FA6735312Ea738005dD2E799c60b401f3e` |
| `TelcoinBridge` | `0xE0F8c41A778b660442bA509F041f24ad2261DA8C` |
| `MintBurnWrapper` | `0x6832DdA7dCCF0338c9cC5C29277709b24496777F` |

### Base Sepolia

| Contract | Address |
|---|---|
| `TelcoinV3` | `0x5666F1FA6735312Ea738005dD2E799c60b401f3e` |
| `TelcoinBridge` | `0xE0F8c41A778b660442bA509F041f24ad2261DA8C` |
| `MintBurnWrapper` | `0x6832DdA7dCCF0338c9cC5C29277709b24496777F` |

### TelcoinNetwork / Adiri (TBD)

| Contract | Address |
|---|---|
| `NativeBridge` | TBD once Adiri testnet launches |

## LayerZero Endpoint IDs (EIDs)

EIDs identify chains within the LayerZero network. They are **not** EVM chain IDs.

| Chain | EID |
|---|---|
| Ethereum Sepolia | `40161` |
| Base Sepolia | `40245` |
| Adiri (TelcoinNetwork testnet) | TBD |

For a full list: https://docs.layerzero.network/v2/deployments/chains

---

## TelcoinBridge — Satellite Chains

Used on Ethereum Sepolia and Base Sepolia. TEL is an ERC20 on these chains.

### The 3-Step Flow

#### Step 1 — Approve `MintBurnWrapper`

`TelcoinBridge` burns tokens via `MintBurnWrapper`. Because `TelcoinV3.burn()` enforces an allowance check, the user must approve `MintBurnWrapper` as the spender — **not** the bridge itself.

```js
await telcoinV3.approve(mintBurnWrapperAddress, amountWei)
```

You can check whether approval is required programmatically:
```js
const required = await telcoinBridge.approvalRequired() // always true for TelcoinBridge
```

#### Step 2 — Get a fee quote

Call `quoteSend()` to get the LayerZero messaging fee. The fee is paid in native ETH and passed as `msg.value` in Step 3.

```js
const sendParam = buildSendParam(dstEid, recipientAddress, amountWei, options)
const { nativeFee, lzTokenFee } = await telcoinBridge.quoteSend(sendParam, false)
// lzTokenFee will be 0
```

#### Step 3 — Send

```js
await telcoinBridge.send(
  sendParam,
  { nativeFee, lzTokenFee },
  refundAddress,       // receives any excess native fee
  { value: nativeFee }
)
```

---

## NativeBridge — TelcoinNetwork (Adiri — TBD)

> **Note:** NativeBridge will be deployed once the Adiri testnet (TelcoinNetwork) launches. This section documents the integration so the frontend can be prepared in advance.

On TelcoinNetwork, TEL is the **native gas token** rather than an ERC20. `NativeBridge` locks native TEL when bridging out and unlocks it when bridging in from satellite chains.

### Key Differences from TelcoinBridge

| | TelcoinBridge (satellite) | NativeBridge (TelcoinNetwork) |
|---|---|---|
| Token type | ERC20 | Native gas token |
| Approval required | Yes — approve `MintBurnWrapper` | No |
| `msg.value` | LZ fee only | LZ fee **+ bridge amount** |

### The 2-Step Flow

There is no approval step — native tokens don't use ERC20 allowances.

#### Step 1 — Get a fee quote

```js
const { nativeFee, lzTokenFee } = await nativeBridge.quoteSend(sendParam, false)
```

#### Step 2 — Send

`msg.value` must equal `nativeFee + amountWei`. The contract validates this and will revert if they don't match.

```js
await nativeBridge.send(
  sendParam,
  { nativeFee, lzTokenFee },
  refundAddress,
  { value: nativeFee + amountWei }  // fee AND amount combined
)
```

---

## Shared: Building `SendParam`

Both bridges use the same `SendParam` struct:

```ts
interface SendParam {
  dstEid: number        // destination chain EID (see table above)
  to: bytes32           // recipient address, zero-padded to 32 bytes
  amountLD: bigint      // amount in local decimals (18 for TEL)
  minAmountLD: bigint   // minimum acceptable after dust removal — set 0 or apply slippage
  extraOptions: bytes   // LZ executor options (see below)
  composeMsg: bytes     // leave as "0x" — unused
  oftCmd: bytes         // leave as "0x" — unused in standard OFT
}
```

Encoding `to` as `bytes32` in ethers v6:
```js
const to = ethers.zeroPadValue(recipientAddress, 32)
```

---

## Shared: Building `extraOptions`

`extraOptions` tells the LZ executor how much gas to provide on the destination for `lzReceive`. Use the official utilities package:

```bash
npm install @layerzerolabs/lz-v2-utilities
```

```js
import { Options } from "@layerzerolabs/lz-v2-utilities"

const options = Options.newOptions()
  .addExecutorLzReceiveOption(200_000, 0) // 200k gas limit, 0 extra native airdrop
  .toHex()
```

`200_000` gas is sufficient for a standard TEL bridge. If the destination runs out of gas, the message will need to be retried via the LayerZero endpoint — do not set this too low.

---

## Shared: Dust / Decimal Rounding

Both bridges use `sharedDecimals = 6`. Amounts are truncated to the nearest `1e12` wei before the message is sent — the last 12 decimal places are zeroed. For example, `1.000000000001 TEL` becomes `1.000000000000 TEL`.

Use `quoteOFT()` to show the user the exact amounts before they confirm:

```js
const [limit, feeDetails, oftReceipt] = await bridge.quoteOFT(sendParam)
// oftReceipt.amountSentLD  — exact amount debited from the user
// oftReceipt.amountReceivedLD — exact amount arriving on destination
```

Apply slippage tolerance using the quoted values:
```js
const minAmountLD = oftReceipt.amountReceivedLD * 99n / 100n // 1% tolerance
sendParam.minAmountLD = minAmountLD
```

---

## Shared: Events

### Source chain — `OFTSent`

```solidity
event OFTSent(
    bytes32 indexed guid,        // unique message ID — use this to track delivery
    uint32  dstEid,              // destination EID
    address indexed fromAddress, // sender
    uint256 amountSentLD,        // tokens burned/locked on source
    uint256 amountReceivedLD     // tokens to be minted/unlocked on destination
)
```

### Destination chain — `OFTReceived`

```solidity
event OFTReceived(
    bytes32 indexed guid,      // same GUID as OFTSent — links the two events
    uint32  srcEid,            // source EID
    address indexed toAddress, // recipient
    uint256 amountReceivedLD   // tokens minted/unlocked
)
```

---

## Tracking Message Delivery

After `send()` confirms, use the `guid` from `OFTSent` to track the message:

- **Testnet:** https://testnet.layerzeroscan.com/
- **Mainnet:** https://layerzeroscan.com/

States: `INFLIGHT` → `DELIVERED` (or `FAILED` if destination ran out of gas).

---

## Checking Bridge State

```js
const paused = await bridge.paused()
// if true, both send() and lzReceive() are blocked — surface an error to the user
```

---

## Complete Example — TelcoinBridge (ethers v6)

```js
import { ethers } from "ethers"
import { Options } from "@layerzerolabs/lz-v2-utilities"

async function bridgeTEL(signer, addresses, dstEid, recipient, amountWei) {
  const telcoinV3     = new ethers.Contract(addresses.telcoinV3,     ERC20_ABI,          signer)
  const telcoinBridge = new ethers.Contract(addresses.telcoinBridge, TELCOIN_BRIDGE_ABI, signer)

  // 1. Approve MintBurnWrapper
  await telcoinV3.approve(addresses.mintBurnWrapper, amountWei)

  // 2. Build params
  const options = Options.newOptions().addExecutorLzReceiveOption(200_000, 0).toHex()
  const sendParam = {
    dstEid,
    to: ethers.zeroPadValue(recipient, 32),
    amountLD: amountWei,
    minAmountLD: 0n,
    extraOptions: options,
    composeMsg: "0x",
    oftCmd: "0x"
  }

  // 3. Get exact amounts and apply slippage
  const [, , oftReceipt] = await telcoinBridge.quoteOFT(sendParam)
  sendParam.minAmountLD = oftReceipt.amountReceivedLD * 99n / 100n

  // 4. Get fee
  const { nativeFee } = await telcoinBridge.quoteSend(sendParam, false)

  // 5. Send
  const tx = await telcoinBridge.send(
    sendParam,
    { nativeFee, lzTokenFee: 0n },
    await signer.getAddress(),
    { value: nativeFee }
  )
  return await tx.wait()
}
```

## Complete Example — NativeBridge (ethers v6, TBD)

```js
import { ethers } from "ethers"
import { Options } from "@layerzerolabs/lz-v2-utilities"

async function bridgeNativeTEL(signer, addresses, dstEid, recipient, amountWei) {
  const nativeBridge = new ethers.Contract(addresses.nativeBridge, NATIVE_BRIDGE_ABI, signer)

  // 1. Build params (no approval needed — native token)
  const options = Options.newOptions().addExecutorLzReceiveOption(200_000, 0).toHex()
  const sendParam = {
    dstEid,
    to: ethers.zeroPadValue(recipient, 32),
    amountLD: amountWei,
    minAmountLD: 0n,
    extraOptions: options,
    composeMsg: "0x",
    oftCmd: "0x"
  }

  // 2. Get exact amounts and apply slippage
  const [, , oftReceipt] = await nativeBridge.quoteOFT(sendParam)
  sendParam.minAmountLD = oftReceipt.amountReceivedLD * 99n / 100n

  // 3. Get fee
  const { nativeFee } = await nativeBridge.quoteSend(sendParam, false)

  // 4. Send — msg.value = fee + amount
  const tx = await nativeBridge.send(
    sendParam,
    { nativeFee, lzTokenFee: 0n },
    await signer.getAddress(),
    { value: nativeFee + amountWei }  // combined
  )
  return await tx.wait()
}
```