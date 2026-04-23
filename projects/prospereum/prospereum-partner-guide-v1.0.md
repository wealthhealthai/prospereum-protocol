# Prospereum Partner Guide v1.0

**How to Earn Protocol Rewards as a Prospereum Partner**
*April 2026 — For Registered Partners and Brand Prospects*

---

## What This Document Is

This guide explains exactly how the Prospereum protocol rewards you as a brand partner — what drives rewards, how your tier affects your earnings, and how to set up your commerce operations to maximize return. No technical blockchain knowledge required.

---

## 1. The Core Idea in Plain Language

Prospereum rewards you when your customer ecosystem genuinely grows. Specifically: when the total amount of PSRE held across your PartnerVault and all your registered CustomerVaults reaches a new all-time high.

**The ratchet:** Your ecosystem has a running record of its highest-ever PSRE balance. We call this your "high-water mark." Rewards are earned only when you exceed that mark. If your balance drops and then recovers, you earn rewards on the net new growth above the prior peak — not on the recovery itself.

Think of it like a fitness tracker that only counts new personal bests, not reps.

---

## 2. What You Control — and What Drives Your Rewards

### 2.1 Your Ecosystem Balance

Your ecosystem balance = all PSRE currently held in your PartnerVault + all PSRE in your registered CustomerVaults.

**Actions that GROW your ecosystem balance (and can earn rewards):**
- Buying PSRE via your PartnerVault (the `buy()` function)
- Distributing PSRE to customers (moves PSRE within your ecosystem — balance unchanged, customers now hold more)
- Customers retaining their PSRE rewards rather than withdrawing them

**Actions that REDUCE your ecosystem balance (no rewards until you recover):**
- Customers withdrawing PSRE to their personal wallets
- You calling `transferOut()` to move PSRE out of your ecosystem

**The key insight:** When customers hold their PSRE — because they see value in it appreciating — your ecosystem balance stays high, and your reward potential stays high. Commerce loyalty and protocol rewards are aligned.

### 2.2 Getting Past Your High-Water Mark

Your first reward requires: **you must grow your ecosystem past your initial buy amount.**

The initial PSRE you bought when registering your vault establishes your starting high-water mark. This initial buy earns *zero reward* — it is your entry baseline. After that, every time your ecosystem breaks through its previous peak, rewards are generated on the growth increment.

**Practical implication:** New partners have a two-step journey:
1. Distribute enough PSRE to customers that their holding grows the ecosystem above your initial buy
2. Continue growing — each new peak earns a proportional reward

### 2.3 Slow Seasons Are OK

If your ecosystem goes flat for a month — no growth — you earn zero rewards during that period. But your high-water mark does *not* reset. The moment growth resumes, rewards resume. You are never penalized for a slow season.

---

## 3. Your Tier — Bronze, Silver, Gold

Prospereum assigns every partner a tier based on their share of total ecosystem growth across all partners. Tier determines your reward multiplier:

| Tier | Reward Multiplier | Meaning |
|------|------------------|---------|
| Bronze | 0.8× | Below-average share of growth |
| Silver | 1.0× | Average share of growth |
| Gold | 1.2× | Top-tier share of growth |

**How your tier is calculated:**

Your tier is based on your rolling average contribution to total protocol demand over approximately the last 13 weeks (one quarter). This prevents a single big month from permanently locking you into Gold — and prevents a slow month from permanently dropping you to Bronze. It is a smooth, rolling measure.

**What this means operationally:**
- Consistent, sustained growth earns and maintains a high tier better than irregular spikes
- A partner who grows steadily every week outperforms a partner who has one explosive month and then goes flat
- Early partners who grow consistently will establish Gold tier naturally as the protocol scales

---

## 4. The Epoch Cycle — What Happens Every 7 Days

Prospereum runs in weekly **epochs**. Here is what happens automatically each week:

1. **Snapshot:** The protocol checks every partner's current ecosystem balance and computes their growth since last week
2. **Budget calculation:** The protocol calculates the total rewards available this week based on aggregate demand and the scarcity curve
3. **Distribution:** Each qualifying partner receives their share of the reward pool, weighted by their growth contribution and tier multiplier
4. **Claim:** Your earned PSRE becomes available to claim from the RewardEngine

You do not need to do anything for this to happen. The `buy()` function in your PartnerVault automatically triggers epoch finalization on every transaction — no external keeper required.

---

## 5. Setting Up for Maximum Reward Effectiveness

### 5.1 CustomerVault Strategy

Every customer who holds PSRE contributes to your ecosystem balance. The more customers you onboard with CustomerVaults, and the more PSRE they retain, the higher your ecosystem balance.

**Best practices:**
- Create a CustomerVault for every customer who participates in your rewards program
- Distribute enough PSRE per purchase that customers have an incentive to hold rather than immediately withdraw
- Design your customer experience to make holding PSRE feel rewarding — e.g., display its current market value in your app

### 5.2 Distribution Cadence

Frequent, regular PSRE purchases and distributions tend to grow ecosystem balance more steadily than infrequent large buys. Steady growth builds tier status more effectively than lumpy behavior.

**Recommended pattern:**
- Buy PSRE and distribute to new customers on a regular schedule (weekly or per-purchase)
- Track your ecosystem balance regularly — your dashboard will show how close you are to your next high-water mark

### 5.3 Avoiding Balance Drops

Large drops in ecosystem balance reset progress toward your next reward. Common causes:
- Customers en masse withdrawing PSRE (often triggered by not seeing value in holding)
- You withdrawing PSRE from your PartnerVault before distributing it

**Mitigation:** Give customers a reason to hold. The more PSRE appreciates, the more natural retention becomes — creating a positive loop between protocol adoption and your reward earnings.

---

## 6. Economics: What You Actually Earn

To be concrete: your reward is a percentage of a weekly pool that the protocol makes available, weighted by your growth contribution and tier. The exact formula is kept proprietary, but the principle is:

- **More growth this week** = larger share of the pool
- **Higher tier** = larger multiplier on your share
- **More total partners growing** = pool grows larger overall

Your reward is always proportional to genuine incremental growth — the protocol is designed so that only real ecosystem expansion earns rewards. A partner who grows their ecosystem by $10,000 this week earns more than a partner who grew by $1,000.

**The net economics:** For legitimate partners running real customer programs, the protocol rewards are a rebate on your loyalty program spend. You buy PSRE to fund customer rewards; when those rewards drive customer retention and ecosystem growth, the protocol returns a portion of that value to you.

---

## 7. Quick Reference — What Earns Rewards

| Action | Effect on Ecosystem | Earns Reward? |
|--------|--------------------|-|
| Buy PSRE via `buy()` | Increases ecosystem balance | Yes, if new high-water mark exceeded |
| Distribute PSRE to CustomerVault | PSRE moves within ecosystem (neutral) | Indirectly — enables customer growth |
| Customer holds PSRE | Maintains ecosystem balance | Protects prior high-water mark |
| Customer withdraws PSRE | Decreases ecosystem balance | No — reduces future potential |
| Transfer PSRE out via `transferOut()` | Decreases ecosystem balance | No |
| Ecosystem flat (no change) | Same balance | No — must exceed prior peak |

---

## 8. Frequently Asked Questions

**Q: Do I earn rewards on my initial buy?**
A: No. The initial buy establishes your baseline. Rewards begin when you grow past it.

**Q: What if I don't grow for a few weeks?**
A: No rewards during flat periods, but your high-water mark is preserved. Growth resumes → rewards resume.

**Q: Can I earn more by creating multiple vaults?**
A: Each vault starts at zero with a new baseline. Spreading customers across vaults is inefficient — concentrate growth in one vault.

**Q: How do I check my current ecosystem balance and tier?**
A: Your ecosystem balance and cumulative high-water mark are on-chain and readable at any time. The Prospereum dashboard displays your current balance, tier, and pending rewards.

**Q: When can I claim my rewards?**
A: Rewards are claimable after each epoch finalizes (every 7 days). They accumulate and can be claimed any time — no expiry.

**Q: Is there a minimum size to earn rewards?**
A: There is no minimum weekly growth — any net new high triggers a proportional reward. Very small ecosystems will earn small rewards, but the structure is the same.

---

## 9. Getting Started

1. **Register your PartnerVault** — minimum $500 USDC initial buy
2. **Set up your CustomerVault deployment** — integrate with your ecommerce backend or use the Prospereum integration layer
3. **Distribute PSRE to customers** — set your per-purchase reward rate
4. **Track your ecosystem** — watch your balance grow toward new highs
5. **Claim rewards weekly** — after each epoch, claim your earned PSRE

For technical integration support: **partnerships@prospereum.io**

---

*Prospereum Partner Guide v1.0 — April 2026*
*Live on Base Mainnet | Audited by BlockApex*
*On-chain contracts are the authoritative source of truth for all reward calculations.*
