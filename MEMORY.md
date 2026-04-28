# MEMORY.md — Kin (Prospereum Protocol Engineer)

*Curated long-term memory. Updated at significant milestones. Target: < 20KB.*
*Last updated: 2026-04-28*

---

## 1. Identity

- **Agent:** Kin (金 — gold), Prospereum protocol engineer
- **Model:** claude-sonnet-4-6 on OpenClaw
- **Workspace:** `/Users/wealthhealth_admin/.openclaw/workspace-kin`
- **GitHub repo:** `https://github.com/wealthhealthai/prospereum-protocol` (branch: master)
- **Supervisor:** Shiro (Jason's primary agent). Ask Shiro if confused about config, gateway, or memory.

---

## 2. Key People

| Person | Role | Contact |
|--------|------|---------|
| **Jason Li** | CEO WealthHealth AI, final authority on everything | Discord: chemist001 / `229342241787871234`, iMessage: +19494633308 |
| **Shu (boytaichi)** | Co-founder, spec author, equal authority on Prospereum | Discord: `755858520452366420` |
| **Shiro** | Kin's supervisor agent | Bot in Discord |

**Chain of command:** Jason > Shu (equal on Prospereum) > Kin

---

## 3. What Prospereum Is

Prospereum (PSRE) is a decentralized **behavioral mining protocol** on Base (EVM). It issues new PSRE only when verified on-chain commerce growth occurs — measured by the **cumulative high-water-mark (cumS)** of a partner's vault ecosystem. Never decreases. Partners earn rewards only when their ecosystem exceeds its all-time PSRE balance peak.

**Proof of Prosperity:** rewards = commerce growth, not passive holding.

---

## 4. Mainnet Deployment — Base (chainId 8453) — April 22, 2026

| Contract | Address |
|----------|---------|
| PSRE Token | `0x2fE08f304f1Af799Bc29E3D4E210973291d96702` |
| PartnerVault (impl) | `0xa1BcD31cA51Ba796c73578d1C095c9EE0adb9F18` |
| CustomerVault (impl) | `0xAb5906f5a3f03576678416799570d0A0ceEc40f2` |
| PartnerVaultFactory | `0xFF84408633f79b8f562314cC5A3bCaedA8f76902` |
| StakingVault | `0x684BEA07e979CB5925d546b2E2099aA1c632ED2D` |
| RewardEngine (impl) | `0xE194EF5ABB93cb62089FB5a3b407B9B7f38F04f5` |
| RewardEngine (proxy) | `0x9Ab37Fc6D01B85491Ed0863B7F832784bE717EF5` |

**Genesis timestamp:** `1776829977`
**Ops wallet (throwaway, gas only):** `0xa3C082910FF91425d45EBf15C52120cBc97aFef5`
**Ops wallet DEPLOYER_PK:** stored in `.env` (gitignored) on Mac Studio

### Gnosis Safes (2-of-3 each, Base mainnet)

| Safe | Address | Role |
|------|---------|------|
| Founder Safe | `0xc59816CAC94A969E50EdFf7CF49ce727aec1489F` | Governance, upgrades, DEFAULT_ADMIN_ROLE on PSRE |
| Treasury Safe | `0xa9Fde837EBC15BEE101d0D895c41a296Ac2CAfCe` | 4.2M PSRE treasury, LP seeding |

**Signers (both Safes):** `0xDb2ba138...` (Shu), `0xDA9EF138...` (Jason), `0xA0214b23...` (cold backup)

---

## 5. Token Allocation

| Category | Amount | Status |
|----------|--------|--------|
| Behavioral Mining Reserve | 12,600,000 (60%) | Locked — minted by RE over epochs |
| Team & Founders | 4,200,000 (20%) | In Founder Safe — Sablier vesting (1yr cliff, 4yr linear) |
| Treasury | 4,200,000 (20%) | In Treasury Safe — genesis LP + ops |

**Total supply cap:** 21,000,000 PSRE (immutable)

---

## 6. Architecture — Key Decisions (LOCKED)

- **cumS tracking:** Explicit flows only (`buy()` / `distributeToCustomer()` / `reportLeakage()`). No `balanceOf()` scanning. Flash-loan vector closed.
- **effectiveCumS:** `cumS - cumulativeRewardMinted`. Reward PSRE excluded from future reward basis. Anti-inflation.
- **StakingVault v3.1:** Synthetix-style cumulative accumulator. O(1) settlement. `cumulativePSRERewardPerToken` incremented at each `distributeStakerRewards()`. New users auto-initialized — no retroactive access.
- **Two staker sub-pools:** PSRE pool + LP pool (50/50 default). Governance-adjustable via `setSplit()`.
- **LP staking at launch:** `psreSplit = 1e18, lpSplit = 0` (LP staking deferred — Uniswap v3 positions are NFTs, not ERC-20).
- **Epoch-aware minting:** `mintForEpoch(to, amount, historicalEpochId)` — each historical epoch charges its own mint budget. Prevents batch-finalization DoS.
- **autoFinalizeEpochs():** Called from `buy()` and `createVault()`. Cap: 10 epochs. Lazy — no dedicated keeper required.
- **scarcityCeiling clamped to E0_MAX:** Prevents mint cap exceeded revert during batch.
- **RewardEngine:** UUPS proxy, 7-day upgrade timelock, 48-hour parameter timelock.
- **PSRE:** Immutable (no proxy). 21M hard cap. `MAX_MINT_PER_EPOCH = 25,200e18`.
- **partnerOf removed from auth:** All owner checks use live `vault.owner()` / `IPartnerVault(parentVault).owner()`.
- **Zero-staker epoch:** RE skips staker mint if both pools empty. StakingVault returns early without pulling tokens.

---

## 7. Security Audit — BlockApex (April 2026)

- **Dates:** April 2–17, 2026 (Phase 1 + re-audit)
- **Fixed commit:** `31eb31384dee7385b14b1f02ac033e2e488e721f`
- **Findings:** 29 total (5C, 5H, 13M, 5L, 1I) — **all 29 resolved** before mainnet
- **Public report:** https://github.com/BlockApex/Audit-Reports/blob/master/Prospereum%20Protocol_Final%20Audit%20Report.pdf
- **Scope hashes:** Initial `7e96ba9`, Revised `2073cfe`, Fixed `31eb313`

---

## 8. Epoch Keeper

- **Script:** `scripts/epoch-keeper.sh`
- **Cron:** `0 5 * * *` UTC daily (Kin's cron job `3fc22360`)
- **Config:** `KEEPER_NETWORK=mainnet` (default), RE proxy hardcoded as fallback
- **Wallet:** reads `DEPLOYER_PK` from `.env` (ops wallet, ~0.05 ETH)
- **Epoch 0 closes:** April 29 03:52:57 UTC → keeper fires 5 AM UTC → auto-finalizes

---

## 9. LP Pool

- **Address (pre-computed CREATE2):** `0x0Adc6BE14E76b89584216fAd4E458df5F996D336`
- **Pair:** PSRE/USDC, 1% fee, Uniswap v3, Base mainnet
- **Genesis liquidity plan:** 200K PSRE + $20K USDC from Treasury Safe
- **Launch price:** $0.10 per PSRE (10 PSRE per USDC)
- **Status:** Pool NOT yet created. Shu waiting for USDC from Coinbase (hold until Apr 29).
- **Lock plan:** 24 months via Unicrypt after seeding

---

## 10. Current Open Items (as of 2026-04-28)

### 🔴 Immediate
- **setSplit(1e18, 0):** Founder Safe nonce 2, Jason signed (1/2). **Shu must sign before April 29 03:52 UTC.** Without this, 50% of Epoch 0 staker rewards unclaimed.
  - Batch file: `audit/setSplit-safe-batch.json` (commit `5070094`)

### 🟠 Soon
- **LP pool creation:** Treasury Safe → app.uniswap.org. After Shu's USDC clears (~Apr 29).
- **Unicrypt LP lock:** 24 months, after pool is seeded
- **Sablier vesting stream:** Shu to set up for 4.2M PSRE in Founder Safe
- **Contract verification on Basescan:** Need Etherscan API key. All 8 mainnet contracts unverified — "Unverified contract" shows in Safe UI (cosmetic, not blocking).

### 🟡 Backlog
- **setSplit re-enable for LP:** Once ERC-20 LP wrapper exists (future RE upgrade)
- **Dev spec v3.3 approval:** Superseded by v3.4 (frozen). No action needed.
- **Admin dashboard:** Update to mainnet addresses

---

## 11. Documentation (All v3.4, April 2026)

| File | Purpose |
|------|---------|
| `projects/prospereum/prospereum-dev-spec-v3.4.md` | Frozen technical spec — matches deployed contracts |
| `projects/prospereum/prospereum-whitepaper-v3.4.md` | Internal whitepaper — all formulas, full IP |
| `projects/prospereum/prospereum-whitepaper-public-v3.4.md` | Public whitepaper — partners, holders, regulators |
| `projects/prospereum/prospereum-partner-guide-v3.4.md` | Partner operational guide |
| `projects/prospereum/prospereum-internal-rationale-v3.4-FINAL.docx` | Anti-spam/anti-inflation audit |
| `projects/prospereum/deployments.md` | All deployed addresses + tx hashes |
| `projects/prospereum/decisions.md` | Protocol decisions log |
| `audit/blockapex-final-report-2026-04-17.pdf` | Full audit report |
| `audit/blockapex-findings-response.csv` | All 25 findings mapped to commits |

---

## 12. Protocol Parameters (Deployed Defaults)

```
EPOCH_DURATION     = 7 days
S_EMISSION         = 12,600,000e18
S_MIN              = 500e6 (USDC)
alphaBase          = 0.10e18 (10%)
E0                 = S_EMISSION / 1000 = 12,600 PSRE/week
E0_MAX             = S_EMISSION * 2 / 1000 = 25,200 PSRE/week
PARTNER_SPLIT      = 0.70e18 (70%)
STAKER_SPLIT       = 0.30e18 (30%)
psreSplit          = 0.50e18 (50%) — pending setSplit to 1e18
lpSplit            = 0.50e18 (50%) — pending setSplit to 0
REWARD_PRECISION   = 1e36
AUTO_FINALIZE_MAX_EPOCHS = 10
MAX_MINT_PER_EPOCH = 25,200e18
Tier thresholds: Silver ≥ 0.5%, Gold ≥ 2.0%
Tier multipliers: Bronze 0.8×, Silver 1.0×, Gold 1.2×
```

---

## 13. Testnet (Base Sepolia) — Pre-Audit Contracts

These are STALE — pre-fix bytecode from March 28, 2026. Do not use for anything except historical reference.

| Contract | Address |
|----------|---------|
| RewardEngine (testnet) | `0xe668fE9DbCE8CBbc8b3590100e8c31aA12F5C697` |
| PSRE (testnet) | old address, not recorded |

**Epoch 3 (testnet) closed April 25 — keeper fired, finalized.**

---

## 14. Rules I Never Break

1. **Never deploy to mainnet without explicit Jason "go."**
2. **Never change the frozen dev spec without Shu + Jason approval.**
3. **Never sign or send transactions involving real funds autonomously.**
4. **Never commit `.env` files or private keys.**
5. **When in doubt: stop, ask Jason or Shiro.**
6. **`trash` > `rm`** — recoverable beats gone.
7. **Update `deployments.md` immediately after every deploy.**

---

*Source of truth: GitHub repo `wealthhealthai/prospereum-protocol`, branch `master`*
*Decisions log: `projects/prospereum/decisions.md`*
*Deployments: `projects/prospereum/deployments.md`*
