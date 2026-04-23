# Prospereum Protocol (PSRE)

**Proof of Prosperity** — Live on Base Mainnet

[![Audited by BlockApex](https://img.shields.io/badge/Audited%20by-BlockApex-green)](https://github.com/BlockApex/Audit-Reports/blob/master/Prospereum%20Protocol_Final%20Audit%20Report.pdf)

Prospereum is a decentralized behavioral mining protocol on [Base](https://base.org) (EVM). Token emissions are driven by verifiable, on-chain economic activity — not passive holding.

## Overview

Partners (ecommerce brands) purchase PSRE tokens to distribute as customer loyalty rewards. The protocol mints reward emissions based on provable, on-chain economic activity — specifically, the net growth of PSRE held within a partner's registered vault ecosystem.

Key properties:
- **Progressive scarcity** — emission rate decreases asymptotically as total supply approaches the 21M cap
- **Anti-wash-trading** — cumulative high-water-mark (cumS) ratchet prevents reward recycling
- **Anti-inflation** — effectiveCumS deduction excludes minted rewards from future reward calculations
- **Commerce-aligned** — rewards only flow when a partner's ecosystem genuinely grows
- **Passive staking** — Synthetix-style accumulator; stake once, earn forever without checkpointing

## Deployed Contracts (Base Mainnet — Chain ID 8453)

| Contract | Address |
|----------|---------|
| PSRE Token | [`0x2fE08f304f1Af799Bc29E3D4E210973291d96702`](https://basescan.org/address/0x2fE08f304f1Af799Bc29E3D4E210973291d96702) |
| PartnerVaultFactory | [`0xFF84408633f79b8f562314cC5A3bCaedA8f76902`](https://basescan.org/address/0xFF84408633f79b8f562314cC5A3bCaedA8f76902) |
| PartnerVault (impl) | [`0xa1BcD31cA51Ba796c73578d1C095c9EE0adb9F18`](https://basescan.org/address/0xa1BcD31cA51Ba796c73578d1C095c9EE0adb9F18) |
| CustomerVault (impl) | [`0xAb5906f5a3f03576678416799570d0A0ceEc40f2`](https://basescan.org/address/0xAb5906f5a3f03576678416799570d0A0ceEc40f2) |
| StakingVault | [`0x684BEA07e979CB5925d546b2E2099aA1c632ED2D`](https://basescan.org/address/0x684BEA07e979CB5925d546b2E2099aA1c632ED2D) |
| RewardEngine (proxy) | [`0x9Ab37Fc6D01B85491Ed0863B7F832784bE717EF5`](https://basescan.org/address/0x9Ab37Fc6D01B85491Ed0863B7F832784bE717EF5) |
| RewardEngine (impl) | [`0xE194EF5ABB93cb62089FB5a3b407B9B7f38F04f5`](https://basescan.org/address/0xE194EF5ABB93cb62089FB5a3b407B9B7f38F04f5) |

**Genesis timestamp:** `1776829977`  
**Deployment date:** April 22, 2026

## Contracts

| Contract | Description |
|----------|-------------|
| `PSRE.sol` | ERC-20 token, 21M hard cap, MINTER_ROLE gated, epoch-capped minting |
| `PartnerVaultFactory.sol` | EIP-1167 clone factory, deploys PartnerVaults via USDC→PSRE swap |
| `PartnerVault.sol` | Per-partner vault — tracks cumS, executes buys, routes customer rewards |
| `CustomerVault.sol` | Lightweight holding contract deployed for each customer |
| `RewardEngine.sol` | Epoch math, cumS reward formula, EMA tier scoring, scarcity curve. UUPS upgradeable (7-day timelock). |
| `StakingVault.sol` | Synthetix-style passive PSRE + LP staking. Cumulative accumulator, O(1) settlement. |

## Security

- **Audited by [BlockApex](https://blockapex.io)** — April 2026 — [Full Report](https://github.com/BlockApex/Audit-Reports/blob/master/Prospereum%20Protocol_Final%20Audit%20Report.pdf)
- 29 findings identified across 2 audit phases; all resolved before mainnet deployment
- 249 tests passing (Foundry: unit, integration, invariant fuzz)

## Documentation

- [Developer Spec v3.4](projects/prospereum/prospereum-dev-spec-v3.4.md) — frozen at mainnet
- [Whitepaper v3.3](projects/prospereum/prospereum-whitepaper-v3.3.md) — public-ready
- [Deployed Contracts](projects/prospereum/deployments.md)
- [Protocol Decisions](projects/prospereum/decisions.md)
- [Audit CSV](audit/blockapex-findings-response.csv)

## Development

**Prerequisites:** [Foundry](https://book.getfoundry.sh/)

```bash
# Install dependencies
forge install

# Build
forge build

# Test
forge test

# Full suite with gas report
forge test --gas-report
```

## Governance

- **Founder Safe** (governance/upgrades): `0xc59816CAC94A969E50EdFf7CF49ce727aec1489F`
- **Treasury Safe** (PSRE treasury/LP): `0xa9Fde837EBC15BEE101d0D895c41a296Ac2CAfCe`
- Both are 2-of-3 Gnosis Safes on Base mainnet

## License

MIT
