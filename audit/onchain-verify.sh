#!/usr/bin/env bash
#
# On-chain state verification for TEL v3 (tel-v3 + tel-v3-staking).
# Re-runnable version of audit/audit-2-onchain.md in both repos: re-checks
# roles, ownership, proxy wiring, and key config against what the deploy
# scripts intend. Read-only (cast call/storage/code) — never broadcasts.
#
# Why this exists: CREATE2/CREATE3 deploys plus a separate post-deploy
# initializer call (MigrationVault and StakingModule are both upgradeable
# proxies with `initialize()`) are a known target for front-running — if
# anyone else's transaction calls `initialize()` or grabs a role before the
# legitimate deployer's batched Safe transaction lands, they can seize
# admin/owner/role control of an otherwise-correctly-coded contract, with
# no bug in the source at all. This script doesn't prevent that; it catches
# it after the fact by independently re-deriving who *should* hold every
# role/owner slot (from source + deploy scripts) and then reading who
# *actually* does, live. A mismatch here is the signature of a successful
# front-run or silent drift, not just a formatting issue.
#
# Requires: foundry (`cast` on PATH). No API keys needed — uses public RPCs
# by default; override any of them via env vars if you hit rate limits:
#   ETH_RPC_URL, BASE_RPC_URL, POLYGON_RPC_URL, ETH_SEPOLIA_RPC_URL, BASE_SEPOLIA_RPC_URL
#
# Usage: ./onchain-verify.sh [mainnet|testnet|staking|all]   (default: all)

set -u

ETH_RPC_URL=${ETH_RPC_URL:-https://ethereum-rpc.publicnode.com}
BASE_RPC_URL=${BASE_RPC_URL:-https://mainnet.base.org}
POLYGON_RPC_URL=${POLYGON_RPC_URL:-https://polygon-bor-rpc.publicnode.com}
ETH_SEPOLIA_RPC_URL=${ETH_SEPOLIA_RPC_URL:-https://ethereum-sepolia-rpc.publicnode.com}
BASE_SEPOLIA_RPC_URL=${BASE_SEPOLIA_RPC_URL:-https://sepolia.base.org}

MODE=${1:-all}

# ---------
# Addresses
# ---------

TEL_V3=0x7E13B43065380aCdeC1c2d138c579cbBbafA0731
ADMIN=0x6012dBcb4350Ab297FeB7f96D4d86258062aeB03      # governance Safe, 2-of-8
PAUSER=0xC4D09Da0825dBf89A2B755E20b35f39fF455B086     # pauser Safe, 1-of-7
UNPAUSER=0xf0700ccbf77F05CB1bDB6b9EdbEc6B0d33214f07    # unpauser Safe, 2-of-7

# testnet (Aug 18 2026 deployment) — shared CREATE3 addresses across ETH/Base Sepolia
LEGACY_FAUCET=0x9c5AE301f86305b580e4A01fb86c5924438E7874
MIGRATION_VAULT=0x222213DeB441C5A9F71Df2942db431978a733333
MINT_BURN_WRAPPER=0x4A1c2ab0661651Ee55C41DB1239F292e00C3D149
TELCOIN_BRIDGE=0x6A7E6616653e84eee0c70257eC2E3d79A4476a7e
TEL_V3_FAUCET=0x7E1a15f7B25bdcfB58D81B90d4F1769b72E1bc00
TOKEN_MIGRATION=0x2703E00cAE30A7707e4d18C38f8CB6A4a40c2703
MIGRATION_VAULT_IMPL_EXPECTED=0xcb4dd481bc39ce4da402ec1e00539b4c29153372
# TelcoinLegacy differs per chain (not a CREATE3 deploy)
TEL_LEGACY_ETH_SEPOLIA=0x1355E162c9Ab248b5357494E5BD68c6A63eD82FB
TEL_LEGACY_BASE_SEPOLIA=0xa4253Ed090D6e280e4880b4319B306498731Ee04
LEGACY_FAUCET_KNOWN_STALE_OWNER=0x765327d1AeA74cC360B1C6Cc567200d7e4baC3fD  # see audit-2-onchain.md 3.1

# staking (ETH Sepolia only — Polygon not deployed yet)
STAKING_PROXY=0x573105BE2148B8621F202a6d510016a2Aa825731
STAKING_IMPL_EXPECTED=0xD12ba966cc3eBc87F1b8bcbF1fa3Bfed397203Ae
STAKING_V2=0xdAaf7da2ebE75ab8A768B4D8Bf4ede1246b11241
STAKING_MIGRATOR=0x5731937345D426025aFb2eBf9EE50067D5bb2703
SIMPLE_PLUGIN=0x5731ab138f5eb41dd62C722AeF8Bf3BE26cafEe5

EIP1967_IMPL_SLOT=0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc
DEFAULT_ADMIN_ROLE=$(printf '0x%064x' 0)

# ------------------
# Colors and counters
# ------------------

PASS=0; FAIL=0; WARN=0
GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[0;33m'; NC='\033[0m'

# ok LABEL [VALUE]  — VALUE is the actual on-chain value that just passed,
# printed so a reviewer can sanity-check it without re-running the query.
ok() {
  PASS=$((PASS+1))
  if [ -n "${2:-}" ]; then
    printf "  ${GREEN}PASS${NC}  %s\n     value:    %s\n" "$1" "$2"
  else
    printf "  ${GREEN}PASS${NC}  %s\n" "$1"
  fi
}
bad()  { FAIL=$((FAIL+1)); printf "  ${RED}FAIL${NC}  %s\n     expected: %s\n     actual:   %s\n" "$1" "$2" "$3"; }
warn() { WARN=$((WARN+1)); printf "  ${YELLOW}WARN${NC}  %s (known finding, see audit-2-onchain.md)\n     value:    %s\n" "$1" "$2"; }

# check LABEL EXPECTED ACTUAL
check() {
  if [ "$(echo "$2" | tr '[:upper:]' '[:lower:]')" = "$(echo "$3" | tr '[:upper:]' '[:lower:]')" ]; then
    ok "$1" "$3"
  else
    bad "$1" "$2" "$3"
  fi
}

role_hash() { cast keccak "$1"; }

# hasRole CONTRACT ROLE_NAME ROLE_HASH ACCOUNT RPC -> true/false string
has_role() {
  cast call "$1" "hasRole(bytes32,address)(bool)" "$3" "$4" --rpc-url "$5" 2>/dev/null
}

# name_for ADDRESS -> a human-readable label for known testnet contracts, or "unrecognized address"
name_for() {
  case "$(echo "$1" | tr '[:upper:]' '[:lower:]')" in
    "$(echo "$MINT_BURN_WRAPPER" | tr '[:upper:]' '[:lower:]')") echo "MintBurnWrapper" ;;
    "$(echo "$TOKEN_MIGRATION" | tr '[:upper:]' '[:lower:]')") echo "TokenMigration" ;;
    "$(echo "$TEL_V3_FAUCET" | tr '[:upper:]' '[:lower:]')") echo "TelcoinV3Faucet" ;;
    *) echo "unrecognized address" ;;
  esac
}

section() { printf "\n=== %s ===\n" "$1"; }

# ============================================================
# MAINNET — TelcoinV3 only (Ethereum, Base, Polygon)
# ============================================================
run_mainnet() {
  MINTER_ROLE=$(role_hash "MINTER_ROLE")
  BURNER_ROLE=$(role_hash "BURNER_ROLE")
  PAUSER_ROLE=$(role_hash "PAUSER_ROLE")
  UNPAUSER_ROLE=$(role_hash "UNPAUSER_ROLE")

  for pair in "ethereum:$ETH_RPC_URL" "base:$BASE_RPC_URL" "polygon:$POLYGON_RPC_URL"; do
    chain=${pair%%:*}; rpc=${pair#*:}
    section "MAINNET / $chain / TelcoinV3 ($TEL_V3)"

    check "DEFAULT_ADMIN_ROLE holder count == 1" "1" \
      "$(cast call $TEL_V3 'getRoleMemberCount(bytes32)(uint256)' $DEFAULT_ADMIN_ROLE --rpc-url $rpc 2>/dev/null)"
    check "DEFAULT_ADMIN_ROLE holder == governance Safe ($ADMIN)" "$ADMIN" \
      "$(cast call $TEL_V3 'getRoleMember(bytes32,uint256)(address)' $DEFAULT_ADMIN_ROLE 0 --rpc-url $rpc 2>/dev/null)"
    check "PAUSER_ROLE holder == pauser Safe ($PAUSER)" "$PAUSER" \
      "$(cast call $TEL_V3 'getRoleMember(bytes32,uint256)(address)' $PAUSER_ROLE 0 --rpc-url $rpc 2>/dev/null)"
    check "UNPAUSER_ROLE holder == unpauser Safe ($UNPAUSER)" "$UNPAUSER" \
      "$(cast call $TEL_V3 'getRoleMember(bytes32,uint256)(address)' $UNPAUSER_ROLE 0 --rpc-url $rpc 2>/dev/null)"
    check "MINTER_ROLE holder count == 0 (bridges not live on mainnet)" "0" \
      "$(cast call $TEL_V3 'getRoleMemberCount(bytes32)(uint256)' $MINTER_ROLE --rpc-url $rpc 2>/dev/null)"
    check "BURNER_ROLE holder count == 0" "0" \
      "$(cast call $TEL_V3 'getRoleMemberCount(bytes32)(uint256)' $BURNER_ROLE --rpc-url $rpc 2>/dev/null)"
    check "totalSupply == 0 (no mainnet minting yet)" "0" \
      "$(cast call $TEL_V3 'totalSupply()(uint256)' --rpc-url $rpc 2>/dev/null)"
    check "paused == false" "false" \
      "$(cast call $TEL_V3 'paused()(bool)' --rpc-url $rpc 2>/dev/null)"
  done
}

# ============================================================
# TESTNET — tel-v3 full suite (ETH Sepolia + Base Sepolia)
# ============================================================
run_testnet() {
  MINTER_ROLE=$(role_hash "MINTER_ROLE")
  BURNER_ROLE=$(role_hash "BURNER_ROLE")
  PAUSER_ROLE=$(role_hash "PAUSER_ROLE")
  UNPAUSER_ROLE=$(role_hash "UNPAUSER_ROLE")
  TREASURY_ROLE=$(role_hash "TREASURY_ROLE")

  for pair in "eth-sepolia|$ETH_SEPOLIA_RPC_URL|$TEL_LEGACY_ETH_SEPOLIA" "base-sepolia|$BASE_SEPOLIA_RPC_URL|$TEL_LEGACY_BASE_SEPOLIA"; do
    chain=$(echo "$pair" | cut -d'|' -f1); rpc=$(echo "$pair" | cut -d'|' -f2); tel_legacy=$(echo "$pair" | cut -d'|' -f3)

    section "TESTNET / $chain / TelcoinV3 roles ($TEL_V3)"
    check "MINTER_ROLE holder count == 3" "3" \
      "$(cast call $TEL_V3 'getRoleMemberCount(bytes32)(uint256)' $MINTER_ROLE --rpc-url $rpc 2>/dev/null)"
    for i in 0 1 2; do
      holder=$(cast call $TEL_V3 'getRoleMember(bytes32,uint256)(address)' $MINTER_ROLE $i --rpc-url $rpc 2>/dev/null)
      hname=$(name_for "$holder")
      if [ "$hname" != "unrecognized address" ]; then
        ok "MINTER_ROLE member[$i] is a known contract" "$holder ($hname)"
      else
        bad "MINTER_ROLE member[$i] is one of {MintBurnWrapper, TokenMigration, TelcoinV3Faucet}" \
          "$MINT_BURN_WRAPPER | $TOKEN_MIGRATION | $TEL_V3_FAUCET" "$holder"
      fi
    done
    check "BURNER_ROLE holder count == 1" "1" \
      "$(cast call $TEL_V3 'getRoleMemberCount(bytes32)(uint256)' $BURNER_ROLE --rpc-url $rpc 2>/dev/null)"
    check "BURNER_ROLE holder == MintBurnWrapper ($MINT_BURN_WRAPPER)" "$MINT_BURN_WRAPPER" \
      "$(cast call $TEL_V3 'getRoleMember(bytes32,uint256)(address)' $BURNER_ROLE 0 --rpc-url $rpc 2>/dev/null)"

    section "TESTNET / $chain / MintBurnWrapper ($MINT_BURN_WRAPPER)"
    check "owner == governance Safe ($ADMIN)" "$ADMIN" \
      "$(cast call $MINT_BURN_WRAPPER 'owner()(address)' --rpc-url $rpc 2>/dev/null)"
    check "token == TelcoinV3 ($TEL_V3)" "$TEL_V3" \
      "$(cast call $MINT_BURN_WRAPPER 'token()(address)' --rpc-url $rpc 2>/dev/null)"
    check "bridge == TelcoinBridge ($TELCOIN_BRIDGE)" "$TELCOIN_BRIDGE" \
      "$(cast call $MINT_BURN_WRAPPER 'bridge()(address)' --rpc-url $rpc 2>/dev/null)"

    section "TESTNET / $chain / TelcoinBridge ($TELCOIN_BRIDGE)"
    check "owner == governance Safe ($ADMIN)" "$ADMIN" \
      "$(cast call $TELCOIN_BRIDGE 'owner()(address)' --rpc-url $rpc 2>/dev/null)"
    check "token == TelcoinV3 ($TEL_V3)" "$TEL_V3" \
      "$(cast call $TELCOIN_BRIDGE 'token()(address)' --rpc-url $rpc 2>/dev/null)"
    check "paused == false" "false" \
      "$(cast call $TELCOIN_BRIDGE 'paused()(bool)' --rpc-url $rpc 2>/dev/null)"
    check "PAUSER_ROLE count == 1" "1" \
      "$(cast call $TELCOIN_BRIDGE 'getRoleMemberCount(bytes32)(uint256)' $PAUSER_ROLE --rpc-url $rpc 2>/dev/null)"

    section "TESTNET / $chain / MigrationVault (UUPS proxy, $MIGRATION_VAULT)"
    impl_raw=$(cast storage $MIGRATION_VAULT $EIP1967_IMPL_SLOT --rpc-url $rpc 2>/dev/null)
    impl_addr="0x${impl_raw: -40}"
    check "implementation slot == expected impl ($MIGRATION_VAULT_IMPL_EXPECTED)" "$MIGRATION_VAULT_IMPL_EXPECTED" "$impl_addr"
    check "OLD_TOKEN == this chain's TelcoinLegacy ($tel_legacy)" "$tel_legacy" \
      "$(cast call $MIGRATION_VAULT 'OLD_TOKEN()(address)' --rpc-url $rpc 2>/dev/null)"
    check "NEW_TOKEN == TelcoinV3 ($TEL_V3)" "$TEL_V3" \
      "$(cast call $MIGRATION_VAULT 'NEW_TOKEN()(address)' --rpc-url $rpc 2>/dev/null)"
    check "hasRole(DEFAULT_ADMIN_ROLE, Safe $ADMIN)" "true" "$(has_role $MIGRATION_VAULT DEFAULT_ADMIN_ROLE $DEFAULT_ADMIN_ROLE $ADMIN $rpc)"
    check "hasRole(TREASURY_ROLE, Safe $ADMIN)" "true" "$(has_role $MIGRATION_VAULT TREASURY_ROLE $TREASURY_ROLE $ADMIN $rpc)"
    check "paused == false" "false" \
      "$(cast call $MIGRATION_VAULT 'paused()(bool)' --rpc-url $rpc 2>/dev/null)"

    section "TESTNET / $chain / TokenMigration ($TOKEN_MIGRATION)"
    check "oldToken == this chain's TelcoinLegacy ($tel_legacy)" "$tel_legacy" \
      "$(cast call $TOKEN_MIGRATION 'oldToken()(address)' --rpc-url $rpc 2>/dev/null)"
    check "telcoinV3 == TelcoinV3 ($TEL_V3)" "$TEL_V3" \
      "$(cast call $TOKEN_MIGRATION 'telcoinV3()(address)' --rpc-url $rpc 2>/dev/null)"
    check "migrationClosed == false" "false" \
      "$(cast call $TOKEN_MIGRATION 'migrationClosed()(bool)' --rpc-url $rpc 2>/dev/null)"
    check "paused == false" "false" \
      "$(cast call $TOKEN_MIGRATION 'paused()(bool)' --rpc-url $rpc 2>/dev/null)"

    section "TESTNET / $chain / Faucets"
    check "TelcoinV3Faucet.owner == governance Safe ($ADMIN)" "$ADMIN" \
      "$(cast call $TEL_V3_FAUCET 'owner()(address)' --rpc-url $rpc 2>/dev/null)"
    check "TelcoinV3Faucet.token == TelcoinV3 ($TEL_V3)" "$TEL_V3" \
      "$(cast call $TEL_V3_FAUCET 'token()(address)' --rpc-url $rpc 2>/dev/null)"
    legacy_faucet_owner=$(cast call $LEGACY_FAUCET 'owner()(address)' --rpc-url $rpc 2>/dev/null)
    legacy_faucet_owner_lc=$(echo "$legacy_faucet_owner" | tr '[:upper:]' '[:lower:]')
    if [ "$legacy_faucet_owner_lc" = "$(echo "$ADMIN" | tr '[:upper:]' '[:lower:]')" ]; then
      ok "LegacyTelcoinFaucet.owner == governance Safe (finding 3.1 fixed!)" "$legacy_faucet_owner"
    elif [ "$legacy_faucet_owner_lc" = "$(echo "$LEGACY_FAUCET_KNOWN_STALE_OWNER" | tr '[:upper:]' '[:lower:]')" ]; then
      warn "LegacyTelcoinFaucet.owner still the known stale Safe" "$legacy_faucet_owner"
    else
      bad "LegacyTelcoinFaucet.owner is neither the governance Safe nor the known stale Safe -- investigate" \
        "$ADMIN (fixed) or $LEGACY_FAUCET_KNOWN_STALE_OWNER (known stale)" "$legacy_faucet_owner"
    fi
  done
}

# ============================================================
# TESTNET — tel-v3-staking (ETH Sepolia only; Polygon not live)
# ============================================================
run_staking() {
  rpc=$ETH_SEPOLIA_RPC_URL
  UPGRADER_ROLE=$(role_hash "UPGRADER_ROLE")
  PLUGIN_EDITOR_ROLE=$(role_hash "PLUGIN_EDITOR_ROLE")
  PARAM_SETTER_ROLE=$(role_hash "PARAM_SETTER_ROLE")
  RECOVERY_ROLE=$(role_hash "RECOVERY_ROLE")
  MIGRATOR_ROLE=$(role_hash "MIGRATOR_ROLE")
  PAUSER_ROLE=$(role_hash "PAUSER_ROLE")
  UNPAUSER_ROLE=$(role_hash "UNPAUSER_ROLE")
  BATCH_MIGRATOR_ROLE=$(role_hash "BATCH_MIGRATOR_ROLE")

  section "STAKING / polygon / deployment check"
  check "StakingModuleProxy ($STAKING_PROXY) has no code on Polygon (not deployed there yet)" "0" \
    "$(cast codesize $STAKING_PROXY --rpc-url $POLYGON_RPC_URL 2>/dev/null)"

  section "STAKING / eth-sepolia / StakingModule (proxy, $STAKING_PROXY)"
  impl_raw=$(cast storage $STAKING_PROXY $EIP1967_IMPL_SLOT --rpc-url $rpc 2>/dev/null)
  impl_addr="0x${impl_raw: -40}"
  check "implementation slot == expected impl ($STAKING_IMPL_EXPECTED)" "$STAKING_IMPL_EXPECTED" "$impl_addr"
  check "tel() == TelcoinV3, not legacy V2 token ($TEL_V3)" "$TEL_V3" \
    "$(cast call $STAKING_PROXY 'tel()(address)' --rpc-url $rpc 2>/dev/null)"
  check "paused == false" "false" \
    "$(cast call $STAKING_PROXY 'paused()(bool)' --rpc-url $rpc 2>/dev/null)"

  for r in "DEFAULT_ADMIN_ROLE|$DEFAULT_ADMIN_ROLE|$ADMIN" \
           "UPGRADER_ROLE|$UPGRADER_ROLE|$ADMIN" \
           "PLUGIN_EDITOR_ROLE|$PLUGIN_EDITOR_ROLE|$ADMIN" \
           "PARAM_SETTER_ROLE|$PARAM_SETTER_ROLE|$ADMIN" \
           "RECOVERY_ROLE|$RECOVERY_ROLE|$ADMIN" \
           "MIGRATOR_ROLE|$MIGRATOR_ROLE|$STAKING_MIGRATOR" \
           "PAUSER_ROLE|$PAUSER_ROLE|$PAUSER" \
           "UNPAUSER_ROLE|$UNPAUSER_ROLE|$UNPAUSER"; do
    name=$(echo "$r" | cut -d'|' -f1); hash=$(echo "$r" | cut -d'|' -f2); expected=$(echo "$r" | cut -d'|' -f3)
    check "hasRole($name, $expected)" "true" "$(has_role $STAKING_PROXY $name $hash $expected $rpc)"
  done

  section "STAKING / eth-sepolia / StakingMigratorV2toV3 ($STAKING_MIGRATOR)"
  check "hasRole(DEFAULT_ADMIN_ROLE, Safe $ADMIN)" "true" "$(has_role $STAKING_MIGRATOR DEFAULT_ADMIN_ROLE $DEFAULT_ADMIN_ROLE $ADMIN $rpc)"
  check "hasRole(BATCH_MIGRATOR_ROLE, Safe $ADMIN)" "true" "$(has_role $STAKING_MIGRATOR BATCH_MIGRATOR_ROLE $BATCH_MIGRATOR_ROLE $ADMIN $rpc)"
  check "v2Staking == StakingModuleV2 legacy ($STAKING_V2)" "$STAKING_V2" \
    "$(cast call $STAKING_MIGRATOR 'v2Staking()(address)' --rpc-url $rpc 2>/dev/null)"
  check "v3Staking == StakingModuleProxy ($STAKING_PROXY)" "$STAKING_PROXY" \
    "$(cast call $STAKING_MIGRATOR 'v3Staking()(address)' --rpc-url $rpc 2>/dev/null)"
  check "tokenMigration == TokenMigration ($TOKEN_MIGRATION)" "$TOKEN_MIGRATION" \
    "$(cast call $STAKING_MIGRATOR 'tokenMigration()(address)' --rpc-url $rpc 2>/dev/null)"
  check "migrator ($STAKING_MIGRATOR) holds MIGRATOR_ROLE on legacy StakingModuleV2 (manual step)" "true" \
    "$(has_role $STAKING_V2 MIGRATOR_ROLE $MIGRATOR_ROLE $STAKING_MIGRATOR $rpc)"
  check "paused == false" "false" \
    "$(cast call $STAKING_MIGRATOR 'paused()(bool)' --rpc-url $rpc 2>/dev/null)"

  section "STAKING / eth-sepolia / SimplePlugin_TEL ($SIMPLE_PLUGIN)"
  check "owner == governance Safe ($ADMIN)" "$ADMIN" \
    "$(cast call $SIMPLE_PLUGIN 'owner()(address)' --rpc-url $rpc 2>/dev/null)"
  check "rewardToken == TelcoinV3 ($TEL_V3)" "$TEL_V3" \
    "$(cast call $SIMPLE_PLUGIN 'rewardToken()(address)' --rpc-url $rpc 2>/dev/null)"
}

# ============================================================
case "$MODE" in
  mainnet) run_mainnet ;;
  testnet) run_testnet ;;
  staking) run_staking ;;
  all) run_mainnet; run_testnet; run_staking ;;
  *) echo "Usage: $0 [mainnet|testnet|staking|all]"; exit 2 ;;
esac

printf "\n=== Summary: %d passed, %d failed, %d known-finding warnings ===\n" "$PASS" "$FAIL" "$WARN"
[ "$FAIL" -eq 0 ]
