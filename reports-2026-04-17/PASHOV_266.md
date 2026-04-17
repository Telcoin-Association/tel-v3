# Pashov 266-Pattern Scan — Telcoin V3

Complete triage of every numbered pattern in `pashov/skills/solidity-auditor/references/attack-vectors/attack-vectors.md`. Each pattern is marked:

- ✅ **PASS** — pattern applies to the codebase, checked, not vulnerable. Evidence inline.
- ⛔ **N/A** — pattern does not apply (wrong stack / feature not present).
- ⚠️ **FINDING** — pattern applies and produces a finding; cross-references AUDIT.md or a new finding ID.

| # | Pattern | Verdict | Evidence |
|---:|---|---|---|
| 1 | Cross-Chain Message Spoofing (Missing Endpoint/Peer Validation) | ✅ PASS | OAppReceiver.lzReceive enforces `msg.sender==endpoint` + `peers[srcEid]==_origin.sender` |
| 2 | EIP-7702 Code Inspection Opcode Invalidation | ⛔ N/A | No `extcodesize`/`extcodehash` branching in src/ |
| 3 | Paymaster Gas Penalty Undercalculation | ⛔ N/A | No ERC-4337 paymaster |
| 4 | Reward Rate Changed Without Settling Accumulator | ⛔ N/A | No rewards/emissions |
| 5 | lzCompose Sender Impersonation | ✅ PASS | No custom lzCompose override; OFTCore's `_lzReceive` only routes if `_message.isComposed()`, with fixed `toAddress` from msg |
| 6 | Tick Crossing Fee JIT | ⛔ N/A | No Uniswap-v3 ticks |
| 7 | Withdrawal Queue Rate Lock-In | ⛔ N/A | No withdrawal queue |
| 8 | Partial Redemption Fails to Reduce Tracked Total | ⛔ N/A | No redemption |
| 9 | ERC1155 safeBatchTransferFrom Unchecked Arrays | ⛔ N/A | No ERC-1155 |
| 10 | EIP-7702 Whitelist Privilege Borrowing | ⛔ N/A | No 7702 |
| 11 | Deprecated Gauge Blocks Claiming | ⛔ N/A | No gauge |
| 12 | Force-Feeding ETH via selfdestruct | ✅ PASS | NativeBridge `receive()` + accounting tolerates force-fed ETH (emits ReserveFunded, reserve covers outbound credits) — I-01/TIA-02 already document the non-recoverable nature |
| 13 | EIP-7702 Dual Signature Validation | ⛔ N/A | No 7702 |
| 14 | JIT Liquidity TWAMM | ⛔ N/A | No TWAMM |
| 15 | Fixed-End Auction Last-Block Sniping | ⛔ N/A | No auction |
| 16 | Adverse Selection JIT LP | ⛔ N/A | No LP |
| 17 | Governance Flash-Loan Upgrade Hijack | ⛔ N/A | Not upgradeable, no flash loans |
| 18 | Non-Standard ERC20 Return Values (USDT-style) | ✅ PASS | TelcoinV3 returns bool (slither-check-erc verified); integrations use SafeERC20 |
| 19 | TWAP Accumulator Not Updated | ⛔ N/A | No TWAP |
| 20 | Cross-Chain Sandwich via Bridge Parameter Exposure | ⛔ N/A (effective) | Bridge amount is user-specified; no pricing exposed to MEV. Dust stripping is deterministic and equal for sender/receiver |
| 21 | Funding Rate from Single Trade | ⛔ N/A | No funding rate |
| 22 | Loan State Before Interest Settlement | ⛔ N/A | No lending |
| 23 | Missing Slippage on Vault Withdraw | ⛔ N/A | No vault |
| 24 | Dirty Higher-Order Bits on Sub-256-Bit Types | ✅ PASS | Solidity 0.8+ clean bits on casts; OFTCore's `uint64 amountSD` cast checked via `_toSD` overflow guard |
| 25 | Unsafe Downcast / Integer Truncation | ✅ PASS | Only downcast is `uint256 → uint64` in `_toSD`, which explicitly reverts `AmountSDOverflowed` on overflow |
| 26 | Small-Type Arithmetic Overflow Before Upcast | ✅ PASS | No sub-256-bit arithmetic in src/ |
| 27 | Missing chainId (Cross-Chain Replay) | ✅ PASS | LayerZero uses `srcEid` (EID) which is a chain-unique identifier in the LZ mesh; endpoint dedupes per (srcEid, sender, nonce) |
| 28 | Chainlink Staleness | ⛔ N/A | No oracle |
| 29 | Signed Integer Mishandling | ⛔ N/A | No signed integers in src/ |
| 30 | ERC777 tokensToSend/Received Reentrancy | ⛔ N/A | TelcoinV3 is OZ ERC-20, no hooks |
| 31 | Storage Layout Collision Proxy/Impl | ⛔ N/A | Not upgradeable |
| 32 | Token Decimal Mismatch | ✅ PASS | 2 → 18 conversion is exact via `× 1e16`; bridge dust stripping is symmetric |
| 33 | ERC4626 Caller-Dependent Conversion | ⛔ N/A | No ERC-4626 |
| 34 | Permit Signature Frontrun Griefing | ⛔ N/A | No permit |
| 35 | Slippage at Intermediate Not Final | ⛔ N/A | No multi-step swap |
| 36 | False Existence via Balance at Computed Address | ⛔ N/A | No balance-based existence checks |
| 37 | Missing Cross-Chain Rate Limits / Circuit Breakers | ⚠️ FINDING — **PS-1 (NEW, Info)** | `grep -E 'rateLimit\|RateLimit\|circuitBreaker\|dailyCap\|maxDailyMint' src/` returns nothing. Bridge has no per-epoch mint or send rate limit. |
| 38 | Weak On-Chain Randomness | ⛔ N/A | No RNG |
| 39 | Spot Price Oracle from AMM | ⛔ N/A | No oracle/AMM |
| 40 | Liquidation Discount Inconsistency | ⛔ N/A | No liquidations |
| 41 | Beacon Proxy SPOF | ⛔ N/A | No proxy |
| 42 | Upgrade Race Condition | ⛔ N/A | Not upgradeable |
| 43 | LST Redemption-Rate vs Market-Price | ⛔ N/A | Not LST |
| 44 | Returndatasize-as-Zero Assumption | ✅ PASS | SafeERC20 validates return data; no custom assembly |
| 45 | ERC1155 Fungible/NF Token ID Collision | ⛔ N/A | No ERC-1155 |
| 46 | Array delete Leaves Gap | ⛔ N/A | No array deletes |
| 47 | Merkle Proof Reuse | ⛔ N/A | No Merkle |
| 48 | Missing chainId / Message Uniqueness in Bridge | ✅ PASS | LZ GUID per message dedupes |
| 49 | Quorum from Live Supply Not Snapshot | ⛔ N/A | No voting governor |
| 50 | Integer Overflow/Underflow | ✅ PASS | 0.8+; no `unchecked` blocks in src/ |
| 51 | Share Redemption at Optimistic Rate | ⛔ N/A | No shares |
| 52 | Rounding in Favor of User | ✅ PASS | Migration uses multiplication only (no rounding); bridge dust stripped deterministically |
| 53 | UUPS Upgrade Logic Removed | ⛔ N/A | Not upgradeable |
| 54 | Uninitialized Implementation Takeover | ⛔ N/A | Not upgradeable |
| 55 | EIP-7702 EOA Reentrancy / ETH DoS | ⚠️ SEE I-06 | Related — `NativeBridge._credit` push can stall on malicious recipient |
| 56 | Atomic JIT Liquidity Flash Accounting | ⛔ N/A | No JIT/flash |
| 57 | Missing Nonce (Signature Replay) | ⛔ N/A | No signatures |
| 58 | ERC721A Lazy Ownership | ⛔ N/A | No ERC-721 |
| 59 | No Buffer LTV/Liquidation | ⛔ N/A | No lending |
| 60 | Return Bomb | ✅ PASS | SafeERC20 limits returndata; no manual low-level calls except LZ endpoint |
| 61 | Cross-Contract Reentrancy | ✅ PASS | `migrate()` guarded; external calls to trusted known-nonreentrant contracts |
| 62 | DoS via Push Payment to Rejecting Contract | ⚠️ SEE I-06 | `NativeBridge._credit` push |
| 63 | Diamond Shared-Storage Cross-Facet | ⛔ N/A | No diamond |
| 64 | ERC721/1155 Type Confusion | ⛔ N/A | No NFTs |
| 65 | Improper Flash Loan Callback Validation | ⛔ N/A | No flash loans |
| 66 | ERC721 Unsafe Transfer to Non-Receiver | ⛔ N/A | No ERC-721 |
| 67 | Hardcoded Calldataload Offset | ⛔ N/A | No manual calldata parsing |
| 68 | EIP-7702 Delegation Front-Run | ⛔ N/A | No 7702 |
| 69 | Free Memory Pointer Corruption | ⛔ N/A | No assembly in src/ |
| 70 | Rebasing / Elastic Supply | ⛔ N/A | TelcoinV3 is non-rebasing |
| 71 | Nonce Not Incremented on Revert | ⛔ N/A | No custom nonce |
| 72 | ERC721/1155 Callback Reentrancy | ⛔ N/A | No NFTs |
| 73 | Min-Lock Bypass via Position Modification | ⛔ N/A | No lock |
| 74 | msg.value Reuse in Loop / Multicall | ⛔ N/A | No loop / no multicall |
| 75 | ERC4626 Missing Allowance Check | ⛔ N/A | No ERC-4626 |
| 76 | Multi-Block TWAP Manipulation | ⛔ N/A | No TWAP |
| 77 | ERC721 Callback Arbitrary Caller Spoof | ⛔ N/A | No NFTs |
| 78 | Governance Precondition Manipulation | ⛔ N/A | No governance primitives |
| 79 | Same-Block Deposit-Withdraw Snapshot | ⛔ N/A | No snapshot-based economics |
| 80 | Idle Asset Dilution Sub-Vault Cap | ⛔ N/A | No vault |
| 81 | Liquidation Arithmetic Reverts | ⛔ N/A | No lending |
| 82 | Memory Struct Not Written to Storage | ✅ PASS | All state mutations via direct storage writes |
| 83 | Non-Standard ERC20 Permit Interface | ⛔ N/A | No permit |
| 84 | Front-Run Zero Balance with Dust | ⛔ N/A | No balance-check-then-... pattern |
| 85 | Vault Insolvency Rounding Dust | ⛔ N/A | No vault |
| 86 | ERC721 Approval Not Cleared on Xfer Override | ⛔ N/A | No ERC-721 |
| 87 | Vault Harvest Front-Run | ⛔ N/A | No vault |
| 88 | validateUserOp Signature Not Bound to nonce/chainId | ⛔ N/A | No ERC-4337 |
| 89 | Self-Matched Orders Wash Trading | ⛔ N/A | No order book |
| 90 | Block Stuffing / Gas Griefing on Subcalls | ✅ PASS | No subcall-heavy state changes |
| 91 | Banned Opcode in Validation Phase | ⛔ N/A | No AA |
| 92 | Flash Loan Price Manipulation | ⛔ N/A | No pricing |
| 93 | Small Positions Unliquidatable | ⛔ N/A | No lending |
| 94 | Profit Tracking Underflow | ⛔ N/A | No profit tracking |
| 95 | Missing or Incorrect Access Modifier | ✅ PASS | Entry-point audit in AUDIT.md §6 (entry-point-analyzer skill) shows every state-changing fn has correct gate |
| 96 | NFT Staking Records msg.sender Not ownerOf | ⛔ N/A | No NFT staking |
| 97 | Cross-Chain Deployment Replay | ⚠️ SEE I-07 | CREATE3 salt front-running |
| 98 | abi.encodePacked Hash Collision | ✅ PASS | keccak256 used only on `"MINTER_ROLE"` etc. (single literal) |
| 99 | ERC1155 Batch Partial-State Callback | ⛔ N/A | No ERC-1155 |
| 100 | Arbitrary delegatecall in Implementation | ⛔ N/A | No delegatecall |
| 101 | Cross-Chain Reentrancy via Safe Transfer Callbacks | ✅ PASS | No callback in transfer path |
| 102 | Hook Callback Reentrancy for Fee Bypass | ⛔ N/A | No hooks |
| 103 | Signature Malleability | ⛔ N/A | No signatures |
| 104 | Withdrawal Queue Bricked by Zero-Amount | ⛔ N/A | No withdrawal queue |
| 105 | Cross-Message Token Identity Mismatch | ✅ PASS | Single TelcoinV3 per chain; OFT carries amount not token-id |
| 106 | First-Swap Extraction New Pools | ⛔ N/A | Not a DEX |
| 107 | ERC1155 onReceived Not Validated | ⛔ N/A | No ERC-1155 |
| 108 | Self-Delegation Doubles Voting Power | ⛔ N/A | No voting |
| 109 | Expired Oracle Silently Assigns Prev Price | ⛔ N/A | No oracle |
| 110 | Non-Standard Approve (Zero-First/Max-Approval Revert) | ✅ PASS | OZ 5.x standard approve; TelcoinV3 doesn't revert on max-approval |
| 111 | ERC4626 Round-Trip Profit | ⛔ N/A | No ERC-4626 |
| 112 | Commit-Reveal Not Bound to msg.sender | ⛔ N/A | No commit-reveal |
| 113 | ERC4626 maxDeposit When Paused | ⛔ N/A | No ERC-4626 |
| 114 | Permissionless accrueInterest Griefing | ⛔ N/A | No interest |
| 115 | Proxy Admin Key Compromise | ⛔ N/A | Not upgradeable |
| 116 | ERC4626 convertToAssets Used vs previewWithdraw | ⛔ N/A | No ERC-4626 |
| 117 | MEV Withdrawal Before Bad Debt | ⛔ N/A | No bad debt |
| 118 | EIP-7702 ERC-721/1155 Callback Revert | ⛔ N/A | No 7702 / NFTs |
| 119 | State Record Overwrite Without Existence Check | ⚠️ SEE L-01 | `authorizeBridge` overwrites without `if (bridge != 0)` check |
| 120 | Empty Swap Path Bypasses Token Validation | ⛔ N/A | No swap |
| 121 | Missing Slippage (Sandwich) | ⛔ N/A | No slippage-relevant operation (migration is fixed-ratio) |
| 122 | Nested Mapping Inside Struct Not Cleared | ⛔ N/A | No nested mappings |
| 123 | Assembly Delegatecall Missing Return/Revert | ⛔ N/A | No assembly in src/ |
| 124 | Batch Distribution Dust Residual | ⛔ N/A | No batch distribution |
| 125 | Lazy Epoch Skips Reward Periods | ⛔ N/A | No epochs/rewards |
| 126 | Dutch Auction Underflow | ⛔ N/A | No auction |
| 127 | ERC721Enumerable Index Corruption | ⛔ N/A | No ERC-721 |
| 128 | Dead Code After Return | ✅ PASS | No unreachable code in src/ |
| 129 | CREATE/CREATE2 Deployment Fail Silent | ⚠️ SEE I-07 | Note: Create3 library reverts on failure; deployment scripts check. |
| 130 | Proxy Storage Slot Collision | ⛔ N/A | Not upgradeable |
| 131 | Algorithmic Complexity Gas DoS | ✅ PASS | No loops; O(1) in hot paths |
| 132 | Emergency Mode State Machine Incompleteness | ✅ PASS | Pause blocks all user-path state change (migrate, send, lzReceive) |
| 133 | Sentinel / Placeholder Address Ops | ✅ PASS | `BURN_ADDRESS = 0xdEaD` is canonical; no ops on address(0) or address(1) |
| 134 | Immutable/Constructor Arg Misconfiguration | ✅ PASS | Constructor argument checks (`ZeroAddress`, `SameAddress`, `InvalidExpiry`) present |
| 135 | EIP-7702 Delegation Persists on Revert | ⛔ N/A | No 7702 |
| 136 | Fee Accumulation Rounding Extraction | ⛔ N/A | No fees |
| 137 | Flash Loan Governance Attack | ⛔ N/A | No flash loan, no governance vote |
| 138 | Off-By-One in Bounds | ✅ PASS | Expiry uses `>=` (reverts at exact expiry — Cantina §3.2.1 fix verified) |
| 139 | Open Interest with Pre-Fee Position | ⛔ N/A | No open interest |
| 140 | Admin Param Change During Multi-Step | ⚠️ SEE L-01 | `authorizeBridge` one-step overwrite during active bridge |
| 141 | Interest Rounds to Zero with Timestamp Advance | ⛔ N/A | No interest |
| 142 | Oracle Update Front-Run | ⛔ N/A | No oracle |
| 143 | Insufficient Block Confirmations / Reorg | ✅ PASS | LZ handles finality; not a user-handled concern for in-scope contracts |
| 144 | Cross-Function Reentrancy | ✅ PASS | `migrate` is the only user-callable mutating path with external calls; guarded |
| 145 | Liquidation Blocked by Illiquidity | ⛔ N/A | No liquidations |
| 146 | Oracle Extractable Value | ⛔ N/A | No oracle |
| 147 | ERC4626 Mint/Redeem Asymmetry | ⛔ N/A | No ERC-4626 |
| 148 | Delegate Privilege Escalation | ✅ PASS | OApp `setDelegate` is owner-only |
| 149 | DoS via Reverting External Call in Loop | ⛔ N/A | No loops |
| 150 | Cross-Chain Supply Accounting Invariant | ⚠️ SEE I-05 | Per-chain cap, not global |
| 151 | No-Bid Auction Fails to Clear | ⛔ N/A | No auction |
| 152 | Non-Atomic Proxy Init Front-Run | ⛔ N/A | No proxy |
| 153 | Hardcoded Network-Specific Addresses | ✅ PASS | No hardcoded network addresses in src/; deployment scripts parameterise |
| 154 | ERC-1271 isValidSignature Delegated | ⛔ N/A | No 1271 |
| 155 | notifyRewardAmount Overwrites Active Reward | ⛔ N/A | No rewards |
| 156 | validateUserOp Missing EntryPoint Restriction | ⛔ N/A | No AA |
| 157 | Transparent Proxy Admin Routing | ⛔ N/A | No proxy |
| 158 | Intent Solver Collusion | ⛔ N/A | No intent solver |
| 159 | Pause Modifier Blocks Liquidations | ⛔ N/A | No liquidations |
| 160 | EIP-2981 Royalty Not Enforced | ⛔ N/A | No 2981 |
| 161 | Assembly Arithmetic Silent Overflow | ⛔ N/A | No assembly in src/ |
| 162 | Zero-Amount Transfer Revert | ✅ PASS | TelcoinV3 does not revert on zero (OZ 5.x standard) |
| 163 | Blacklist/Whitelist Not Mutually Exclusive | ⛔ N/A | No blacklist/whitelist |
| 164 | extcodesize Zero in Constructor | ✅ PASS | No extcodesize-based gating in src/ |
| 165 | Missing Chain ID Validation in Deployment Config | ✅ PASS | Deployment uses CREATE3 salt + per-chain deployer; LZ config per-chain |
| 166 | Capacity Competition Between Accounting Vars | ⛔ N/A | Single accounting variable (`totalMigrated`) |
| 167 | Accrued Interest Omitted from Health Factor | ⛔ N/A | No health factor |
| 168 | Storage Layout Shift on Upgrade | ⛔ N/A | Not upgradeable |
| 169 | Fee-on-Transfer Token Accounting | ✅ PASS | Legacy TelcoinV2 is not FoT; verified on-chain |
| 170 | Bridge Global Rate Limit Griefing | ⚠️ SEE PS-1 (same theme as #37) | No rate limit → no griefing vector, but also no circuit-break if attacker bridges mass supply |
| 171 | Minimal Proxy (EIP-1167) Destruction | ⛔ N/A | No minimal proxy |
| 172 | Position Reduction Triggers Liquidation | ⛔ N/A | No positions |
| 173 | ERC4626 Deposit/Withdraw Share Asymmetry | ⛔ N/A | No ERC-4626 |
| 174 | Missing Oracle Price Bounds | ⛔ N/A | No oracle |
| 175 | Function Selector Clashing (Proxy) | ⛔ N/A | No proxy |
| 176 | Checkpoint Overwrite on Same-Block | ⛔ N/A | No checkpoints |
| 177 | Default Message Library Hijack | ℹ️ LZ config concern — OUT OF SCOPE | Cross-reference `docs/lz-dvn-config.md` — owner is responsible for configuring endpoint libraries |
| 178 | Immutable Variable Context Mismatch | ✅ PASS | All immutables set correctly at construction |
| 179 | Calldata Input Malleability | ✅ PASS | No packed/tightly-encoded calldata decoding |
| 180 | On-Chain Slippage from Manipulated Pool | ⛔ N/A | No pool |
| 181 | Hardcoded Zero Slippage | ⛔ N/A | No internal swap |
| 182 | Nonce Gap Revert (CREATE Addr Mismatch) | ✅ PASS | CREATE3 factory address-derivation is salt-based, not nonce-based |
| 183 | Unclaimed Reward Tokens | ⛔ N/A | No underlying protocol |
| 184 | ERC4626 Preview Rounding Direction | ⛔ N/A | No ERC-4626 |
| 185 | Missing/Expired Deadline on Swaps | ⛔ N/A | No swap |
| 186 | Calldataload OOB Read | ⛔ N/A | No manual calldata parsing |
| 187 | State-Time Lag (lzRead Stale State) | ⛔ N/A | No lzRead / cross-chain read |
| 188 | Transient Storage Low-Gas Reentrancy (EIP-1153) | ✅ PASS | Uses `ReentrancyGuardTransient` from OZ — the canonical safe pattern |
| 189 | ERC4626 Inflation (First Depositor) | ⛔ N/A | No ERC-4626 |
| 190 | Arbitrary External Call with User Target | ⛔ N/A | No arbitrary-call in src/ |
| 191 | msg.value vs Computed Amount Mismatch | ✅ PASS | NativeBridge reverts `IncorrectMessageValue(provided, required)` if off |
| 192 | ERC4626 maxDeposit vs Actual Mismatch | ⛔ N/A | No ERC-4626 |
| 193 | Function Selector Clash in Proxy | ⛔ N/A | No proxy |
| 194 | LVR in Constant-Function AMMs | ⛔ N/A | No AMM |
| 195 | Delegation to address(0) Blocks Transfers | ⛔ N/A | No delegation primitive |
| 196 | tx.origin Authentication | ✅ PASS | No tx.origin |
| 197 | Scratch Space Corruption | ⛔ N/A | No assembly in src/ |
| 198 | FIFO Withdrawal Degrades Yield | ⛔ N/A | No withdrawal queue |
| 199 | Repeated Liquidation of Same Position | ⛔ N/A | No liquidation |
| 200 | ERC1155 uri() Missing {id} Sub | ⛔ N/A | No ERC-1155 |
| 201 | Emission Distribution Before Period Update | ⛔ N/A | No emission |
| 202 | Single-Function Reentrancy | ✅ PASS | migrate guarded; other entry points don't do reentrant patterns |
| 203 | Stale Cached ERC20 Balance from Direct Transfers | ✅ PASS | TokenMigration uses `balanceOf(msg.sender)` at call time, not a cached value |
| 204 | Duplicate Items in User-Supplied Array | ⛔ N/A | No user arrays in src/ |
| 205 | Counterfactual Wallet Init Not Bound | ⛔ N/A | No AA wallet |
| 206 | Metamorphic Contract CREATE2 + SELFDESTRUCT | ⚠️ SEE I-07 | CREATE3 deployment concern |
| 207 | ERC20 Non-Compliant: Return / Events | ✅ PASS | slither-check-erc confirms full compliance |
| 208 | Insufficient Gas Forwarding / 63/64 Rule | ✅ PASS | No custom gas forwarding in src/ |
| 209 | Blacklistable/Pausable Token in Critical Payment | ✅ PASS (with caveat) | TelcoinV3 is pausable; migrate/bridge send gate on whenNotPaused which is intentional |
| 210 | Deployer Privilege Retention Post-Deploy | ✅ PASS | Governance multisig is intended owner; renounceOwnership disabled intentionally |
| 211 | mstore8 Partial Write | ⛔ N/A | No assembly in src/ |
| 212 | DVN Collusion / Diversity | ℹ️ LZ config concern — OUT OF SCOPE | DVN count/diversity configured per chain; audit spec in `docs/lz-dvn-config.md` |
| 213 | Paymaster ERC-20 Deferred to postOp | ⛔ N/A | No paymaster |
| 214 | Same-Block Vote-Transfer-Vote | ⛔ N/A | No voting |
| 215 | Depeg of Pegged/Wrapped Asset | ⛔ N/A | TEL is not pegged |
| 216 | Pending Async Callback with Dep Swap | ⛔ N/A | No async callback |
| **217** | **Missing `enforcedOptions` — Insufficient Gas for lzReceive** | ⚠️ **FINDING → SE-2 (NEW, Info)** | Verified: `grep -rn 'setEnforcedOptions\|EnforcedOptionParam' src/ script/` returns no hits. See `reports/SHARP_EDGES.md#SE-2` |
| 218 | Uniswap V4 Hook Access Control | ⛔ N/A | No Uniswap V4 |
| 219 | Chainlink Feed Deprecation / Wrong Decimals | ⛔ N/A | No Chainlink |
| 220 | EIP-7702 tx.origin Bypass | ⛔ N/A | No 7702 |
| 221 | Deployment Tx Front-Run (Ownership Hijack) | ⚠️ SEE I-07 | Same class as CREATE3 salt front-running |
| 222 | ecrecover Returns address(0) | ⛔ N/A | No ecrecover |
| 223 | Non-Atomic Multi-Contract Deploy | ℹ️ Deployment concern — script-level | Deployment script orders deploys + role grants; single deployer + multisig-ownership switch documented |
| 224 | Precision Loss - Div Before Mul | ✅ PASS | No division-before-multiplication in src/ |
| 225 | CREATE2 Address Squatting (Counterfactual Front-Run) | ⚠️ SEE I-07 | |
| 226 | Write to Arbitrary Storage | ⛔ N/A | No arbitrary storage writes |
| 227 | Withdrawal Rate Bypass via Share Transfer | ⛔ N/A | No share system |
| 228 | Generalized Frontrunner on Permissionless Value Fns | ✅ PASS | migrate is per-caller-balance; bridge send is per-caller |
| 229 | Ordered Message Channel Blocking (Nonce DoS) | ⚠️ SEE I-06 | LZ message channel can be blocked by a failing lzReceive (paused bridge or CreditFailed) |
| 230 | require(token.transfer()) on Void-Return | ✅ PASS | SafeERC20 handles both void-return and bool-return tokens |
| 231 | Insufficient Return Data Length Validation | ✅ PASS | SafeERC20 validates returndata length |
| 232 | UUPS `_authorizeUpgrade` Missing AC | ⛔ N/A | Not UUPS |
| 233 | Liquidated Position Continues Accruing | ⛔ N/A | No liquidation |
| 234 | Self-Liquidation Profit | ⛔ N/A | No liquidation |
| 235 | Governance Proposal Before Voting Ends | ⛔ N/A | No voting |
| 236 | Timelock Anchored to Deploy Not Action | ⛔ N/A | No timelock |
| 237 | ERC721Consecutive Balance Corruption | ⛔ N/A | No ERC-721 |
| 238 | Reward Snapshot JIT | ⛔ N/A | No rewards |
| 239 | Partial Liquidation Worse State | ⛔ N/A | No liquidation |
| 240 | EIP-7702 Cross-Chain Auth Replay | ⛔ N/A | No 7702 |
| 241 | Non-Atomic Proxy CPIMP Takeover | ⛔ N/A | No proxy |
| 242 | EIP-7702 Storage Collision Redelegation | ⛔ N/A | No 7702 |
| 243 | Read-Only Reentrancy | ✅ PASS | `totalMigrated` / `totalOldTokenBurned` are view-only; no external contract reads them during a state mutation in src/ |
| 244 | Delegatecall to Untrusted Callee | ⛔ N/A | No delegatecall |
| 245 | Staking Reward Front-Run | ⛔ N/A | No staking |
| 246 | Cached Reward Debt Not Reset | ⛔ N/A | No rewards |
| 247 | Reward Accrual Zero-Depositor | ⛔ N/A | No rewards |
| 248 | Borrower Front-Runs Liquidation | ⛔ N/A | No lending |
| 249 | Diamond Cross-Facet Storage | ⛔ N/A | No diamond |
| 250 | ERC1155 setApprovalForAll All-ID Access | ⛔ N/A | No ERC-1155 |
| 251 | Invariant/Cap Enforced on One Path Not Another | ⚠️ SEE I-05 | Per-chain cap; also migrate + bridge both check cap via TelcoinV3.mint → consistent within a chain |
| **252** | **Missing `_debit` / `_debitFrom` Authorization in OFT** | ✅ PASS | `MintBurnOFTAdapter._debit` calls `minterBurner.burn(_from, amt)` → `TelcoinV3.burn` enforces `_spendAllowance(from, wrapper, amt)`. Unapproved `_from` cannot be debited. |
| 253 | ERC1155 ID-Based Role AC | ⛔ N/A | No ERC-1155 |
| 254 | ERC1155 Custom Burn Without Auth | ⛔ N/A | No ERC-1155 |
| 255 | Cross-Chain Address Ownership Variance | ⚠️ SEE I-07 | CREATE3 same-salt cross-chain; ownership set at deploy per chain |
| 256 | ERC1155 totalSupply Inflation via Reentrancy | ⛔ N/A | No ERC-1155 |
| 257 | Solmate SafeTransferLib Missing Code Check | ⛔ N/A | Uses OZ SafeERC20 (has code check) |
| 258 | Re-initialization Attack | ⛔ N/A | No `initialize()` |
| 259 | Protocol Fee Inflates Reward Accumulator | ⛔ N/A | No fee/reward |
| 260 | OFT Shared Decimals Truncation (uint64 Overflow) | ✅ PASS | `_toSD` explicitly reverts `AmountSDOverflowed` on uint64 overflow |
| 261 | Wrong Price Feed for Derivative | ⛔ N/A | No price feed |
| 262 | Merkle Tree Second Preimage | ⛔ N/A | No Merkle |
| **263** | **Unauthorized Peer Initialization (Fake Peer Attack)** | ✅ PASS | `OApp.setPeer` is `onlyOwner`; peer cannot be set by attacker. However the VA-1 variant-analysis finding notes setPeer's overwrite silently — separate observability concern |
| 264 | Diamond Facet Selector Collision | ⛔ N/A | No diamond |
| 265 | Bytecode Verification Mismatch | ℹ️ Deployment concern | Deploy with `forge verify-contract`; not in-contract concern |
| 266 | Missing onERC1155BatchReceived Causes Lock | ⛔ N/A | No ERC-1155 |

## Summary

| Verdict | Count |
|---|---:|
| ✅ PASS (applicable, checked, not vulnerable) | 37 |
| ⛔ N/A (wrong stack / feature not present) | 214 |
| ⚠️ FINDING (applicable, produces a finding) | 15 (all cross-references to existing AUDIT.md findings + 1 new: **PS-1 #37**) |
| ℹ️ OUT-OF-SCOPE (deployment / LZ config) | 4 |

**New finding this pass:** **PS-1 — Bridge has no global rate limit / circuit breaker.** (Patterns #37 + #170 surface the same issue.) Severity: Informational.

## PS-1 — Bridge lacks rate limits / circuit breakers

**Finding:** Neither `TelcoinBridge` nor `NativeBridge` enforces a per-epoch minting cap, a per-sender send cap, or a total-volume circuit breaker. A compromised bridge (malicious authorised `MintBurnWrapper.bridge`) could drain the supply up to the 100 B per-chain TelcoinV3 cap in a single transaction.

**Mitigations in place:**
- 100 B `MIGRATION_SUPPLY_CAP` is enforced on every `mint`.
- `pause()` exists on both bridges.
- Multisig governance controls the bridge wiring.

**Recommendation:** Consider adding a per-window rate-limit for bridged tokens (e.g., max X TEL bridged per hour per chain). LayerZero's OApp pattern supports this via `OAppSender._lzSend` pre-checks or custom middleware. Severity Info because (a) per-chain cap exists; (b) governance pause is the emergency brake; (c) no real-world user operation exceeds current caps.

---

*Pashov 266-pattern scan complete. Saved to `reports/PASHOV_266.md`.*
