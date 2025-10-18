# GMUNY to nGMUNY Migration

## Overview
This project implements a migration system from GMUNY (2 decimals) to nGMUNY (18 decimals) tokens at a 1:1 exchange rate using CREATE3 for deterministic deployment.

## Contract Features

### nGMUNY Token
- ERC-20 compliant token with 18 decimals
- Total supply: 100 billion tokens
- Initial mint to migration contract upon deployment

### Migration Contract
- **1:1 exchange rate** with automatic decimal conversion (2 → 18)
- **Pausable** by owner for emergency situations
- **GMUNY tokens locked permanently** in the contract after migration
- **Owner functions:**
  - Pause/unpause migrations
  - Withdraw remaining nGMUNY tokens
  - Recover stuck GMUNY tokens (optional emergency function)
  - Recover other accidentally sent tokens

## Deployment Instructions

### Prerequisites
1. Install Foundry: https://book.getfoundry.sh/getting-started/installation
2. Set up your environment variables:
```bash
export PRIVATE_KEY="your-private-key"
export RPC_URL="your-ethereum-rpc-url"
export ETHERSCAN_API_KEY="your-etherscan-api-key" # For verification
```

### Step 1: Update GMUNY Address
Edit the deployment script and replace the placeholder with your actual GMUNY token address:
```solidity
address constant GMUNY_ADDRESS = 0x... // Your GMUNY token address
```

### Step 2: Deploy Contracts
Run the deployment script:
```bash
# Deploy with random salts
forge script script/DeployScript.s.sol:DeployScript --rpc-url $RPC_URL --broadcast --verify

# Or deploy with custom salts for more control
forge script script/DeployScript.s.sol:DeployWithCustomSalt --rpc-url $RPC_URL --broadcast --verify --sig "run(string,string)" "my-ngmuny-salt" "my-migration-salt"
```

### Step 3: Verify Deployment
After deployment, verify:
1. nGMUNY total supply is 100B tokens (10^29 base units)
2. Migration contract holds all nGMUNY tokens
3. Migration contract has correct GMUNY and nGMUNY addresses

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
1. **Approve** the migration contract to spend your GMUNY tokens
2. **Call migrate()** with the amount of GMUNY you want to exchange
3. **Receive** nGMUNY tokens automatically (amount × 10^16)

Example using Etherscan:
1. Go to GMUNY token contract
2. Call `approve(migrationAddress, amount)`
3. Go to Migration contract
4. Call `migrate(amount)`

### For Owner/Admin

#### Pause Migrations
```solidity
migration.pause() // Stop all migrations
migration.unpause() // Resume migrations
```

#### Withdraw Remaining nGMUNY
After migration period ends:
```solidity
migration.withdrawRemainingNGMUNY(treasuryAddress)
```

#### Recover Stuck Tokens
If needed:
```solidity
migration.recoverStuckGMUNY(recoveryAddress) // For GMUNY
migration.recoverOtherTokens(tokenAddress, recoveryAddress) // For other tokens
```

## Key Calculations

- **GMUNY (2 decimals):** 100B = 10,000,000,000.00 = 10^13 base units
- **nGMUNY (18 decimals):** 100B = 100,000,000,000.000000000000000000 = 10^29 base units
- **Conversion multiplier:** 10^16 (to convert from 2 to 18 decimals)

### Example Migration
- User has: 1,000 GMUNY (2 decimals) = 100,000 base units
- User receives: 1,000 nGMUNY (18 decimals) = 1,000,000,000,000,000,000,000 base units

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
GMUNY Token: 0x... (existing)
nGMUNY Token: 0x... (new)
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
- **Deployment order independence** between nGMUNY and migration contracts

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

-   **Forge**: Ethereum testing framework (like Truffle, Hardhat and DappTools).
-   **Cast**: Swiss army knife for interacting with EVM smart contracts, sending transactions and getting chain data.
-   **Anvil**: Local Ethereum node, akin to Ganache, Hardhat Network.
-   **Chisel**: Fast, utilitarian, and verbose solidity REPL.

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
$ forge script script/Counter.s.sol:CounterScript --rpc-url <your_rpc_url> --private-key <your_private_key>
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
