#!/usr/bin/env bash
# Deploy CreateX to the canonical address 0xba5Ed099633D3B313e4D5F7bdc1305d3c28ba5Ed
# on Adiri (Telcoin Network testnet, chain 2017) by broadcasting pcaversaccio's
# presigned pre-EIP-155 transaction (nonce 0, 100 gwei, gasLimit 3M).
#
# Prereq: the deployer EOA 0xeD456e05CaAb11d66C4c797dD6c1D6f9A7F352b5 must hold
# >= 0.3 TEL (gasLimit x gasPrice, required upfront; actual burn ~0.258 TEL).
#
# Pre-flight already validated (2026-08-21, see docs/notes/adiri-deployment.md):
#   - Adiri accepts pre-EIP-155 txs
#   - eth_estimateGas on Adiri: 2,602,553 (< 3M limit)
#   - anvil dry-run: gasUsed exactly 2,580,902 (canonical), runtime codehash
#     matches Ethereum mainnet
#
# No private key needed by this script: the deployment tx is already signed,
# and funding is sent manually (e.g. from MetaMask).
#
# Usage: ./0-deploy-createx.sh            (uses https://rpc.adiri.tel)
#        ./0-deploy-createx.sh --wait     (poll until the deployer is funded,
#                                          then deploy — start it, then do the
#                                          MetaMask send)
#        ADIRI_RPC_URL=<url> ./0-deploy-createx.sh
set -euo pipefail
export FOUNDRY_DISABLE_NIGHTLY_WARNING=1

RPC="${ADIRI_RPC_URL:-https://rpc.adiri.tel}"
CREATEX=0xba5Ed099633D3B313e4D5F7bdc1305d3c28ba5Ed
DEPLOYER=0xeD456e05CaAb11d66C4c797dD6c1D6f9A7F352b5
# MetaMask EOA used to fund the deployer (informational only — never signs here)
FUNDER=0x28937C70A08390c55b65Eab24600c4b059A50991
# keccak256 of CreateX runtime code, cross-checked against Ethereum mainnet
EXPECTED_CODEHASH=0xbd8a7ea8cfca7b4e5f5041d7d4b17bc317c5ce42cfbc42066a00cf26b43eb53f
# Hash of the presigned tx itself — identical on every chain it's published to
EXPECTED_TXHASH=0xb6274b80bc7cda162df89894c7748a5cb7ba2eaa6004183c41a1837c3b072f1e
PRESIGNED_FILE="$(dirname "$0")/presigned-createx-gaslimit-3000000.txt"

verify_code() {
    local code codehash
    code=$(cast code $CREATEX --rpc-url "$RPC")
    if [ "$code" = "0x" ]; then return 1; fi
    codehash=$(cast keccak "$code")
    if [ "$codehash" != "$EXPECTED_CODEHASH" ]; then
        echo "FATAL: code at $CREATEX has UNEXPECTED hash $codehash" >&2
        exit 1
    fi
    return 0
}

echo "== CreateX bootstrap on $RPC"

CHAIN_ID=$(cast chain-id --rpc-url "$RPC")
if [ "$CHAIN_ID" != "2017" ]; then
    echo "FATAL: expected chain id 2017 (Adiri), got $CHAIN_ID" >&2
    exit 1
fi

if verify_code; then
    echo "CreateX already deployed at $CREATEX with matching codehash. Nothing to do."
    exit 0
fi

NONCE=$(cast nonce $DEPLOYER --rpc-url "$RPC")
if [ "$NONCE" != "0" ]; then
    echo "FATAL: deployer nonce is $NONCE (expected 0) but no CreateX code exists —" >&2
    echo "       the presigned tx can never land. Investigate before proceeding." >&2
    exit 1
fi

REQUIRED=300000000000000000 # 0.3 TEL = gasLimit(3M) x gasPrice(100 gwei)
BALANCE=$(cast balance $DEPLOYER --rpc-url "$RPC")
if [ "$(echo "$BALANCE < $REQUIRED" | bc)" = "1" ]; then
    echo "Deployer $DEPLOYER holds $(cast from-wei "$BALANCE") TEL; needs 0.3 TEL."
    echo "Fund it from MetaMask ($FUNDER, currently $(cast from-wei "$(cast balance $FUNDER --rpc-url "$RPC")") TEL):"
    echo "  network:  Adiri Testnet — RPC https://rpc.adiri.tel, chain ID 2017, symbol TEL"
    echo "  send:     0.3 TEL -> $DEPLOYER"
    if [ "${1:-}" = "--wait" ]; then
        echo "Waiting for funding (checking every 10s, ctrl-c to abort)..."
        while [ "$(echo "$BALANCE < $REQUIRED" | bc)" = "1" ]; do
            sleep 10
            BALANCE=$(cast balance $DEPLOYER --rpc-url "$RPC")
        done
        echo "Funded: deployer now holds $(cast from-wei "$BALANCE") TEL."
    else
        exit 1
    fi
fi

# Sanity: estimate deployment gas against the live node (must fit 3M limit)
INIT=$(cast decode-transaction "$(cat "$PRESIGNED_FILE")" | python3 -c 'import sys,json; print(json.load(sys.stdin)["input"])')
EST=$(cast estimate --rpc-url "$RPC" --from $DEPLOYER --create "$INIT")
echo "eth_estimateGas: $EST"
if [ "$EST" -gt 3000000 ]; then
    echo "FATAL: estimate exceeds the presigned tx gas limit of 3,000,000" >&2
    exit 1
fi

echo "Publishing presigned tx (expect hash $EXPECTED_TXHASH)..."
cast publish "$(cat "$PRESIGNED_FILE")" --rpc-url "$RPC" --async
cast receipt $EXPECTED_TXHASH --rpc-url "$RPC" --confirmations 1 --json \
    | python3 -c 'import sys,json; r=json.load(sys.stdin); print("status:", r["status"], "gasUsed:", int(r["gasUsed"],16)); exit(0 if r["status"]=="0x1" else 1)'

if verify_code; then
    echo "SUCCESS: CreateX deployed at $CREATEX, codehash verified against mainnet."
else
    echo "FATAL: tx mined but no code at $CREATEX" >&2
    exit 1
fi
