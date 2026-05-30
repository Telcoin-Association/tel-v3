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
| **Notes** | Default DVN for most applications. Battle-tested with 200M+ messages verified. Most protocols include LZ DVN as a required verifier. |

#### 2. Canary DVN

| Attribute | Details |
|-----------|---------|
| **Client** | Custom Go implementation |
| **Cloud** | AWS (Nitro TEE) |
| **Entity** | Canary Protocol |
| **Chain Coverage** | 90+ chains — largest coverage of any third-party DVN |
| **Chains We Need** | Ethereum, Base, Polygon — all supported |
| **Security Model** | TEE-based verification (AWS Nitro enclaves) with cryptographic attestation + EigenLayer cryptoeconomic security (staking/slashing). Slashable stake backs every verification. |
| **Notes** | Only DVN with a non-TypeScript, non-Rust client — provides true client diversity against LayerZero's Gasolina. TEE + staking model provides both hardware and economic security guarantees. |

#### 3. Nethermind DVN

| Attribute | Details |
|-----------|---------|
| **Client** | Custom (Nethermind team) |
| **Cloud** | Multi-AZ with load balancing |
| **Entity** | Nethermind (Ethereum execution client team) |
| **Chain Coverage** | 70+ chains |
| **Chains We Need** | Ethereum, Base, Polygon — all supported |
| **Notes** | Described as LayerZero's most "robust" partner with a **dedicated team** for DVN maintenance. Nethermind also builds the flagship Nethermind Ethereum execution client (C#/.NET). Hybrid globally redundant platform with 24/7 SRE coverage and unified observability. One of LayerZero's original DVN launch partners. |

#### 4. Deutsche Telekom MMS DVN

| Attribute | Details |
|-----------|---------|
| **Client** | Custom |
| **Cloud** | Open Telekom Cloud (OTC) — European data centers, **not** AWS/GCP/Azure |
| **Entity** | Deutsche Telekom MMS (subsidiary of Deutsche Telekom AG) |
| **Chain Coverage** | 25+ chains |
| **Chains We Need** | Ethereum, Base, Polygon — ✅ all supported |
| **Notes** | Unique cloud diversity — runs on Deutsche Telekom's own European cloud infrastructure, independent of US hyperscalers. Institutional-grade entity (€100B+ parent company). Has operated blockchain validators since 2020 (NEAR, Polygon). Joined LayerZero May 2025. |

### Tier 2 — Additional Providers

#### 5. FCAT (Fidelity Center for Applied Technology)

| Attribute | Details |
|-----------|---------|
| **Client** | Custom |
| **Cloud** | Fidelity infrastructure |
| **Entity** | FCAT (Fidelity Investments R&D arm) |
| **Chain Coverage** | ~7 chains (Ethereum, Polygon, Arbitrum, Base, Optimism, Avalanche, Solana) |
| **Chains We Need** | Ethereum, Base, Polygon — ✅ all supported |
| **Notes** | Primarily utilized by Ondo Finance for institutional RWA bridging. Fidelity entity adds strong institutional credibility. Limited chain coverage (focused on major chains only). |

#### 6. Luganodes

| Attribute | Details |
|-----------|---------|
| **Client** | Custom |
| **Cloud** | TBD |
| **Entity** | Luganodes (Lugano-based validator operator) |
| **Chain Coverage** | 20+ chains |
| **Chains We Need** | Ethereum, Base, Polygon — ✅ all supported |
| **Notes** | Smaller operator. |

#### 7. P2P

| Attribute | Details |
|-----------|---------|
| **Client** | Custom |
| **Cloud** | GCP |
| **Entity** | P2P.org (original Lido incubator) |
| **Chain Coverage** | 20+ chains |
| **Chains We Need** | Ethereum, Base, Polygon — ✅ all supported |
| **Notes** | Reputable PoS validator operator since 2018. GCP cloud overlaps with LayerZero Labs — less cloud diversity value. |

#### 8. Nansen

| Attribute | Details |
|-----------|---------|
| **Client** | Custom |
| **Cloud** | TBD |
| **Entity** | Nansen (blockchain analytics company) |
| **Chain Coverage** | 15+ chains |
| **Chains We Need** | Ethereum, Base, Polygon — ✅ all supported |
| **Notes** | Known primarily for on-chain analytics. Smaller DVN footprint. |

---

## Diversity Analysis

### Client Diversity Matrix

| Client Language | DVN Provider(s) |
|----------------|-----------------|
| TypeScript (Gasolina) | LayerZero Labs |
| Go | Canary |
| Custom (C#/.NET team) | Nethermind |
| Custom (unknown) | Deutsche Telekom, FCAT, Luganodes, P2P, Nansen |
| Rust | (Not yet released — future option) |
| OpenZeppelin client | (Not yet released — future option) |

> **Key insight:** LayerZero Labs + Canary + Nethermind gives us 3 distinct client implementations. This is the strongest client diversity achievable today.

### Cloud/Infrastructure Diversity Matrix

| Cloud Provider | DVN Provider(s) |
|---------------|-----------------|
| GCP | LayerZero Labs, P2P |
| AWS (Nitro TEE) | Canary |
| Open Telekom Cloud (Europe) | Deutsche Telekom |
| Multi-AZ (hybrid) | Nethermind |
| Fidelity infra | FCAT |
| Unknown | Luganodes, Nansen |

> **Key insight:** LayerZero (GCP) + Canary (AWS) + Deutsche Telekom (OTC) gives us 3 completely independent cloud providers. Nethermind's multi-AZ setup adds further resilience.

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

| Config | DVN Count | DVN Cost (USD) | vs. Option A |
|--------|-----------|----------------|-------------|
| **Option A** — 2 required (LZ + Nethermind) | 2 | $0.0065 | baseline |
| **Option B** — 2 req + 1-of-2 opt (+ Canary, DT) | 4 | $0.0131 | +101% |
| **Option C** — 2 req + 2-of-3 opt (+ Canary, DT, FCAT) | 5 | $0.0164 | +151% |
| **Option D** — 3 required (LZ + Canary + Nethermind) | 3 | $0.0098 | +51% |
| **Option E** — 3 req + 1-of-2 opt (+ DT, FCAT) | 5 | $0.0164 | +151% |

> **Bottom line:** Even at 5 DVNs (Options C/E), total DVN cost is ~$0.016 per message — **less than 2 cents**. The difference between 2 and 5 DVNs is ~$0.01. Security should drive this decision, not cost.

### Cost Impact of N-of-M Configurations

| Config | Required DVNs Pay | Optional DVNs Pay | Notes |
|--------|-------------------|-------------------|-------|
| 2 Required, 0 Optional | 2 always | 0 | Cheapest. Both must verify. |
| 2 Required, 1-of-2 Optional | 2 always | All optional DVNs verify (fee charged) | More secure, +$0.007 |
| 2 Required, 2-of-3 Optional | 2 always | All optional DVNs verify (fee charged) | Most secure, +$0.010 |
| 3 Required, 0 Optional | 3 always | 0 | Strong security, +$0.003 |

> **Important:** All configured DVNs (both required and optional) verify every message and charge fees. The "optional" label only affects the *threshold for acceptance*, not whether they run and charge.

### Protocol Fee Switch

LayerZero governance controls a protocol fee of up to 100% of DVN + executor costs. The fee switch was **activated in December 2025** via governance vote (97% approval). Since February 2026, protocol fees are being collected, converted to ZRO, and burned. This effectively adds a surcharge on top of DVN + executor fees. The exact current rate should be confirmed via the [LayerZero fee switch page](https://layerzero.foundation/fee-switch) before finalizing cost projections.

---

## Mesh Configuration Options

### Option A: Minimal Secure (2 Required)

```
Required: [LayerZero Labs, Nethermind]
Optional: none
Threshold: 2-of-2
```

| Metric | Assessment |
|--------|-----------|
| Security | Moderate — two independent verifications |
| Client diversity | Partial (TS + custom) |
| Cloud diversity | Partial (GCP + multi-AZ) |
| DVN cost per msg | ~$0.007 |
| Liveness risk | Higher — either DVN going down blocks all messages |

### Option B: Strong Security (2 Required + 1-of-2 Optional)

```
Required: [LayerZero Labs, Nethermind]
Optional: [Canary, Deutsche Telekom]
Threshold: 2 Required + 1-of-2 Optional
```

| Metric | Assessment |
|--------|-----------|
| Security | Strong — 3 of 4 must agree (2 required + 1 optional) |
| Client diversity | Strong (TS, Go, custom×2) |
| Cloud diversity | Strong (GCP, AWS, OTC, multi-AZ) |
| DVN cost per msg | ~$0.013 |
| Liveness risk | Low — optional set provides redundancy |

### Option C: Maximum Security (2 Required + 2-of-3 Optional)

```
Required: [LayerZero Labs, Nethermind]
Optional: [Canary, Deutsche Telekom, FCAT]
Threshold: 2 Required + 2-of-3 Optional
```

| Metric | Assessment |
|--------|-----------|
| Security | Maximum — 4 of 5 must agree |
| Client diversity | Strongest |
| Cloud diversity | Strongest (GCP, AWS, OTC, Fidelity, multi-AZ) |
| DVN cost per msg | ~$0.016 |
| Liveness risk | Lowest — multiple layers of redundancy |

### Option D: Balanced (3 Required)

```
Required: [LayerZero Labs, Canary, Nethermind]
Optional: none
Threshold: 3-of-3
```

| Metric | Assessment |
|--------|-----------|
| Security | Strong — all 3 must agree |
| Client diversity | Strong (TS, Go, custom) |
| Cloud diversity | Good (GCP, AWS, multi-AZ) |
| DVN cost per msg | ~$0.010 |
| Liveness risk | Moderate — any single DVN outage blocks messages |

### Option E: Balanced + Resilience (3 Required + 1-of-2 Optional)

```
Required: [LayerZero Labs, Canary, Nethermind]
Optional: [Deutsche Telekom, FCAT]
Threshold: 3 Required + 1-of-2 Optional
```

| Metric | Assessment |
|--------|-----------|
| Security | Very strong — 4 of 5 must agree |
| Client diversity | Strongest |
| Cloud diversity | Strongest |
| DVN cost per msg | ~$0.016 |
| Liveness risk | Moderate (required set) but optional adds audit trail |

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
