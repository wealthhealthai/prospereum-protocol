# Prospereum — Protocol Decisions Log

**Record every significant decision here: what was decided, why, and by whom.**

---

## Locked Design Decisions (from Dev Spec v2.10)

These are FROZEN. Do not deviate without Jason's explicit approval.

| Decision | Value | Rationale |
|----------|-------|-----------|
| Emission model | Epoch-based (weekly), not per-claim | Predictable, gas-efficient |
| Mining primitive | Vault-executed PSRE buys only | Proof of real demand |
| Vault sells | Disabled in v1 | Prevents buy/sell cycle gaming |
| Price oracle | None — no USD normalization | Eliminates oracle manipulation vector |
| Scarcity function | x = T/S_emission only | Pure on-chain, no external dependency |
| Revenue split | 70% partners / 30% stakers | Partners drive demand, stakers provide liquidity |
| Staker rewards | Time-weighted (anti flash-stake) | Prevents capital efficiency exploits |
| Partner status | Rolling EMA with tier multipliers | Smooth, manipulation-resistant |
| Launch policy | No presale, no ICO, no private sale | Fair launch, treasury seeds LP |
| Team vesting | 1-year cliff, 4-year linear | Standard alignment |

---

## In-Progress Decisions

_(add items here as they arise)_

## Completed Decisions

| Decision | Value | Decided By | Date |
|----------|-------|-----------|------|
| Reward rates (C1) | Whitepaper rates: Bronze 8%, Silver 10%, Gold 12% | Shu | 2026-03-07 |
| alphaBase | 0.08e18 (not 0.10e18) | Shu | 2026-03-07 |
| Tier multipliers | M_BRONZE=1.0, M_SILVER=1.25, M_GOLD=1.5 | Shu | 2026-03-07 |
| TeamVesting contract | Add to spec and build: 1yr cliff, 4yr linear, no governance override | Shu | 2026-03-07 |
| Epoch finalization | Permissionless (anyone can call). Team-run keeper/cron as ops plan | Shu | 2026-03-07 |
| Partner identity | PartnerVault address = permanent identity. owner = controller (mutable via updateOwner/Ownable2Step) | Shu | 2026-03-07 |
| Target chain | Base (EVM) | Shu | 2026-03-06 |
| PartnerNFT | Removed from v1. No NFT. | Shu | 2026-03-06 |
| Upgradeability | PSRE immutable. Peripheral contracts versioned. RewardEngine UUPS+multisig+timelock early phase | Shu | 2026-03-06 |
| Genesis liquidity | Base-native, treasury-only LP seeding from Bootstrap Liquidity bucket. Exact price/depth TBD | Shu | 2026-03-07 |

---

## Completed Decisions

_(move items here once decided and implemented)_
