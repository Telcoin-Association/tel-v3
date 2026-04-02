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

**Invariant**: The total whole-token count across v2 and v3 remains constant during migration

```
∀ time t:
  whole_v2_remaining(t) + whole_v3_minted_via_migration(t) == INITIAL_TOTAL_SUPPLY_whole
  i.e. (oldToken.totalSupply() - totalOldTokenBurned) / 1
       + totalMigrated / DECIMAL_MULTIPLIER
       == INITIAL_TOTAL_SUPPLY_whole
```

**Properties**:

- Total economic value is preserved (1 whole v2 == 1 whole v3 in value)
- No token creation or destruction of value occurs through migration
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
  AND telcoinV3.balanceOf(u) = pre(m).telcoinV3.balanceOf(u) + (amount * DECIMAL_MULTIPLIER)
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

### I5: Minter Role Requirement

**Invariant**: The migration contract must hold `MINTER_ROLE` on TelcoinV3 for migrations to succeed

```
∀ migration m:
  pre(m): telcoinV3.hasRole(MINTER_ROLE, migrationContract) == true
```

**Properties**:

- Migration is mint-based; the contract holds no TelcoinV3 reserve
- If `MINTER_ROLE` is revoked, all subsequent `migrate()` calls revert
- Role is granted at deployment and managed by the TelcoinV3 `DEFAULT_ADMIN_ROLE`

---

## Security Invariants

### S1: Access Control

**Invariant**: Only authorized roles can perform privileged operations

```
onlyOwner functions (TokenMigration):
  - pause()
  - unpause()
  - setMigrationExpiry()
  - recoverERC20()

onlyOwner functions (TelcoinBridge):
  - pause()
  - unpause()
  - rescueTokens()
  - setDelegate() (inherited from OApp)
  - transferOwnership() / acceptOwnership()
```

**Properties**:

- Owner is initially set to governance multisig
- Both contracts use Ownable2Step: `transferOwnership()` sets a pending owner, transfer only finalizes when the new owner calls `acceptOwnership()`
- `renounceOwnership()` is disabled on TelcoinBridge (reverts with `CannotRenounceOwnership`)
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

**Invariant**: `recoverERC20` can recover any token accidentally sent to the migration contract

```
∀ recoverERC20(dest, token, amount):
  dest == address(0) OR dest == BURN_ADDRESS → revert ZeroAddress
  token == address(0) → revert ZeroAddress
  amount == 0 OR amount > balance → revert InvalidAmount
  otherwise → transfer allowed
```

**Properties**:

- Migration is mint-based; the contract holds no TelcoinV3 reserve, so recovery of TelcoinV3 is not a concern in normal operation
- Allows recovery of mistakenly sent OldTokens or any other ERC20 for user support
- Recovered OldTokens can be re-migrated on behalf of users who made mistakes
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

### F3: Mint-Based Supply Expansion

**Invariant**: Each successful migration increases TelcoinV3 total supply by exactly `userBalance * DECIMAL_MULTIPLIER`

```
∀ migration m by user u with balance b:
  post(m): telcoinV3.totalSupply() == pre(m).telcoinV3.totalSupply() + (b * DECIMAL_MULTIPLIER)
```

**Properties**:

- Migration is mint-based; no pre-funded reserve is held or depleted
- Total supply expansion is bounded by the circulating supply of OldToken
- No mechanism within TokenMigration can decrease TelcoinV3 total supply

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

- Each chain's TelcoinV3 is deployed with a chain-specific initial supply (minted to admin at construction)
- Approximate distribution: Ethereum ~65B, Polygon ~30B, Base ~5B (subject to final adjustment)
- Total initial supply across all chains: 100B TEL v3
- Migration contracts mint on demand; there is no per-contract reserve to deplete
- No cross-chain double-spending possible; MINTER_ROLE is scoped per chain
- Native bridges: Ethereum ↔ Polygon (native bridge), Ethereum ↔ Base (native bridge)

### E3: Post-Expiry Governance Action

**Invariant**: After `migrationExpiry`, governance controls the migration contract and TelcoinV3 roles

```
After migration_end_time:
  migrate() reverts for all callers
  Governance may revoke MINTER_ROLE from migration contract on TelcoinV3
  Any accidentally sent tokens in migration contract recoverable via recoverERC20()
```

**Properties**:

- No unclaimed TelcoinV3 sits in the migration contract (mint-based design)
- Governance decides post-expiry fate of unclaimed OldToken value via off-chain policy
- Approximately 1-year initial migration window (managed by Governance off-chain)
- Migration window can be extended before expiry via `setMigrationExpiry()`

---

## State Transition Invariants

### ST1: State Consistency

**Invariant**: Contract state variables remain internally consistent

```
At any time t:
  totalMigrated == totalOldTokenBurned * DECIMAL_MULTIPLIER
  oldToken.balanceOf(BURN_ADDRESS) >= totalOldTokenBurned
```

**Properties**:

- `totalOldTokenBurned` and `totalMigrated` are updated atomically within `migrate()`
- Burned tokens correspond exactly to minted new tokens
- No state corruption possible; ReentrancyGuard prevents concurrent state modification
- Both values are public state variables, directly readable on-chain

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
telcoinV3 == immutable address set at construction
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
2. **Role Management**: Ensure migration contract holds `MINTER_ROLE` on TelcoinV3 before launch; revoke post-expiry
3. **Monitoring**: Real-time tracking of migration progress via `totalMigrated` and `totalOldTokenBurned`
4. **Grace Period**: Consider extension mechanisms if needed
5. **Support Channels**: Dedicated assistance for migration issues
6. **Recovery Mechanism**: Governance can recover accidentally sent OldTokens to help users complete migration
7. **Extended Claims**: Governance may extend `migrationExpiry` before deadline or grant `MINTER_ROLE` to a new migration contract to support a late-claims period

---

---

## TelcoinBridge Invariants

### B1: Burn-Mint Conservation

**Invariant**: Every outbound bridge call burns exactly `_amount` tokens; the matching inbound call mints exactly `_amount` tokens on the destination chain

```
∀ bridge(dstEid, to, amount, options):
  telcoin.totalSupply() decreases by amount on source chain
  telcoin.totalSupply() increases by amount on destination chain (upon delivery)
```

### B2: Peer Authorization

**Invariant**: `_lzReceive` only processes messages from registered peers

```
∀ inbound message:
  sender != peers[srcEid] → revert (enforced by LayerZero endpoint via _getPeerOrRevert)
```

### B3: Pausability

**Invariant**: When paused, both `bridge()` and `_lzReceive()` revert

```
paused == true → bridge() reverts with EnforcedPause
paused == true → _lzReceive() reverts with EnforcedPause (message enters retry queue)
```

### B4: Ownership Safety

**Invariant**: Bridge ownership cannot be transferred in a single step or renounced

```
transferOwnership(newOwner) → sets pendingOwner; owner unchanged until acceptOwnership()
renounceOwnership() → always reverts with CannotRenounceOwnership
```

---

## Audit Focus Areas

### High Priority

1. Decimal conversion mathematics and overflow protection
2. Reentrancy vulnerabilities in migration flow
3. Access control implementation and Ownable2Step ownership transfers
4. Token recovery function restrictions
5. Cross-chain deployment consistency (TelcoinBridge peer configuration)
6. LayerZero V2 message delivery guarantees and retry behavior

### Medium Priority

1. Event emission completeness and accuracy
2. Pause mechanism effectiveness
3. Error message clarity and gas optimization
4. View function accuracy

### Low Priority

1. Code formatting and documentation
2. Gas optimization opportunities
3. Future upgradeability considerations
