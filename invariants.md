# Token Migration Invariants
## TEL v2 to TEL v3 Migration System

### Executive Summary
This document defines the invariants and security properties for the TEL token migration system, facilitating the upgrade from TEL v2 (2 decimals) to TEL v3 (18 decimals) across Ethereum, Polygon, and Base chains.
The migration maintains a 1:1 value ratio while adjusting for decimal precision differences.

---

## System Overview

### Architecture Components
1. **OldToken (TEL v2)**: Existing ERC20 token with 2 decimal places
2. **NewToken (TEL v3)**: New ERC20 token with 18 decimal places
3. **TokenMigration Contract**: Facilitates the swap at a 1:1 ratio with decimal adjustment
4. **Governance Multisig**: Controls migration parameters and recovery functions

### Deployment Strategy
- Deterministic deployment using CREATE3 for consistent addresses across chains
- Chain-specific TEL v3 supply allocation:
  - Ethereum: ~65B TEL v3
  - Polygon: ~30B TEL v3
  - Base: ~5B TEL v3
  - Total: 100B TEL v3 (maintaining total supply parity with v2)

---

## Core Invariants

### I1: Supply Conservation
**Invariant**: The total circulating supply value remains constant during migration
```
∀ time t:
  circulating_supply_v2(t) * 10^2 + circulating_supply_v3(t) * 10^18
  = INITIAL_TOTAL_SUPPLY * 10^2
```

**Properties**:
- Total economic value is preserved
- No token creation or destruction of value occurs
- Only decimal representation changes

### I2: Decimal Conversion Correctness
**Invariant**: Migration maintains exact 1:1 value ratio with proper decimal adjustment
```
∀ migration m:
  newTokenAmount = oldTokenAmount * 10^16
  where 10^16 = 10^(18-2) = DECIMAL_MULTIPLIER
```

**Properties**:
- No rounding errors or precision loss
- Conversion factor is immutable (constant)
- Mathematical equivalence: `value_v2 * 10^2 == value_v3 * 10^18`

### I3: Migration Irreversibility
**Invariant**: Once tokens are migrated, the operation cannot be reversed
```
∀ user u, ∀ migration m:
  post(m): oldToken.balanceOf(BURN_ADDRESS) = pre(m).oldToken.balanceOf(BURN_ADDRESS) + amount
  AND newToken.balanceOf(u) = pre(m).newToken.balanceOf(u) + (amount * DECIMAL_MULTIPLIER)
```

**Properties**:
- Old tokens sent to burn address (0x000000000000000000000000000000000000dEaD)
- No mechanism exists to recover burned tokens
- Prevents double-spending and replay attacks

### I4: Migration Atomicity
**Invariant**: Each migration is atomic - either fully succeeds or fully fails
```
∀ migration m:
  success(m) → all state changes applied
  failure(m) → no state changes applied
```

**Properties**:
- Protected by ReentrancyGuard
- No partial migrations possible
- Transaction reverts on any failure condition

### I5: Balance Sufficiency
**Invariant**: Migration contract must have sufficient NewToken balance
```
∀ migration m:
  pre(m): newToken.balanceOf(migrationContract) ≥ requestedAmount * DECIMAL_MULTIPLIER
```

**Properties**:
- Migrations fail gracefully if insufficient NewToken available
- Contract cannot promise tokens it doesn't possess
- Explicit revert with `InsufficientContractBalance` error

---

## Security Invariants

### S1: Access Control
**Invariant**: Only authorized roles can perform privileged operations
```
onlyOwner functions:
  - pause()
  - unpause()
  - withdrawRemainingNewToken()
  - recoverERC20()
```

**Properties**:
- Owner is initially set to governance multisig
- Ownership transfers follow OpenZeppelin Ownable pattern
- No backdoor or emergency functions bypass ownership

### S2: Pausability Safety
**Invariant**: When paused, no migrations can occur
```
whenPaused → ∀ user u: migrate() reverts
```

**Properties**:
- Pause mechanism for emergency situations
- Only affects `migrate()` function
- Administrative functions remain accessible when paused

### S3: Token Recovery Constraints
**Invariant**: NewToken cannot be recovered via `recoverERC20`, but OldToken can be
```
∀ recoverERC20(dest, token, amount):
  token == address(newToken) → revert CannotRecoverProtectedToken
  token == address(oldToken) → transfer allowed
```

**Properties**:
- Prevents accidental recovery of migration reserves (NewToken)
- Allows recovery of mistakenly sent OldTokens for user support
- Recovered OldTokens can be migrated on behalf of users who made mistakes
- `withdrawRemainingNewToken` is the only way to recover NewToken
- Support mechanism: governance can recover accidentally sent OldTokens and help users complete migration

### S4: User Authorization
**Invariant**: Users must explicitly approve full balance for migration
```
∀ migration m by user u:
  oldToken.allowance(u, migrationContract) ≥ oldToken.balanceOf(u)
```

**Properties**:
- Prevents unauthorized token transfers
- Users maintain control until approval granted
- Clear user intent requirement

---

## Functional Invariants

### F1: Whole Balance Migration
**Invariant**: Each migration transfers user's entire OldToken balance
```
∀ user u calling migrate():
  post: oldToken.balanceOf(u) == 0
```

**Properties**:
- Simplifies user experience (one-click migration)
- Prevents partial migration confusion
- Reduces gas costs from multiple transactions

### F2: Burn Address Accumulation
**Invariant**: Burn address monotonically accumulates old tokens
```
∀ time t1 < t2:
  oldToken.balanceOf(BURN_ADDRESS, t2) ≥ oldToken.balanceOf(BURN_ADDRESS, t1)
```

**Properties**:
- Provides on-chain tracking of migrated amounts
- Burn address balance = total migrated old tokens
- No mechanism to decrease burn address balance

### F3: Contract Balance Monotonic Decrease
**Invariant**: Migration contract's NewToken balance only decreases (except initial funding)
```
Post-deployment: ∀ time t1 < t2:
  newToken.balanceOf(migrationContract, t2) ≤ newToken.balanceOf(migrationContract, t1)
```

**Properties**:
- No minting capability in migration contract
- Balance decreases through migrations or owner withdrawal
- Predictable reserve depletion

---

## Economic Invariants

### E1: No Value Extraction
**Invariant**: Migration process creates no economic profit or loss
```
∀ migration m:
  economic_value_in == economic_value_out
```

**Properties**:
- No fees charged for migration (besides gas)
- No slippage or spread
- Pure 1:1 value transfer

### E2: Cross-Chain Supply Distribution
**Invariant**: Sum of NewToken across all chains equals total supply exactly
```
supply_ethereum + supply_polygon + supply_base = 100B * 10^18
```

**Properties**:
- Each chain's migration contract funded with predetermined amount
- Approximate distribution: Ethereum ~65B, Polygon ~30B, Base ~5B (subject to final adjustment)
- Exact total supply of 100B TEL v3 maintained across all chains
- No cross-chain double-spending possible
- If one chain's migration contract depletes, users must bridge TEL v2 via native bridges to another chain
- Native bridges: Ethereum ↔ Polygon (native bridge), Ethereum ↔ Base (native bridge)

### E3: Unclaimed Token Recovery
**Invariant**: After migration period, unclaimed tokens recoverable by governance
```
After migration_end_time:
  governance can call withdrawRemainingNewToken()
  to recover: newToken.balanceOf(migrationContract)
```

**Properties**:
- Recovers value from lost/burned/unclaimed old tokens
- Funds partially allocated to governance treasury
- Some remainder reserved for extended claim period
- Approximately 1-year initial migration window (managed by Governance off-chain)
- Governance multisig determines allocation between treasury and extended claims

---

## State Transition Invariants

### ST1: State Consistency
**Invariant**: Contract state remains internally consistent
```
At any time t:
  totalOldTokenBurned() * DECIMAL_MULTIPLIER ≤ initialNewTokenBalance - remainingNewTokenBalance()
```

**Properties**:
- Burned tokens correspond to distributed new tokens
- No state corruption possible
- Verifiable through view functions

### ST2: Event Emission
**Invariant**: Every successful migration emits corresponding event
```
∀ successful migrate():
  emits TokensMigrated(user, amount)
```

**Properties**:
- Complete audit trail on-chain
- Off-chain monitoring capability
- Event arguments match state changes

---

## Implementation-Specific Invariants

### IM1: Immutable Token References
**Invariant**: Token contract addresses are immutable
```
oldToken == immutable address set at construction
newToken == immutable address set at construction
```

**Properties**:
- No token contract upgrade path
- Prevents address manipulation attacks
- Gas optimization through immutability

### IM2: Constant Decimal Multiplier
**Invariant**: DECIMAL_MULTIPLIER remains constant
```
DECIMAL_MULTIPLIER == 10^16 (constant)
```

**Properties**:
- Compile-time constant
- Cannot be modified post-deployment
- Ensures conversion consistency

### IM3: Fixed Burn Address
**Invariant**: BURN_ADDRESS is constant and well-known
```
BURN_ADDRESS == 0x000000000000000000000000000000000000dEaD (constant)
```

**Properties**:
- Industry-standard burn address
- Publicly verifiable
- No private key exists for this address

---

## Operational Invariants

### O1: Migration Window
**Invariant**: Migrations allowed only during active period
```
t < migration_end_time AND !paused → migrations allowed
t ≥ migration_end_time OR paused → migrations blocked
```

**Properties**:
- Clear timeline for users
- Governance decision point for recovery
- Approximately 1-year window planned

### O2: Multisig Governance
**Invariant**: All administrative functions require multisig approval
```
owner == multisig_wallet_address
```

**Properties**:
- No single point of failure
- Time-locked operations where applicable
- Transparent governance process

### O3: User Support Workflow
**Invariant**: Governance can assist users who mistakenly send OldTokens to migration contract
```
User mistake flow:
1. User accidentally sends OldToken to migration contract
2. User contacts support
3. Governance calls recoverERC20(supportWallet, oldToken, amount)
4. Support helps user approve and migrate tokens properly
```

**Properties**:
- Safety net for user errors
- Maintains user agency (they still must approve migration)
- Clear support process
- No ability to force migrations on behalf of users
- Only works for tokens sent to contract, not other mistakes

---

## Risk Considerations

### Known Limitations & Design Decisions
1. **Whole Balance Migration**: Users must migrate entire balance at once (intentional design)
2. **Migration Window Risk**: Users who do not migrate within timeframe will lose access to their tokens (intentional incentive mechanism)
3. **Irreversibility**: No mechanism to reverse migrations once completed
4. **Gas Costs**: Users bear gas costs for migration transaction
5. **Burn Address Usage**: OldToken sent to dead address (0xdEaD) as TEL v2 lacks native burn functionality
6. **Supply Distribution**: Slight variations possible between chains, users may need to bridge to chains with remaining liquidity

### Mitigation Strategies
1. **Clear Documentation**: Comprehensive user guides and warnings
2. **Sufficient Funding**: Ensure migration contracts have adequate reserves
3. **Monitoring**: Real-time tracking of migration progress and reserves
4. **Grace Period**: Consider extension mechanisms if needed
5. **Support Channels**: Dedicated assistance for migration issues
6. **Recovery Mechanism**: Governance can recover accidentally sent OldTokens to help users complete migration
7. **Extended Claims**: Portion of unclaimed TEL v3 reserved for late claims after initial window

---

## Audit Focus Areas

### High Priority
1. Decimal conversion mathematics and overflow protection
2. Reentrancy vulnerabilities in migration flow
3. Access control implementation and ownership transfers
4. Token recovery function restrictions
5. Cross-chain deployment consistency
6. **Code Review Note**: `recoverERC20` transfers entire balance instead of specified amount (line 135)

### Medium Priority
1. Event emission completeness and accuracy
2. Pause mechanism effectiveness
3. Error message clarity and gas optimization
4. View function accuracy

### Low Priority
1. Code formatting and documentation
2. Gas optimization opportunities
3. Future upgradeability considerations

---

## Axelar ITS Bridge Integration (TEL v3 Only)

### Overview
TEL v3 will be registered with Axelar's Interchain Token Service (ITS) to enable native mint/burn functionality across supported chains, replacing the lock/unlock mechanism used by native bridges for TEL v2.

### Bridge Architecture Invariants

#### AX1: Mint/Burn Mechanism
**Invariant**: TEL v3 uses native mint/burn for cross-chain transfers via Axelar ITS
```
∀ bridge operation b from chain_A to chain_B:
  burn(amount, chain_A) → mint(amount, chain_B)
```

**Properties**:
- No token lock/unlock pools required
- True supply movement between chains
- Eliminates bridge liquidity constraints
- Reduces systemic risk from bridge exploits

#### AX2: Total Supply Conservation Across Chains
**Invariant**: Sum of all TEL v3 tokens across ITS-connected chains remains constant
```
∀ time t:
  Σ(supply_chain_i) = 100B * 10^18
  where chain_i ∈ {Ethereum, Polygon, Base, ...future chains}
```

**Properties**:
- Burns on source chain always equal mints on destination chain
- No tokens created or destroyed in transit
- Atomic cross-chain supply adjustments

#### AX3: Bridge Authority Control
**Invariant**: Only Axelar ITS contracts can mint/burn TEL v3
```
∀ mint/burn operation:
  msg.sender == ITS_CONTRACT_ADDRESS → allowed
  msg.sender != ITS_CONTRACT_ADDRESS → revert
```

**Properties**:
- Centralized mint/burn authority through ITS
- No unauthorized supply manipulation
- Clear permission boundaries

### Operational Invariants

#### AXO1: Bridge Migration Timing
**Invariant**: Native bridges remain operational for TEL v2 during migration period
```
During migration_period:
  TEL_v2: uses native bridges (lock/unlock)
  TEL_v3: uses Axelar ITS (mint/burn)
  No direct bridge between v2 and v3
```

**Properties**:
- Users must migrate before bridging with new system
- Clear separation between legacy and new infrastructure
- Prevents confusion during transition period

#### AXO2: Chain Expansion Capability
**Invariant**: New chains can be added to TEL v3 ecosystem via ITS
```
∀ new chain c:
  ITS registration → mint/burn capability enabled
  Initial supply on c = 0 (supplied via bridging)
```

**Properties**:
- Flexible expansion to new chains
- No need for liquidity pre-funding
- Consistent integration pattern

### Security Considerations

#### AXS1: ITS Contract Verification
**Invariant**: All ITS contract addresses must be verified before integration
```
∀ chain:
  ITS_contract_address must be verified on official Axelar sources
  Contract code must match Axelar's audited implementation
```

**Properties**:
- Prevents integration with malicious contracts
- Ensures consistent security model
- Verifiable through Axelar's official channels

#### AXS2: Pause Mechanism Independence
**Invariant**: Migration pause does not affect ITS bridge operations
```
migration.paused() = true → ITS bridging continues functioning
ITS.paused() = true → migration continues functioning
```

**Properties**:
- Independent failure domains
- Granular control over different operations
- Prevents complete system lockup
