# GOODNIGHT.md — 2026-04-22

## What Was Done Today — THE BIG ONE

**Prospereum is deployed to Base mainnet.** All 8 contracts live. Wire-up pending Shu's Safe signature.

### Deployed Contracts (Base Mainnet)
```
PSRE:                  0x2fE08f304f1Af799Bc29E3D4E210973291d96702
PartnerVaultFactory:   0xFF84408633f79b8f562314cC5A3bCaedA8f76902
PartnerVault impl:     0xa1BcD31cA51Ba796c73578d1C095c9EE0adb9F18
CustomerVault impl:    0xAb5906f5a3f03576678416799570d0A0ceEc40f2
StakingVault:          0x684BEA07e979CB5925d546b2E2099aA1c632ED2D
RewardEngine (impl):   0xE194EF5ABB93cb62089FB5a3b407B9B7f38F04f5
RewardEngine (proxy):  0x9Ab37Fc6D01B85491Ed0863B7F832784bE717EF5
LP Pool (computed):    0x0Adc6BE14E76b89584216fAd4E458df5F996D336
Founder Safe:          0xc59816CAC94A969E50EdFf7CF49ce727aec1489F
Treasury Safe:         0xa9Fde837EBC15BEE101d0D895c41a296Ac2CAfCe
Genesis timestamp:     1776829977
```

### Key decisions
- Two-phase deploy: PSRE first (Phase 1), rest after LP pool computed (Phase 2)
- LP pool address pre-computed via CREATE2 (no pool creation required before deploy)
- LP staking placeholder: pool address stored, but setSplit(1e18,0) needed after wiring
- Safe wiring batch: JSON file generated, uploaded, Jason signed — Shu pending

## In Progress / Waiting

**MOST URGENT:** Shu must sign Safe wiring tx
- app.safe.global → Founder Safe → Transactions → Queue → Sign → Execute
- Without this: protocol is deployed but dead

## Open Decisions / Actions (Jason or Shu)

1. **Shu — Sign Safe wiring tx** (immediate — protocol dead without it)
2. **Shu — Create Uniswap v3 LP pool** via Treasury Safe:
   - 200K PSRE + $20K USDC, 1% fee, price = 10 PSRE per USDC
   - app.safe.global → Treasury Safe → Apps → Uniswap
3. **Shu + Jason — Lock LP** via Unicrypt (24 months) after pool seeded
4. **Founder Safe — setSplit(1e18, 0)** to disable LP staking temporarily
   (Uniswap v3 positions are NFTs, not ERC-20 — LP staking needs wrapper)
5. **Shu — Sablier vesting stream** for 4.2M PSRE in Founder Safe
6. **Jason — website audit badge** (BlockApex GitHub URL available)

## Blockers
- None on Kin's side — code complete, all deployed
- Shu's Safe signature is the immediate gate

## Notes for Tomorrow
1. Check if Shu signed and wiring executed → verify with `cast call factory rewardEngine()`
2. If wired: help Shu create LP pool via Treasury Safe
3. Get Etherscan API key and verify all contracts on Basescan
4. Update admin dashboard with mainnet contract addresses
5. Epoch 3 closes April 25 19:43 UTC — keeper auto-fires (no action needed)
