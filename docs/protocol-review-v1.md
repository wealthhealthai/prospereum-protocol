# Prospereum Protocol — Comprehensive Review
**Reviewer:** Kin (Protocol Engineer)
**Date:** 2026-03-06
**Documents Reviewed:** Whitepaper v2.3, Dev Spec v2.10
**Scope:** Security risks, design issues, internal inconsistencies, recommendations

---

## Executive Summary

The Prospereum protocol is well-conceived. The core mechanic — demand-bounded, scarcity-controlled emission with no oracle dependency — is architecturally sound and genuinely novel. The anti-exploitation constraints (monotonic creditedNB, no vault sell, time-weighted staking) are correct and clearly specified.

However, the review identified **2 critical inconsistencies**, **6 meaningful security vulnerabilities**, and **8 design concerns** that should be resolved before or during v1 implementation. None are fatal — all are correctable.

---

## 🔴 CRITICAL — Must Resolve Before Building

### C1: Reward Rate Discrepancy Between Whitepaper and Dev Spec

This is the most important inconsistency found. The two documents specify different reward rates.

**Whitepaper §6.2 (explicit flat rates):**
| Tier | Rate |
|------|------|
| Bronze | 8% |
| Silver | 10% |
| Gold | 12% |

**Dev Spec §1.3–1.4 (alphaBase × multiplier):**
| Tier | alphaBase × multiplier | Effective rate |
|------|------------------------|----------------|
| Bronze | 0.10 × 1.00 | **10%** |
| Silver | 0.10 × 1.25 | **12.5%** |
| Gold | 0.10 × 1.60 | **16%** |

**The gap:** Bronze differs by 2pp, Silver by 2.5pp, Gold by 4pp. These produce materially different economics. Gold partners in particular would receive 33% more rewards under the dev spec vs the whitepaper.

**Also:** The whitepaper uses a different algorithm (direct rate × deltaNB, with proportional scaling λ if D > B_partners), while the dev spec uses weighted distribution (w_p = alpha_p × deltaNB_p / W × B_partners). These are mathematically equivalent in outcome **only when every partner gets their full rate**. When budget is constrained (B_partners < D), both reduce pro-rata — but the whitepaper's λ-scaling approach and the dev spec's W-weighting approach will produce the same final result. ✅ The algorithms reconcile. Only the rates differ.

**Resolution required:** Decide which rates are canonical — whitepaper (8/10/12%) or dev spec (10/12.5/16%) — and update the other document.

**My recommendation:** Whitepaper rates (8/10/12%) are cleaner and more conservative. To achieve them via the dev spec mechanism, set `alphaBase = 0.08e18` with multipliers `1.0 / 1.25 / 1.5`, giving 8% / 10% / 12% exactly. This also requires updating the governance bounds proportionally.

---

### C2: Team Vesting Contract Not Specified

The whitepaper states 4,200,000 PSRE is minted at genesis to **"a vesting contract of founders."** This contract is not in the dev spec's contract list and is not described anywhere.

This is a genesis-critical component. At deployment, 4.2M PSRE (20% of total supply) must be minted to this contract. If it doesn't exist or is deployed incorrectly, team tokens are either inaccessible or unprotected.

**Required:** Specify and build the `TeamVesting.sol` contract before genesis deployment. Standard parameters per whitepaper: 1-year cliff, 4-year linear vest, no governance override.

---

## 🟠 SECURITY — Attack Vectors and Mitigations

### S1: buy() Sandwich Attack (MEV)

**Vector:** Partners call `buy()` to swap USDC→PSRE via Uniswap v3. On Base, MEV bots monitor the mempool. A bot can front-run a large partner buy: buy PSRE before the partner, then sell immediately after, extracting value from the partner.

**Impact:** Partners receive fewer PSRE tokens per buy than expected → their cumBuy is lower → they earn fewer rewards. Protocol integrity is unaffected, but partners lose value.

**Mitigation:** `buy()` must accept a `minAmountOut` (slippage tolerance) parameter and pass it to the Uniswap v3 router. Without it, any large buy is sandwichable.

```solidity
// Required in buy():
ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
    ...
    amountOutMinimum: minAmountOut, // caller-specified, NOT zero
    ...
});
require(minAmountOut > 0, "slippage protection required");
```

**Severity:** MEDIUM (economic loss for partners, not protocol funds)

---

### S2: finalizeEpoch() Griefing / Epoch Liveness

**Vector:** `finalizeEpoch()` is callable by anyone, one epoch at a time, sequentially. If no one calls it for multiple consecutive epochs, rewards accumulate but cannot be claimed — partners and stakers cannot access rewards for epoch N until epoch N is finalized.

**Scenario:** The protocol launches with no keeper infrastructure. A malicious actor or simply operational neglect causes epochs to go unfinalized. Partners accumulate deltaNB but earn no rewards.

**Deeper issue:** If epoch 4 is never finalized, epoch 5 can never be finalized. A single skipped epoch blocks all future rewards permanently until recovered.

**Mitigation:** 
1. Deploy a keeper bot (Chainlink Automation or custom) to call `finalizeEpoch()` at epoch end
2. Consider allowing finalization of multiple epochs in one call (with gas limit) if lagging
3. Document the liveness assumption explicitly — the protocol is NOT self-running without infrastructure

**Severity:** HIGH (operational; could block rewards indefinitely)

---

### S3: Epoch Boundary Buy Manipulation (Epoch Sandwiching)

**Vector:** A partner monitors the blockchain for the epoch end timestamp. In the final block before epoch end, they execute a large `buy()`. Their cumBuy spikes. `finalizeEpoch()` is called immediately after, capturing the large deltaNB. They then stop buying next epoch.

**Current mitigation:** EMA with theta=1/13 smooths out single-epoch spikes. A one-epoch spike contributes only 1/13 (~7.7%) weight to the rolling score, so tier assignment is resistant. ✅

**Remaining risk:** The single-epoch spike **still** earns rewards proportional to w_p = alpha_p × deltaNB. Even at Bronze tier (lowest alpha), a massive single-epoch buy earns large rewards that epoch. The EMA only affects tier (and thus alpha), not the raw deltaNB contribution.

**Mitigation options:**
- Time-lock: require PSRE purchased via vault to be held for minimum duration before it counts toward deltaNB (adds complexity)
- Cap maximum single-epoch deltaNB per partner at some multiple of their EMA (prevents extreme spikes)
- Accept as-is: the partner is providing real capital to the protocol (buying PSRE), so even spike buys represent genuine demand. This may be acceptable by design.

**My recommendation:** Accept for v1 with documentation. Partners providing large capital — even opportunistically — still benefits the protocol. The EMA correctly prevents them from gaming their tier over time.

**Severity:** LOW-MEDIUM (economic edge case, not a funds-at-risk issue)

---

### S4: RewardEngine Single Point of Failure

**Vector:** RewardEngine is the sole authorized minter of PSRE. If RewardEngine is compromised (via an upgrade bug in a UUPS proxy, or a multisig key compromise), an attacker can mint up to the full emission reserve (12.6M PSRE) to themselves.

**Current state:** UUPS + multisig + timelock proposed for early-phase RewardEngine.

**Critical dependency:** The security of the entire emission schedule is equal to the security of the multisig. If 3-of-5 signers are compromised, all future emissions can be stolen.

**Mitigations:**
1. Timelock on all RewardEngine upgrades (minimum 48 hours, ideally 72 hours for mainnet)
2. Gnosis Safe 3-of-5 minimum for the multisig controlling upgrades
3. PSRE token's mint authority should be transferred to the **final immutable** RewardEngine address before any significant liquidity exists — minimize the window where an upgradeable RewardEngine controls minting
4. Consider a hard epoch rate limiter in PSRE itself: `mint()` reverts if called more than `MAX_MINT_PER_EPOCH` times or with amount exceeding `E0_MAX` in any 7-day window

**Severity:** HIGH (catastrophic if exploited)

---

### S5: LP Token Staking Valuation Mismatch

**Vector:** The StakingVault treats 1 LP token as equivalent to 1 PSRE for staking weight. But 1 Uniswap v3 LP token is worth significantly more than 1 PSRE (it contains both PSRE and USDC). This creates an arbitrage: provide liquidity to get LP tokens, then stake them to earn staking rewards at an inflated weight.

**Specific scenario:** PSRE price = $1.00. Partner buys 1,000 PSRE and stakes it: `stakeTime = 1,000 × duration`. Another actor buys 500 PSRE, pairs with $500 USDC, gets ~1,000 LP tokens (depending on pool pricing), stakes 1,000 LP tokens: same `stakeTime = 1,000 × duration`. But the LP staker deployed $1,000 of capital vs the PSRE staker's $1,000 of PSRE — roughly fair. However, as PSRE price rises, LP tokens become worth more than 1:1 PSRE, making LP staking increasingly advantageous.

**Dev spec note:** "No weighting multiplier is applied" — this is an intentional design choice to incentivize LP provision without oracle dependency. This is acceptable. The tradeoff is documented.

**Risk:** If PSRE price rises sharply, LP stakers dominate the staking pool and crowd out pure PSRE stakers. This could reduce incentive to hold PSRE without providing liquidity.

**Severity:** LOW (known tradeoff, not a security exploit, but worth monitoring in v2)

---

### S6: PartnerRegistry Squatting and Sybil Registration

**Vector:** With a permissionless PartnerRegistry (replacement for PartnerNFT), anyone can register a `partnerId` and create a vault. An attacker could pre-register 1,000 `partnerIds` cheaply, creating dummy vaults.

**Impact:** In finalization, the loop over all registered partners could become expensive if registration is unbounded. A griefing actor could also squat desirable partner names/IDs.

**Mitigations:**
1. Require a small registration fee (e.g., 0.01 ETH on Base) to deter spam registration
2. Or: allow DAO/admin to whitelist partners in early phase, transition to permissionless later
3. Hard cap on registered partner count (e.g., max 500 in v1) with DAO ability to raise it
4. Keep finalization loop gas-bounded: `require(registeredPartners.length <= MAX_PARTNERS)`

**Severity:** MEDIUM (gas griefing; also matters for protocol reputation)

---

## 🟡 DESIGN CONCERNS

### D1: Demand Cap Formula Inconsistency

**Whitepaper §5.2.2:** `E_demand = r_base × NB_total` (uniform base rate on total net buy)

**Dev Spec §5.3:** `E_demand = Σ alpha_p × deltaNB_p` (per-partner alpha, sum of weighted buys)

These give the same result **only** when all partners have the same alpha (i.e., all Bronze). When tiers differ, the dev spec's demand cap is **higher** than the whitepaper's because Gold partners have alpha=0.16 (under dev spec rates), lifting the demand cap above 10% of total buys.

**Example:**
- 1 Gold partner, deltaNB = 1,000 PSRE
- Whitepaper: E_demand = 10% × 1,000 = 100 PSRE
- Dev Spec: E_demand = 16% × 1,000 = 160 PSRE

The whitepaper's uniform rate gives a tighter demand cap. The dev spec's per-partner alpha gives higher emitting capacity for high-tier partners.

**Resolution:** Decide which is intended. The dev spec formula is richer but the whitepaper formula is simpler and more predictable. If whitepaper rates (8/10/12%) are adopted and matched in the dev spec, this discrepancy resolves cleanly.

---

### D2: Epoch Missed / Skipped Recovery

What happens if multiple epochs are skipped? The spec says `epochId == lastFinalizedEpoch + 1` (strictly sequential). If epoch N is missed, the only recovery is to call `finalizeEpoch(N)` before N+1 can be finalized. This is correct, but there is no documented procedure for catching up on missed epochs, nor a maximum finalization lag.

**Recommendation:** Add `catchUpEpochs(uint256 maxEpochs)` to allow finalizing multiple epochs in one transaction (gas-capped), with documentation on the expected keeper SLA.

---

### D3: No Minimum Staking Duration Specified

The whitepaper states "Users may lock PSRE tokens in the staking contract for a minimum duration" but no minimum duration is defined in either document. Without a minimum, a user could stake 1 block before epoch end, earn time-weighted rewards (small but non-zero), and withdraw immediately.

The time-weighted mechanism mostly prevents this (1 block of stake time vs 7 days = negligible reward). But it should be explicit: **is there a minimum lock period?** If yes, specify it. If no, document that time-weighting is sufficient.

---

### D4: Genesis Price and Initial Liquidity Strategy Not Specified

The whitepaper says "liquidity seeded solely from treasury allocation" but doesn't specify:
- What price to seed the PSRE/USDC Uniswap v3 pool at
- What tick range to use (Uniswap v3 concentrated liquidity requires this)
- What proportion of the 1,050,000 Bootstrap Liquidity tokens to deploy vs hold in reserve

**Risk:** If the initial pool is seeded at the wrong price or with too little depth, the first partner buy will move the price dramatically, creating large slippage and potentially front-running at pool creation.

**Recommendation:** Define the launch price (e.g., $0.10/PSRE), tick range, and initial liquidity depth in the deployment plan before genesis.

---

### D5: Treasury Sub-Allocation Siloing

The whitepaper defines three treasury categories:
- Ecosystem Growth: 1,680,000 PSRE (8%)
- DAO Treasury: 1,470,000 PSRE (7%)
- Bootstrap Liquidity: 1,050,000 PSRE (5%)

All three are "minted at genesis to Treasury Wallet (SAFE)." However, there is no on-chain enforcement that Bootstrap Liquidity tokens are used only for liquidity, or that Ecosystem Growth is used only for ecosystem purposes.

**Risk:** Treasury multisig can freely move tokens between purposes without protocol-level accountability.

**Recommendation for v1:** Keep all in a single multisig for simplicity. For v2: consider sub-wallets or on-chain modules to enforce allocation intent. Disclose to partners/investors that allocation boundaries are social/governance-enforced, not technical, in v1.

---

### D6: No Claim Expiry

There is no expiry on `claimPartner()` or `claimStake()`. Partners and stakers can wait indefinitely to claim past epoch rewards. While not an exploit, this creates:
- Unbounded accounting state (owedPartner/owedStaker mappings grow forever)
- Stale claims from inactive wallets decades in the future
- No mechanism to reclaim unclaimed rewards to treasury

**Recommendation:** Optional but clean — add a `CLAIM_WINDOW` (e.g., 2 years). After expiry, unclaimed rewards return to treasury. Emit a `ClaimExpired` event.

---

### D7: sumR Precision Drift Over Time

The EMA formula computes:
```
R_new = (R_old * (1e18 - theta) + deltaNB * theta) / 1e18
```
Each division by 1e18 truncates. Over hundreds of epochs, this truncation accumulates. Additionally, `sumR` is updated incrementally:
```
sumR = sumR - R_old + R_new
```
If truncation consistently rounds down `R_new`, `sumR` will drift slightly below the true sum. Share calculations `s = R_new * 1e18 / sumR` could become slightly inflated.

**Impact:** Very small (sub-wei level per epoch), but may cause tier assignments to drift over 1,000+ epochs.

**Recommendation:** Add a periodic reconciliation function (`recalculateSumR()`) that recomputes `sumR` from scratch over all partners. Can be called by anyone or by governance. Low priority for v1.

---

### D8: No Pause Mechanism on PSRE Token or RewardEngine

Neither document specifies an emergency pause capability. If a critical bug is found in RewardEngine post-mainnet, there is no circuit breaker to stop minting while a fix is prepared.

**Recommendation:** Add `Pausable` to RewardEngine. Pause should only halt `finalizeEpoch()` (to stop new minting), not `claimPartner()`/`claimStake()` (users must still be able to claim already-earned rewards). Pause authority: multisig with no timelock (emergencies require fast response).

---

## 🟢 RECOMMENDATIONS SUMMARY

| Priority | Item | Action |
|----------|------|--------|
| 🔴 CRITICAL | C1: Reward rate discrepancy | Reconcile WP and spec rates. Recommend: 8/10/12% with alphaBase=0.08, multipliers 1.0/1.25/1.5 |
| 🔴 CRITICAL | C2: TeamVesting contract missing | Specify and build `TeamVesting.sol` before genesis |
| 🟠 HIGH | S2: Epoch liveness | Deploy keeper on Day 1; add multi-epoch catchup function |
| 🟠 HIGH | S4: RewardEngine single-point-of-failure | Timelock on upgrades; migrate to immutable as soon as possible |
| 🟠 MEDIUM | S1: buy() sandwich | Add `minAmountOut` parameter to `buy()` |
| 🟠 MEDIUM | S6: Partner registry griefing | Registration fee or whitelist; partner count cap |
| 🟡 LOW-MED | S3: Epoch boundary buy spike | Document as acceptable for v1; add EMA cap in v2 |
| 🟡 DESIGN | D1: Demand cap formula | Reconcile with rate decision (C1 resolution fixes this) |
| 🟡 DESIGN | D2: Epoch catchup | Add `catchUpEpochs()` function |
| 🟡 DESIGN | D3: Minimum stake duration | Define explicitly or document time-weighting sufficiency |
| 🟡 DESIGN | D4: Genesis liquidity strategy | Define launch price, tick range, and LP depth before deployment |
| 🟡 DESIGN | D5: Treasury siloing | Document as governance-enforced only in v1 |
| 🟡 DESIGN | D6: Claim expiry | Optional: add 2-year claim window with reclamation |
| 🟡 DESIGN | D7: sumR precision drift | Add periodic reconciliation function |
| 🟡 DESIGN | D8: No pause mechanism | Add `Pausable` to RewardEngine (halt minting only, not claims) |

---

## Appendix A: Math Verification

### Scarcity curve at key milestones (k=2, E0=0.001×12.6M=12,600 PSRE/week)

| T emitted | x = T/12.6M | (1-x)² | E_scarcity (PSRE/week) |
|-----------|-------------|--------|------------------------|
| 0 | 0.000 | 1.000 | 12,600 |
| 1,260,000 | 0.100 | 0.810 | 10,206 |
| 3,150,000 | 0.250 | 0.563 | 7,088 |
| 6,300,000 | 0.500 | 0.250 | 3,150 |
| 9,450,000 | 0.750 | 0.063 | 788 |
| 11,340,000 | 0.900 | 0.010 | 126 |
| 12,474,000 | 0.990 | 0.0001 | 1.3 |

**Observation:** The curve is very steep in the final 10%. After 90% depletion, weekly emissions drop to ~126 PSRE. The tail extends indefinitely but practically approaches zero.

**Total theoretical years to exhaust at max E0:** ~19 years at E0 constant, but scarcity tightens as reserve depletes — the reserve is asymptotically permanent, never technically hitting zero.

### EMA convergence (theta = 1/13)

Weight of epoch N-k on current score: `(1 - 1/13)^k = (12/13)^k`

| Epochs ago | Weight of that epoch |
|------------|---------------------|
| 0 (current) | 7.69% |
| 1 | 7.10% |
| 4 | 5.58% |
| 13 | 3.54% |
| 26 | 1.57% |
| 52 | 0.37% |

**Observation:** A single epoch spike has max 7.69% influence on the rolling score. After 26 epochs (~6 months), an epoch's contribution falls below 2%. The EMA is appropriately resistant to manipulation.

---

## Appendix B: Questions for Shu / Jason

1. **C1 Resolution:** Which reward rates are authoritative — whitepaper (8/10/12%) or dev spec (10/12.5/16%)?
2. **C2:** What is the team vesting contract design? Should I build standard `TokenVesting.sol` (cliff + linear) or is a specific implementation required?
3. **D3:** Is there a minimum staking duration, or is time-weighting the sole anti-flash-stake mechanism?
4. **D4:** What is the intended launch price of PSRE/USDC? This determines the initial pool seeding.
5. **S6:** Should PartnerRegistry be permissioned (whitelist by multisig) in v1, transitioning to permissionless in v2? Or permissionless from Day 1 with a registration fee?

---

*Report generated by Kin. Questions and corrections welcome from Jason and Shu.*
