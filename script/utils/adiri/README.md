# Adiri (Telcoin Network testnet) bootstrap

One-time infrastructure bootstrap for chain 2017 before the Safe-based
deployment pipeline can run there. Adiri ships Safe v1.4.1 singleton + proxy
factory in genesis but lacks CreateX, MultiSendCallOnly, and (crucially) the
Safe Transaction Service — see `docs/notes/adiri-deployment.md` (local, not
committed) for the full recon.

All bootstrap steps are broadcast from a plain **EOA** — our deployer Safe
doesn't exist on Adiri until step 2 recreates it, and none of these steps'
resulting addresses depend on who broadcasts them (CreateX's address is bound
to the presigned deployer key, the Safe's to factory+initializer+saltNonce,
MultiSendCallOnly's to Nick's-factory CREATE2). Only the protocol deployments
that come *after* bootstrap (NativeBridge etc.) must go through the replayed
Safe, because the CreateX salt guard binds addresses to it.

Order:

1. `0-deploy-createx.sh` — publishes pcaversaccio's presigned pre-EIP-155 tx
   (vendored in `presigned-createx-gaslimit-3000000.txt`, source:
   [pcaversaccio/createx](https://github.com/pcaversaccio/createx/blob/main/scripts/presigned-createx-deployment-transactions/signed_serialised_transaction_gaslimit_3000000_.json))
   to place CreateX at the canonical `0xba5Ed099633D3B313e4D5F7bdc1305d3c28ba5Ed`.
   Requires the deployer EOA `0xeD456e05CaAb11d66C4c797dD6c1D6f9A7F352b5` to be
   pre-funded with 0.3 TEL. Idempotent; verifies the runtime codehash against
   the Ethereum mainnet deployment
   (`0xbd8a7ea8cfca7b4e5f5041d7d4b17bc317c5ce42cfbc42066a00cf26b43eb53f`).
2. (planned) replay the deployer Safe `0x6012dBcb…eB03` via
   `SafeProxyFactory.createProxyWithNonce` with the original initializer.
3. (planned) deploy MultiSendCallOnly v1.4.1 and register its address for
   chain 2017 in our safe-utils fork.

Per the CreateX README, after a successful deploy we should open a PR against
pcaversaccio/createx adding Adiri to `deployments/deployments.json`.
