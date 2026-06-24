# Custom DVN Mesh Configuration

> Research & planning document for Telcoin's LayerZero V2 DVN security mesh.
> Last updated: 2026-05-30

## Table of Contents

- [Overview](#overview)
- [Target Chains](#target-chains)
- [DVN Provider Research](#dvn-provider-research)
- [Diversity Analysis](#diversity-analysis)
- [Fee Structure & Cost Analysis](#fee-structure--cost-analysis)
- [Mesh Configuration Options](#mesh-configuration-options)
- [Decision Log](#decision-log)

---

## Overview

The LayerZero V2 protocol allows applications to configure a custom Security Stack consisting of **Required DVNs** (all must sign) and **Optional DVNs** (X-of-Y threshold). Our goal is to build the most **secure and diverse** DVN mesh possible for Telcoin's OFT bridge.

### Key Principles

1. **Client diversity** — no single software bug should compromise verification
2. **Cloud/infra diversity** — no single cloud provider outage should halt verification
3. **Entity diversity** — no single organizational compromise should affect the mesh
4. **Chain coverage** — all DVNs in the mesh must be deployed on every chain we use

### How DVN Verification Works

When an OApp sends a cross-chain message via `EndpointV2.send()`:
1. The message is emitted on the source chain
2. Each configured DVN independently verifies the `payloadHash` on the source chain
3. DVNs submit their attestations to the destination chain
4. Once the Required DVN threshold **and** Optional DVN threshold are both met, the message is committed
5. The Executor delivers the message to the destination OApp

A DVN must be deployed on **both** the source and destination chain to verify a pathway.

---

## Target Chains

| Chain | Bridge Contract | LZ Endpoint ID |
|-------|----------------|----------------|
| Ethereum | `TelcoinBridge` (MintBurnOFTAdapter) | 30101 |
| Base | `TelcoinBridge` (MintBurnOFTAdapter) | 30184 |
| Polygon | `TelcoinBridge` (MintBurnOFTAdapter) | 30109 |
| TelcoinNetwork | `NativeBridge` (NativeOFTAdapter) | TBD |

---

## DVN Provider Research

### Tier 1 — Priority Providers (Recommended by LayerZero)

#### 1. LayerZero Labs DVN

| Attribute | Details |
|-----------|---------|
| **Client** | Gasolina (TypeScript) |
| **Cloud** | GCP |
| **Entity** | LayerZero Labs |
| **Chain Coverage** | 80+ chains — broadest coverage of any DVN |
| **Chains We Need** | Ethereum, Base, Polygon — all supported |
| **Notes** | Default DVN for most applications. Battle-tested with 100M+ messages verified (as of Oct 2024). Most protocols include LZ DVN as a required verifier. |

#### 2. Canary DVN

| Attribute | Details |
|-----------|---------|
| **Client** | Custom Go implementation |
| **Cloud** | AWS (Nitro TEE) |
| **Entity** | Canary Protocol |
| **Chain Coverage** | Wide coverage (exact count unconfirmed — verify via [LZ DVN addresses](https://docs.layerzero.network/v2/deployments/dvn-addresses)) |
| **Chains We Need** | Ethereum, Base, Polygon — all supported |
| **Security Model** | TEE-based verification (AWS Nitro enclaves) with cryptographic attestation + EigenLayer cryptoeconomic security (staking/slashing). Slashable stake backs every verification. |
| **Notes** | The **only** DVN provider not running LayerZero's Gasolina client — provides the only source of client diversity in the ecosystem. TEE + staking model provides both hardware and economic security guarantees. |

#### 3. Nethermind DVN

| Attribute | Details |
|-----------|---------|
| **Client** | Gasolina (TypeScript) |
| **Cloud** | GCP (multi-AZ with load balancing) — Nethermind is a [Google Cloud customer](https://cloud.google.com/customers/nethermind); overlaps with LayerZero Labs |
| **Entity** | Nethermind (Ethereum execution client team) |
| **Chain Coverage** | 70+ chains |
| **Chains We Need** | Ethereum, Base, Polygon — all supported |
| **Notes** | Described as LayerZero's most "robust" partner with a **dedicated team** for DVN maintenance. Nethermind also builds the flagship Nethermind Ethereum execution client (C#/.NET). Hybrid globally redundant platform with 24/7 SRE coverage and unified observability. One of LayerZero's original DVN launch partners. Uses LayerZero's Gasolina client like most DVN operators. |
| **⚠️ Independence Concern** | The KelpDAO exploit post-mortem (April 2026) revealed that the LayerZero Labs DVN and Nethermind DVN share **substantial ADMIN_ROLE overlap on-chain** (10+ shared admin addresses). This raises questions about the true independence of these two DVNs — a compromise of shared admin keys could affect both simultaneously. Consider this when evaluating mesh options that rely on both as "required" verifiers. See [KelpDAO incident discussion](https://x.com/catwychan/status/2051805623906402570). |

#### 4. Deutsche Telekom MMS DVN

| Attribute | Details |
|-----------|---------|
| **Client** | Gasolina (TypeScript) |
| **Cloud** | Open Telekom Cloud (OTC) — European data centers, **not** AWS/GCP/Azure |
| **Entity** | Deutsche Telekom MMS (subsidiary of Deutsche Telekom AG) |
| **Chain Coverage** | 12+ chains (Ethereum, Mantle, Linea, Fantom, Arbitrum, Solana, Avalanche, Base, BNB, Gnosis, Optimism, Polygon at launch) |
| **Chains We Need** | Ethereum, Base, Polygon — ✅ all supported |
| **Notes** | Unique cloud diversity — runs on Deutsche Telekom's own European cloud infrastructure, independent of US hyperscalers. Institutional-grade entity (€100B+ parent company). Has operated blockchain validators, oracles, and indexers since 2020 (Injective, SQD, NEAR). Joined LayerZero May 2025. |

### Tier 2 — Additional Providers

#### 5. FCAT (Fidelity Center for Applied Technology)

| Attribute | Details |
|-----------|---------|
| **Client** | Gasolina (TypeScript) |
| **Cloud** | Fidelity infrastructure |
| **Entity** | FCAT (Fidelity Investments R&D arm) |
| **Chain Coverage** | ~11 chains (launched with 7: Ethereum, Polygon, Arbitrum, Base, Optimism, Avalanche, Solana; expanded to 11 by Feb 2026) |
| **Chains We Need** | Ethereum, Base, Polygon — ✅ all supported |
| **Notes** | Primarily utilized by Ondo Finance for institutional RWA bridging. Fidelity entity adds strong institutional credibility. Limited chain coverage (focused on major chains only). |

#### 6. Luganodes

| Attribute | Details |
|-----------|---------|
| **Client** | Gasolina (TypeScript) |
| **Cloud** | TBD |
| **Entity** | Luganodes (Lugano-based validator operator) |
| **Chain Coverage** | 20+ chains |
| **Chains We Need** | Ethereum, Base, Polygon — ✅ all supported |
| **Notes** | Smaller operator. |

#### 7. P2P

| Attribute | Details |
|-----------|---------|
| **Client** | Gasolina (TypeScript) |
| **Cloud** | GCP |
| **Entity** | P2P.org (original Lido incubator) |
| **Chain Coverage** | 20+ chains |
| **Chains We Need** | Ethereum, Base, Polygon — ✅ all supported |
| **Notes** | Reputable PoS validator operator since 2018. GCP cloud overlaps with LayerZero Labs — less cloud diversity value. |

#### 8. Nansen

| Attribute | Details |
|-----------|---------|
| **Client** | Gasolina (TypeScript) |
| **Cloud** | TBD |
| **Entity** | Nansen (blockchain analytics company) |
| **Chain Coverage** | 15+ chains |
| **Chains We Need** | Ethereum, Base, Polygon — ✅ all supported |
| **Notes** | Known primarily for on-chain analytics. Smaller DVN footprint. |

---

## Diversity Analysis

### Client Diversity Matrix

Only two DVN client implementations exist today:

| Client | DVN Provider(s) |
|--------|-----------------|
| Gasolina (TypeScript, built by LayerZero) | LayerZero Labs, Nethermind, Deutsche Telekom, FCAT, Luganodes, P2P, Nansen |
| Canary (Go, built by Canary Protocol) | Canary |

### Cloud/Infrastructure Diversity Matrix

| Cloud Provider | DVN Provider(s) |
|---------------|-----------------|
| GCP | LayerZero Labs, Nethermind, P2P |
| AWS (Nitro TEE) | Canary |
| Open Telekom Cloud (Europe) | Deutsche Telekom |
| Fidelity infra | FCAT |
| Unknown | Luganodes, Nansen |

> **Key insight:** LayerZero Labs, Nethermind, and P2P all run on GCP — less cloud diversity than previously assumed. Canary (AWS) and Deutsche Telekom (OTC) are the only confirmed independent cloud providers. Note that Gasolina offers both GCP and AWS deployment tooling, so providers *could* run on either — but confirmed deployments cluster on GCP.

### Entity Diversity Summary

| Category | DVN Provider(s) |
|----------|-----------------|
| Protocol team | LayerZero Labs |
| Crypto-native infra | Canary, Nethermind, Luganodes, P2P, Nansen |
| Institutional / TradFi | Deutsche Telekom, FCAT (Fidelity) |

---

## Fee Structure & Cost Analysis

### How LayerZero DVN Fees Work

DVN fees are **not fixed** — they are dynamic and determined by each DVN operator independently. When a message is sent:

1. `OApp.quoteSend()` calls the endpoint, which queries each configured DVN's fee contract
2. Each DVN returns its fee for verifying that specific pathway (source → destination)
3. The total messaging fee = **source gas + Σ(DVN fees) + executor fee + destination gas**
4. Fees are recorded in the send library for DVNs to claim later (not paid directly)

### Fee Drivers

| Factor | Impact |
|--------|--------|
| **Number of DVNs** | Linear — each additional DVN adds its fee to the total |
| **Source/destination chains** | Gas costs vary dramatically (Ethereum >> L2s) |
| **DVN operator pricing** | Each DVN sets its own fee schedule |
| **Network congestion** | Affects gas components, not DVN base fees |
| **Required vs Optional** | All configured DVNs (required + optional) verify and charge for every message |

### Live Fee Data (queried 2026-05-30)

Fees queried via `ILayerZeroDVN.getFee()` on each DVN contract. ETH ≈ $2,020 at time of query.

> Query script: [`script/utils/QueryDVNFees.s.sol`](../script/utils/QueryDVNFees.s.sol)

#### Ethereum → Base (EID 30184)

| DVN Provider | Fee (gwei) | Fee (USD) |
|-------------|------------|-----------|
| LayerZero Labs | 1,666.66 | $0.00337 |
| Nethermind | 1,562.20 | $0.00316 |
| Canary | 1,628.68 | $0.00329 |
| Deutsche Telekom | 1,628.68 | $0.00329 |
| FCAT | 1,628.68 | $0.00329 |
| Luganodes | 1,562.20 | $0.00316 |
| P2P | 1,562.20 | $0.00316 |
| Nansen | 1,628.68 | $0.00329 |
| **Average per DVN** | **1,608.50** | **$0.00325** |

#### Ethereum → Polygon (EID 30109)

| DVN Provider | Fee (gwei) | Fee (USD) |
|-------------|------------|-----------|
| LayerZero Labs | 1,238.52 | $0.00250 |
| Nethermind | 1,160.90 | $0.00235 |
| Canary | 1,210.30 | $0.00244 |
| Deutsche Telekom | 1,210.30 | $0.00244 |
| FCAT | 1,210.30 | $0.00244 |
| Luganodes | 1,160.90 | $0.00235 |
| P2P | 1,160.90 | $0.00235 |
| Nansen | 1,210.30 | $0.00244 |
| **Average per DVN** | **1,195.30** | **$0.00241** |

#### Key Takeaway

DVN verification fees are **extremely cheap** — roughly **$0.003 per DVN per message** from Ethereum. The DVN fee component is negligible compared to source chain gas and executor costs (which typically dominate total bridging costs at $1–$5 from Ethereum). **Adding more DVNs has near-zero marginal cost impact on the user.**

### Cost by Mesh Configuration

Total DVN-only costs per message (Ethereum → Base pathway, ETH ≈ $2,020):

| Config | DVN Count | DVN Cost (USD) | Notes |
|--------|-----------|----------------|-------|
| **Option F** ⭐ — 3 req (LZ + Canary + DT) + 1-of-2 opt (Nethermind, FCAT) | 5 | ~$0.016 | Recommended — 4-of-5, fully independent required set |
| **Option G** — 3 req (LZ + Canary + DT) + 1-of-2 opt (FCAT, P2P) | 5 | ~$0.016 | Nethermind-free variant |
| **Option H** — 3 req (LZ + Canary + DT) + 2-of-3 opt (Nethermind, FCAT, P2P) | 6 | ~$0.019 | Maximum — 5-of-6 |

> **Bottom line:** All preferred options cost ~$0.016–$0.019 per message — **less than 2 cents**. Security and independence should drive this decision, not cost.

### Cost Impact of N-of-M Configurations

| Config | Required DVNs Pay | Optional DVNs Pay | Notes |
|--------|-------------------|-------------------|-------|
| 2 Required, 0 Optional | 2 always | 0 | Cheapest. Both must verify. |
| 2 Required, 1-of-2 Optional | 2 always | All optional DVNs verify (fee charged) | More secure, +$0.007 |
| 2 Required, 2-of-3 Optional | 2 always | All optional DVNs verify (fee charged) | Most secure, +$0.010 |
| 3 Required, 0 Optional | 3 always | 0 | Strong security, +$0.003 |

> **Important:** All configured DVNs (both required and optional) verify every message and charge fees. The "optional" label only affects the *threshold for acceptance*, not whether they run and charge.

### Protocol Fee Switch

LayerZero governance controls a protocol fee of up to 100% of DVN + executor costs. Referendum #3 (Dec 20–27, 2025) saw 97% approval but **failed to reach quorum** (required 230M ZRO / 40.59% of circulating supply), so the **fee switch remains OFF**. The next referendum is expected ~6 months after the failed vote. If activated in the future, it would add a surcharge on top of DVN + executor fees, with proceeds converted to ZRO and burned. Monitor the [LayerZero fee switch page](https://layerzero.foundation/fee-switch) for updates.

---

## Mesh Configuration Options

### Preferred Options (LZ + Canary + Deutsche Telekom core)

The following options are built around the strongest available required set: **LayerZero Labs, Canary, and Deutsche Telekom**. These three have:
- **True client diversity** — Gasolina + Canary's Go client
- **Full cloud independence** — GCP + AWS (Nitro TEE) + Open Telekom Cloud
- **No shared admin keys** — each operated by a fully independent entity
- **Entity diversity** — protocol team + crypto-native + institutional/TradFi

#### Option F: Recommended (3 Required + 1-of-2 Optional) ⭐

```
Required: [LayerZero Labs, Canary, Deutsche Telekom]
Optional: [Nethermind, FCAT]
Threshold: 3 Required + 1-of-2 Optional (4 of 5 must agree)
```

| Metric | Assessment |
|--------|-----------|
| Security | Very strong — 4 of 5 must agree, with fully independent required set |
| Client diversity | Yes — Gasolina + Canary client (in required set) |
| Cloud diversity | Strongest (GCP, AWS, OTC in required; GCP + Fidelity infra in optional) |
| Entity independence | Strongest — no admin overlap between required DVNs |
| DVN cost per msg | ~$0.016 |
| Liveness risk | Low — any 1 optional can go down; all 3 required must be live |
| **Notes** | Nethermind in optional still provides value (depth, entity diversity) without the risk of relying on it as required alongside LZ Labs given their admin overlap. FCAT adds institutional/Fidelity credibility. |

#### Option G: Nethermind-Free Variant (3 Required + 1-of-2 Optional)

```
Required: [LayerZero Labs, Canary, Deutsche Telekom]
Optional: [FCAT, P2P]
Threshold: 3 Required + 1-of-2 Optional (4 of 5 must agree)
```

| Metric | Assessment |
|--------|-----------|
| Security | Very strong — 4 of 5 must agree, fully independent required set |
| Client diversity | Yes — Gasolina + Canary client (in required set) |
| Cloud diversity | Strong (GCP, AWS, OTC in required; Fidelity infra + GCP in optional) |
| Entity independence | Strongest — completely avoids LZ/Nethermind admin overlap concern |
| DVN cost per msg | ~$0.016 |
| Liveness risk | Low — any 1 optional can go down; all 3 required must be live |
| **Notes** | Eliminates Nethermind entirely for maximum separation from LZ Labs infrastructure. Trades Nethermind's track record for P2P's long validator history. |

#### Option H: Maximum (3 Required + 2-of-3 Optional)

```
Required: [LayerZero Labs, Canary, Deutsche Telekom]
Optional: [Nethermind, FCAT, P2P]
Threshold: 3 Required + 2-of-3 Optional (5 of 6 must agree)
```

| Metric | Assessment |
|--------|-----------|
| Security | Maximum — 5 of 6 must agree, fully independent required set |
| Client diversity | Yes — Gasolina + Canary client (in required set) |
| Cloud diversity | Strongest (GCP, AWS, OTC, Fidelity infra) |
| Entity independence | Strongest required set + deep optional bench |
| DVN cost per msg | ~$0.019 |
| Liveness risk | Lowest — optional set tolerates 1 failure; required set must be live |
| **Notes** | Exceeds 4-of-5 threshold. Higher than requested but near-zero marginal cost (~$0.003 more than Option F). Nethermind admin overlap is tolerable in optional since the required set is fully independent. |

---

### Deprecated Options (A–E)

> **⚠️ The following options were drafted before the KelpDAO incident (April 2026) revealed that LayerZero Labs and Nethermind share substantial ADMIN_ROLE overlap on-chain and both run on GCP with the same Gasolina client. Options that rely on both as required verifiers have weaker actual independence than originally assessed. They are preserved here for reference but are superseded by Options F–H above.**

<details>
<summary>Click to expand deprecated options</summary>

#### Option A: Minimal Secure (2 Required)

```
Required: [LayerZero Labs, Nethermind]
Optional: none
Threshold: 2-of-2
```

| Metric | Assessment |
|--------|-----------|
| Security | ~~Moderate~~ → **Weak** — shared admin keys, same client, same cloud |
| Client diversity | None — both use Gasolina |
| Cloud diversity | None — both on GCP |
| DVN cost per msg | ~$0.007 |
| Liveness risk | Higher — either DVN going down blocks all messages |

#### Option B: Strong Security (2 Required + 1-of-2 Optional)

```
Required: [LayerZero Labs, Nethermind]
Optional: [Canary, Deutsche Telekom]
Threshold: 2 Required + 1-of-2 Optional
```

| Metric | Assessment |
|--------|-----------|
| Security | ~~Strong~~ → **Moderate** — if LZ+Nethermind compromised via shared admin keys, security degrades to 1-of-2 optional only |
| Client diversity | Yes — Gasolina + Canary client |
| Cloud diversity | Strong (GCP, AWS, OTC) |
| DVN cost per msg | ~$0.013 |
| Liveness risk | Low — optional set provides redundancy |

#### Option C: Maximum Security (2 Required + 2-of-3 Optional)

```
Required: [LayerZero Labs, Nethermind]
Optional: [Canary, Deutsche Telekom, FCAT]
Threshold: 2 Required + 2-of-3 Optional
```

| Metric | Assessment |
|--------|-----------|
| Security | ~~Maximum~~ → **Strong** — if LZ+Nethermind compromised via shared admin keys, security degrades to 2-of-3 optional only |
| Client diversity | Yes — Gasolina + Canary client |
| Cloud diversity | Strongest (GCP, AWS, OTC, Fidelity infra) |
| DVN cost per msg | ~$0.016 |
| Liveness risk | Lowest — multiple layers of redundancy |

#### Option D: Balanced (3 Required)

```
Required: [LayerZero Labs, Canary, Nethermind]
Optional: none
Threshold: 3-of-3
```

| Metric | Assessment |
|--------|-----------|
| Security | ~~Strong~~ → **Moderate** — Canary is independent but LZ+Nethermind share admin overlap; a compromise of both means only Canary blocks the forged message |
| Client diversity | Yes — Gasolina + Canary client |
| Cloud diversity | Partial (GCP + AWS) — LZ Labs and Nethermind both on GCP |
| DVN cost per msg | ~$0.010 |
| Liveness risk | Moderate — any single DVN outage blocks messages |

#### Option E: Balanced + Resilience (3 Required + 1-of-2 Optional)

```
Required: [LayerZero Labs, Canary, Nethermind]
Optional: [Deutsche Telekom, FCAT]
Threshold: 3 Required + 1-of-2 Optional
```

| Metric | Assessment |
|--------|-----------|
| Security | ~~Very strong~~ → **Strong** — same LZ+Nethermind admin overlap concern in required set |
| Client diversity | Yes — Gasolina + Canary client |
| Cloud diversity | Strongest (GCP, AWS, OTC, Fidelity infra) |
| DVN cost per msg | ~$0.016 |
| Liveness risk | Moderate (required set) but optional adds audit trail |

</details>

---

## DVN Contract Addresses

All providers confirmed deployed on Ethereum, Base, and Polygon (queried from [LZ metadata API](https://metadata.layerzero-api.com/v1/metadata/dvns) on 2026-05-30):

| Provider | Ethereum | Base | Polygon |
|----------|----------|------|---------|
| LayerZero Labs | `0xDb979D0A36aF0525AFa60Fc265B1525505c55D79` | `0x9e059a54699a285714207b43B055483E78FAac25` | `0xA70C51C38D5A9990F3113a403D74EBa01fce4CCb` |
| Nethermind | `0xa59BA433ac34D2927232918Ef5B2eaAfcF130BA5` | `0x658947BC7956aea0067a62Cf87ab02ae199Ef3f3` | `0xbCefdAdB8d24b1d36c26B522235012Cd4cf162f6` |
| Canary | `0xa4fE5A5B9A846458a70Cd0748228aED3bF65c2cd` | `0x554833698Ae0FB22ECC90B01222903fD62CA4B47` | `0x13feb7234Ff60A97af04477d6421415766753Ba3` |
| Deutsche Telekom | `0x373a6E5c0C4E89E24819f00AA37ea370917AAfF4` | `0xc2A0C36f5939A14966705c7Cec813163FaEEa1F0` | `0x5CcCb8DE6Cdba9D2Af9d84465653af7390FDf9Dd` |
| FCAT | `0xc61aF5706b80Ca941a0aAb1C7B3D7a953E4dD8C4` | `0xEaE72C81F3FCe1313EeeE26717F42af91E178516` | `0x14206011d192E4F41D694d21ac599D0e88c2c12A` |
| Luganodes | `0x58249a2Ec05c1978bF21DF1f5eC1847e42455CF4` | `0xa0AF56164F02bDf9d75287ee77c568889F11d5f2` | `0xD1b5493e712081A6FBAb73116405590046668F6b` |
| P2P | `0x06559EE34D85a88317Bf0bfE307444116c631b67` | `0x5b6735c66d97479cCD18294fc96B3084EcB2fa3f` | `0x9EEee79F5dBC4D99354b5CB547c138Af432F937b` |
| Nansen | `0x3a4636E9AB975d28d3Af808b4e1c9fd936374E30` | `0x93aC538152E1BC4F093aE5666Ee9FD1d84f4f4bF` | `0x0a8618F71dB88AB5D0CAF0610Ede19F0AB8817c5` |

---

## Decision Log

| Date | Decision | Rationale |
|------|----------|-----------|
| 2026-05-30 | Initial provider shortlist confirmed | Based on LayerZero team call — prioritizing client, cloud, and entity diversity |
| | | |

### Open Questions

1. ~~**Deutsche Telekom Base support**~~ — ✅ Confirmed deployed on all 3 chains.
2. ~~**FCAT chain coverage**~~ — ✅ Confirmed deployed on Ethereum, Base, Polygon.
3. ~~**Luganodes/P2P/Nansen viability**~~ — ✅ All confirmed deployed on Ethereum, Base, Polygon.
4. **TelcoinNetwork DVN support** — Which providers will support TelcoinNetwork when it launches? This could narrow our options.
5. ~~**Exact fee quotes**~~ — ✅ Queried via `getFee()` on 2026-05-30. DVN fees are ~$0.003/DVN/msg from Ethereum. Cost is negligible.
6. **Liveness SLAs** — Do any providers offer uptime guarantees or SLAs?
7. **Preferred mesh option** — Need team alignment on which option (A–E). Given negligible cost delta, security should be the primary driver.

---

## References

- [LayerZero DVN Providers & Addresses](https://docs.layerzero.network/v2/deployments/dvn-addresses)
- [LayerZero DVN Metadata API](https://metadata.layerzero-api.com/v1/metadata/dvns)
- [LayerZero V2: Explaining DVNs](https://layerzero.network/blog/layerzero-v2-explaining-dvns)
- [LayerZero Gas Fee Estimation](https://docs.layerzero.network/v2/developers/evm/configuration/gas-fees)
- [LayerZero x EigenLayer: CryptoEconomic DVN Framework](https://layerzero.network/blog/layerzero-x-eigenlayer-cryptoeconomic-dvn-framework)
- [Deutsche Telekom MMS Joins LayerZero](https://layerzero.network/blog/deutsche-telekom-mms-joins-layerzero-as-dvn)
- [FCAT DVN Announcement](https://www.fcatalyst.com/trends-and-signals/fcat-deploys-decentralized-verifier-network-dvn-on-layerzero-protocol-with-ondo-as-an-early-integrator)
- [Canary DVN Documentation](https://canary-protocol.gitbook.io/canary/overview/canary-products/canary-dvn)
- [Nethermind Infrastructure](https://www.nethermind.io/infrastructure-management)
- [LayerZero Fee Switch](https://layerzero.foundation/fee-switch)
