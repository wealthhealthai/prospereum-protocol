# Prospereum (PSRE) — Proof of Prosperity: The Commerce Rewards Protocol

**Public Whitepaper v3.4 — April 2026**
**Status: LIVE on Base Mainnet**

> *Bitcoin solved digital scarcity. Ethereum solved programmable coordination. Prospereum solves commerce rewards.*

---

## Executive Summary

Prospereum (PSRE) is a decentralized commerce rewards protocol built on the Base blockchain — **live on mainnet as of April 22, 2026.** It allows ecommerce brands and DTC merchants to replace traditional loyalty points with a real, appreciating digital asset — distributed directly to their customers as purchase rewards.

The protocol introduces **Proof of Prosperity**: a mechanism where new PSRE is issued only when genuine commerce growth is verified on-chain. There is no pre-sale, no ICO, and no insider allocation. PSRE has a fixed maximum supply of **21,000,000 tokens** — the same hard cap discipline that makes Bitcoin scarce — with a $0.10 launch price and $40,000 in genesis liquidity.

**Independently audited by BlockApex (April 2026) — all findings resolved before mainnet launch.**

---

## 1. The Problem: Loyalty Programs Are Broken

Every major brand in the world runs a loyalty program. Airlines give miles. Coffee shops give stamps. Retailers give points. And almost universally, these programs fail to deliver lasting value to customers or meaningful differentiation for brands.

**For customers, loyalty points are a bad deal:**
- Points expire, devalue, or get discontinued without warning
- They can only be spent at one brand — usually for discounts on things you were already going to buy
- They represent no real financial value; you can't sell them, transfer them, or hold them as an asset
- The average American household holds over $200 in loyalty points they'll never use

**For brands, loyalty programs are expensive and ineffective:**
- Building and maintaining points infrastructure is costly
- Customers quickly learn that "10% back in points" is just a delayed discount — not a reason to stay loyal
- Points create liability on the balance sheet and churn when customers realize redemption is capped or devalued

**Meanwhile, crypto tokens haven't solved this either:**
- Most brand tokens issued via ICOs or NFTs are pure speculation with no utility backing
- Token prices crash after launch hype fades because there's no sustained demand mechanism
- Customers who receive brand tokens often immediately sell them — the opposite of loyalty

**The gap:** There is no token that rises in value because of genuine commerce activity, not speculation.

Prospereum fills that gap.

---

## 2. The Solution: Prospereum (PSRE)

Prospereum is a **commerce rewards layer** — a protocol that connects real ecommerce activity to a scarce, appreciating digital asset.

Think of it this way: Bitcoin is digital gold. It's scarce and valuable because the protocol mathematically limits supply. Prospereum is like digital gold for commerce rewards — scarce and valuable because the protocol only issues new tokens when real commerce growth is verified.

**Here's the simple version:**

1. Brands (called **Partners**) buy PSRE from the open market and distribute it to their customers as purchase rewards
2. Customers receive PSRE tokens in their digital wallet — tokens that have real market value and can be held, traded, or spent
3. The Prospereum protocol watches how much PSRE is held across a partner's customer base
4. When that ecosystem genuinely grows — more customers holding more PSRE — the protocol issues a small amount of new PSRE as a reward to the partner
5. This new supply is tightly constrained by a mathematical scarcity function that becomes stricter over time

The result: the more real commerce activity flows through the protocol, the more demand there is for PSRE — and the more scarce it becomes.

---

## 3. Proof of Prosperity: Rewards Flow When Commerce Grows

Prospereum introduces a new consensus primitive: **Proof of Prosperity**.

Like Proof of Work (Bitcoin mining) and Proof of Stake (Ethereum validation), Proof of Prosperity is a verifiable on-chain mechanism — but instead of rewarding computation or capital lockup, it rewards **genuine growth in commerce activity**.

The core principle is elegant:

> **New PSRE is issued only when a partner's customer ecosystem holds more PSRE than it ever has before.**

Not more than last week. Not more than a threshold. More than *all-time peak*. Ever.

This means:
- If commerce grows → rewards flow
- If commerce is flat → rewards pause (but don't reset)
- If the ecosystem shrinks → no rewards until it grows past the previous all-time high

The protocol is designed to reward genuine commerce growth and is structurally resistant to gaming. The reward mechanism cannot be exploited by short-term buying and selling — only sustained, real growth in customer holdings triggers new issuance.

This is not a subjective judgment. It is verified automatically, every seven days, by smart contracts on the Base blockchain.

---

## 4. How Partners Use Prospereum

A **Partner** is any ecommerce brand or DTC merchant that joins the Prospereum protocol to offer PSRE as customer rewards.

**The partner flow is simple:**

### Step 1: Register and Fund
The partner registers on the Prospereum protocol by creating a **PartnerVault** — a smart contract that serves as their on-chain identity. This requires an initial PSRE purchase of at least $500 USDC equivalent, which establishes their baseline.

### Step 2: Distribute Rewards to Customers
When a customer makes a purchase, the partner's backend automatically delivers PSRE to that customer's **CustomerVault** — a lightweight wallet contract linked to the partner's ecosystem. Customers don't need to interact with the blockchain directly. From their perspective, it looks just like any other rewards program — except the rewards are a real digital asset.

### Step 3: Watch the Ecosystem Grow
As more customers join and hold PSRE, the partner's total ecosystem balance grows. The protocol tracks this growth in real time.

### Step 4: Earn Protocol Rewards
When the partner's ecosystem crosses a new all-time high in total holdings, the Prospereum protocol mints a small amount of new PSRE as a reward to the partner. The partner can use this to fund further customer rewards — creating a self-sustaining flywheel.

**The minimum buy-in is $500 USDC.** There are no subscription fees. There is no ongoing cost beyond the PSRE the partner chooses to distribute to customers.

Partners earn rewards proportional to their growth, and top-performing partners are recognized with **Bronze, Silver, and Gold tier status** — unlocking higher reward rates.

---

## 5. How Customers Benefit

When a customer earns PSRE as a purchase reward, they receive something fundamentally different from traditional loyalty points:

| Feature | Traditional Loyalty Points | PSRE Rewards |
|---------|--------------------------|--------------|
| Real market value | ❌ No | ✅ Yes |
| Can be sold or traded | ❌ No | ✅ Yes |
| Expires | ❌ Often | ✅ Never |
| Appreciates over time | ❌ No | ✅ Possible |
| Works across brands | ❌ No | ✅ Yes (DEX tradeable) |
| Locked to one app | ❌ Yes | ✅ No |

Customers can:
- **Hold it** — if PSRE appreciates, their rewards grow in value
- **Claim it** — transfer to their own personal wallet at any time
- **Spend it** — use PSRE at any partner that accepts it, or trade it on decentralized exchanges

Instead of earning a 5% discount that disappears if they don't redeem it this quarter, a customer earns PSRE that could be worth more next year than it is today.

---

## 6. Token Economics

### 6.1 Supply — The 21 Million Cap

Like Bitcoin, Prospereum has an absolute, immutable maximum supply:

> **21,000,000 PSRE — total, forever. No exceptions.**

This cap is enforced by smart contract and cannot be changed by any governance vote or external party.

### 6.2 Allocation

| Category | Amount | Notes |
|----------|--------|-------|
| **Behavioral Mining Reserve** | 12,600,000 (60%) | Not minted at launch — released only as earned rewards through commerce activity |
| **Team & Founders** | 4,200,000 (20%) | Locked at genesis in Founder Safe; 4-year Sablier vesting, 1-year cliff |
| **Treasury** | 4,200,000 (20%) | Held in Treasury Safe; used for genesis LP, ecosystem growth, and infrastructure |

**The most important number:** 60% of all PSRE ever to exist — 12.6 million tokens — is locked in the emission reserve and can *only* be released through verified commerce activity. It cannot be sold, given to founders, or released by governance decision.

### 6.3 Scarcity Model

Emission from the reserve is not linear. It follows a **declining scarcity curve** — the more that has already been emitted, the slower new PSRE is released. As the reserve depletes, emission declines mathematically toward zero.

The weekly emission ceiling is also capped by actual commerce demand — if partners don't grow their ecosystems, no new PSRE is emitted at all.

### 6.4 Launch Parameters

- **Launch price:** $0.10 per PSRE
- **Network:** Base (Ethereum L2, chain ID 8453)
- **Genesis liquidity:** $40,000 — 200K PSRE + $20K USDC, Uniswap v3
- **Launch date:** April 22, 2026
- **Circulating supply at launch:** 8,400,000 PSRE (team + treasury; emission reserve is locked)

---

## 7. Why PSRE Appreciates

PSRE is not a speculative asset whose price is based on hype. Its appreciation is driven by two structural forces:

### Force 1: Scarcity
The 21M supply cap is absolute. 60% is locked in the emission reserve and released only gradually, with the emission rate declining over time. Long-run supply is profoundly deflationary.

### Force 2: Demand from Real Commerce
Partners must **buy PSRE from the open market** to fund their customer reward programs. Every new partner that joins, every new customer that receives PSRE, every purchase made through a participating brand — all of it creates real, sustained buying pressure.

Unlike speculative tokens, this demand is based on business operations. Brands buy PSRE because they need it to run their loyalty program.

**Net deflationary mechanics:** For every 100 PSRE a partner distributes to customers, only a small amount of new supply is emitted as their reward — and that reward re-enters customer wallets, not the open market.

---

## 8. The Commerce Flywheel

```
More Partners join
        ↓
More customers receive PSRE rewards
        ↓
More PSRE held across the ecosystem
        ↓
Higher demand → PSRE price appreciation
        ↓
PSRE rewards become more valuable to customers
        ↓
Better loyalty program → more customer retention for partners
        ↓
Partners earn more PSRE back from the protocol
        ↓
Appreciation attracts more Partners
        ↑___________________________________|
```

Each rotation of this flywheel adds more real commerce activity to the protocol, removes more PSRE from circulation, and increases the value of every PSRE held by customers.

---

## 9. Launch Policy: No Presale, No ICO

Prospereum launched with a simple, fair principle: **everyone gets in at the same price.**

- ❌ No pre-sale
- ❌ No private token sale
- ❌ No ICO
- ❌ No discounted insider allocation
- ✅ Public DEX launch at $0.10 with $40,000 genesis liquidity

On day one of public trading, no insider held liquid tokens — founder tokens vest over four years and the emission reserve is locked until earned through commerce.

---

## 10. Team Vesting: Aligned for the Long Term

The 4,200,000 PSRE team allocation is locked in a **Sablier streaming contract**:

- **1-year cliff:** No tokens released for the first 12 months
- **4-year linear vesting:** Tokens released smoothly over 48 months
- **Smart contract enforced:** Cannot be accelerated, overridden, or modified

Founders cannot accelerate their vesting. Anyone can verify the lock on-chain.

---

## 11. Technical Architecture

Prospereum is built on **Base** — Ethereum's leading Layer 2, offering low fees, fast finality, and full EVM compatibility.

The protocol consists of six smart contracts:

| Contract | Role |
|----------|------|
| **PSRE Token** | ERC-20 token with hard-capped supply and epoch-rate-limited minting |
| **PartnerVaultFactory** | Creates PartnerVaults for incoming partners via initial USDC→PSRE swap |
| **PartnerVault** | Manages a partner's ecosystem balance and CustomerVault registry |
| **CustomerVault** | Lightweight wallet for each customer, linked to their partner's ecosystem |
| **StakingVault** | Manages PSRE staking for protocol reward sharing |
| **RewardEngine** | Calculates and distributes epoch rewards. UUPS upgradeable with 7-day timelock. |

**Mainnet contract addresses (Base, April 2026):**

| Contract | Address |
|----------|---------|
| PSRE | `0x2fE08f304f1Af799Bc29E3D4E210973291d96702` |
| PartnerVaultFactory | `0xFF84408633f79b8f562314cC5A3bCaedA8f76902` |
| StakingVault | `0x684BEA07e979CB5925d546b2E2099aA1c632ED2D` |
| RewardEngine | `0x9Ab37Fc6D01B85491Ed0863B7F832784bE717EF5` |

All contracts are:
- **Audited** by BlockApex before mainnet deployment
- **Non-upgradeable** in their core monetary logic (RewardEngine upgradeable only with 7-day timelock)
- **Transparent** — all state is publicly verifiable on-chain

The protocol operates in **7-day epochs**. Every seven days, the RewardEngine evaluates all partner ecosystems, calculates earned rewards, and distributes them. No human intervention is required.

---

## 12. Security

Prospereum was independently audited by **BlockApex** before mainnet launch.

- **Audit period:** April 2–17, 2026
- **Findings:** 29 total across two audit phases
- **Resolution:** All 29 findings resolved before deployment
- **Report:** https://github.com/BlockApex/Audit-Reports/blob/master/Prospereum%20Protocol_Final%20Audit%20Report.pdf

The protocol uses a 2-of-3 Gnosis Safe multisig for governance operations, with a 7-day timelock on any protocol upgrades.

---

## 13. Governance

Prospereum governance is structured for both security and decentralization:

**Operational governance (current):** A 2-of-3 multisig (Gnosis Safe) held by the founding team controls protocol parameters. All parameter changes are timelocked by 48 hours. Upgrade proposals for the RewardEngine require a 7-day timelock.

**What can be adjusted:**
- Base reward rate (within defined bounds)
- Partner tier thresholds
- Reward pool allocation
- Weekly emission ceiling (within bounds)
- Minimum partner entry requirement

**What can never be changed:**
- The 21,000,000 PSRE maximum supply
- The 12,600,000 emission reserve
- The scarcity function structure
- The rule that new PSRE can only be minted through Proof of Prosperity

---

## 14. Staking Rewards

Prospereum distributes 30% of each epoch's emission to **PSRE stakers**:

- **PSRE Stakers** lock their tokens in the StakingVault and earn a share of epoch rewards
- Staking is **passive** — stake once and rewards accrue automatically, no ongoing interaction required
- Rewards are proportional to the amount staked and duration held
- Flash staking is structurally ineffective; sustained participation is rewarded

---

## 15. Use Cases

**For DTC Brands and Ecommerce Merchants:**
- Replace points programs with an appreciating digital asset
- Differentiate your loyalty program with something customers actually want to hold
- Earn protocol rewards when your customer base grows
- No blockchain expertise required

**For Investors:**
- Fixed 21M supply with 60% locked in emission reserve
- Demand driven by real commerce, not speculation
- Fair launch — no insider advantage at genesis

**For Crypto Community:**
- Stake PSRE to earn protocol rewards
- Transparent, audited, immutable core mechanics

---

## 16. Summary

| Property | Prospereum |
|----------|-----------|
| **Status** | Live on Base mainnet (April 22, 2026) |
| **Supply** | 21,000,000 — fixed forever |
| **Emission** | Demand-gated + scarcity-capped |
| **Demand** | Real commerce buying from brand partners |
| **Launch** | Fair — no presale, no ICO, $0.10 public launch |
| **Team** | Locked — 4-year vest, 1-year cliff, Sablier contract |
| **Chain** | Base (Ethereum L2, chain ID 8453) |
| **Security** | Audited by BlockApex — all findings resolved |
| **Governance** | Multisig (Gnosis Safe, 2-of-3) + governance timelocks |

---

## Call to Action

### For Brand Partners
If you run an ecommerce brand or DTC business and spend money on loyalty programs — Prospereum is built for you.

> **Contact:** partnerships@prospereum.io | prospereum.io/partners

### For Investors
PSRE is live on Base. The team is locked for four years. The emission reserve is locked until earned through commerce.

> **Trade PSRE on Base:** Uniswap v3, PSRE/USDC pool

### For the Community
Stake PSRE. Help build the commerce rewards layer that the internet deserves.

> **Learn more:** prospereum.io | Discord: discord.gg/prospereum

---

## Legal Disclaimer

This document is a public whitepaper intended for informational purposes only. It does not constitute financial advice, an offer to sell securities, or a solicitation of investment. PSRE is a utility token used within the Prospereum protocol ecosystem. Cryptocurrency investments involve significant risk, including loss of principal. Please consult qualified legal and financial advisors before making investment decisions. The Prospereum protocol is governed by its smart contracts; this document describes protocol mechanics in accessible language — the on-chain contracts are the authoritative source of truth.

---

*Prospereum (PSRE) — Proof of Prosperity: The Commerce Rewards Protocol*
*Public Whitepaper v3.4 — April 2026*
*All core protocol mechanics governed by immutable smart contracts on Base.*
