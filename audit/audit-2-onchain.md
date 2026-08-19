# TEL v3 On-Chain State Verification (Mainnet + Testnet)

**Target:** `Telcoin-Association/tel-v3`
**Commit reviewed:** `03d29d490f245c4015f550d89badb4892577f70a` (`main`)
**Date:** 2026-08-19
**Reviewer:** Claude (Anthropic), automated + manual review, run by aisecurity@telco.in
**Type:** On-chain state verification, companion to `audit/audit.md` (source-code review, same date)

## 0. Read this first

`audit/audit.md` in this same folder reviewed the *source code*. This document instead reviews the *live deployed contracts*: does the bytecode actually on-chain, and the roles/ownership/configuration actually set right now, match what the source and deploy scripts say should be there? A verified contract that doesn't match audited source, or a role quietly granted to an unexpected address, is exactly the class of problem a source-only review cannot catch.

Addresses were taken from Telcoin's own Confluence page ("TEL v3 Contract Addresses", August 18, 2026 deployment) and independently cross-checked against this repo's own `deployments/eth-sepolia.json` and `deployments/base-sepolia.json` — they matched exactly. All queries below are read-only (`cast call`/`cast storage`/`cast code`, Foundry 1.5.1-stable); nothing was broadcast.

**Bottom line up front:** no privilege-escalation or fund-safety issue was found on any of the five networks checked. One real but low-impact governance inconsistency was found on testnet (§3.1: a legacy faucet still owned by a stale, unrelated Safe instead of the current governance Safe). One apparent anomaly (same address, different bytecode hash, across chains) was investigated byte-by-byte and is fully explained by legitimate per-chain immutables (§3.2), not a backdoor.

---

## 1. Scope

**Mainnet** (Ethereum, Base, Polygon — chain IDs 1, 8453, 137): only `TelcoinV3` is deployed so far, at the same address on all three, `0x7E13B43065380aCdeC1c2d138c579cbBbafA0731`. Bridges and migration infrastructure are not yet live on mainnet (confirmed below, not assumed).

**Testnet** ("August 18, 2026" deployment, ETH Sepolia chainId 11155111 + Base Sepolia chainId 84532): the full stack — `TelcoinV3`, `TelcoinLegacy`, `TokenMigration`, `MigrationVault`, `TelcoinBridge`, `MintBurnWrapper`, `TelcoinV3Faucet`, `LegacyTelcoinFaucet`.

Queried at ETH Sepolia block 11,524,642 and Base Sepolia block 45,703,046 (2026-08-19).

---

## 2. Verified correct

### 2.1 Mainnet — TelcoinV3, all three chains (Ethereum, Base, Polygon)

Constructor (`src/TelcoinV3.sol:41-44`) only grants `DEFAULT_ADMIN_ROLE`; `PAUSER_ROLE`/`UNPAUSER_ROLE` are granted separately in the same deploy batch (`script/base/BaseDeployToken.s.sol:94-102`); `MINTER_ROLE`/`BURNER_ROLE` are never granted by the token-only mainnet script. Live state on **all three** mainnet chains matches this exactly:

| Check | Ethereum | Base | Polygon |
|---|---|---|---|
| `DEFAULT_ADMIN_ROLE` holder | `0x6012d...eB03` (1) | same | same |
| `PAUSER_ROLE` holder | `0xC4D09...B086` (1) | same | same |
| `UNPAUSER_ROLE` holder | `0xf0700...4f07` (1) | same | same |
| `MINTER_ROLE` count | 0 | 0 | 0 |
| `BURNER_ROLE` count | 0 | 0 | 0 |
| `totalSupply()` | 0 | 0 | 0 |
| `paused()` | false | false | false |

All three addresses match `script/mainnet/utils/Roles.sol:8-10` (`ADMIN`/`PAUSER`/`UNPAUSER`) exactly. No role has ever drifted from what a fresh, token-only deploy should produce.

**Multisig structure, independently verified (not assumed from a variable name):**

- `ADMIN` (`0x6012dBcb4350Ab297FeB7f96D4d86258062aeB03`) is a real Gnosis Safe: `getOwners()` returns 8 addresses, `getThreshold()` = **2**.
- `PAUSER` (`0xC4D09Da0825dBf89A2B755E20b35f39fF455B086`) is a separate Safe: 7 of the same 8 owners (missing one), `getThreshold()` = **1**.
- `UNPAUSER` (`0xf0700ccbf77F05CB1bDB6b9EdbEc6B0d33214f07`) is a third Safe: the same 7 owners as `PAUSER`, `getThreshold()` = **2**.

This is a coherent, deliberately graduated design: pausing (an emergency brake) needs only 1-of-7 signers and can happen fast; unpausing and full admin actions (role grants, `rescueBurn`, `rescueTokens`) need 2-of-7 or 2-of-8. Worth recording as a positive finding, not just an absence of problems.

### 2.2 Bytecode identity across all four TelcoinV3 deployments

`cast codesize` = `16172` identically on ETH Sepolia, Base Sepolia, ETH mainnet, and Base mainnet. A full byte-level diff of the runtime bytecode (32,346 hex chars each) found it **identical on all four except one ~35-40 byte region**, which is fully explained: OpenZeppelin's `EIP712`/`ERC20Permit` cached chain-ID and domain-separator immutables. The embedded chain-ID literal reads `aa36a7` (11155111), `014a34` (84532), `000001` (1), `002105` (8453) respectively — exactly each chain's real ID — followed by the correspondingly different cached domain-separator hash. This is the correct EIP-712 anti-replay design, not a backdoor or unauthorized modification. See also §3.2.

### 2.3 Testnet — TelcoinV3 role wiring, both chains, byte-for-byte identical

Now that bridges + migration are live on testnet, `MINTER_ROLE`/`BURNER_ROLE` are expected to be populated (unlike mainnet). Verified via `getRoleMemberCount`/`getRoleMember` (the contract is `AccessControlEnumerable`):

| Role | Expected (script citation) | ETH Sepolia | Base Sepolia |
|---|---|---|---|
| `DEFAULT_ADMIN_ROLE` | ADMIN Safe (`src/TelcoinV3.sol:41-44`) | 1 holder, match | 1 holder, match |
| `PAUSER_ROLE` | PAUSER EOA-Safe (`BaseDeployToken.s.sol:97`) | 1 holder, match | 1 holder, match |
| `UNPAUSER_ROLE` | UNPAUSER Safe (`BaseDeployToken.s.sol:102`) | 1 holder, match | 1 holder, match |
| `MINTER_ROLE` | MintBurnWrapper + TokenMigration + TelcoinV3Faucet (`BaseDeployBridges.s.sol:165`, `BaseDeployMigrationInfra.s.sol:148`, `BaseDeployFaucets.s.sol:130`) | 3 holders, exact match | identical 3 holders |
| `BURNER_ROLE` | MintBurnWrapper only (`BaseDeployBridges.s.sol:171`) | 1 holder, match | 1 holder, match |

No extra or missing holder on either chain. `paused()` = false, `name/symbol/decimals` = `Telcoin/TEL/18` on both.

### 2.4 Testnet — bridge/wrapper/migration/faucet wiring, both chains

All cross-referenced via live getters, not assumed from deploy-script intent alone:

- **MintBurnWrapper** (`0x4A1c...D149`): `owner()` = ADMIN Safe, `token()` = TelcoinV3, `bridge()` = TelcoinBridge, `pendingOwner()` = 0x0 — all match on both chains. Codehash identical cross-chain (its only immutable, `token`, is the same literal on every chain).
- **TelcoinBridge** (`0x6A7E...476a7e`): `owner()` = ADMIN Safe, `token()` = TelcoinV3, `endpoint()` = the real LayerZero V2 endpoint (24,005 bytes of code, present on both chains), `paused()` = false, `getRoleMemberCount(DEFAULT_ADMIN_ROLE)` = **0** (role admin here is `onlyOwner`, by design — `src/TelcoinBridge.sol:136-145` — not `DEFAULT_ADMIN_ROLE`, so 0 is correct, not a bug), `PAUSER_ROLE`/`UNPAUSER_ROLE` = 1 holder each, matching. LayerZero `peers()` on each chain correctly resolves to the bridge's own (CREATE3-identical) address on the other chain. Codehash identical cross-chain.
- **MigrationVault** (`0x222213...733333`, UUPS proxy): EIP-1967 implementation slot resolves to `0xcb4dd481bc39ce4da402ec1e00539b4c29153372` on both chains, which carries real code (10,876 bytes). `OLD_TOKEN()`/`NEW_TOKEN()` correctly resolve per-chain (each chain's own legacy token / the shared TelcoinV3). `hasRole` confirms ADMIN/PAUSER/UNPAUSER/TREASURY roles are exactly where `initialize()` (`src/MigrationVault.sol:134-147`) and `BaseDeployMigrationInfra.s.sol:154` put them. `paused()` = false, `getReserves()` = `(0,0)` (not yet funded — consistent with `totalSupply()` = 0 everywhere).
- **TokenMigration** (`0x2703...c2703`): `oldToken()`/`telcoinV3()` correctly resolve per chain; `withdrawalDelay()` = 90 days, `migrationExpiry()` ≈ 365 days out from the actual broadcast timestamp on each chain (the 86-second cross-chain gap in the expiry timestamp is exactly what a sequential per-chain deploy loop produces, not an anomaly); `migrationClosed()`/`paused()` = false; admin/pauser/unpauser roles match.
- **Faucets**: `TelcoinV3Faucet` — owner/token/drip(1000 TEL)/cooldown(1h) all match script intent, identical bytecode both chains. `LegacyTelcoinFaucet` — token resolves per-chain, drip/cooldown match, and it actually holds ~10M legacy TEL to dispense on each chain (won't revert empty) — **except its `owner()`, see Finding 3.1.**
- **No stray funds:** `balanceOf()` for TelcoinV3 and each chain's legacy TEL against MigrationVault, TokenMigration, MintBurnWrapper, and TelcoinBridge all returned 0 on both chains — consistent with a freshly wired, not-yet-used stack, not a drain.
- **TelcoinLegacy** (the pre-existing v2 token, not a fresh CREATE3 deploy): both chains' addresses are real 0.4.18-era ERC20s, `totalSupply()` = 100B raw units (matches the hardcoded constant in `src/legacy/Telcoin.sol:45`) — the two chains legitimately have independent bytecode/addresses here, that was never expected to match.

---

## 3. Findings

### 3.1 [Low] `LegacyTelcoinFaucet` is owned by a stale, unrelated Safe — not the current governance Safe

**Contract:** `LegacyTelcoinFaucet` `0x9c5AE301f86305b580e4A01fb86c5924438E7874` — **both** ETH Sepolia and Base Sepolia.

**Expected:** `script/testnet/4_DeployFaucets.s.sol:36` sets `_admin = ADMIN` (the current 2-of-8 governance Safe, `0x6012d...eB03`); a fresh `LegacyTelcoinFaucet` deploy sets `owner = _admin`.

**Actual:** `owner()` on both chains returns `0x765327d1AeA74cC360B1C6Cc567200d7e4baC3fD` — a **different**, real Gnosis Safe (v1.4.1, 1-of-2, owners `0xDCe4Ef...45B5BA` and `0xa21B09...f8fDaff248`). This address is independently documented elsewhere in this repo as an older testnet vanity-address artifact (`script/utils/vanity/README.md:82`, `script/utils/vanity/mine_vanity_salt.c:478`), predating the current `ADMIN` Safe.

**Why it happened:** `BaseDeployFaucets.s.sol:110-125` deliberately does not redeploy an already-existing `LegacyTelcoinFaucet` on each run (so it keeps its accumulated balance across stack redeploys). That's reasonable, but it means this one contract's ownership was never migrated forward when the pipeline's governance Safe changed to the current address — and nothing in the current deploy script surfaces that, since the script's `_admin` variable is always the current `ADMIN`.

**Impact:** the current governance Safe has **zero control** over this contract — it cannot pause drips, edit any allowlist, or withdraw the ~10M test TEL v2 it holds; that authority sits entirely with two EOAs behind an unrelated 1-of-2 Safe. Capped at Low severity because this is testnet play-money with no real value at risk, but it is a genuine governance inconsistency a source-only read of the current script would never reveal.

**Recommendation:** either call `transferOwnership` to the current `ADMIN` Safe, or explicitly document in `Roles.sol`/README that this specific contract is intentionally carved out of standard governance rotation.

### 3.2 [Informational] Same-address-different-codehash cases are real but fully explained

**Contracts:** TelcoinV3 (across all four chains) and MigrationVault's implementation (across the two testnets).

`codesize` matches but `codehash` differs for these two. Byte-level diffing (not just a codehash comparison) traced every differing byte to a legitimate per-chain immutable: TelcoinV3's EIP-712 chain-ID/domain-separator cache (§2.2), and MigrationVault implementation's embedded `OLD_TOKEN` address (genuinely different per chain, since ETH Sepolia and Base Sepolia have independent legacy-token deployments). No other byte differs in either case. Recorded because a same-address-different-bytecode pattern is exactly the shape a real backdoor would take — worth documenting that this one was checked byte-by-byte and cleared, not just glanced at.

### 3.3 No other drift found

Every other cross-chain-identical testnet address (MintBurnWrapper, TelcoinBridge, TelcoinV3Faucet, MigrationVault's proxy) has byte-for-byte identical codehash on both chains. TokenMigration's and LegacyTelcoinFaucet's cross-chain codehash differences were byte-diffed and traced exclusively to their own legacy-token immutables. Every role holder, owner address (except §3.1), peer config, endpoint address, drip amount, cooldown, and conversion factor matched deploy-script intent exactly, on every chain checked. No RPC call failed during this review.

---

## 4. Method notes

- Public RPCs used: `https://ethereum-rpc.publicnode.com`, `https://mainnet.base.org`, `https://polygon-bor-rpc.publicnode.com` (mainnet); `https://ethereum-sepolia-rpc.publicnode.com`, `https://sepolia.base.org` (testnet). `https://polygon-rpc.com` (the first Polygon endpoint tried) returned `HTTP 401 API key disabled` — a dead public endpoint, unrelated to the target contracts; the publicnode alternative worked.
- The EIP-1967 implementation-slot constant used in early drafts of this review's brief was one hex digit short (`...382bb` instead of the canonical `...382bbc`); this was caught before it produced a false "empty slot" reading, by cross-validating against `cast implementation` and the constant already present in this repo at `lib/forge-deploy-utils/src/DeployBase.sol:21`.
- All role/ownership/getter values above are exact `cast` output against live RPC endpoints, not inferred from source or from the deployments JSON alone.
