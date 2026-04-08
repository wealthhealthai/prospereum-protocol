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

## ✅ SPEC APPROVED & FROZEN — 2026-03-27

**Shu approved the v3.2 spec and whitepaper on 2026-03-27.**
**Jason is aware. Shu authorized contract build to proceed without waiting for Jason's separate approval on this step.**
**Dev spec:** `projects/prospereum/prospereum-dev-spec-v3.2.md` (frozen)
**Whitepaper:** `projects/prospereum/prospereum-whitepaper-v3.2.md` (frozen)

Contract rebuild begins immediately. Any spec changes after this point require Shu + Jason approval.

---

## Completed Decisions — v3.2 Design Session (2026-03-18 to 2026-03-27)

| Decision | Value | Decided By | Date |
|----------|-------|-----------|------|
| Reward metric | cumS high-water-mark ratchet: `cumS(t) = max(S_eco(t), cumS(t-1))`. Replaces gross cumBuy. | Shu | 2026-03-21 |
| Anti-compounding formula | `effectiveCumS(t) = cumS(t) - cumulativeRewardMinted(t)`. Reward PSRE excluded from cumS calculation. No provenance tagging needed. | Shu | 2026-03-25 |
| Initial buy earns zero | S(N) (vault creation buy) sets baseline, earns no reward. Only growth above S(N) earns. | Shu | 2026-03-21 |
| First qualification condition | First reward only paid when cumS(M) > S(N) for any M > N. First reward = r_base × (cumS(M) - S(N)). | Shu | 2026-03-22 |
| Vault bond | ELIMINATED. Replaced by un-rewarded initial buy (irrecoverable swap fees serve as entry cost). | Shu | 2026-03-22 |
| Reward vesting | ELIMINATED. Replaced by first qualification condition. | Shu | 2026-03-22 |
| Distribution reward | ELIMINATED. Distribution to customers earns no direct protocol reward (indirect commerce incentive sufficient). | Shu | 2026-03-21 |
| CustomerVault architecture | Partner deploys CustomerVaults on behalf of customers. Customers are blockchain-agnostic. CustomerVault balances included in S_eco. | Shu | 2026-03-21 |
| CustomerVault gas | Partner pays CustomerVault deployment gas (cost of running rewards program). | Shu | 2026-03-25 |
| S_min | $500 USDC minimum initial buy to create a PartnerVault. USDC-denominated (not PSRE) to avoid price volatility. | Shu | 2026-03-25 |
| Vault expiry | 52 epochs (~1 year) of zero cumS growth. Governance sends off-chain notification before deactivation. | Shu | 2026-03-25 |
| Tier multipliers (corrected) | M_BRONZE=0.8e18, M_SILVER=1.0e18, M_GOLD=1.2e18. Effective rates: 8%/10%/12%. (Corrected from 1.0/1.25/1.5 mismatch.) | Shu | 2026-03-25 |
| Enterprise vault management | NOT in protocol. WealthHealth Olympus builds service layer on top. Prospereum stays simple — partnerOwner can be any address. | Shu + Jason | 2026-03-26 |
| Tier floor for enterprise | None. Every partner earns their tier via EMA regardless of platform or commitment size. Protocol is fair and consistent. | Shu | 2026-03-26 |
| Primary anti-spam mechanism | Reward qualification conditions (no reward on S(N), cumS(M)>S(N) required). NOT the scarcity cap. | Shu | 2026-03-26 |
| External audit | BlockApex signed 2026-04-01. $5K total, 2 SSAs, ~4-5 days. $2,500 upfront wire due from Shu. Audit running now. Results ~April 7–8. (Cantina $20-30K = over budget. Pashov = unavailable. Cyberscope = rejected.) | Shu | 2026-04-01 |
| UPGRADE_TIMELOCK duration | 7 days. Rationale: Cantina would flag 2 days; RewardEngine upgrades should be rare; stronger security posture at mainnet launch. | Jason | 2026-03-28 |
| v3.2 Base Sepolia testnet deploy | Deploy green-lit by Jason 2026-03-28. All 8 contracts deployed + Sourcify verified. RewardEngine proxy: `0xe668fE9DbCE8CBbc8b3590100e8c31aA12F5C697` | Jason | 2026-03-28 |
| Launch target | Mainnet ~April 4-7, 2026. Base Sepolia testnet March 28 (post v3.2 rebuild). | Shu | 2026-03-26 |
| v3.2 contract rebuild | Full rebuild required. v2.3 contracts (deployed on Base Sepolia) are superseded. Rebuild starts after Jason + Shu approve v3.2 spec. | Kin | 2026-03-26 |
| finalizeEpoch gas ceiling | At max scale (200 vaults × 1000 CVs = 200K balanceOf calls ≈ 420M gas), a single finalizeEpoch() transaction would exceed block limits. Mitigation before mainnet scale: paginated epoch finalization (split across multiple transactions) or off-chain keeper with merkle proof pattern. Not a current concern at launch scale. | Kin | 2026-03-27 |
| Epoch keeper architecture | Option A (OpenClaw cron + cast send) for testnet. Option C (cron primary + Gelato fallback) for mainnet. Cron wired 2026-04-03: every Saturday 20:00 UTC, cron ID 3fc22360. First run targets Epoch 0 close (2026-04-04 19:43 UTC). | Kin | 2026-04-03 |
| Lazy epoch auto-finalization | autoFinalizeEpochs() added to RewardEngine. Called by createVault() and buy(). Partners' own activity triggers epoch finalization — no dedicated keeper required. AUTO_FINALIZE_MAX_EPOCHS = 10. Permissionless standalone call also preserved. | Shu | 2026-04-02 |
| Mainnet launch target (revised) | April 14–16, 2026. BlockApex audit signed April 1 (2 SSAs, commit 7e96ba9). Initial report ~April 8–9, fixes ~April 11, final report ~April 13–14. | Shu + Jason | 2026-04-01 |
| Mainnet launch target (revised x2) | April 18–21, 2026. BlockApex returned 22 findings (3C/3H/11M/4L/1I). StakingVault refactor + architectural fixes required before mainnet. | Shu | 2026-04-07 |
| cumS tracking method | cumS grows ONLY through explicit buy() and distributeToCustomer() calls. Direct ERC-20 transfers to vault addresses are ignored for cumS/reward purposes. Removes live balanceOf() scanning from _updateCumS(). Fixes BlockApex finding #3 (flash loan inflation). | Shu | 2026-04-07 |
| LP staking in v1 | KEEP LP staking. Rebuild StakingVault with two separate sub-pools within the 30% staker allocation: (1) PSRE staker pool, (2) LP staker pool. Default split: 50%/50% (governance-adjustable). No cross-asset comparison. Fixes BlockApex finding #13. | Shu | 2026-04-07 |
| StakingVault accounting model | Synthetix-style epoch-aware checkpointing. Remove manual recordStakeTime(). Time-weighted contributions tracked per-epoch, per-asset. _checkpoint() splits elapsed time correctly across epoch boundaries. Users claim without any manual recording step. Separate totalPSREStakedTime and totalLPStakedTime per epoch. Fixes BlockApex findings #5, #9, #15, #20. | Shu | 2026-04-07 |
