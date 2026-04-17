# Pashov/skills — attack-vectors.md coverage

Pashov's `solidity-auditor/references/attack-vectors/attack-vectors.md` contains ~100 numbered attack patterns. This file records the patterns that are *active* for this codebase (ERC-20 + migration + LayerZero OFT mesh):

| # | Pattern | Applicability | Finding (if any) |
|---|---------|---------------|------------------|
| 1 | Cross-Chain Message Spoofing (missing endpoint/peer validation) | Active | ✅ OAppReceiver.lzReceive verifies `msg.sender == endpoint` + peer — not vulnerable |
| 2 | EIP-7702 Code Inspection Opcode Invalidation | N/A | No `extcodesize`/`extcodehash` branching in scope |
| 3 | Paymaster Gas Penalty Undercalculation | N/A | No ERC-4337 paymaster |
| 4 | Reward Rate Changed Without Settling Accumulator | N/A | No staking/rewards |
| 5 | lzCompose Sender Impersonation | Active | ✅ OFTCore `_lzReceive` doesn't compose custom app payloads; `_message.isComposed()` routes to `endpoint.sendCompose` only with `toAddress` from the message. No custom `lzCompose` override in scope |
| 6 | Tick Crossing Fee Accounting (JIT) | N/A | No Uniswap-v3-style liquidity |
| 7 | Withdrawal Queue Rate Lock-In | N/A | No queued withdrawals |
| 8 | Partial Redemption Fails to Reduce Tracked Total | N/A | No redemption queue |
| … (ERC-20 patterns) | Approve front-running, infinite approval drainage | Active | ✅ Migration uses per-call `balanceOf(msg.sender)` → front-runner cannot migrate someone else's tokens (msg.sender's own balance consumed). Wrapper burn requires user's explicit approval |
| … (Role patterns) | Compromised BURNER drains wallets | Active | ✅ `TelcoinV3.burn` requires allowance; `rescueBurn` gated by DEFAULT_ADMIN_ROLE (separate from BURNER_ROLE) |
| … (Upgrade patterns) | Storage collision, uninitialised proxy | N/A | No proxies |
| … (Oracle patterns) | Spot-price / TWAP manipulation, stale rounds | N/A | No oracle |
| … (MEV patterns) | Sandwich, front-run, back-run | Active | ✅ Migration is 1:1 fixed — not MEV-extractable. Bridge messages are gas-priority-agnostic |
| … (DoS patterns) | Unbounded loops, gas limits | Active | ✅ No loops in critical paths. `NativeBridge._credit` push-ETH noted as I-06 (LZ platform limitation) |
| … (Signature patterns) | Replay, malleability, s-bound | N/A | No signatures |

Relevant patterns actively reviewed and not found vulnerable. See `reports/AUDIT.md` for the exhaustive checklist coverage table.
