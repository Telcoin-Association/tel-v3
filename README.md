# OldToken to Telcoin V3 Migration

## Overview

This project implements a migration system from OldToken (2 decimals) to Telcoin V3 (18 decimals) tokens at a 1:1 exchange rate using CREATE3 for deterministic deployment.

## Contract Features

### New Token (TelcoinV3)

- ERC-20 compliant token with 18 decimals
- Total supply: 100 billion tokens
- Minted on demand by the migration contract (no pre-funding required)
- Role-based access: `MINTER_ROLE`, `BURNER_ROLE`, `PAUSER_ROLE`, `UNPAUSER_ROLE`
- Pause only blocks transfers between non-zero addresses; mints and burns remain active

### Migration Contract

- **1:1 exchange rate** with automatic decimal conversion (2 → 18)
- **Mint-based**: mints TelcoinV3 directly; does not hold a pre-funded token reserve
- **Whole-balance migration**: `migrate()` exchanges the caller's entire OldToken balance in one call
- **OldToken sent permanently to burn address** (0x000000000000000000000000000000000000dEaD)
- **Pausable** by owner for emergency situations
- **Time-bounded**: migrations revert at or after `migrationExpiry`
- **Ownable2Step**: ownership transfers require acceptance by the new owner
- **Owner functions:**
  - Pause/unpause migrations
  - Extend migration expiry via `setMigrationExpiry()`
  - Recover accidentally sent tokens via `recoverERC20(destination, tokenAddress, amount)`

### TelcoinBridge

- LayerZero V2 OApp for cross-chain TelcoinV3 transfers
- Burn-and-mint model: burns on source chain, mints on destination chain
- **Ownable2Step**: ownership transfers require acceptance; `renounceOwnership()` is permanently disabled
- **Owner functions:**
  - Pause/unpause bridge
  - Rescue accidentally sent tokens via `rescueTokens(token, amount)`
  - Configure LayerZero delegate via `setDelegate()`

## Deployment Instructions

### Prerequisites

1. Install Foundry: https://book.getfoundry.sh/getting-started/installation
2. Set up environment variables:

```bash
export PRIVATE_KEY="private-key"
export RPC_URL="ethereum-rpc-url"
export ETHERSCAN_API_KEY="etherscan-api-key" # For verification
```

### Step 1: Update OldToken Address

Edit the deployment script and replace the placeholder with OldToken token address:

```solidity
address constant OLDTOKEN_ADDRESS = 0x... // old token address
```

### Step 2: Deploy Contracts

Run the deployment script:

```bash
# Deploy with random salts
forge script script/DeployScript.s.sol:DeployScript --rpc-url $RPC_URL --broadcast --verify

# Or deploy with custom salts for more control
forge script script/DeployScript.s.sol:DeployWithCustomSalt --rpc-url $RPC_URL --broadcast --verify --sig "run(string,string)" "my-telcoin-v3-salt" "my-migration-salt"
```

### Step 3: Verify Deployment

After deployment, verify:

1. TelcoinV3 total supply matches chain allocation (up to 100B tokens, 10^29 base units)
2. Migration contract has `MINTER_ROLE` on TelcoinV3
3. Migration contract has correct OldToken and TelcoinV3 addresses
4. `migrationExpiry` is set to the intended deadline

### Step 4: Test Migration (Optional)

Test with a small amount first:

```bash
# Run tests
forge test -vvv

# Test on testnet first
forge script script/DeployScript.s.sol:DeployScript --rpc-url $TESTNET_RPC_URL --broadcast
```

## Usage Guide

### For Users

1. **Approve** the migration contract to spend your entire OldToken balance
2. **Call `migrate()`** — no arguments required; migrates your entire OldToken balance
3. **Receive** TelcoinV3 tokens automatically (OldToken balance × 10^16)

Example using Etherscan:

1. Go to OldToken token contract
2. Call `approve(migrationAddress, yourFullBalance)`
3. Go to Migration contract
4. Call `migrate()`

### For Owner/Admin

#### Pause Migrations

```solidity
migration.pause() // Stop all migrations
migration.unpause() // Resume migrations
```

#### Extend Migration Window

```solidity
migration.setMigrationExpiry(newTimestamp) // Must be greater than current expiry
```

#### Recover Accidentally Sent Tokens

```solidity
migration.recoverERC20(destination, tokenAddress, amount)
```

## Key Calculations

- **OldToken (2 decimals):** 100B = 10,000,000,000.00 = 10^13 base units
- **Telcoin V3 (18 decimals):** 100B = 100,000,000,000.000000000000000000 = 10^29 base units
- **Conversion multiplier:** 10^16 (to convert from 2 to 18 decimals)

### Example Migration

- User has: 1,000 OldToken (2 decimals) = 100,000 base units
- User receives: 1,000 Telcoin V3 (18 decimals) = 1,000,000,000,000,000,000,000 base units

## Security Considerations

1. **Reentrancy Protection**: Contract uses OpenZeppelin's ReentrancyGuard
2. **Pausable**: Owner can pause in case of emergency
3. **Immutable Token Addresses**: Token addresses cannot be changed after deployment
4. **Access Control**: Critical functions restricted to owner only
5. **Safe Math**: Solidity 0.8+ automatic overflow protection

## Gas Estimates

- Migration transaction: ~100,000 gas
- Deployment: ~2,000,000 gas (both contracts)

## Addresses (After Deployment)

Update these after deployment:

```
OldToken Token: 0x... (existing)
Telcoin V3 Token: 0x... (new)
Migration Contract: 0x...
```

## Testing

Run the full test suite:

```bash
# Run all tests
forge test

# Run specific test
forge test --match-test testMigration -vvv

# Gas report
forge test --gas-report
```

## CREATE3 Benefits

Using CREATE3 provides:

- **Deterministic addresses** before deployment
- **Cross-chain same addresses** if using same salt
- **Deployment order independence** between Telcoin V3 and migration contracts

## Support

For issues or questions:

1. Check contract events for migration history
2. Use read functions to check balances and rates
3. Ensure sufficient gas for transactions (recommend 150,000 gas limit)

## License

MIT

## Foundry

**Foundry is a blazing fast, portable and modular toolkit for Ethereum application development written in Rust.**

Foundry consists of:

- **Forge**: Ethereum testing framework (like Truffle, Hardhat and DappTools).
- **Cast**: Swiss army knife for interacting with EVM smart contracts, sending transactions and getting chain data.
- **Anvil**: Local Ethereum node, akin to Ganache, Hardhat Network.
- **Chisel**: Fast, utilitarian, and verbose solidity REPL.

## Documentation

https://book.getfoundry.sh/

## Usage

### Build

```shell
$ forge build
```

### Test

```shell
$ forge test
```

### Format

```shell
$ forge fmt
```

### Gas Snapshots

```shell
$ forge snapshot
```

### Anvil

```shell
$ anvil
```

### Deploy

```shell
$ forge script script/Counter.s.sol:CounterScript --rpc-url <RPC_URL> --private-key <PRIVATE_KEY>
```

### Cast

```shell
$ cast <subcommand>
```

### Help

```shell
$ forge --help
$ anvil --help
$ cast --help
```
