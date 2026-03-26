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

| Decision | Options | Status | Date Raised |
|----------|---------|--------|-------------|
| **Managed Partner / Platform Manager architecture** | A→B hybrid (WH holds `partnerOwner`, `updateOwner()` to migrate) vs. registry-level Platform Manager role | Direction: A→B hybrid agreed with Jason. Decision document to be drafted by Kin before spec changes. | 2026-03-26 |
| **Tier fast-track for enterprise partners** | Add DAO-settable `tierFloor(vault)` minimum tier for verified partners vs. keep pure EMA | Proposed by Kin. Pending Jason + Shu decision. | 2026-03-26 |
| **C2 — Reward destination** | Rewards to vault owner wallet (dev spec) vs. rewards deposited into PartnerVault (whitepaper) | Kin recommends: owner wallet. Existing review flagged. Pending Jason + Shu call. | 2026-03-24 |
| **Open Question 1** — Tier multiplier on first reward | Apply Bronze multiplier vs. flat r_base | Recommendation: apply Bronze multiplier. Lock before implementation. | 2026-03-24 |
| **Open Question 2** — Unqualified vault EMA | Zero EMA credit during unqualified period vs. retroactive credit | Recommendation: zero credit. Lock before implementation. | 2026-03-24 |
| **REGISTRATION_FEE** | Keep optional $50 fee vs. remove entirely (S_MIN is sufficient) | Recommendation: remove. Pending decision. | 2026-03-24 |
| **Vault expiry threshold** | 4 epochs (spec default) vs. 6 epochs (protocol review recommendation) | Pending Jason + Shu decision. | 2026-03-24 |
| **Phase 1 static analysis fixes** | Implement 3 items from Slither/Mythril run (nonReentrant on createVault, extract interfaces, gas benchmark) | Awaiting Jason go-ahead since 2026-03-12. | 2026-03-12 |
| **Phase 2 fuzz tests** | Proceed with Foundry invariant fuzzing | Awaiting Jason go-ahead. | 2026-03-12 |

## Completed Decisions (continued)_

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
| Website stack | Vite 7 + React 19 + TypeScript + Tailwind v4 + Framer Motion + Three.js vanilla. NOT Next.js (GitHub Pages CDN issues). Scaffold in projects/prospereum-site/ | Jason via Shiro handoff | 2026-03-09 |
| Founder vesting | Sablier (not custom TeamVesting.sol). Founder tokens held in Founder Safe, streamed via Sablier. TeamVesting.sol removed from mainnet deploy. | Shu | 2026-03-12 |
| D4 — Genesis LP | PSRE/USDC on Uniswap v3. Launch price: $0.10/PSRE. Liquidity: $40K ($20K USDC + 200K PSRE from treasury). Fee tier: 1%. Price range: $0.04–$0.50. | Shu | 2026-03-12 |
| LP lock | Genesis LP NFT locked for 24 months via Unicrypt (app.uncx.network). Locked from Treasury Safe. | Shu | 2026-03-12 |
| Multisig setup | Three wallets required before mainnet: (1) Founder Safe — Jason + Shu, controls governance/upgrades. (2) Treasury Safe — Jason + Shu, controls PSRE treasury + LP. (3) Ops wallet — Jason EOA, day-to-day keeper/gas. | Shu | 2026-03-12 |

---

## Completed Decisions

_(move items here once decided and implemented)_
