# DRAFT v3.0 — FOR REVIEW BY JASON AND SHU BEFORE IMPLEMENTATION
# Do not implement until explicitly approved.

---

# Prospereum — Whitepaper v3.0

---

PROSPEREUM Protocol (PSRE)
Proof of Net Retention
White Paper v3.0 (March 2026)

---

## 1. Abstract

Prospereum is a decentralized behavioral mining protocol that aligns economic demand with
progressive scarcity.

Unlike Proof-of-Work (Bitcoin) or Proof-of-Stake (Ethereum), Prospereum introduces:

**Proof of Net Retention**

Token issuance is unlocked only when provable, sustained on-chain demand for PSRE is
generated — measured not by gross purchasing activity but by net retention of PSRE within
the partner's ecosystem over time. Issuance is permanently constrained by an asymptotic
scarcity function tied solely to emitted supply.

Prospereum is neutral infrastructure built for commerce rewards. It does not encode moral
judgment. Partners — ecommerce brands and DTC merchants — define aligned economic
activity by distributing PSRE to their customers as purchase rewards. The protocol measures
only net retained PSRE across the partner's vault ecosystem and time-weighted participation.

Wash trading is rendered economically impossible: any PSRE bought and immediately sold
produces zero net retention, zero reward, and a net loss equal to transaction costs plus the
non-refundable registration fee.

---

## 2. Vision

Bitcoin demonstrated decentralized scarcity.
Ethereum demonstrated programmable coordination.
Prospereum unifies both principles:

- Scarcity discipline
- Behavioral alignment

It is designed to:

- Reward real economic contribution — partners who genuinely distribute PSRE to customers
- Prevent inflationary farming and wash trading
- Eliminate discretionary mint authority
- Transition naturally from growth incentives to scarcity dominance

---

## 3. Supply Model

### 3.1 Total Supply

$$S_{total} = 21{,}000{,}000 \text{ PSRE}$$

This supply is immutable.

### 3.2 Allocation

| Category | % | Amount | Comments |
|---|---|---|---|
| Behavioral Mining Emission Reserve | 60% | 12,600,000 | Not minted at genesis; reserved for future emission |
| Team & Founders | 20% | 4,200,000 | Minted at genesis to a vesting contract |
| Ecosystem Growth | 8% | 1,680,000 | Minted at genesis to Treasury Wallet (SAFE) |
| DAO Treasury | 7% | 1,470,000 | Minted at genesis to Treasury Wallet (SAFE) |
| Bootstrap Liquidity | 5% | 1,050,000 | Minted at genesis to Treasury Wallet (SAFE) |

### 3.3 Team Vesting

- 1-year cliff
- 4-year linear vesting
- Locked at genesis via Sablier streaming contract
- No governance override

### 3.4 Treasury Purpose

DAO Treasury is reserved for:

- Liquidity stabilization
- Audit funding
- Infrastructure support
- Ecosystem expansion

Treasury cannot mint additional tokens.

---

## 4. Launch Policy

- No pre-sale
- No private token sale
- No ICO
- No discounted insider allocation

Liquidity seeded solely from treasury allocation.
Behavioral mining begins only after first full epoch.

---

## 5. Partner Ecosystem Architecture

### 5.1 What a Partner Is

A **partner** is an ecommerce brand or DTC merchant that participates in Prospereum's
commerce rewards infrastructure. Instead of offering customers a percentage discount at
checkout, the partner purchases PSRE and distributes it to customers as on-chain purchase
rewards.

From the customer's perspective, this is seamless: they receive "X PSRE rewards" credited in
the partner's app or storefront. Customers do not need to interact with the blockchain directly.
The partner's ecommerce backend (or Midas integration layer) handles all on-chain
interactions on their behalf.

### 5.2 PartnerVault

Each partner holds a single **PartnerVault** — a dedicated smart contract that serves as the
partner's on-chain identity for reward accounting. The PartnerVault:

- Receives USDC from the partner's backend and executes PSRE purchases via a DEX
- Tracks the partner's net retained PSRE balance across its ecosystem
- Maintains a registry of linked CustomerVaults
- Is the canonical accounting boundary for reward calculations

### 5.3 CustomerVault

For each customer who receives rewards, the partner deploys a lightweight **CustomerVault**
contract. Key properties:

- The partner pays all gas costs for CustomerVault deployment and operation
- The CustomerVault is registered to (linked with) the parent PartnerVault at creation
- PSRE held in registered CustomerVaults counts toward the partner's net retention score
- Customers interact with their rewards through the partner's app UI, not the blockchain directly
- A CustomerVault can be claimed by the customer at any time by asserting their wallet address

This architecture makes Prospereum **blockchain-agnostic for end customers** while
preserving full on-chain verifiability for the protocol.

### 5.4 Vault Lifecycle and Anti-Spam Controls

To prevent vault spam and maintain registry integrity, the following lifecycle rules apply:

**Registration Fee**
A non-refundable fee of approximately $50 USDC equivalent is paid to the protocol treasury
at PartnerVault creation. This discourages throwaway vault creation.

**Vault Bond**
Partners must post a **$500 USDC bond** to create a PartnerVault. The bond is held in
escrow by the factory contract and returned upon proper deregistration. This ensures
skin-in-the-game and prevents trivial registration/deregistration cycling.

*Rationale:* A PSRE-denominated bond would become prohibitively expensive for legitimate
partners as PSRE appreciates in value over time. A fixed USDC denomination maintains
consistent deterrence value regardless of PSRE price, and avoids the need for a price oracle
for bond valuation.

**Minimum Activity**
A PartnerVault must generate at least $50 USDC equivalent in buy activity per epoch to
remain in active status. Vaults below this threshold are considered inactive for that epoch.

**Vault Expiry**
PartnerVaults with zero qualifying activity for 4 consecutive epochs are automatically marked
inactive, freeing their slot. The vault bond remains claimable by the partner upon
deregistration.

---

## 6. Behavioral Mining — Proof of Net Retention

### 6.1 Overview

Each partner participates in the Prospereum protocol by maintaining a PartnerVault and a
network of linked CustomerVaults. The protocol rewards partners based on how much PSRE
they retain within their vault ecosystem, weighted by time.

This is the core shift from v2.x: rewards are no longer based on **gross buying activity** but
on **net retained PSRE** — the amount of PSRE that stays within the partner's ecosystem
(partner vault + customer vaults) after accounting for any PSRE that leaves to unregistered
addresses (DEX sales, external wallet transfers).

**Wash trading is structurally impossible under this model:**
- A wash trader buys PSRE through their vault, then sells it to a DEX
- The PSRE leaving to an unregistered address is counted as "leaked"
- Net retention = purchased − leaked ≈ 0
- Reward = 0
- The attacker's only outcome is a loss equal to trading costs plus registration fee

**Real partners are unaffected:**
- Partner buys PSRE, distributes to registered CustomerVaults
- All distributed PSRE remains within the registered vault ecosystem
- Net retention stays high
- Reward is positive and proportional to retained value × time held

### 6.2 Epoch

The protocol operates in discrete time intervals called **epochs**.

$$T_{epoch} = 7 \text{ days}$$

All mining activity and rewards are calculated and emitted once per epoch.

### 6.3 Net Retained PSRE

Let $NR_p(t)$ be the net retained PSRE for partner $p$ at epoch $t$, defined as:

$$NR_p(t) = \text{PSRE in PartnerVault}_p + \sum_{cv \in \text{registered}(p)} \text{PSRE in } cv - \text{cumulative PSRE leaked to unregistered addresses}$$

Where "leaked" PSRE means PSRE transferred from any vault in $p$'s ecosystem to an address
that is not a registered vault (i.e., sent to a DEX, an external EOA, or any unregistered
contract).

### 6.4 Time-Weighted Retention Score

To reward not just the amount retained but the duration of retention, the protocol computes a
time-weighted retention score:

$$TWR_p(t) = \int_{t-1}^{t} NR_p(\tau)\, d\tau$$

In discrete implementation:

$$TWR_p(t) = \sum_i NR_p(\tau_i) \cdot \Delta\tau_i$$

where $\tau_i$ are checkpoints within the epoch (triggered by vault activity events) and
$\Delta\tau_i$ is the duration between checkpoints.

This mirrors the time-weighted stake model used for stakers, ensuring that holding PSRE
longer within an epoch produces a higher retention score.

### 6.5 Total Retention Budget

Total time-weighted retention across all active partners:

$$TWR_{total}(t) = \sum_p TWR_p(t)$$

### 6.6 Demand-Based Emission Limit

The demand-based emission limit is driven by the **net increase** in total time-weighted
retention across all partners relative to the previous epoch:

$$E_{demand}(t) = \max\left(0,\ r_{base} \times \frac{TWR_{total}(t) - TWR_{total}(t-1)}{T_{epoch}}\right)$$

where $r_{base}$ is the base reward rate (default 10%, DAO-adjustable within bounds).

*Rationale:* This formula measures the net increase in time-weighted retention per epoch,
not the absolute level. It rewards new buying **and** sustained holding that expands the total
retention base, while applying zero reward (not negative) when ecosystem retention decreases.
Partners who simply maintain their existing holdings produce a positive $\Delta TWR$ (since
$TWR_p(t) = NR_p \times T_{epoch}$ for a constant hold). Partners who buy more or attract new
customers increase their $\Delta TWR$ further.

This ensures that emission scales with genuine, sustained demand growth — not transient buy
pressure or static position holding that doesn't reflect new ecosystem participation.

### 6.7 Scarcity-Based Emission Limit

To enforce long-term scarcity, emission is also limited by the remaining emission reserve.

Let:

$$S_{emission} = 12{,}600{,}000 \text{ PSRE} \quad \text{(total emission reserve)}$$

$$x(t) = \frac{T(t)}{S_{emission}}$$

where $T(t)$ is the cumulative PSRE already emitted. The scarcity-based emission cap is:

$$E_{scarcity}(t) = E_0 \cdot (1 - x(t))^k$$

where:

- $E_0$ = initial weekly emission ceiling (default: 0.1% of $S_{emission}$, i.e., 12,600 PSRE/week)
- $k$ = scarcity exponent (default: 2, immutable)

As the reserve is depleted, emission decreases smoothly toward zero.

### 6.8 Final Emission Budget

$$B(t) = \min\left(E_{demand}(t),\ E_{scarcity}(t),\ S_{emission} - T(t)\right)$$

---

## 7. Individual Reward Calculation

### 7.1 Budget Split

The total emission budget for epoch $t$ is divided into two pools:

$$B_{partners}(t) = 0.70 \times B(t)$$

$$B_{stakers}(t) = 0.30 \times B(t)$$

### 7.2 Partner Status — Rolling Behavioral Mining Performance

The protocol maintains a rolling contribution score for each partner based on their
time-weighted retention:

$$R_p(t) = (1 - \theta) \cdot R_p(t-1) + \theta \cdot TWR_p(t)$$

where:

$$\theta = \frac{1}{13} \approx 0.0769 \quad \text{(13-epoch exponential moving average} \approx \text{one calendar quarter)}$$

The partner's percentage share of ecosystem contribution is:

$$s_p(t) = \frac{R_p(t)}{\sum_q R_q(t)}$$

Based on this share, the partner is assigned a tier:

| Tier | Contribution Share |
|---|---|
| Bronze | $s_p < s_{silver}$ |
| Silver | $s_{silver} \leq s_p < s_{gold}$ |
| Gold | $s_p \geq s_{gold}$ |

Default thresholds:

$$s_{silver} = 0.005 \quad (0.5\%), \qquad s_{gold} = 0.020 \quad (2.0\%)$$

### 7.3 Tier Reward Rate

| Tier | Reward Rate |
|---|---|
| Bronze | 8% |
| Silver | 10% |
| Gold | 12% |

If total raw rewards demanded by partners exceed the protocol's emission budget for that
epoch, reward rates are proportionally scaled down so that total rewards remain within the
allowed emission.

### 7.4 Partner Reward Calculation

Let $r_p(t)$ be the reward rate assigned to partner $p$ in epoch $t$.

Raw reward entitlement (based on time-weighted retention):

$$\text{Reward}_{p,\text{raw}}(t) = r_p(t) \times TWR_p(t)$$

Total reward demand:

$$D(t) = \sum_p \text{Reward}_{p,\text{raw}}(t)$$

If $D(t) \leq B_{partners}(t)$, partners receive the full reward.

If $D(t) > B_{partners}(t)$, rewards are scaled proportionally:

$$\lambda = \frac{B_{partners}(t)}{D(t)}, \qquad \text{Reward}_p(t) = \lambda \times \text{Reward}_{p,\text{raw}}(t)$$

### 7.5 Reward Vesting

To prevent hit-and-run participation, partner rewards are subject to a **4-epoch vesting
schedule** before they become claimable.

Rewards earned in epoch $t$ are released linearly across epochs $t+1$ through $t+4$ (25% per
epoch). Once a partner has been active for 4+ epochs, rewards vest continuously — new
tranches unlock each epoch, providing a smooth and predictable reward stream for genuine
long-term partners.

This vesting period eliminates the profitability of single-epoch wash trading: an attacker who
spends gas and fees to achieve artificially high retention for one epoch cannot exit before the
vesting period expires, and sustained wash trading produces net retention ≈ 0 by design.

### 7.6 Staker and Liquidity Provider (LP) Rewards

Participants may earn rewards from the staking pool by locking PSRE tokens or providing
liquidity. Two forms of staking are supported:

**PSRE Staking**
Users lock PSRE tokens in the staking contract for a minimum duration. This reduces
circulating supply and aligns long-term participants with the protocol.

**Liquidity Provider Staking**
Users who provide liquidity to PSRE trading pools may stake their LP tokens to earn rewards.
This encourages deeper market liquidity and lower trading slippage.

Both forms of staking share the same reward pool and are treated equivalently with no
weighting multiplier. Rewards are distributed according to time-weighted stake:

$$\text{StakeTime}_p(t) = \int_{t-1}^{t} S_p(\tau)\, d\tau$$

$$\text{TotalStakeTime}(t) = \sum_p \text{StakeTime}_p(t)$$

$$\text{Reward}_{staker,p}(t) = B_{stakers}(t) \times \frac{\text{StakeTime}_p(t)}{\text{TotalStakeTime}(t)}$$

---

## 8. Anti-Wash-Trading Design

Prospereum v3.0 introduces a multi-layered defense against wash trading and reward
manipulation:

### 8.1 Net Retention Accounting

The fundamental change: rewards are based on PSRE that **stays** in the ecosystem, not
PSRE that passes through it. Any PSRE that exits to an unregistered address is subtracted
from the retention score. A zero-retention partner earns zero reward regardless of buy volume.

### 8.2 Registered Vault Ecosystem

PSRE distributed to registered CustomerVaults remains "in ecosystem" and contributes to
retention. This design means partners can freely distribute rewards to customers without
penalty — as intended — while preventing leakage to DEXes or unregistered addresses.

### 8.3 Reward Vesting (4 Epochs)

Rewards cannot be claimed until 4 epochs after earning. This eliminates the profitability of
any strategy that requires extracting rewards quickly after a wash-trade burst.

### 8.4 Vault Bond

The **$500 USDC bond** required to create a PartnerVault creates a meaningful economic cost
for attackers attempting to create disposable vaults. The bond is returned only on legitimate
deregistration (paid to the factory contract), not on vault abandonment.

### 8.5 Registration Fee

The ~$50 USDC non-refundable registration fee ensures each vault represents a deliberate,
committed partner — not a throwaway attack surface.

### 8.6 Vault Expiry

Inactive vaults are automatically expired after 4 consecutive epochs of zero activity, keeping
the registry clean and preventing ghost vaults from accumulating any historical advantage.

### 8.7 Minimum Activity Threshold

The $50 USDC minimum activity per epoch prevents micro-activity spam from generating
legitimate vault status without meaningful participation.

---

## 9. Governance

The Prospereum protocol is governed by a decentralized autonomous organization (DAO)
responsible for maintaining operational parameters while preserving the protocol's core
monetary policy.

### 9.1 Adjustable Parameters

**Base Reward Rate**

$$0.05 \leq \alpha_{base} \leq 0.15$$

**Partner Tier Thresholds**
Contribution-share thresholds for Bronze/Silver/Gold may be adjusted within bounds.

**Reward Pool Allocation**
Default: 70% partners / 30% stakers. DAO may adjust within:

$$60\% \leq B_{partners} \leq 80\%, \qquad 20\% \leq B_{stakers} \leq 40\%$$

**Initial Weekly Emission Ceiling**

$$0.0005 \times S_{emission} \leq E_0 \leq 0.002 \times S_{emission}$$

For PSRE: lower bound ≈ 6,300 PSRE/week; upper bound ≈ 25,200 PSRE/week.

**Vault Bond Amount**
DAO may adjust the vault bond requirement within predefined bounds (denominated in USDC).

**Minimum Activity Threshold**
DAO may adjust the minimum epoch activity threshold for active vault status.

### 9.2 Non-Modifiable Parameters

The following are permanently fixed and cannot be modified by governance:

| Parameter | Value |
|---|---|
| Maximum Supply | $S_{total} = 21{,}000{,}000$ |
| Emission Reserve | $S_{emission} = 12{,}600{,}000$ |
| Scarcity Function Form | $E_{scarcity}(t) = E_0 \cdot (1 - x(t))^k$ |
| Scarcity Exponent | $k = 2$ |
| Minting Rule | $B(t) = \min(E_{demand},\ E_{scarcity},\ S_{emission} - T)$ |

The DAO cannot mint tokens outside the minting rule.

### 9.3 Monetary Policy Integrity

The immutable supply cap, scarcity function, and emission reserve ensure that Prospereum's
monetary policy remains predictable and resistant to discretionary inflation. Governance is
limited to adjusting operational parameters while the fundamental token issuance model
remains fixed.

---

## 10. Why the Reward Mechanism is Non-Inflationary

A common question about behavioral mining protocols is whether reward emission creates
inflationary pressure on the token. The Prospereum design is specifically constructed to be
non-inflationary in both supply and circulating terms. Here is why.

### 10.1 The Scarcity Cap is Always the Binding Constraint

The actual emission in any epoch is bounded by:

$$B(t) = \min\left(E_{demand}(t),\ E_{scarcity}(t),\ S_{emission} - T(t)\right)$$

The scarcity cap $E_{scarcity}(t) = E_0 \cdot (1 - x(t))^2$ is always active and declines
monotonically as $x(t)$ increases. At genesis, the maximum possible emission is:

$$E_{scarcity}(0) = E_0 = 0.001 \times S_{emission} = 12{,}600 \text{ PSRE/week}$$

This ceiling declines toward zero as the emission reserve is consumed. Regardless of how much
demand partners generate, emission **cannot exceed this ceiling**. Total emission over the
protocol's entire lifetime is absolutely bounded at:

$$\sum_{t=0}^{\infty} B(t) \leq S_{emission} = 12{,}600{,}000 \text{ PSRE}$$

### 10.2 Partner Buying Creates Net Deflationary Pressure on Circulating Supply

Partners must purchase PSRE from the open market to increase their vault balance and earn
rewards. For every 100 PSRE a partner buys and holds in the vault ecosystem:

- **100 PSRE is removed from circulating supply** (bought from market, locked in vault)
- **Only ~10 PSRE of new supply is emitted as reward** (at $r_{base} = 10\%$ applied to the TWR delta)
- That reward PSRE **also enters the vault** — it is distributed to CustomerVaults, not sold

The net circulating supply effect per epoch of partner buying is approximately **−90%**: for
every 100 PSRE worth of buying pressure, only ~10 PSRE of new supply is created, and both
the purchased PSRE and the reward enter the vault ecosystem rather than circulating.

### 10.3 Reward PSRE Does Not Circulate

Reward PSRE minted by the RewardEngine is deposited into the PartnerVault and distributed
to registered CustomerVaults. It does not enter the open market. It only becomes potentially
circulating if a customer explicitly withdraws their CustomerVault balance to an external
address — and that withdrawal is tracked as **leakage**, reducing the partner's future
retention score. This creates a strong economic disincentive for partners to allow or encourage
customer withdrawals.

### 10.4 Absolute Supply Cap

Total emission over the protocol's lifetime cannot exceed $S_{emission} = 12{,}600{,}000$ PSRE
by construction of the minting rule. The DAO cannot mint additional PSRE, cannot override the
scarcity function, and cannot increase $S_{emission}$.

### 10.5 Compounding Rewards are Intentional

The reward PSRE that enters a vault increases the vault's $NR_p$ balance. This higher balance
produces a higher $TWR_p$ in subsequent epochs, which increases the vault's share of future
rewards. This compounding is intentional — it is the mechanism by which long-term
participants are rewarded for sustained holding. It does not create supply inflation because the
compounded rewards remain locked in the vault ecosystem and the scarcity cap is unaffected
by vault balances.

---

## 11. Conclusion

Prospereum v3.0 introduces **Proof of Net Retention** — a behavioral mining primitive that
rewards genuine, sustained economic participation while making exploitative strategies
structurally unprofitable.

Prospereum is:

**Demand-Bounded ∩ Scarcity-Controlled ∩ Retention-Verified ∩ Governance-Limited**

It bridges Bitcoin's scarcity discipline with Ethereum's programmable ecosystem model, and
extends both with a commerce-native reward layer that aligns the interests of ecommerce
brands, their customers, and the protocol's long-term sustainability.
