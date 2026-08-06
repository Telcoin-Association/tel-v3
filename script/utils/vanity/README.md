# CREATE3 Vanity-Salt Miner

Mines raw salts for CreateX `deployCreate3` so a contract deployed by our Safe
lands at a vanity address (e.g. `0x7e13…731`). Built for the TEL v3 mainnet
deployment; works for any contract deployed through this repo's pipeline
(bridges, migration, …) — the pattern and salt constant are the only things
that change.

## Why a custom miner

This repo does not deploy with plain CREATE2. `DeployBase` calls **CreateX
`deployCreate3`** (`0xba5Ed099633D3B313e4D5F7bdc1305d3c28ba5Ed`) with a
sender-guarded salt (`SaltMath.guardSalt`). Consequences:

- The deployed address depends **only** on (CreateX, deployer Safe, low 11
  bytes of the raw salt). Contract bytecode and constructor args are
  irrelevant — `cast create2` cannot mine this.
- Only the low 11 bytes (88 bits) of the salt are mineable; `guardSalt`
  overwrites the top 21 bytes with `[Safe (20B)][0x00]`. Byte 20 = `0x00` is
  CreateX's cross-chain mode: the address is **identical on every chain**.
- The salt is only valid when the deployment is executed by that exact Safe.
  CreateX's `_guard` re-derives the salt from `msg.sender`, so **nobody else
  can front-run or squat the mined address** — publishing a salt before
  deploying is safe.

## Quickstart

```sh
# Mine 5 candidate salts for 0x7e13…731 from the canonical mainnet Safe:
script/utils/vanity/mine-vanity-salt.sh

# Then independently verify a candidate with the production SaltMath:
VANITY_SALT=0x<rawSalt from miner output> \
    forge script script/utils/VerifyVanitySalt.s.sol -vvvv

# Strongest check — ask CreateX itself on a live chain (repeat per chain):
VANITY_SALT=0x<rawSalt> forge script script/utils/VerifyVanitySalt.s.sol \
    --rpc-url $ETHEREUM_RPC_URL -vvvv
```

The wrapper compiles `mine_vanity_salt.c` on first use (plain C11, zero
dependencies, `cc` required) and recompiles when the source changes.

## CLI

| Flag        | Default                                      | Meaning                                   |
| ----------- | -------------------------------------------- | ----------------------------------------- |
| `--safe`    | `0x10DC2EFbd84ebFb92eef5f145e3D84CC8b511799` | Deployer Safe (canonical mainnet 2/7)     |
| `--prefix`  | `7e13`                                       | Address prefix nibbles (after `0x`)       |
| `--suffix`  | `731`                                        | Address suffix nibbles                    |
| `--threads` | online CPU cores                             | Worker threads                            |
| `--count`   | `5`                                          | Stop after this many matches (streamed)   |

Matching is case-insensitive; addresses are displayed EIP-55 checksummed. With
5 matches there is a ~97% chance at least one renders the `7e13` prefix
lowercase as typed — rerun with `--count 20` if you're picky about the
checksummed rendering of specific characters. Matches go to stdout, progress
to stderr. Exit 0 iff at least one match was found.

Both the miner (at every startup) and the verifier (at every run) self-test
against golden vectors of live deployments and refuse to run on mismatch.

## Derivation

```
guarded     = safe(20B) ++ 0x00 ++ suffix(11B)          # SaltMath.guardSalt
transformed = keccak256( zeros(12B) ++ safe ++ guarded ) # CreateX _guard (x-chain mode)
proxy       = keccak256( 0xff ++ CreateX ++ transformed
                         ++ 0x21c35dbe1b344a2488cf3321d6ce542f8e9f305544ff09e4993a62319a497c1f )[12:]
final       = keccak256( 0xd6 0x94 ++ proxy ++ 0x01 )[12:]   # RLP [proxy, nonce 1]
```

`0x21c35dbe…7c1f` is the keccak of the CREATE3 proxy child bytecode
(`lib/create3/contracts/Create3.sol`). Each candidate costs exactly 3 keccak
permutations; the miner rewrites only the 11 suffix bytes per attempt.

### Golden vectors (live, explorer-verified deployments)

| Safe | suffix (low 11B) | address |
| ---- | ---------------- | ------- |
| `0x10DC2EFbd84ebFb92eef5f145e3D84CC8b511799` (mainnet) | `0xba53b2975250769c18dc51` | `0xE6B8f90D047A4f7294DC6C5E369Ec75EefD62C7b` |
| `0x765327d1AeA74cC360B1C6Cc567200d7e4baC3fD` (testnet) | `0x24e77a99c5af7fcc618069` | `0x6B46d2f2a27f16dC1ef29a71C38A7E274132C7E7` |

Manual third-implementation check with `cast` (mainnet vector):

```sh
SAFE=10dc2efbd84ebfb92eef5f145e3d84cc8b511799
SUF=ba53b2975250769c18dc51
T=$(cast keccak 0x000000000000000000000000${SAFE}${SAFE}00${SUF})
P=$(cast keccak 0xffba5ed099633d3b313e4d5f7bdc1305d3c28ba5ed${T#0x}21c35dbe1b344a2488cf3321d6ce542f8e9f305544ff09e4993a62319a497c1f)
cast keccak 0xd694${P:26}01   # last 40 hex chars = e6b8f90d…2c7b
```

Substitute the mined suffix for `SUF` to hand-check any candidate.

## Difficulty

Expected candidates per match = `16^nibbles`. At this machine's ~20M/s
(24 cores):

| Constrained nibbles | Expected candidates | Expected time |
| ------------------- | ------------------- | ------------- |
| 6                   | 16.8M               | ~1 s          |
| 7 (`7e13` + `731`)  | 268M                | ~13 s         |
| 8                   | 4.3G                | ~4 min        |
| 9                   | 68.7G               | ~1 h          |
| 10                  | 1.1T                | ~15 h         |

Times are per match and exponentially distributed — expect a spread.

## Redeploying TEL v3 at a mined address

- The non-vanity V0 TelcoinV3 at `0xE6B8f90D047A4f7294DC6C5E369Ec75EefD62C7b`
  stays on-chain but is abandoned; a new salt in
  `script/mainnet/utils/Salts.sol` (`TELCOIN_V3_SALT`) yields a new expected
  address, so the pipeline's "already deployed, skipping" guard will not fire.
- `deployments/*.json` entries are overwritten on the next broadcast.
- The mined salt is valid **only** when deployed from the Safe it was mined
  for. Before broadcasting, `.env` must set
  `DEPLOYER_SAFE_ADDRESS=0x10DC2EFbd84ebFb92eef5f145e3D84CC8b511799` — a wrong
  Safe silently produces a different (non-vanity) address. The verifier reads
  the same env var, so running it in the deploy environment catches mismatches.
- A raw salt is public calldata once broadcast; secrecy is not required and
  the sender guard prevents squatting (see above).
