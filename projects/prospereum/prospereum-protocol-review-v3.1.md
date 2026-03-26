# Prospereum Protocol Review — v3.1

**Reviewer:** Independent Protocol Reviewer (sub-agent, not affiliated with design team)  
**Date:** 2026-03-24  
**Documents Reviewed:**
- Prospereum Whitepaper v3.1-DRAFT
- Prospereum Developer Specification v3.1-DRAFT
- Prospereum Whitepaper v3.0-DRAFT (context/comparison)
- Prospereum Developer Specification v3.0-DRAFT (context/comparison)

**STATUS: APPROVED WITH CHANGES**

---

## Executive Summary

Prospereum v3.1 represents a significant improvement over v3.0. The replacement of time-weighted retention (TWR) with the cumulative high-water-mark (cumS) simplifies the protocol, reduces gas costs, eliminates timing-based gaming vectors, and provides a cleaner incentive structure. The elimination of the vault bond, vesting schedule, and minimum epoch activity threshold — replacing all three with the un-rewarded initial buy and first qualification condition — is an elegant consolidation of anti-gaming mechanisms into a single structural defense.

The design is fundamentally sound. The cumS ratchet genuinely prevents sustained wash trading — each cycle requires monotonically increasing capital commitment, making the strategy self-defeating over time. The scarcity curve ensures hard-capped, non-inflationary emission. The registered vault ecosystem boundary prevents distribution gaming.

However, the review identifies three issues that require attention before implementation:

1. **A whitepaper-to-dev-spec inconsistency in tier multipliers** that could cause implementation to deviate from design intent
2. **First-cycle wash trading remains modestly profitable** (≈$430 profit on ≈$5,500 capital at r_base = 10%), though it is self-limiting
3. **Reward destination ambiguity** — the whitepaper implies rewards enter the vault ecosystem, but the dev spec sends them to the partner owner's wallet; these have materially different compounding implications

None of these are fatal. All are addressable before implementation. The protocol's core architecture — cumS ratchet, scarcity cap, first qualification gate — is well-designed and ready for implementation after the identified issues are resolved.

---

## Part I: Detailed Design Component Analysis

### 1. Supply Model and Allocation

**Assessment: SOUND — No issues found.**

The 21M hard cap with 60% emission reserve mirrors Bitcoin's deflationary ethos while allocating material portions to team vesting (20%), ecosystem growth (8%), DAO treasury (7%), and bootstrap liquidity (5%). The 1-year cliff with 4-year linear vesting for team tokens is standard practice. The Sablier streaming contract approach is well-tested in the ecosystem.

The genesis mint of 40% (team + ecosystem + treasury + bootstrap) is on the higher end for a behavioral mining protocol but is defensible given that team tokens are locked for up to 5 years and treasury tokens serve specific functional purposes (liquidity, audits, infrastructure).

**No changes recommended.**

### 2. Partner Ecosystem Architecture (PartnerVault + CustomerVault)

**Assessment: WELL-DESIGNED — Minor implementation concerns flagged.**

The two-tier vault architecture (PartnerVault as the accounting boundary, CustomerVaults as lightweight escrow) is practical and gas-efficient. Key strengths:

- **EIP-1167 minimal proxy pattern** for CustomerVaults keeps deployment costs at ≈$3-5 per vault, making it viable for partners with thousands of customers
- **Running `ecosystemBalance` counter** avoids iterating all CustomerVaults at finalize time — O(1) instead of O(n)
- **Customers never touch the blockchain** — the partner's backend manages all interactions
- **CustomerVault claim mechanism** allows customers to assert ownership without requiring prior wallet setup

**Concern 1: Callback discipline for `ecosystemBalance` tracking.**

The `ecosystemBalance` counter requires that ALL balance-changing events in CustomerVaults trigger callbacks to the parent PartnerVault (`reportLeakage()`). If PSRE is sent directly to a CustomerVault via a standard ERC-20 `transfer()` (not via `receiveReward()`), the counter becomes inconsistent because the CV received PSRE that the parent doesn't know about.

**Recommendation:** The CustomerVault should restrict PSRE inflow to only the `receiveReward()` function. If the CustomerVault is an ERC-20 recipient, it should either:
- Override `onERC20Received` (if using ERC-20 with receive hooks) to reject non-parent deposits, or
- Document clearly that direct ERC-20 transfers to CustomerVault addresses are "lost" (not counted toward ecosystem balance), and accept this as a known limitation

**Concern 2: PartnerVault direct PSRE deposits.**

Similarly, if PSRE is sent directly to the PartnerVault address (not via `buy()`), the PSRE balance of the vault increases but `ecosystemBalance` is not updated. The vault should have either:
- A `sweep()` function that accounts for direct deposits and updates `ecosystemBalance`
- Clear documentation that direct transfers are excluded from accounting

**Concern 3: `reportLeakage()` reentrancy.**

The `withdraw() → reportLeakage()` call chain crosses contract boundaries. While both contracts should use `ReentrancyGuard`, the cross-contract call pattern should be carefully reviewed during audit. The CustomerVault's `withdraw()` first transfers PSRE (external call), then calls `reportLeakage()` on the parent. Consider checks-effects-interactions: update state before the PSRE transfer to prevent reentrancy.

### 3. Behavioral Mining — cumS High-Water-Mark (Core Mechanism)

**Assessment: STRONG — Significant improvement over v3.0 TWR model.**

The cumS ratchet is the protocol's crown jewel. It provides:

- **Structural wash trade prevention:** Selling PSRE doesn't reduce cumS. Rebuying requires exceeding the prior peak. Each cycle demands more capital. Self-limiting by construction.
- **Simplicity:** `cumS = max(ecosystemBalance, cumS)` — one comparison, one storage slot update. Compare to TWR's per-checkpoint accumulation across the entire epoch.
- **Gas efficiency:** No within-epoch checkpointing needed. `_updateCumS()` is called on balance-changing events and at epoch finalize via `snapshotEpoch()`. Both are O(1).
- **Timing resistance:** Unlike TWR, where front-running checkpoint timing could manipulate the time-weighted score, cumS only cares about the peak balance — when it occurred within the epoch is irrelevant.

**Comparison to v3.0 TWR:**

| Property | v3.0 TWR | v3.1 cumS |
|---|---|---|
| Gaming resistance | Moderate (timing-dependent) | Strong (structural) |
| Gas cost | Higher (per-checkpoint accumulation) | Lower (max comparison) |
| Complexity | TWR accumulators, checkpoint timestamps | Single uint256 ratchet |
| Wash trading | Sell resets NR → future TWR drops | Sell doesn't reset cumS; rebuy required |
| Vesting needed | Yes (4-epoch vesting to prevent hit-and-run) | No (first qualification + ratchet) |
| Epoch 0 behavior | Positive E_demand (any TWR > 0) | Zero E_demand (all unqualified) |

The transition from TWR to cumS is unambiguously positive.

### 4. First Qualification Condition

**Assessment: ELEGANT — Replaces vesting schedule with a structurally stronger mechanism.**

The v3.0 4-epoch vesting schedule only delayed reward extraction; it didn't change the profitability math. A patient attacker still profits — they just wait longer. The first qualification condition is fundamentally different: it requires demonstrated ecosystem growth, not just elapsed time. No amount of patience earns the first reward without genuine cumS growth above the initial buy.

The implementation is clean: `initialCumS[vault] = S_p(N)` at creation, vault marked qualified when `cumS > initialCumS`. The `lastEpochCumS` is set to `initialCumS` at creation so that the first qualifying delta correctly reflects growth above baseline.

**Edge case verified:** The spec correctly handles the "partial growth across epochs" scenario — any growth above initialCumS immediately qualifies the vault, because `initialCumS == cumS_p(N)`.

**No changes recommended.**

### 5. Un-Rewarded Initial Buy (Registration Deterrent)

**Assessment: ADEQUATE — Replaces vault bond, but the effective deterrent is weaker than described.**

The whitepaper describes the initial buy as "strictly more punitive than a refundable bond." This requires qualification.

A $500 USDC refundable bond has a net cost of zero (you get it back). The un-rewarded initial buy has a net cost of:
- DEX buy slippage/fees: ≈$2.50 (0.5% on $500)
- The PSRE purchased IS still owned by the partner and can be sold later
- If the partner sells immediately after the first reward cycle: additional DEX sell slippage/fees ≈$2.50
- Net irrecoverable cost: ≈$5

So the effective deterrent of the initial buy against a sophisticated attacker is approximately **$5** (trading costs on $500), not $500. The $500 is locked in the ecosystem (which benefits the protocol) but is not lost to the attacker — it remains as PSRE in their vault.

The statement that the initial buy is "strictly more punitive than a refundable bond" is technically correct (a refundable bond costs $0 net; the initial buy costs ≈$5 net), but the margin is thin. The real deterrent comes from the **ratchet property** — the initial buy establishes the cumS baseline that the attacker must exceed to earn any reward.

**Recommendation:** Acknowledge this nuance in the whitepaper. The initial buy's primary value is not as a cost barrier but as a **ratchet baseline** — it forces the attacker to commit additional capital above the initial amount before any reward is earned. The true entry cost for a profitable first cycle is approximately $5,500 (initial buy + enough additional capital to make the 10% reward worthwhile), not $500.

### 6. Scarcity Function

**Assessment: SOUND — Appropriate curve shape.**

$E_{scarcity}(t) = E_0 \cdot (1 - x(t))^2$ with $E_0 = 12{,}600$ PSRE/week.

Curve behavior:
| Emission Reserve Consumed (x) | Weekly Cap (PSRE) | % of E0 |
|---|---|---|
| 0% | 12,600 | 100% |
| 10% | 10,206 | 81% |
| 25% | 7,088 | 56.3% |
| 50% | 3,150 | 25% |
| 75% | 788 | 6.3% |
| 90% | 126 | 1% |
| 99% | 1.26 | 0.01% |

The k=2 quadratic produces a smooth, accelerating decline. This is appropriate: early participants receive meaningfully higher rewards (growth incentive), while late-stage emission is negligible (scarcity dominance). The immutability of k prevents governance from flattening the curve.

**Projection:** At the maximum weekly emission rate (12,600 PSRE/week), it would take approximately 1,000 weeks (19 years) to deplete the emission reserve — but the declining curve means actual depletion would take far longer. This provides a multi-decade runway for the protocol.

**No changes recommended.**

### 7. Tier System (Rolling EMA)

**Assessment: FUNCTIONAL — Minor inconsistency flagged.**

The 13-epoch EMA (≈1 calendar quarter) provides reasonable smoothing. The tier thresholds (0.5% for Silver, 2.0% for Gold) create meaningful differentiation. The multiplier system rewards consistent, large contributors.

**ISSUE: Whitepaper-to-dev-spec inconsistency in tier rates.**

The whitepaper (Section 7.3) states:

| Tier | Base Rate Multiplier | Effective Rate (at r_base = 10%) |
|---|---|---|
| Bronze | 1.0× | 8% |
| Silver | 1.25× | 10% |
| Gold | 1.5× | 12% |

This table is internally inconsistent. If the multiplier is 1.0× and r_base is 10%, the effective rate should be 10%, not 8%. The three columns cannot all be correct simultaneously.

The dev spec (Section 1.4) defines:
```
M_BRONZE = 1.0e18
M_SILVER = 1.25e18
M_GOLD   = 1.5e18
```

With `alpha_p = (alphaBase * m) / 1e18` and `alphaBase = 0.10e18`, this yields:
- Bronze: 10% effective
- Silver: 12.5% effective
- Gold: 15% effective

**Two possible interpretations of design intent:**

**(a)** The intended effective rates are 8%, 10%, 12% (whitepaper rates), which requires multipliers of **0.8×, 1.0×, 1.2×**. This means Bronze receives a *penalty* relative to r_base, Silver receives r_base, and Gold receives a bonus. The dev spec multipliers are wrong.

**(b)** The intended multipliers are 1.0×, 1.25×, 1.5× (dev spec values), which gives effective rates of **10%, 12.5%, 15%**. The whitepaper effective rates are wrong.

**Recommendation:** Resolve this ambiguity before implementation. If the team wants 8/10/12% effective rates, change the multipliers to 0.8/1.0/1.2 in the dev spec. If the team wants 1.0/1.25/1.5× multipliers, correct the whitepaper table to show 10%/12.5%/15%.

My preference is **(a)** (8/10/12% with 0.8/1.0/1.2 multipliers), because it means Bronze partners are mildly penalized, creating a stronger incentive to grow toward Silver/Gold. This also keeps the maximum effective rate at 12%, which is more conservative and reduces wash trade profitability at higher tiers.

### 8. Reward Distribution (No Vesting)

**Assessment: SOUND — Clean simplification from v3.0.**

The elimination of the 4-epoch vesting ledger removes significant storage and gas complexity. The `owedPartner[vault]` balance is immediately claimable via `claimPartnerReward(vault)`. This is made safe by the first qualification condition and cumS ratchet — the vesting schedule was redundant given these structural defenses.

**ISSUE: Reward destination ambiguity.**

The dev spec (Section 4.1, `claimPartnerReward`) clearly states rewards are transferred to "vault owner." The reward PSRE goes to the partner's external wallet, NOT into the vault ecosystem.

However, the whitepaper (Section 11.3) states: "Reward PSRE minted by the RewardEngine is deposited into the PartnerVault and distributed to registered CustomerVaults. It does not enter the open market."

These are contradictory. The implications are significant:

- **If rewards go to vault owner (dev spec):** Reward PSRE exits the ecosystem boundary. It does NOT increase S_eco or cumS. The partner must manually re-invest rewards into the vault to compound. No automatic compounding.
- **If rewards go to the vault (whitepaper):** Reward PSRE enters the ecosystem. S_eco increases. cumS may increase. Automatic compounding occurs — rewards generate more rewards. The non-inflationary argument (Section 11.2) depends on this assumption.

**Recommendation:** The dev spec approach (rewards to owner) is cleaner and more transparent. The partner decides whether to reinvest or sell. Update the whitepaper to match the dev spec. Revise Section 11.2-11.3 to remove the assumption that reward PSRE enters the vault ecosystem — instead, note that the partner may choose to reinvest rewards, which would increase S_eco and cumS, but this is a deliberate action, not an automatic protocol feature.

### 9. Staking and LP Rewards

**Assessment: UNCHANGED FROM v3.0 — Adequate.**

Time-weighted staking (PSRE and LP) at 30% of the emission budget. No weighting multiplier between PSRE and LP staking. Flash-stake prevention via time-weight accounting.

**Minor concern:** Equal weighting of PSRE staking and LP staking may undervalue LP provision in early stages when liquidity is scarce. Consider whether a temporary LP multiplier (e.g., 1.5× for the first year) would better bootstrap liquidity. This is a governance decision, not a structural issue.

### 10. Governance Controls

**Assessment: WELL-BOUNDED.**

The bounded parameter ranges are appropriate:
- r_base: [5%, 15%] — prevents destructive manipulation
- E0: [0.05%, 0.20% of S_emission per week] — reasonable range
- Partner split: [60%, 80%] — maintains meaningful staker incentive
- k, S_total, S_emission: immutable — core monetary policy preserved

**Recommendation:** Add a 72-hour timelock (not just 48 hours as suggested in the spec) for governance parameter changes. This gives the community sufficient time to evaluate and respond to proposed changes, and is consistent with industry best practices for DeFi governance timelocks.

---

## Part II: Answers to Open Questions

### Question 1: S_min Value

**Recommendation: $500 USDC for launch. DAO may increase if spam is observed.**

**Rationale:**
- The DTC ecommerce market ranges from small Shopify brands to large enterprises. $500 is accessible to serious small businesses while being meaningfully costly for spam.
- At $500, a spam attacker creating 100 vaults pays $50,000 total in initial buys with zero reward on any of them. Combined with the first qualification requirement (must grow each vault past its initial buy), the total capital for a useful spam attack is ≈$100K+ — economically irrational.
- $500 is roughly equivalent to 1-2 months of a basic loyalty program SaaS subscription, placing it in a familiar cost range for DTC brands evaluating rewards programs.
- The DAO-adjustability provides a safety valve: if spam emerges at $500, governance can increase to $1,000 or $2,000 without a protocol upgrade.
- A higher initial value (e.g., $2,000) would exclude legitimate small DTC brands and slow ecosystem growth during the critical bootstrap phase.

### Question 2: CustomerVault Gas

**Recommendation: Partner pays all CustomerVault gas costs.**

**Rationale:**
- This is already specified in the whitepaper (Section 5.3) and is the correct approach.
- Partners already manage all on-chain interactions on behalf of customers. Adding gas costs to the partner's operational burden is natural and expected.
- EIP-1167 minimal proxy clones cost ≈$3-5 each (at current L1 gas prices; significantly less on L2). For a partner with 10,000 customers, total CV deployment cost is ≈$30K-50K on L1 or ≈$500-1,000 on an L2. This is within range for a serious commerce operation.
- Customer-pays would require customers to have wallets, ETH for gas, and blockchain knowledge — contradicting the "customers never touch the blockchain" design principle.
- Protocol subsidy creates an attack vector: a malicious partner could create millions of CVs to drain the subsidy fund. It also requires a funding mechanism and governance overhead.
- **If L1 gas costs are prohibitive at scale, the protocol should consider deploying on an L2 (Arbitrum, Base, etc.)** where CV deployment costs are negligible. This is an infrastructure decision, not a protocol design issue.

### Question 3: Vault Expiry Threshold

**Recommendation: 6 epochs (42 days) instead of 4 epochs (28 days).**

**Rationale:**
- 4 epochs (28 days) is too short for legitimate seasonal businesses. A holiday-focused DTC brand might see zero ecosystem growth from January through October — 10 months of inactivity. While cumS is preserved on reactivation, frequent expiry-reactivation cycling creates unnecessary overhead and a poor partner experience.
- However, the primary purpose of vault expiry is **optimization** (skip inactive vaults in the finalize loop), not punishment. An expired vault's cumS is preserved. Reactivation is free — the partner just buys more PSRE.
- 6 epochs (42 days) provides a reasonable buffer for month-to-month fluctuations while still cleaning up truly abandoned vaults within ~6 weeks.
- Since reactivation has zero additional cost (beyond the PSRE purchase that the partner would make anyway to grow their ecosystem), the exact expiry threshold matters less than it might seem. Partners who return after expiry lose nothing — they just need to make a buy.
- **Alternative approach (if the team prefers simplicity):** Keep 4 epochs but add a "seasonal hold" flag that partners can set voluntarily, extending expiry to 13 epochs (≈1 quarter). This adds a small amount of complexity but accommodates seasonal businesses explicitly.

### Question 4: Tier Multiplier on First Reward

**Recommendation: Apply Bronze multiplier (1.0×) to the first reward. No distortion.**

**Rationale:**
- A newly qualified vault has zero EMA history, so it's Bronze by default. Applying the Bronze multiplier to the first reward is the natural, consistent behavior.
- Since the first qualification condition already serves as the behavioral gate (the vault must demonstrate real ecosystem growth), applying the tier multiplier on top doesn't create meaningful distortion — it simply applies the standard reward rate.
- Using a "flat r_base" instead of the Bronze multiplier is identical if M_BRONZE = 1.0×. If the team adopts the 0.8×/1.0×/1.2× multiplier scheme (per my recommendation in the tier analysis), then applying the Bronze multiplier (0.8×) to the first reward slightly penalizes new partners, which creates a mild incentive to build EMA history before claiming large growth deltas. This is acceptable and arguably desirable.
- No special handling is needed in the implementation.

### Question 5: Unqualified Vault EMA

**Recommendation: Current design is correct. Zero EMA credit during unqualified period is fair.**

**Rationale:**
- The "unqualified period" is the span from vault creation to first qualification — typically 1-2 epochs if the partner is actively building. During this period, the partner has only made the initial buy (which is the baseline, not a contribution) and has not yet demonstrated ecosystem growth.
- Zero EMA credit during this period is appropriate because the partner has not yet contributed to the protocol. The EMA reflects cumulative protocol participation, and an unqualified vault has contributed zero.
- Retroactive EMA credit would be problematic: it would give a vault that qualifies late (e.g., after 10 epochs of dormancy) a large EMA bump on qualification — potentially gaming the tier system by accumulating "shadow EMA" while inactive.
- Once qualified, the first growth epoch provides a clean EMA input. The 13-epoch EMA smoothing means the partner's tier position will converge to their actual contribution level within a few epochs regardless of starting position.
- **Practical impact:** Minimal. Most partners who are genuinely building will qualify in epoch N+1 (one additional buy after initial). The unqualified period is short for real partners.

### Question 6: Deregistration with Outstanding Unclaimed Rewards

**Recommendation: Allow claims for 4 epochs (28 days) post-deregistration, then forfeit unclaimed rewards to treasury.**

**Rationale:**
- Rewards in `owedPartner[vault]` have already been minted. The PSRE exists in the RewardEngine contract.
- **Indefinite claim window** (option b) creates orphan state that must be tracked forever. Storage isn't freed, and the RewardEngine holds the PSRE indefinitely. This is wasteful.
- **Immediate forfeit** (option c) is unfair to partners who deregister for legitimate reasons (e.g., business closure, migration to new vault structure) and have earned rewards through genuine growth.
- **4-epoch grace period** balances fairness with protocol cleanliness:
  - 28 days is sufficient for any legitimate partner to claim earned rewards
  - After 28 days, unclaimed PSRE is transferred to the DAO treasury (or burned for scarcity benefit)
  - The vault's `owedPartner` storage can be zeroed out, freeing state
  - Consistent with the vault expiry window (4 epochs is a recurring threshold in the protocol)

**Implementation:**
```solidity
// On deregistration:
deregistrationEpoch[vault] = currentEpoch;
emit VaultDeregistered(vault, currentEpoch, cumS[vault]);

// On claim attempt:
if (deregistered[vault] && currentEpoch > deregistrationEpoch[vault] + 4) {
    revert ClaimWindowExpired();
}

// Separate sweep function (callable by anyone after grace period):
function sweepExpiredRewards(address vault) external {
    require(deregistered[vault]);
    require(currentEpoch > deregistrationEpoch[vault] + 4);
    uint256 amount = owedPartner[vault];
    owedPartner[vault] = 0;
    PSRE.transfer(treasury, amount);
}
```

### Question 7: S_min Oracle Question

**Recommendation: Confirmed — denominate S_MIN in USDC directly. No oracle needed. Architecturally sound.**

**Rationale:**
- If the factory accepts USDC as the input token for the initial buy (USDC → DEX → PSRE), then `require(usdcAmountIn >= S_MIN)` is a simple uint comparison with no oracle dependency.
- USDC ≈ $1 by design. The stable peg eliminates the need for any price feed.
- S_MIN is stored as a USDC amount (e.g., `500 * 10**6` for 500 USDC with 6 decimals).
- The PSRE output from the DEX varies with market price, which becomes the vault's `initialCumS`. This is fine — the deterrent is denominated in dollars (USDC), while the protocol accounting is denominated in PSRE.
- This approach is fully consistent with the no-oracle principle. The protocol never needs to know the PSRE/USD price.
- **Edge case:** If a partner wants to use a non-USDC stablecoin (USDT, DAI), the factory would need either a separate S_MIN per stablecoin or a conversion mechanism. For v3.1, recommend restricting initial buy to USDC-only to maintain simplicity. Other stablecoins can be supported in future versions if needed.
- **Note:** The REGISTRATION_FEE (if kept) should also be USDC-denominated for the same reasons.

### Question 8: Epoch 0 Bootstrap

**Recommendation: Acceptable. Not a chicken-and-egg problem.**

**Rationale:**
- At epoch 0, all vaults are newly created and unqualified. `E_demand = 0` from partners. Only the staker pool receives emission.
- This is correct by design:
  - **Partners don't need emission to operate.** They buy PSRE from the market (bootstrap liquidity pool). Emission rewards come later, as a bonus for demonstrated growth.
  - **Staker emission provides the initial incentive.** Stakers who lock PSRE or provide LP in epoch 0 earn the full staker pool, incentivizing early liquidity.
  - **Partner emission follows naturally.** Partners who register in epoch 0 and grow their ecosystem in epoch 1+ qualify and start earning.
- The bootstrap sequence is clean:
  - **Epoch 0:** Setup. Partners register, make initial buys, start distributing to customers. No partner rewards. Stakers earn.
  - **Epoch 1+:** Partners who grew qualify. Partner rewards begin. Both pools active.
- **Comparison to v3.0:** The v3.0 bootstrap was different — any positive TWR_total(0) yielded positive E_demand, meaning early partners could earn immediately. The v3.1 approach is actually better because it ensures no "free" rewards in the first epoch — every reward requires demonstrated growth.
- There is no chicken-and-egg problem because the 5% bootstrap liquidity allocation (1,050,000 PSRE) provides the initial market from which partners can buy.

### Question 9: r_base Calibration

**Recommendation: Keep r_base = 10% for launch, with awareness that first-cycle wash trading is modestly profitable but self-limiting. Monitor and adjust via DAO if needed.**

**Full Analysis:**

A wash trade cycle under cumS works as follows:
1. Create vault: $500 USDC → X PSRE. cumS = X, initialCumS = X.
2. Buy additional: $Y USDC → Z PSRE. ecosystemBalance = X + Z, cumS = X + Z.
3. Epoch finalize: deltaCumS = Z (vault qualifies). Reward = 0.10 × Z PSRE.
4. Claim reward: 0.10Z PSRE to owner wallet.
5. Transfer everything out: ecosystemBalance = 0, cumS = X + Z.
6. Sell all holdings (X + Z + 0.10Z PSRE).

Economics of the first cycle (at r_base = 10%):
| Item | Amount |
|---|---|
| Total USDC invested | $500 + $Y |
| PSRE purchased | X + Z |
| PSRE reward earned | 0.10Z |
| PSRE sold (if sell all) | X + Z + 0.10Z |
| Revenue (assuming no price impact) | $500 + $Y + 0.10 × $Y |
| DEX fees (0.3% each way, Uniswap v3) | ≈0.6% × ($500 + $Y + 0.10$Y) |
| Net profit | ≈0.10$Y - 0.6% × ($500 + 1.1$Y) |

For $Y = $5,000:
- Reward value: $500
- Fees: ≈$36
- Gas: ≈$15
- **Net profit: ≈$449** on $5,500 capital (8.2% return)

For $Y = $1,000:
- Reward value: $100
- Fees: ≈$10
- Gas: ≈$15
- **Net profit: ≈$75** on $1,500 capital (5.0% return)

**Why this is acceptable despite being profitable:**

1. **Self-limiting by construction.** The second cycle requires buying more than X + Z to grow cumS — meaning ≈$5,500+ additional capital. The third cycle requires even more. Each cycle's capital requirement grows monotonically. After 3-4 cycles, the capital requirement becomes prohibitive.

2. **Opportunity cost.** A DeFi actor with $5,500 can earn similar or better returns through staking, LP farming, or lending with far less operational complexity. The wash trade requires vault creation, DEX trading, epoch timing, and claim management.

3. **Market impact.** On a thin market (which PSRE will be in early stages), selling X + Z + 0.10Z PSRE creates significant slippage. A $5,000+ sell on a newly launched token could easily move the price 5-10%, reducing actual profit substantially.

4. **One-time only.** The ratchet ensures the wash trader cannot repeat the same cycle. Each subsequent cycle requires MORE capital for the SAME percentage reward. The strategy has diminishing returns.

**Alternative r_base values considered:**

| r_base | First-cycle profit ($5K additional) | Commerce incentive | Assessment |
|---|---|---|---|
| 5% | ≈$215 | $500/week on $10K growth | Weak incentive; may not attract partners |
| 7% | ≈$315 | $700/week on $10K growth | Moderate; viable for established brands |
| 10% | ≈$449 | $1,000/week on $10K growth | Strong incentive; attractive to DTC brands |
| 15% | ≈$715 | $1,500/week on $10K growth | Very strong; higher wash trade risk |

**Conclusion:** r_base = 10% provides the best balance between commerce incentive (critical for bootstrap adoption) and wash trade deterrence (acceptable given the self-limiting ratchet). The DAO can reduce to 7% or 5% if wash trading becomes prevalent, but starting at 10% maximizes partner acquisition during the critical growth phase.

### Question 10: Long-Term Partner Sustainability

**Recommendation: The current design is correct. Supplement with documentation on alternative value capture for mature partners.**

**Analysis:**

Under the cumS formula, a partner at steady state (e.g., stable 10K customers, no growth) earns zero protocol reward because deltaCumS = 0. This is the most debated aspect of the v3.1 design.

**Arguments for the current design (rewards only for growth):**
- **Protocol thesis alignment.** Prospereum rewards the creation of new economic value in the form of growing on-chain PSRE demand. A static ecosystem is not creating new value — it's maintaining existing value. The protocol's thesis is "reward growth," not "reward existence."
- **Anti-parking incentive.** Rewarding flat holdings would incentivize capital parking — partners who buy once and never engage again, earning passive rewards forever. This is exactly the behavior the protocol wants to avoid.
- **Scarcity budget allocation.** The emission budget is finite. Allocating it to growing partners ensures emission goes to participants who are actively expanding the ecosystem, maximizing the protocol's growth trajectory.
- **TWR was abandoned for a reason.** The v3.0 TWR model DID reward sustained holdings — and this was specifically identified as a gaming vector because it could be satisfied without genuine economic participation.

**Legitimate concern:**
A mature partner with 10K loyal customers IS still valuable to the ecosystem — they hold a large PSRE balance, they provide market depth, and their customers may still be buying PSRE. They're just not growing their cumS.

**Recommended mitigations (documented, not protocol-level changes):**

1. **Staking yield.** Mature partners can stake PSRE held in their vault ecosystem (or stake LP tokens) to earn from the staker pool. This provides passive yield without requiring cumS growth. The whitepaper should explicitly mention this as the long-term value capture mechanism for mature partners.

2. **Natural micro-growth.** In practice, even "stable" businesses experience some customer churn and acquisition. New customers receiving PSRE and holding it creates small cumS increments. A partner with 10K customers isn't truly static — there's natural ebb and flow.

3. **PSRE appreciation.** Growing partners drive PSRE demand → price appreciation benefits all holders, including mature partners whose vault ecosystems appreciate in dollar terms.

4. **No penalty for stability.** The partner's cumS is preserved. If growth resumes (new product launch, seasonal peak, marketing push), rewards flow immediately. The partner is not penalized for being mature — they simply don't earn growth rewards when they're not growing.

**NOT recommended:** Adding a "maintenance reward" for stable partners. This would reintroduce the TWR-style gaming vector where partners earn for simply existing. The clear growth → reward → no growth → no reward logic is the protocol's most important differentiator.

---

## Part III: Additional Issues Found

### Issue A: Whitepaper Section 11 (Non-Inflationary Argument) Depends on Incorrect Assumption

**Severity: MODERATE**

Section 11.2 states: "For every 100 PSRE a partner ecosystem grows... 100 PSRE is removed from circulating supply (bought from market, held in vault ecosystem)... Only ~10 PSRE of new supply is emitted as reward... That reward PSRE also enters the vault ecosystem."

The claim that reward PSRE "enters the vault ecosystem" is contradicted by the dev spec, where `claimPartnerReward()` sends rewards to the vault owner, not the vault. If rewards go to the owner's wallet, they ARE circulating supply — the owner can sell them immediately.

The "net deflationary" argument in Section 11.2 still holds in a weaker form: for every 100 PSRE of cumS growth, 100 PSRE was bought and placed in the vault ecosystem, and only 10 PSRE of new supply was created. Even if the 10 PSRE reward is immediately sold, the net circulating effect is −90 PSRE. But the language about reward PSRE "not entering the open market" must be revised.

**Recommendation:** Revise Section 11.2-11.3 to reflect the dev spec's reward-to-owner mechanism. The non-inflationary argument holds — the ratio is still ≈10:1 (100 PSRE bought vs. 10 PSRE emitted) — but the claim about reward PSRE not circulating should be removed.

### Issue B: `finalizeEpoch()` Scalability Ceiling

**Severity: LOW (for launch) / MODERATE (at scale)**

The `finalizeEpoch()` function loops over all active PartnerVaults, calling `snapshotEpoch()` on each. Each external call costs approximately 30,000-70,000 gas depending on the state changes.

Estimated gas costs:
| Active Vaults | Estimated Gas | Block Limit Concern? |
|---|---|---|
| 100 | ≈5M gas | No (well within 30M limit) |
| 500 | ≈25M gas | Approaching limit |
| 1,000 | ≈50M gas | Exceeds single-block limit |

**Recommendation:** For v3.1 launch, this is not a concern (unlikely to have >100 partners initially). Document the scalability ceiling and plan a batched finalization mechanism for future versions if the protocol grows beyond ≈500 active partners. Options include:
- Split `finalizeEpoch()` into `startEpoch()` → multiple `processVaults(vaultBatch)` → `commitEpoch()`
- Off-chain aggregation with on-chain verification (Merkle root of per-vault deltas)
- L2 deployment where gas limits are less constraining

### Issue C: EMA Scale Sensitivity to Partner Count

**Severity: LOW**

The tier thresholds (Silver ≥ 0.5%, Gold ≥ 2.0%) are expressed as shares of total EMA contribution. With few partners, a single large partner could easily capture >2% share, reaching Gold immediately. With many partners, achieving 2% share becomes increasingly difficult.

This is inherent in a share-based system and may not require changes, but the team should be aware that the tier dynamics will shift significantly as the number of active partners grows. At 10 partners, Gold requires ≈20% of total contribution. At 1,000 partners, Gold requires ≈20× the average contribution.

**Recommendation:** Monitor tier distributions as the ecosystem grows. The DAO has the ability to adjust thresholds, which should be exercised if tier distributions become skewed.

### Issue D: Missing Specification for Staker Reward Claim Deadline

**Severity: LOW**

The spec does not address whether unclaimed staker rewards expire. If stakers don't claim, the PSRE sits in the RewardEngine indefinitely.

**Recommendation:** Add a claim deadline for staker rewards (e.g., 26 epochs / 6 months). After the deadline, unclaimed staker rewards are swept to treasury. This prevents indefinite storage bloat and aligns with the partner reward claim window precedent.

### Issue E: REGISTRATION_FEE Adds Complexity for Minimal Benefit

**Severity: LOW**

The $50 USDC registration fee is marked as "optional" in the dev spec. Given that S_MIN ($500 un-rewarded initial buy) already provides substantial spam deterrence, the registration fee adds implementation complexity (USDC routing to treasury during vault creation) for only $50 of additional deterrence.

**Recommendation:** Remove REGISTRATION_FEE from v3.1. S_MIN is sufficient. This simplifies the factory contract and reduces the number of token transfers during vault creation.

### Issue F: CustomerVault `claimVault()` Trust Model

**Severity: LOW**

The `claimVault()` function allows any address to assert ownership: `require(msg.sender == customerWallet)` simply means the caller provides their own address. There's no verification that the caller is the "real" customer — anyone who knows the CustomerVault address can claim it.

In practice, this is likely fine because:
- CustomerVault addresses are not publicly enumerated (only via the parent PartnerVault's `customerVaultList`)
- Partners manage the claim flow through their app/backend
- An attacker who claims a vault before the real customer would need to know the CV address AND front-run the real customer

**Recommendation:** Document this trust model explicitly. The partner's backend should manage the claim flow (e.g., by deploying CVs with a delayed reveal pattern or by only revealing CV addresses to authenticated customers via their app). No protocol-level change needed.

---

## Part IV: v3.0 → v3.1 Comparison Summary

| Aspect | v3.0 | v3.1 | Assessment |
|---|---|---|---|
| Mining primitive | TWR (time-weighted retention) | cumS (cumulative high-water-mark) | **Major improvement** |
| Anti-wash mechanism | Net retention + vesting + bond | cumS ratchet + un-rewarded initial buy + first qualification | **Simpler, structurally stronger** |
| Entry cost | $500 bond (refundable) + $50 fee | $500 initial buy (un-rewarded) + optional $50 fee | **Similar cost, better incentive alignment** |
| Reward timing | 4-epoch linear vesting | Immediately claimable | **Simpler; structural defense replaces time-based defense** |
| Gas cost | Higher (TWR checkpoints per event, vesting ledger) | Lower (max comparison, no vesting storage) | **Significant improvement** |
| E_demand formula | r_base × ΔTWR_total / T_epoch | r_base × Σ ΔcumS_p | **Simpler, no time normalization needed** |
| Epoch 0 | Positive E_demand possible | E_demand = 0 (all unqualified) | **Cleaner bootstrap; deliberate** |
| Complexity | Higher (TWR, vesting, bond escrow, min activity) | Lower (cumS, immediate claim, no bond) | **Major simplification** |
| Gaming resistance | Moderate | Strong | **Improvement** |

**Verdict on v3.0 → v3.1 transition:** Unambiguously positive. Every change either simplifies the protocol, reduces gas costs, or strengthens anti-gaming properties. In several cases, all three.

---

## Part V: Final Recommendations

### Critical (Must fix before implementation)

1. **Resolve the tier multiplier inconsistency** between the whitepaper (8%/10%/12% effective rates) and the dev spec (1.0×/1.25×/1.5× multipliers yielding 10%/12.5%/15%). Decide which is correct and update both documents.

2. **Resolve the reward destination ambiguity** between the whitepaper (rewards to vault) and the dev spec (rewards to owner). Update the whitepaper to match the dev spec. Revise Section 11.2-11.3 accordingly.

3. **Add ERC-20 inflow controls to CustomerVault and PartnerVault** to prevent accounting inconsistencies when PSRE is transferred directly (not via protocol functions).

### Recommended (Should fix before implementation)

4. **Increase vault expiry threshold** from 4 to 6 epochs to accommodate seasonal businesses.

5. **Remove REGISTRATION_FEE** to simplify vault creation. S_MIN is sufficient.

6. **Add staker reward claim deadline** (e.g., 26 epochs).

7. **Add deregistration grace period specification** (4 epochs for reward claims, then sweep to treasury).

8. **Explicitly document** that mature partners at steady state earn zero growth reward, and that staking yield and PSRE appreciation are their long-term value capture mechanisms.

### Optional (Nice to have)

9. **Document the `finalizeEpoch()` scalability ceiling** (≈500 active vaults) and plan for batched finalization in a future version.

10. **Consider 72-hour timelock** for governance parameter changes instead of the recommended 48 hours.

11. **Restrict initial buy to USDC-only** in v3.1 for simplicity. Support additional stablecoins in future versions.

---

## Conclusion

Prospereum v3.1 is a well-designed protocol with a strong core mechanism (cumS ratchet) and clean incentive alignment. The v3.0 → v3.1 evolution represents a significant improvement in simplicity, gas efficiency, and gaming resistance. The three critical issues identified (tier inconsistency, reward destination ambiguity, ERC-20 inflow controls) are straightforward to resolve.

The protocol's thesis — "reward genuine ecosystem growth, not existence" — is sound and correctly implemented through the cumS high-water-mark. The first-cycle wash trade profitability is a known trade-off that is acceptable given the self-limiting ratchet and the need for meaningful commerce incentives.

**Overall verdict: APPROVED WITH CHANGES. Ready for implementation after resolving the three critical issues and addressing the recommended items.**
