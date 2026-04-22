# GOODNIGHT.md — 2026-04-22

## 🚀 PROSPEREUM IS LIVE ON BASE MAINNET

Deployed April 21, 2026. Eight contracts. Clean audit. Real chain.

## Contract Addresses — Base Mainnet

| Contract | Address |
|---|---|
| PSRE | `0x2fE08f304f1Af799Bc29E3D4E210973291d96702` |
| PartnerVaultFactory | `0xFF84408633f79b8f562314cC5A3bCaedA8f76902` |
| StakingVault | `0x684BEA07e979CB5925d546b2E2099aA1c632ED2D` |
| **RewardEngine (proxy)** | `0x9Ab37Fc6D01B85491Ed0863B7F832784bE717EF5` |
| LP Token | `0x0Adc6BE14E76b89584216fAd4E458df5F996D336` |

Genesis timestamp: `1776829977`
Founder Safe: `0xc59816CAC94A969E50EdFf7CF49ce727aec1489F`
Treasury Safe: `0xa9Fde837EBC15BEE101d0D895c41a296Ac2CAfCe`

## ⚠️ Wiring Pending — Protocol Not Yet Functional

Three transactions via Founder Safe (batch JSON at commit `773133f`):
1. `factory.setRewardEngine(RewardEngine proxy)`
2. `stakingVault.setRewardEngine(RewardEngine proxy)`
3. `psre.grantRole(MINTER_ROLE, RewardEngine proxy)`

**Execute tomorrow — nothing works until this is done.**

## Immediate Post-Wiring (Jason + Shu)

1. Founder Safe wiring batch → execute via Safe Transaction Builder
2. Treasury Safe → seed $40K genesis LP (200K PSRE + $20K USDC, Uniswap v3 1%)
3. Lock LP NFT on Unicrypt (24 months)
4. Shu: Sablier vesting from Founder Safe (4.2M PSRE)
5. Kin: update keeper cron → mainnet RPC + RewardEngine proxy address
6. Nadir: share final commit hash → audit officially closed

## Keeper Update

- Mainnet genesis: April 21. Epoch 0 closes **April 28 ~19:43 UTC.**
- Keeper cron must be updated to mainnet before April 28.
- Old cron points at Base Sepolia — update REWARD_ENGINE_PROXY + RPC in .env or cron payload.
