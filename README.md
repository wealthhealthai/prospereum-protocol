# Prospereum (PSRE)

**Decentralized behavioral mining protocol on Base.**

Proof of Net Economic Contribution — on-chain token rewards for health & wellness DTC brands.

## Protocol Overview

- **Total Supply:** 21,000,000 PSRE (immutable)
- **Emission Reserve:** 12,600,000 (60%) — behavioral mining
- **Team:** 4,200,000 (20%) — 1yr cliff, 4yr linear vest
- **Treasury/Liquidity:** 4,200,000 (20%) — minted at genesis
- **Chain:** Base (EVM)
- **Epoch:** 7 days
- **Base Reward Rate:** 10% of net partner buy volume

## Contract Architecture

```
contracts/
├── core/
│   ├── PSRE.sol              — ERC-20, mint-only by RewardEngine, hard cap 21M
│   ├── PartnerRegistry.sol   — partner identity, partnerId, vault mapping
│   ├── PartnerVaultFactory.sol — EIP-1167 clone factory
│   └── PartnerVault.sol      — buy() via Uniswap v3, cumBuy tracking
└── periphery/
    ├── StakingVault.sol      — time-weighted PSRE + LP staking
    └── RewardEngine.sol      — epoch finalization, EMA, scarcity math, minting
```

## Build

```bash
npm install
npx hardhat compile
npx hardhat test
```

## Status

🚧 **Pre-alpha — contracts not yet deployed.**

---

*Specs: see `docs/` directory.*
