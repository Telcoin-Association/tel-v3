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
  i.e. (oldToken.totalSupply() - oldToken.balanceOf(migrationContract))
       + oldToken.balanceOf(migrationContract)
       == oldToken.totalSupply()

  and: telcoinV3 minted via migration == oldToken.balanceOf(migrationContract) * DECIMAL_MULTIPLIER
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

**Invariant**: Once tokens are migrated, the operation cannot be reversed by end users

```
∀ user u, ∀ migration m:
  post(m): oldToken.balanceOf(migrationContract) = pre(m).oldToken.balanceOf(migrationContract) + amount
  AND telcoinV3.balanceOf(u) = pre(m).telcoinV3.balanceOf(u) + (amount * DECIMAL_MULTIPLIER)
```

**Properties**:

- Old tokens are escrowed in the migration contract during the migration window
- Users cannot reverse their migration or reclaim escrowed tokens
- After `migrationExpiry + withdrawalDelay`, the owner can withdraw all escrowed legacy tokens to reclaim liquidity from legacy pools
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
��� migration m:
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
  - withdrawOldTokens()
  - recoverERC20()

onlyOwner functions (TelcoinBridge):
  - pause()
  - unpause()
  - rescueTokens()
  - setDelegate() (inherited from OApp)
  - transferOwnership() / acceptOwnership()

onlyOwner functions (NativeBridge):
  - pause()
  - unpause()
  - rescueTokens()
  - setDelegate() (inherited from OApp)
  - transferOwnership() / acceptOwnership()

onlyOwner functions (MintBurnWrapper):
  - authorizeBridge()
  - revokeBridge()
  - transferOwnership() / acceptOwnership()

onlyRole(DEFAULT_ADMIN_ROLE) functions (TelcoinV3):
  - rescueBurn(from, amount)   ← burns without approval; governance emergency only
  - rescueTokens(token, amount)
  - grantRole() / revokeRole()

onlyBridge functions (MintBurnWrapper):
  - mint()
  - burn()
```

**Properties**:

- Owner is initially set to governance multisig
- All contracts use Ownable2Step: `transferOwnership()` sets a pending owner, transfer only finalizes when the new owner calls `acceptOwnership()`
- `renounceOwnership()` is permanently disabled on `TelcoinBridge`, `NativeBridge`, and `MintBurnWrapper` (reverts with `CannotRenounceOwnership`)
- `renounceRole()` is permanently disabled on `TelcoinV3` for all callers including `DEFAULT_ADMIN_ROLE` (reverts with `CannotRenounceRole`) — roles can only be revoked by an admin
- `TelcoinBridge` holds no roles on `TelcoinV3` directly — mint/burn authority flows through `MintBurnWrapper`
- No backdoor or emergency functions bypass ownership

### S1b: Burn Authorization

**Invariant**: `TelcoinV3.burn()` requires explicit approval from the token holder; `rescueBurn()` bypasses approval but is restricted to `DEFAULT_ADMIN_ROLE`

```
∀ call to burn(from, amount) by BURNER_ROLE holder b:
  allowance(from, b) < amount → revert ERC20InsufficientAllowance

∀ call to rescueBurn(from, amount):
  caller lacks DEFAULT_ADMIN_ROLE → revert AccessControlUnauthorizedAccount
  caller has DEFAULT_ADMIN_ROLE   → burns without allowance check
```

**Properties**:

- A compromised `BURNER_ROLE` (e.g. `MintBurnWrapper`) cannot drain wallets that have not approved it
- Users bridging must `approve(wrapper, amount)` before calling `send()` on `TelcoinBridge`
- `rescueBurn` is intentionally separate from `BURNER_ROLE` — normal bridge operation never touches it
- Governance uses `rescueBurn` only in emergency (e.g. confirmed exploit, hacker balance)

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

**Invariant**: `recoverERC20` can recover any token accidentally sent to the migration contract, **except** the legacy (old) token

```
∀ recoverERC20(dest, token, amount):
  dest == address(0) → revert ZeroAddress
  token == address(0) → revert ZeroAddress
  token == address(oldToken) → revert CannotRecoverOldToken
  amount == 0 OR amount > balance → revert InvalidAmount
  otherwise → transfer allowed
```

**Properties**:

- Legacy tokens are blocked from `recoverERC20` to prevent bypassing the withdrawal delay; use `withdrawOldTokens()` instead
- Migration is mint-based; the contract holds no TelcoinV3 reserve, so recovery of TelcoinV3 is not a concern in normal operation
- Allows recovery of any other ERC20 accidentally sent to the contract

### S3b: Legacy Token Withdrawal Constraints

**Invariant**: Escrowed legacy tokens can only be withdrawn after `migrationExpiry + withdrawalDelay`

```
∀ withdrawOldTokens(dest):
  block.timestamp < migrationExpiry + withdrawalDelay → revert WithdrawalLocked
  dest == address(0) → revert ZeroAddress
  oldToken.balanceOf(migrationContract) == 0 → revert InvalidAmount
  otherwise → transfer entire escrowed balance to dest
```

**Properties**:

- Owner-only function; withdraws entire escrowed balance in a single call
- Delay ensures legacy liquidity pool positions can be unwound after migration concludes
- `recoverERC20` cannot be used to bypass this delay (blocked for oldToken)

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

### F2: Escrow Accumulation

**Invariant**: Migration contract escrow balance monotonically accumulates old tokens during the migration window

```
∀ time t1 < t2 (where t2 < migrationExpiry + withdrawalDelay):
  oldToken.balanceOf(migrationContract, t2) ≥ oldToken.balanceOf(migrationContract, t1)
```

**Properties**:

- Provides on-chain tracking of migrated amounts
- Escrow balance accumulates during migration; withdrawn by owner after the withdrawal delay
- `recoverERC20` is blocked for oldToken, preserving escrow integrity

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
  After migrationExpiry + withdrawalDelay:
    Owner can withdraw all escrowed legacy tokens via withdrawOldTokens()
  Any accidentally sent tokens (except oldToken) recoverable via recoverERC20()
```

**Properties**:

- No unclaimed TelcoinV3 sits in the migration contract (mint-based design)
- Escrowed legacy tokens remain in the contract until `migrationExpiry + withdrawalDelay`, allowing governance to reclaim liquidity from legacy constant product pools
- Approximately 1-year initial migration window (managed by Governance off-chain)
- Migration window can be extended before expiry via `setMigrationExpiry()`

---

## State Transition Invariants

### ST1: State Consistency

**Invariant**: Contract state is derivable from on-chain balances

```
At any time t (before withdrawal):
  v3 minted via migration == oldToken.balanceOf(migrationContract) * DECIMAL_MULTIPLIER
```

**Properties**:

- No mutable tracking state; migration progress is derived from the escrowed oldToken balance
- Escrowed balance can be queried directly via `oldToken.balanceOf(migrationContract)`
- No state corruption possible; ReentrancyGuard prevents concurrent state modification

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

### IM3: Immutable Withdrawal Delay

**Invariant**: `withdrawalDelay` is immutable and set at construction

```
withdrawalDelay == immutable value set at construction
```

**Properties**:

- Cannot be modified post-deployment
- Ensures a guaranteed holding period for escrowed legacy tokens after migration expires
- Withdrawal is only possible at or after `migrationExpiry + withdrawalDelay`

---

## Operational Invariants

### O1: Migration Window

**Invariant**: Migrations allowed only during active period

```
t < migration_end_time AND !paused → migrations allowed
t ≥ migration_end_time OR paused ��� migrations blocked
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

**Invariant**: Governance can assist users who mistakenly send non-legacy tokens to the migration contract

```
User mistake flow (non-legacy tokens):
1. User accidentally sends a non-legacy ERC20 to migration contract
2. User contacts support
3. Governance calls recoverERC20(supportWallet, token, amount)
4. Tokens returned to user

Note: Legacy (old) tokens sent directly to the contract cannot be recovered
via recoverERC20 — they become part of the escrow and are withdrawn by the
owner after the withdrawal delay.
```

**Properties**:

- Safety net for user errors with non-legacy tokens
- Legacy tokens are protected from premature recovery (blocked by `CannotRecoverOldToken`)
- No ability to force migrations on behalf of users

---

## Risk Considerations

### Known Limitations & Design Decisions

1. **Whole Balance Migration**: Users must migrate entire balance at once (intentional design)
2. **Migration Window Risk**: Users who do not migrate within timeframe will lose access to their tokens (intentional incentive mechanism)
3. **Irreversibility**: No mechanism for users to reverse migrations once completed
4. **Gas Costs**: Users bear gas costs for migration transaction
5. **Escrow Model**: OldToken is held in the migration contract (not burned) to allow governance to reclaim legacy liquidity pool positions after the withdrawal delay
6. **Supply Distribution**: Slight variations possible between chains, users may need to bridge to chains with remaining liquidity

### Mitigation Strategies

1. **Clear Documentation**: Comprehensive user guides and warnings
2. **Role Management**: Ensure migration contract holds `MINTER_ROLE` on TelcoinV3 before launch; revoke post-expiry
3. **Monitoring**: Real-time tracking of migration progress via `oldToken.balanceOf(migrationContract)` and the `TokensMigrated` event
4. **Grace Period**: Consider extension mechanisms if needed
5. **Support Channels**: Dedicated assistance for migration issues
6. **Recovery Mechanism**: Governance can recover accidentally sent non-legacy tokens; legacy tokens are protected by the withdrawal delay
7. **Legacy Liquidity Recovery**: After `migrationExpiry + withdrawalDelay`, governance can withdraw escrowed legacy tokens to reclaim liquidity from constant product pools
8. **Extended Claims**: Governance may extend `migrationExpiry` before deadline or grant `MINTER_ROLE` to a new migration contract to support a late-claims period

---

---

## Bridge Architecture Overview

The cross-chain TEL system consists of three contract types forming a two-tier OFT mesh:

- **TelcoinBridge** (`MintBurnOFTAdapter`) — deployed on each satellite chain (Ethereum, Polygon, Base, etc.). Delegates mint/burn to `MintBurnWrapper`.
- **NativeBridge** (`NativeOFTAdapter`) — deployed once on TelcoinNetwork where TEL is the native gas token. Locks/credits native TEL.
- **MintBurnWrapper** — adapter between `TelcoinBridge` and `TelcoinV3`'s mint/burn roles. Manages bridge authorization without touching TelcoinV3 access control.

All bridges use `OFTMsgCodec` with `sharedDecimals = 6` (`decimalConversionRate = 1e12`).

---

## TelcoinBridge Invariants

### B1: Burn-Mint Conservation (Satellite Chains)

**Invariant**: On every outbound `send()`, the wrapper burns exactly the dust-adjusted amount from the sender. The matching inbound `lzReceive` mints exactly that amount to the recipient on the destination chain.

```
∀ send(dstEid, to, amountLD, options):
  let amountSD = removeDust(amountLD) / 1e12
  telcoinV3.totalSupply() decreases by (amountSD * 1e12) on source chain
  telcoinV3.totalSupply() increases by (amountSD * 1e12) on destination chain (upon delivery)
```

**Properties**:

- Burn and mint are executed via `MintBurnWrapper`, not by the bridge directly
- Sub-1e12 wei dust is stripped before burn and remains with the sender
- Max transferable per message: `uint64.max * 1e12 ≈ 18.4 trillion TEL`

### B2: Peer Authorization

**Invariant**: `_lzReceive` only processes messages from registered peers

```
∀ inbound message:
  sender != peers[srcEid] → revert (enforced by LayerZero endpoint via _getPeerOrRevert)
```

### B3: Pausability

**Invariant**: When paused, both `send()` and `_lzReceive()` revert

```
paused == true → send() reverts with EnforcedPause
paused == true → _lzReceive() reverts with EnforcedPause (message enters LZ retry queue)
```

### B4: Ownership Safety

**Invariant**: Bridge ownership cannot be transferred in a single step or renounced

```
transferOwnership(newOwner) → sets pendingOwner; owner unchanged until acceptOwnership()
renounceOwnership() → always reverts with CannotRenounceOwnership
```

### B5: Bridge Interchangeability

**Invariant**: Replacing `TelcoinBridge` requires only wrapper authorization changes — no TelcoinV3 role modifications

```
swap bridge:
  wrapperA.revokeBridge(oldBridge)      // old bridge can no longer burn
  wrapperA.authorizeBridge(newBridge)   // new bridge can burn and mint
  newBridge.setPeer(dstEid, peer)       // wire LZ routing
  peer.setPeer(srcEid, newBridge)       // wire reverse
```

**Properties**:

- TelcoinV3's `MINTER_ROLE` and `BURNER_ROLE` remain on the wrapper throughout
- Old bridge immediately loses burn capability upon revocation
- No governance vote or timelock on TelcoinV3 required

---

## NativeBridge Invariants

### N1: Lock-Credit Conservation (TelcoinNetwork)

**Invariant**: Every outbound `send()` locks native TEL in the contract (reserve increases); every inbound `lzReceive` credits native TEL to the recipient (reserve decreases).

```
∀ send(dstEid, to, amountLD, options):
  address(nativeBridge).balance increases by removeDust(amountLD)

∀ lzReceive crediting recipient r with amountLD:
  r.balance increases by amountLD
  address(nativeBridge).balance decreases by amountLD
```

**Properties**:

- No ERC20 mint/burn occurs on TelcoinNetwork — native TEL is the asset
- Reserve must always be ≥ the sum of pending inbound credits; owner is responsible for reserve management

### N2: Reserve Sufficiency

**Invariant**: `lzReceive` will revert if the reserve cannot cover the credit

```
address(nativeBridge).balance < amountLD → lzReceive reverts (ETH transfer fails)
```

**Properties**:

- Owner monitors and tops up the reserve via direct ETH transfer (triggers `receive()`)

### N3: Correct msg.value Enforcement

**Invariant**: `send()` reverts if `msg.value` does not exactly equal `nativeFee + removeDust(amount)`

```
msg.value != nativeFee + removeDust(amount) → revert IncorrectMessageValue(provided, required)
```

### N4: Single Instance Constraint

**Invariant**: Only one `NativeBridge` should exist across the OFT mesh

```
∀ satellite peer registrations:
  peer[EID_TN] == address(nativeBridge)  // one canonical TN-side counterpart
```

**Properties**:

- Multiple `NativeBridge` instances would make lock/credit accounting incoherent
- All satellite `TelcoinBridge` peers for TelcoinNetwork's EID must point to the same `NativeBridge`

---

## MintBurnWrapper Invariants

### W1: Authorization Gate

**Invariant**: Only the single authorized `bridge` address may call `mint` or `burn`

```
∀ call to mint(to, amount) or burn(from, amount):
  msg.sender != bridge → revert UnauthorizedBridge

Idempotency guards:
  authorizeBridge(_bridge) where bridge == _bridge → revert BridgeAlreadySet
  revokeBridge(_bridge) where bridge == address(0) → revert BridgeNotSet
  revokeBridge(_bridge) where bridge != _bridge    → revert UnauthorizedBridge
```

### W2: Role Delegation Stability

**Invariant**: The wrapper holds `MINTER_ROLE` and `BURNER_ROLE` on TelcoinV3 throughout normal operation

```
token.hasRole(MINTER_ROLE, wrapper) == true
token.hasRole(BURNER_ROLE, wrapper) == true
```

**Properties**:

- Revoking these roles from the wrapper would silently brick all authorized bridges
- Only the TelcoinV3 `DEFAULT_ADMIN_ROLE` holder can revoke; should only happen in an emergency

### W3: Immutable Token Reference

**Invariant**: The `token` address is set at construction and cannot be changed

```
token == immutable address set at construction
token != address(0) (enforced by constructor revert)
```

---

## EIP-2612 (Permit) Invariants

### P1: Gasless Approval via Signed Message

**Invariant**: `permit()` sets an ERC-20 allowance using an EIP-712 signed message instead of an on-chain `approve()` transaction

```
∀ permit(owner, spender, value, deadline, signature):
  valid signature from owner → allowance(owner, spender) = value
  invalid signature → revert InvalidSignature
  block.timestamp > deadline → revert ERC2612ExpiredSignature
```

**Properties**:

- Two overloads: `(v, r, s)` for EIP-2612 spec compliance (delegates to bytes version), and `bytes signature` for full EIP-1271 support
- Uses `SignatureChecker` which routes to `ECDSA.recover` for EOAs or `IERC1271.isValidSignature` for contract wallets
- The `bytes` overload accepts arbitrary-length signature blobs (e.g. Gnosis Safe multi-sig concatenated signatures)
- Sequential nonce (`_nonces[owner]`) increments on every successful permit; reverts roll back the increment

### P2: Nonce Sequentiality

**Invariant**: EIP-2612 nonces are sequential per address and monotonically increasing

```
∀ address a:
  nonces(a) after successful permit == nonces(a) before + 1
  nonces(a) can never decrease
```

**Properties**:

- Managed by OpenZeppelin's `Nonces` contract via `_useNonce(owner_)`
- Nonce is consumed inside the permit function; a revert (invalid sig, expired deadline) rolls back the increment
- Completely independent from EIP-3009 nonces (different type, different storage)

### P3: Permit Works While Paused

**Invariant**: `permit()` succeeds even when the token is paused because it calls `_approve()`, not `_update()`

```
paused == true → permit() succeeds (approval only, no transfer)
paused == true → transferFrom() after permit still reverts (transfer blocked by _update)
```

---

## EIP-3009 (Transfer With Authorization) Invariants

### T1: Authorized Transfer via Signed Message

**Invariant**: `transferWithAuthorization` executes a transfer using an EIP-712 signed authorization from the `from` address

```
∀ transferWithAuthorization(from, to, value, validAfter, validBefore, nonce, signature):
  valid signature from `from`
    AND block.timestamp > validAfter
    AND block.timestamp < validBefore
    AND !_authorizationStates[from][nonce]
    → transfer(from, to, value) + nonce marked used

  any condition violated → revert
```

**Note**: Both `(v, r, s)` and `bytes signature` overloads exist. The `(v, r, s)` version packs and delegates to the `bytes` version.

```
```

### T2: Receive Authorization Front-Running Protection

**Invariant**: `receiveWithAuthorization` requires `msg.sender == to`, preventing front-running of the signed authorization

```
∀ receiveWithAuthorization(from, to, value, ...):
  msg.sender != to → revert CallerMustBePayee
```

**Properties**:

- `transferWithAuthorization` is callable by anyone (relayer-friendly but front-runnable)
- `receiveWithAuthorization` restricts the caller to the payee, mitigating front-running
- Both use distinct EIP-712 type hashes — a `transferWithAuthorization` signature cannot be replayed as `receiveWithAuthorization`

### T3: Nonce One-Shot Latch

**Invariant**: EIP-3009 nonces are random `bytes32` values that transition `false → true` and never revert to `false`

```
∀ address a, ∀ nonce n:
  _authorizationStates[a][n]: false → true (via transfer, receive, or cancel)
  _authorizationStates[a][n]: true → true (no path back to false)
```

**Properties**:

- Prevents replay of used authorizations
- `cancelAuthorization` marks a nonce as used without executing a transfer
- Nonce space is `2^256` per address with no sequential constraint

### T4: Time Window Validation

**Invariant**: Authorizations are valid only in the open interval `(validAfter, validBefore)`

```
block.timestamp <= validAfter → revert AuthorizationNotYetValid
block.timestamp >= validBefore → revert AuthorizationExpired
```

**Properties**:

- Both bounds are exclusive: `validAfter == validBefore` creates an unusable authorization (no valid timestamp)
- `validAfter = 0, validBefore = type(uint256).max` means "no time restriction"

### T5: EIP-3009 Transfers Respect Pause

**Invariant**: `transferWithAuthorization` and `receiveWithAuthorization` route through `_transfer()` → `_update()`, which enforces the pause check

```
paused == true → transferWithAuthorization() reverts with EnforcedPause
paused == true → receiveWithAuthorization() reverts with EnforcedPause
```

### T6: Cancel Authorization

**Invariant**: `cancelAuthorization` marks a nonce as used, preventing future use by `transferWithAuthorization` or `receiveWithAuthorization`

```
∀ cancelAuthorization(authorizer, nonce, signature):
  valid signature from authorizer
    AND !_authorizationStates[authorizer][nonce]
    → _authorizationStates[authorizer][nonce] = true + emit AuthorizationCanceled

  _authorizationStates[authorizer][nonce] == true → revert AuthorizationAlreadyUsed
```

---

## EIP-1271 (Smart Contract Wallet) Invariants

### SC1: Dual Signature Support

**Invariant**: Both `permit()` and all EIP-3009 functions accept EOA signatures AND EIP-1271 smart contract wallet signatures (including multi-sig Gnosis Safes)

```
∀ signature verification:
  signer.code.length == 0 → EOA path (ECDSA.tryRecover on the bytes signature)
  signer.code.length > 0  → contract path (staticcall to signer.isValidSignature, forwarding full signature blob)
```

**Properties**:

- Each function has two overloads: `(v, r, s)` (delegates to bytes version) and `bytes signature` (core implementation)
- The `bytes` overload accepts arbitrary-length blobs, enabling multi-sig Gnosis Safes (threshold > 1) whose concatenated owner signatures exceed 65 bytes
- Uses OpenZeppelin's `SignatureChecker.isValidSignatureNow()` in both `permit()` and `_verifyEIP712Signature()`
- The `staticcall` prevents the signer contract from modifying state during verification
- A malicious EIP-1271 contract returning `0x1626ba7e` for arbitrary hashes can only authorize transfers from its own balance — it cannot affect other users

### SC2: Consistent Verification Across All Signature Paths

**Invariant**: All eight signature-verified functions (4 `(v,r,s)` + 4 `bytes`) use the same verification mechanism

```
permit(v,r,s)                    → permit(bytes) → SignatureChecker.isValidSignatureNow()
transferWithAuthorization(v,r,s) → transferWithAuthorization(bytes) → _verifyEIP712Signature() → SignatureChecker
receiveWithAuthorization(v,r,s)  → receiveWithAuthorization(bytes) → _verifyEIP712Signature() → SignatureChecker
cancelAuthorization(v,r,s)       → cancelAuthorization(bytes) → _verifyEIP712Signature() → SignatureChecker
```

---

## EIP-712 Domain Separation Invariants

### D1: Shared Domain Separator

**Invariant**: EIP-2612 and EIP-3009 share a single EIP-712 domain separator but use distinct type hashes

```
DOMAIN_SEPARATOR = keccak256(
  abi.encode(TYPE_HASH, name="Telcoin", version="1", chainId, verifyingContract)
)

PERMIT_TYPEHASH ≠ TRANSFER_WITH_AUTHORIZATION_TYPEHASH
                ≠ RECEIVE_WITH_AUTHORIZATION_TYPEHASH
                ≠ CANCEL_AUTHORIZATION_TYPEHASH
```

**Properties**:

- A permit signature cannot be used as a `transferWithAuthorization` (different struct hash)
- Cross-chain replay is prevented by `chainId` in the domain separator
- Cross-deployment replay is prevented by `verifyingContract` in the domain separator

### D2: Nonce System Independence

**Invariant**: EIP-2612 and EIP-3009 nonce systems are completely independent

```
EIP-2612: sequential uint256 nonces in Nonces._nonces mapping
EIP-3009: random bytes32 nonces in TelcoinV3._authorizationStates mapping

No storage overlap. No type overlap. No interference.
```

---

## Audit Focus Areas

### High Priority

1. Decimal conversion mathematics and dust stripping (`_removeDust`, `decimalConversionRate`)
2. Reentrancy vulnerabilities in migration flow and native ETH crediting in NativeBridge
3. Access control implementation and Ownable2Step ownership transfers across all contracts
4. `MintBurnWrapper` authorization gate — unauthorized `mint`/`burn` access
5. `NativeBridge` reserve sufficiency and lock/credit accounting
6. Cross-chain peer configuration consistency (`TelcoinBridge` ↔ `NativeBridge` peer wiring)
7. LayerZero V2 message delivery guarantees and retry behavior when paused
8. `TelcoinBridge` interchangeability — correctness of revoke/authorize/setPeer sequence
9. EIP-3009 signature verification — ensure `SignatureChecker` correctly validates both EOA and EIP-1271 signatures; verify type hash uniqueness prevents cross-function replay
10. EIP-3009 nonce replay protection — verify nonces are consumed before external effects (`_markAuthorizationUsed` before `_transfer`)
11. EIP-1271 `staticcall` safety — verify no state modification possible during signature verification callback

### Medium Priority

1. Event emission completeness and accuracy (`OFTSent`, `OFTReceived`, `BridgeAuthorized`, `BridgeRevoked`, `BridgeMinted`, `BridgeBurned`, `ReserveFunded`)
2. Pause mechanism effectiveness on both send and receive paths
3. `NativeBridge` single-instance constraint enforcement
4. `MintBurnWrapper` role stability on TelcoinV3
5. `burn()` allowance enforcement — verify a compromised wrapper cannot drain unapproved wallets
6. `rescueBurn()` access control — verify `BURNER_ROLE` holders cannot call it; only `DEFAULT_ADMIN_ROLE`
7. EIP-2612 `permit()` nonce ordering — verify nonce is consumed atomically with signature validation (revert rolls back increment)
8. EIP-3009 time window edge cases — `validAfter == validBefore`, `validBefore = 0`, `validAfter = type(uint256).max`
9. EIP-2612/3009 interaction with pause — verify permits succeed while paused but authorized transfers revert

### Low Priority

1. Code formatting and documentation
2. Gas optimization opportunities
3. Future upgradeability considerations
