# Prospereum v3.4 — Anti-Spam & Anti-Inflation: Design Rationale & Audit

**Classification:** Internal — Founders & Technical Team Only  
**Version:** 3.4 (updated from v3.2)  
**Date:** April 2026  
**Status:** Final — updated with BlockApex audit findings (§2.6 added)

---

## 1. Design Goals

This document provides the complete internal rationale and simulation audit for two core protocol safety properties in Prospereum v3.2.

### Anti-Spam

**Goal:** Prevent economically irrational vault creation or activity designed to extract protocol rewards without genuine commerce participation.

Spam in the context of Prospereum means: creating partner vaults (or generating vault activity) with the sole intent of accumulating reward PSRE, without any real customer base, real buying activity, or genuine commerce function. The protocol must make such behavior unprofitable at every tested scale.

### Anti-Inflation

**Goal:** Prevent reward PSRE from inflating token supply faster than genuine economic demand drives it.

Inflation risk in behavioral mining: if reward PSRE deposited into vaults counts toward the cumulative balance that generates future rewards, a compounding loop could form — rewards increase cumS, which increases future rewards, which increases cumS further. This would decouple emission from real-world buying activity and allow unbounded self-referential growth in the reward stream.

Both properties are addressed by distinct, layered mechanisms. This document traces the full logic of each mechanism, runs adversarial simulations, and documents the accepted residual risks.

---

## 2. Anti-Spam Mechanism

### 2.1 The Problem

An attacker might attempt vault spam if the expected reward from protocol participation exceeds the cost of entry. Consider the naive case: create $N$ vaults, make the minimum required PSRE purchase in each, and collect rewards. If the initial buy were rewarded, or if rewards began immediately with no growth requirement, the expected profit could be positive.

**Why spam would be attempted (naive profit model):**

At genesis, the protocol issues up to 12,600 PSRE/week (E₀ = 0.1% of S_EMISSION). If an attacker could claim a large share of this emission through trivial vault creation, the expected payoff per vault per epoch might be:

```
Expected reward per vault ≈ (share of emission) × (PSRE price)
```

If 200 spam vaults each receive 1% of the weekly staker pool, and PSRE trades at $0.10, the attacker earns:

```
200 × 1% × 12,600 × 0.30 × $0.10 = $7.56/week
```

Against a $500 minimum buy per vault ($100,000 total), this is a poor return — but the analysis changes dramatically if entry costs are lower, or if rewards begin on the initial buy itself. The protocol must make spam unprofitable even in adversarial conditions.

**Structural risk amplification:**

- If rewards were based on gross PSRE holdings (not cumulative growth), a spam wallet could buy once, hold, and earn indefinitely.
- If rewards were proportional to vault count rather than ecosystem growth, creating thousands of vaults would be directly profitable.
- If the initial buy were rewarded, the entry cost effectively becomes zero (entry cost = swap fees; return = reward on initial buy).

The Prospereum v3.2 design closes all three vectors.

### 2.2 The Solution: Reward Qualification Conditions

Two conditions, together, make spam economically irrational.

#### Condition 1 — Initial buy earns zero reward

$S_p(N)$ — the initial vault creation buy, minimum $500 USDC equivalent — earns **no protocol reward**. It sets the baseline high-water-mark only.

$$\text{cumS}_p(N) = S_p(N) = \text{initial buy amount}$$

The spammer pays:
- DEX swap fees (~1% of input) on the initial buy
- Gas costs for vault deployment
- Opportunity cost of the capital committed

And receives:
- Zero protocol reward
- Zero PSRE beyond what they purchased at market price

This makes the initial buy strictly a cost, not a rewarded action.

#### Condition 2 — First reward requires demonstrated growth

The first reward is issued only when:

$$\text{cumS}_p(M) > S_p(N) \quad \text{for some epoch } M > N$$

The ecosystem must demonstrably grow above the initial buy level. The spammer cannot "plant and wait" — patience alone produces zero reward indefinitely. Only genuine ecosystem expansion (more PSRE entering the vault ecosystem from market buys) triggers the first reward.

Together, these two conditions make vault creation a net-negative proposition unless the partner is genuinely growing their ecosystem. The conditions are structural, not punitive — they require demonstrated growth, not compliance attestations or manual review.

### 2.3 Why the Scarcity Cap is NOT the Primary Anti-Spam Mechanism

**Important clarification — corrected from earlier internal analysis:**

An earlier analysis suggested that the scarcity cap ($E_{scarcity}$) provides primary spam protection. This was incorrect. Here is the corrected analysis:

- $E_{scarcity}(0) = E_0 = 12{,}600$ PSRE/week at genesis
- In early epochs with few partners performing small ecosystem buys, $E_{demand} \ll E_{scarcity}$
- The scarcity cap is therefore **not binding** in early epochs
- A non-binding cap cannot be the primary spam protection mechanism

**What the scarcity cap actually does:**

The scarcity cap's role is **anti-inflation** (long-term emission limit), not anti-spam. As $T$ approaches $S_{EMISSION}$, the cap declines asymptotically to zero, ensuring finite total emission regardless of how much demand partners generate. This is a supply-side constraint, not a spam filter.

**The primary anti-spam mechanism** is the qualification conditions in Section 2.2: no reward on initial buy, and first reward only on demonstrated cumS growth. These conditions make spam unprofitable without relying on emission ceilings being binding.

The scarcity cap is a secondary, additive anti-spam protection only in the scenario where spam is performed at massive scale (enough to push $E_{demand}$ toward $E_{scarcity}$) — a scenario that is itself prevented from being economically rational by the qualification conditions.

### 2.4 Spam Attack Simulations

The following scenarios test whether an adversary can extract net positive value from the protocol through vault spam.

**Notation:**
- PSRE price: $0.10 (used for dollar conversions)
- r_base: 10%
- Partner pool: 70% of B(t)
- E₀: 12,600 PSRE/week
- Initial buy minimum: $500 USDC → ~5,000 PSRE at $0.10/PSRE
- Swap fee: ~1% of input

---

#### Scenario S1: 200 vaults, minimum buy only, no growth

**Setup:** An attacker creates 200 PartnerVaults. Each vault receives the minimum $500 USDC initial buy, resulting in cumS(N) = 5,000 PSRE. The attacker never buys additional PSRE.

**Mechanics:**
- Each vault: cumS = 5,000 PSRE = initialCumS → `qualified[vault] = false`
- cumS never grows above initialCumS → first qualification condition never met
- All vaults remain permanently unqualified → all vaults earn zero reward, ever

**Calculation:**
```
Total cost: 200 vaults × 1% × $500 USDC = $1,000 irrecoverable swap fees
Total reward: $0
Net: −$1,000
```

**Result:** ❌ Net loss of $1,000. Spam is entirely unprofitable. The attacker has locked $100,000 USDC equivalent in vault ecosystem balances and earned nothing.

---

#### Scenario S2: 200 vaults, each grows by minimal amount (1 PSRE)

**Setup:** Same as S1, but the attacker makes one additional micro-buy per vault — purchasing 1 PSRE above the initial balance — to trigger qualification.

**Mechanics:**
- Each vault: initial cumS = 5,000, then buys 1 PSRE
- cumS(M) = 5,001 > 5,000 = initialCumS → `qualified[vault] = true` ✓
- First reward delta per vault: cumS(M) − initialCumS = 1 PSRE
- E_demand = r_base × Σ deltaCumS = 10% × (200 × 1 PSRE) = 20 PSRE
- Partner pool = 70% × min(20, 12,600) = 14 PSRE = $1.40

**Cost calculation:**
```
Initial buys:  200 × 1% × $500 = $1,000 swap fees
Growth buys:   200 × ~$0.002 (1 PSRE at $0.10 + ~1% fee) ≈ $0.40 total
Total cost:    ≈ $1,000
```

**Result:**
```
Revenue: 14 PSRE = $1.40
Cost:    $1,000+
Net:     −$998.60
```

**Result:** ❌ Net loss of approximately $998.60. The micro-growth strategy yields negligible reward against overwhelming entry costs. Even with perfect qualification by all 200 vaults, the reward pool is vanishingly small compared to the cost.

---

#### Scenario S3: 1 vault spam, large initial + large growth (bounded residual risk)

**Setup:** A single sophisticated attacker creates one vault with a larger initial buy ($1,000 USDC) and then makes a matching growth buy ($1,000 USDC) to qualify for a meaningful first reward.

**Mechanics:**
- Initial buy: $1,000 USDC → ~10,000 PSRE, cumS(N) = initialCumS = 10,000 PSRE
- Growth buy: $1,000 USDC → ~10,000 PSRE, cumS(M) = 20,000 PSRE
- deltaCumS = 20,000 − 10,000 = 10,000 PSRE
- E_demand = 10% × 10,000 = 1,000 PSRE
- Partner pool = 70% × 1,000 = 700 PSRE = $70

**Cost calculation:**
```
Initial buy fee:  1% × $1,000 = $10
Growth buy fee:   1% × $1,000 = $10
Total fees:       $20
```

(Note: the $2,000 principal is not lost — it is held in the vault as PSRE. Only the $20 in swap fees is irrecoverable.)

**Result:**
```
Revenue: 700 PSRE = $70
Cost:    $20 (fees only)
Net:     +$30
```

**Result:** ⚠️ Small one-time profit of approximately $30. **This is the accepted residual risk.**

**Why this residual risk is accepted:**

1. **Bounded:** The profit is not amplified by vault count or repetition. This is a one-time first-cycle profit for a single vault.

2. **Non-repeatable:** The cumS ratchet prevents the attacker from recycling this profit. After earning the first reward, the vault's cumS is 20,000 PSRE. To earn again, the attacker must buy more PSRE and push cumS above 20,000 — committing additional permanent capital. Each subsequent cycle requires more capital than the last.

3. **Bootstrapping cost:** The protocol effectively provides a $30 subsidy to the first genuine adopters who demonstrate ecosystem growth. This is not economically harmful and is treated as an acceptable bootstrapping cost.

4. **Asymmetric deterrence:** For this to be exploitable at scale (e.g., 1,000 vaults, each doing $2,000 in buys), the attacker would need $2,000,000 in committed capital and would earn $30,000 in fees arbitrage — a 1.5% return with full capital at risk. Not economically rational as an attack strategy.

---

#### Scenario S4: cumS ratchet prevents repeat wash cycle

**Setup:** An attacker attempts to earn rewards repeatedly by cycling a large buy, collecting reward, selling, rebuying, and repeating.

**Mechanics:**

- Epoch N: Buy 100,000 PSRE → ecosystemBalance = cumS = 100,000 PSRE. Earns reward on growth from initialCumS.
- Epoch N+1 (sell): Attacker withdraws 100,000 PSRE from vault. ecosystemBalance drops to 0. **cumS stays at 100,000 PSRE** (ratchet — never decreases).
- Epoch N+2 (rebuy): Attacker rebuys 100,000 PSRE. ecosystemBalance = 100,000. cumS = max(100,000, 100,000) = 100,000. No change. effectiveCumS unchanged. **Reward = ZERO.**
- To earn any reward again, the attacker must buy > 100,000 PSRE, pushing cumS above its prior peak.

**Result:**
```
Epoch N reward:   earned (one-time, on initial growth)
Epoch N+2 reward: $0 (cumS not exceeded)
Epoch N+3 rebuy to 110,000: earns on Δ = 10,000 PSRE only
→ Each cycle requires permanent net capital growth
→ Non-repeatable wash cycle: strategy is self-limiting by construction
```

**Result:** ✅ The cumS ratchet completely defeats the wash cycle. Each earning cycle requires permanently higher committed capital. No fixed capital base can sustain indefinite reward extraction. The strategy degrades monotonically.

### 2.5 Conclusion on Anti-Spam

The qualification conditions (no reward on initial buy; first reward only on demonstrated cumS growth) make spam economically irrational in all tested scenarios.

- **Mass vault spam (S1):** 100% loss. No reward possible without growth.
- **Micro-growth spam (S2):** 99.9% loss. Reward is orders of magnitude smaller than entry cost.
- **Single-vault arbitrage (S3):** Small one-time profit (~$30 on $20 in fees and $2,000 committed capital). Accepted residual risk. Bounded, non-repeatable, non-scalable.
- **Wash cycle (S4):** Structurally impossible. Ratchet defeats all recycling strategies.

The one-time first-cycle profit in Scenario S3 is documented as an accepted bootstrapping cost. It is bounded by the emission cap, non-repeatable by the ratchet, and insufficient to justify the capital commitment required to execute it at scale.

### 2.6 Flash-Loan cumS Inflation (v3.4 Closure)

**Threat (identified in BlockApex audit, April 2026):**

The original v3.2 `_updateCumS()` implementation scanned live ERC-20 balances (`balanceOf`) to determine ecosystem balance. This created a flash-loan vector:

1. Attacker takes a flash loan of X PSRE
2. Transfers X PSRE directly to their PartnerVault (or CustomerVault)
3. Calls `buy()` with minimal USDC to trigger `_updateCumS()`
4. `balanceOf` scan detects inflated balance → cumS ratchets to X
5. Attacker returns the flash loan (PSRE leaves vault)
6. cumS remains at the inflated peak
7. Protocol rewards the attacker in the next epoch as if X PSRE was genuine committed capital

**Why this works under v3.2:** The high-water-mark ratchet is permanent. A single flash loan could permanently inflate cumS without committing any real capital beyond gas fees.

**v3.4 closure:**

`_updateCumS()` now advances cumS exclusively from the `ecosystemBalance` counter — which is only incremented by `buy()` and decremented by `transferOut()` / `reportLeakage()`. Direct ERC-20 transfers to the vault do not update `ecosystemBalance` and therefore cannot affect cumS.

The flash-loan vector is fully closed: an attacker cannot inflate cumS without committing genuine PSRE through tracked protocol flows.

**Residual risk:** None. The fix is architectural — it removes the `balanceOf` scan entirely. Flash-loan attacks against cumS are structurally impossible in v3.4.

---

## 3. Anti-Inflation Mechanism

### 3.1 The Problem

A behavioral mining protocol that distributes newly minted tokens as rewards faces a structural inflation risk: if reward PSRE lands in partner vaults and increases the ecosystem balance, it could increase cumS, which would generate reward in the next epoch, which would further increase cumS, creating a compounding feedback loop.

**The specific risk in Prospereum:**

$$S_{eco,p}(t) = \text{PSRE in PartnerVault} + \sum_{cv} \text{PSRE in CustomerVault}_cv$$

Reward PSRE is deposited into the PartnerVault and distributed to CustomerVaults. Both categories count toward $S_{eco,p}(t)$.

If reward PSRE increases $S_{eco,p}$ without adjustment:
- cumS rises (because cumS = max(S_eco, cumS_prev))
- Next epoch deltaCumS = cumS_new − cumS_prev > 0
- Reward = r_base × deltaCumS > 0
- Repeat: each epoch's reward generates more cumS growth, generating more reward

This loop would allow emission to grow faster than genuine economic demand, inflating PSRE supply relative to the real commerce activity backing it. In the extreme case, a single large partner ecosystem could mint tokens indefinitely without any new market-purchased PSRE entering the vault.

### 3.2 The Solution: effectiveCumS Deduction

The protocol introduces a deduction to the cumS calculation that cancels out reward PSRE exactly. The effective cumulative high-water-mark is:

$$\text{effectiveCumS}_p(t) = \text{cumS}_p(t) - \text{cumulativeRewardMinted}_p(t)$$

The reward formula becomes:

$$\text{reward}_p(t) = r_{base} \times \max\!\left(0,\ \text{effectiveCumS}_p(t) - \text{effectiveCumS}_p(t-1)\right)$$

Where `cumulativeRewardMinted(p)` is:
- A running total of **all rewards ever minted** for partner p across all epochs
- Incremented **only in `finalizeEpoch()`**, immediately after computing the reward for epoch t
- **Never decreases** — it is a ratchet on the reward side, complementary to the cumS ratchet on the balance side

**Why this works:**

When reward PSRE enters the vault and increases cumS by amount $R$:
- `cumS` increases by $R$ (reward landed in vault)
- `cumulativeRewardMinted` also increases by $R$ (reward just minted and recorded)
- Net effect on effectiveCumS: $(+R) - (+R) = 0$

The deduction cancels the reward contribution exactly. `effectiveCumS` only grows when NEW market-purchased PSRE enters the ecosystem via `buy()` — a genuine commerce-driven action that cannot be synthesized from prior rewards.

**Key properties:**
- No tag tracking required — we don't need to distinguish "market PSRE" from "reward PSRE" in individual balances
- No dual balance system — a single `cumulativeRewardMinted` accumulator per vault is sufficient
- The deduction is monotonically increasing (rewards never clawed back), matching the monotonically increasing cumS ratchet

### 3.3 Anti-Inflation Simulations

The following scenarios verify that the effectiveCumS deduction correctly prevents reward compounding in all material cases.

**Notation:**
- r_base = 10%
- Epoch steps are weekly (7 days)
- "cumS" refers to the raw ratchet value; "effectiveCumS" includes the deduction

---

#### Scenario I1: Reward PSRE lands in vault — no compounding

**Epoch 1 state:**
```
Buy: 10,000 PSRE via market purchase
cumS: 10,000 PSRE
cumulativeRewardMinted: 0
effectiveCumS(t): 10,000 − 0 = 10,000
effectiveCumS(t-1): 0 (vault just qualified)
Δ effectiveCumS: 10,000
Reward: 10% × 10,000 = 1,000 PSRE → minted and deposited into vault
```

**After epoch 1 finalization:**
```
cumulativeRewardMinted: 1,000 (updated in finalizeEpoch)
cumS: max(10,000 + 1,000, 10,000) = 11,000 (reward landed in vault, ecosystemBalance = 11,000)
effectiveCumS(t): 11,000 − 1,000 = 10,000
```

**Epoch 2 state (no new buying):**
```
effectiveCumS(t): 10,000
effectiveCumS(t-1): 10,000  (stored from epoch 1)
Δ effectiveCumS: 0
Reward: 0 ✅
```

**Conclusion:** Reward PSRE landing in the vault does NOT generate any further reward. The deduction cancels it exactly. The feedback loop is closed.

---

#### Scenario I2: Partner buys more + has prior rewards

**Continuing from I1. Epoch 2 state (with new buying):**
```
New market buy: 5,000 PSRE
ecosystemBalance: 11,000 + 5,000 = 16,000
cumS: max(16,000, 11,000) = 16,000
cumulativeRewardMinted: 1,000 (unchanged until finalization)
effectiveCumS(t): 16,000 − 1,000 = 15,000
effectiveCumS(t-1): 10,000
Δ effectiveCumS: 15,000 − 10,000 = 5,000
Reward: 10% × 5,000 = 500 PSRE
```

**After epoch 2 finalization:**
```
cumulativeRewardMinted: 1,000 + 500 = 1,500
cumS: max(16,000 + 500, 16,000) = 16,500 (500 reward PSRE deposited)
effectiveCumS(t): 16,500 − 1,500 = 15,000
```

**Epoch 3 state (no new buying):**
```
effectiveCumS(t): 15,000
effectiveCumS(t-1): 15,000
Δ effectiveCumS: 0
Reward: 0 ✅
```

**Conclusion:** New market buying correctly generates reward proportional to genuine ecosystem growth. Prior accumulated rewards do not create any additional reward entitlement.

---

#### Scenario I3: Customer sells reward PSRE — ecosystem shrinks

**Continuing from I2. Epoch 3 state (customer withdrawal):**

A customer withdraws 2,000 PSRE from a CustomerVault to an external wallet. This triggers `reportLeakage(2,000)` in the parent PartnerVault.

```
Before withdrawal:
  ecosystemBalance: 16,500
  cumS: 16,500
  cumulativeRewardMinted: 1,500
  effectiveCumS(t-1): 15,000

After withdrawal:
  ecosystemBalance: 16,500 − 2,000 = 14,500
  cumS: max(14,500, 16,500) = 16,500  (ratchet holds — cumS does NOT drop)
  cumulativeRewardMinted: 1,500 (unchanged)
  effectiveCumS(t): 16,500 − 1,500 = 15,000
  Δ effectiveCumS: 15,000 − 15,000 = 0
  Reward: 0
```

**Path to earning again:**
```
To push effectiveCumS above 15,000, the partner must:
  Buy at least 2,001 PSRE from market
  ecosystemBalance: 14,500 + 2,001 = 16,501
  cumS: 16,501
  effectiveCumS: 16,501 − 1,500 = 15,001
  Δ effectiveCumS: 15,001 − 15,000 = 1 PSRE
  Reward: 10% × 1 PSRE = 0.1 PSRE ✅
```

**Conclusion:** Customer sell-outs reduce the ecosystem balance but do not lower cumS (ratchet) and do not lower cumulativeRewardMinted. The partner must purchase new market PSRE to grow effectiveCumS above its prior value. The protocol correctly requires new genuine market demand to resume reward generation.

---

#### Scenario I4: Long-term emission is bounded

**Upper bound on total emission:**

Total rewards ever minted = sum over all epochs and partners of:

$$\text{reward}_p(t) = r_{base} \times \Delta\text{effectiveCumS}_p(t)$$

Since $\Delta\text{effectiveCumS}_p(t) \leq \Delta\text{cumS}_{market,p}(t)$ (only market-purchased PSRE drives effectiveCumS growth), total emission is bounded by:

$$\sum_{all\ t,\ p} \text{reward}_p(t) \leq r_{base} \times \sum_{all\ t,\ p} \Delta\text{cumS}_{market,p}(t) \leq r_{base} \times S_{emission}$$

In absolute terms:
```
Hard cap: S_EMISSION = 12,600,000 PSRE
Maximum total rewards: ≤ 12,600,000 PSRE (plus the initial 60% emission reserve definition)
effectiveCumS deduction: ensures no epoch's reward is based on prior rewards
Scarcity curve: ensures emission rate → 0 as S_EMISSION is approached
```

The effectiveCumS deduction ensures rewards never self-amplify beyond what genuine buying supports. Even if every reward PSRE were immediately recycled back into a buy (to maximize cumS growth), the deduction would cancel the round-trip: `cumulativeRewardMinted` tracks the recycled amount and subtracts it from effectiveCumS. Only the portion bought from the open market in excess of prior mints generates new effectiveCumS growth.

**Result:** ✅ Long-term emission is strictly bounded by $S_{EMISSION}$ and structurally non-self-amplifying.

### 3.4 Scarcity Curve Role

The scarcity curve provides the long-term emission rate bound:

$$E_{scarcity}(t) = E_0 \cdot (1 - x(t))^k, \qquad x(t) = \frac{T(t)}{S_{emission}}, \qquad k = 2$$

**Properties:**
- At genesis ($T = 0$, $x = 0$): $E_{scarcity}(0) = E_0 = 12{,}600$ PSRE/week
- At 50% depleted ($x = 0.5$): $E_{scarcity} = 12{,}600 \times 0.25 = 3{,}150$ PSRE/week  
- At 90% depleted ($x = 0.9$): $E_{scarcity} = 12{,}600 \times 0.01 = 126$ PSRE/week
- As $T \to S_{emission}$: $E_{scarcity} \to 0$

The scarcity curve is the **final anti-inflation safety net**. Even if the effectiveCumS deduction were somehow circumvented (not possible in the current design, but considered as defense-in-depth), the scarcity curve would cap emission at an asymptotically declining rate. The protocol cannot mint tokens faster than the scarcity curve allows, regardless of demand pressure.

**The scarcity curve's role in the full emission formula:**

$$B(t) = \min\left(E_{demand}(t),\ E_{scarcity}(t),\ S_{emission} - T(t)\right)$$

All three terms are binding constraints:
- $E_{demand}$: demand-side limit (tied to genuine commerce activity via effectiveCumS)
- $E_{scarcity}$: supply-side limit (declines as reserve depletes)
- $S_{emission} - T$: hard cap (prevents any emission past the 12,600,000 PSRE reserve)

### 3.5 Conclusion on Anti-Inflation

The effectiveCumS deduction eliminates compounding. Reward PSRE deposited into vaults increases cumS — but the deduction cancels the effect exactly. effectiveCumS only grows when new market-purchased PSRE enters the ecosystem. No reward cycle can self-amplify.

The scarcity curve ensures finite total emission. As the emission reserve is consumed, the weekly emission ceiling declines asymptotically to zero. Total emission across the protocol's lifetime is absolutely bounded at 12,600,000 PSRE.

Together, these mechanisms make Prospereum v3.2 anti-inflationary: genuine market demand always exceeds or equals reward emission in the long run, and reward emission is structurally prevented from outpacing demand.

---

## 4. Summary Table

| Mechanism | Anti-Spam | Anti-Inflation | Notes |
|-----------|:---------:|:--------------:|-------|
| No reward on S(N) | ✅ **Primary** | — | Entry cost without reward; swap fees irrecoverable |
| cumS(M) > S(N) qualification | ✅ **Primary** | — | Must demonstrate genuine growth to earn first reward |
| effectiveCumS deduction | — | ✅ **Primary** | Eliminates reward compounding exactly and elegantly |
| cumS ratchet | ✅ Secondary | ✅ Secondary | Prevents wash cycle recycling; raises bar per cycle |
| Scarcity cap (per-epoch) | — | ✅ Secondary | Weekly emission ceiling; not binding in early epochs |
| Scarcity curve (asymptotic) | — | ✅ **Primary** | Long-term bound; emission → 0 as reserve depletes |

**Reading the table:**

- The **primary anti-spam mechanisms** are the qualification conditions. They work regardless of emission levels and regardless of how many vaults exist. They are purely behavioral — they require demonstrated growth, not time elapsed or deposits made.

- The **primary anti-inflation mechanisms** are the effectiveCumS deduction (prevents compounding) and the scarcity curve (ensures finite total emission). These are structural and mathematical, not behavioral.

- The cumS ratchet is **secondary to both**: it prevents wash cycling (anti-spam) and prevents balance recycling from gaming effectiveCumS (anti-inflation, since cumulativeRewardMinted would cancel any recycled rewards anyway).

- The per-epoch scarcity cap ($E_{scarcity}$) is a **secondary anti-inflation** mechanism only — it was incorrectly described as anti-spam in earlier analysis. It caps weekly emission but is not binding in early epochs when E_demand is small.

---

*End of Internal Rationale & Audit — Prospereum v3.2*
