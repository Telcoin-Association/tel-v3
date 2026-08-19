# TEL Migration — Integrator Guide

This guide explains how to integrate the TEL v2 → TEL v3 token migration into your own platform or UI: how the migration works, which contracts are involved, and the on-chain checks your integration should perform before and after executing a migration.

## Overview

Telcoin is migrating from the legacy TEL token ("TEL v2", 2 decimals) to a new token ("TEL v3", 18 decimals).

- **Exchange rate is 1:1 in whole tokens.** Because decimals change from 2 to 18, base units are converted by a factor of `10^16` (e.g. `100,000` v2 base units = 1,000.00 TEL → `1,000 × 10^18` v3 base units).
- **Migration runs on Ethereum, Polygon, and Base** — each chain has its own legacy TEL contract and its own migration contracts.
- **Migration is one-way and irreversible.** There is no path from TEL v3 back to TEL v2.
- **There are no fees** beyond gas.

## The Two Phases

Migration runs in two sequential phases, backed by two different contracts:

### Phase 1 — [`TokenMigration`](https://github.com/Telcoin-Association/tel-v3/blob/main/src/TokenMigration.sol) (time-limited window)

A migration window (initially 365 days, extendable by governance). The caller's **entire TEL v2 balance** is migrated in a single call: the contract escrows the legacy tokens and mints the equivalent TEL v3 directly to the caller. Partial migration is not supported in this phase — `migrate()` takes no amount argument and always converts the caller's full balance.

### Phase 2 — [`MigrationVault`](https://github.com/Telcoin-Association/tel-v3/blob/main/src/MigrationVault.sol) (long-tail migration)

After the Phase 1 window closes, the remaining TEL v3 supply is deposited into a pre-funded vault. Late holders swap TEL v2 for TEL v3 at the same 1:1 rate until the vault's reserves are depleted. Unlike Phase 1, the vault supports **arbitrary amounts** and an explicit **recipient address**.

## Contract Addresses

| Contract | Ethereum | Polygon | Base |
|---|---|---|---|
| TEL v2 (legacy) | `0x467Bccd9d29f223BcE8043b84E8C8B282827790F` | `0xdF7837DE1F2Fa4631D716CF2502f8b230F1dcc32` | `0x09bE1692ca16e06f536F0038fF11D1dA8524aDB1` |
| TEL v3 | `0x7E13B43065380aCdeC1c2d138c579cbBbafA0731` | `0x7E13B43065380aCdeC1c2d138c579cbBbafA0731` | `0x7E13B43065380aCdeC1c2d138c579cbBbafA0731` |
| TokenMigration (Phase 1) | _TBA_ | _TBA_ | _TBA_ |
| MigrationVault (Phase 2) | _TBA_ | _TBA_ | _TBA_ |

TEL v3 is deployed at the **same address on every chain** (deterministic CREATE3 deployment); only the legacy TEL address differs per chain. TokenMigration and MigrationVault addresses will be published in the repo's per-chain deployment files: [`deployments/ethereum.json`](https://github.com/Telcoin-Association/tel-v3/blob/main/deployments/ethereum.json), [`deployments/polygon.json`](https://github.com/Telcoin-Association/tel-v3/blob/main/deployments/polygon.json), [`deployments/base.json`](https://github.com/Telcoin-Association/tel-v3/blob/main/deployments/base.json).

Source code: [github.com/Telcoin-Association/tel-v3](https://github.com/Telcoin-Association/tel-v3) — see [`src/TelcoinV3.sol`](https://github.com/Telcoin-Association/tel-v3/blob/main/src/TelcoinV3.sol), [`src/TokenMigration.sol`](https://github.com/Telcoin-Association/tel-v3/blob/main/src/TokenMigration.sol), and [`src/MigrationVault.sol`](https://github.com/Telcoin-Association/tel-v3/blob/main/src/MigrationVault.sol).

## Determining the Active Phase

Do not hardcode the phase — derive it from on-chain state:

```solidity
bool phase1Active = !migration.migrationClosed()
    && block.timestamp < migration.migrationExpiry()
    && !migration.paused();
```

If Phase 1 is not active, use the `MigrationVault` (Phase 2), provided it holds sufficient TEL v3 reserves (see below). Note that `migrationExpiry` can be **extended** by governance, so re-read it rather than caching a date. Each chain has its own contract instances, so perform these checks per chain — expiry and pause state are not guaranteed to be identical across Ethereum, Polygon, and Base.

## Phase 1 Integration — `TokenMigration`

### Relevant interface

```solidity
function migrate() external returns (uint256 amountNewToken); // migrates caller's FULL v2 balance
function getAmountOut(uint256 amountIn) external pure returns (uint256); // amountIn * 1e16
function migrationExpiry() external view returns (uint256);
function migrationClosed() external view returns (bool);
function paused() external view returns (bool);

event TokensMigrated(address indexed user, uint256 amount); // amount = TEL v3 minted
```

### Steps

1. **Approve**: `telV2.approve(tokenMigration, balance)` — the allowance must cover the wallet's full TEL v2 balance at execution time.
2. **Execute**: call `migrate()` from the wallet. TEL v2 is transferred from the `msg.sender` and TEL v3 is minted to `msg.sender` — it cannot be redirected to another address in this phase.

### Pre-flight checks

Verify all of the following before submitting, and treat any failure as "do not submit":

```
migrationClosed() == false
block.timestamp < migrationExpiry()
paused() == false
telV2.balanceOf(wallet) > 0
telV2.allowance(wallet, tokenMigration) >= telV2.balanceOf(wallet)
```

### Post-execution verification

- Expected TEL v3 received: `getAmountOut(v2Balance)` = `v2Balance * 10^16`.
- Confirm via the `TokensMigrated(wallet, amount)` event in the receipt, or by checking that the wallet's TEL v3 balance increased by exactly that amount and its TEL v2 balance is now `0`.

## Phase 2 Integration — `MigrationVault`

### Relevant interface

```solidity
function migrate(address recipient, uint256 amountIn) external returns (uint256 amountOut);
function previewMigrate(uint256 amountIn) external view returns (uint256 amountOut);
function getReserves() external view returns (uint256 oldReserve, uint256 newReserve);
function paused() external view returns (bool);

event Migrated(address indexed sender, address indexed recipient, uint256 amountIn, uint256 amountOut);
```

### Steps

1. **Approve**: `telV2.approve(migrationVault, amountIn)`.
2. **Execute**: call `migrate(recipient, amountIn)`. Any amount can be migrated (no full-balance requirement), and TEL v3 is transferred from the vault's reserves to `recipient` — which may differ from the sender.

### Pre-flight checks

```
paused() == false
amountIn > 0
previewMigrate(amountIn) > 0
newReserve >= previewMigrate(amountIn)   // from getReserves()
telV2.allowance(wallet, migrationVault) >= amountIn
```

### Post-execution verification

- Expected TEL v3 received: `previewMigrate(amountIn)` (for the 2 → 18 decimal pair this is exactly `amountIn * 10^16`).
- Confirm via the `Migrated(sender, recipient, amountIn, amountOut)` event or the recipient's TEL v3 balance delta.

## Additional Integration Notes

- **Update your token configuration.** TEL v3 is a new contract at a new address with **18 decimals** (v2 has 2). Deposit detection, withdrawal processing, balance display, and any amount parsing must be updated accordingly.
- **Pausability.** Both contracts can be paused by Telcoin governance in an emergency. Handle a `paused() == true` state (or an `EnforcedPause` revert) by retrying later, not by failing over to the other contract.
- **TEL v3 supports modern approvals.** The new token implements EIP-2612 (`permit`) and EIP-3009 (`transferWithAuthorization` / `receiveWithAuthorization`) with EIP-1271 smart-contract-wallet support, which you may want to leverage for gasless flows after migration.
- **Events for reconciliation.** Index `TokensMigrated` (Phase 1) and `Migrated` (Phase 2) to reconcile migrated amounts against your internal ledger.

## Support

For integration questions, open an issue on the [tel-v3 repository](https://github.com/Telcoin-Association/tel-v3) or contact the Telcoin Association through official channels.
