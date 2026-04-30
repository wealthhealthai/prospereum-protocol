# Prospereum Whitepaper v3.4

**Status:** LIVE on Base Mainnet (April 22, 2026)
**Audited by:** BlockApex — all findings resolved
**Supersedes:** v3.2 (March 2026)

---

PROSPEREUM Protocol (PSRE) — Proof of Prosperity
White Paper v3.4 (April 2026)

---

## 1. Abstract

Prospereum is a decentralized behavioral mining protocol that aligns economic demand with progressive scarcity.

Unlike Proof-of-Work (Bitcoin) or Proof-of-Stake (Ethereum), Prospereum introduces:

**Proof of Prosperity**

Token issuance is unlocked only when provable, sustained on-chain demand for PSRE is generated — measured not by gross purchasing activity or time-weighted retention levels, but by **cumulative net growth** in ecosystem PSRE holdings. Issuance is permanently constrained by an asymptotic scarcity function tied solely to emitted supply.

Prospereum is neutral infrastructure built for commerce rewards. It does not encode moral judgment. Partners — for example, ecommerce brands and DTC merchants — define aligned economic activity by distributing PSRE to their customers as purchase rewards. The protocol measures only cumulative net growth in retained PSRE across the partner's vault ecosystem.

Wash trading is rendered economically impossible: any PSRE bought and then sold resets progress toward the cumulative high-water-mark without reducing it. To earn any reward after selling, an attacker must rebuy past their previous peak — permanently committing more capital with each cycle. This is self-limiting by construction.

**Prospereum is live on Base mainnet as of April 22, 2026.** The protocol was independently audited by BlockApex (April 2026) with all 29 findings resolved before launch.

---

## 2. Vision

Bitcoin demonstrated decentralized scarcity. Ethereum demonstrated programmable coordination. Prospereum unifies both principles:

- Scarcity discipline
- Behavioral alignment

It is designed to:

- Reward real economic contribution — partners who genuinely grow their PSRE ecosystem
- Prevent inflationary farming and wash trading through structural, not punitive, mechanisms
- Eliminate discretionary mint authority
- Transition naturally from growth incentives to scarcity dominance

---

## 3. Supply Model

### 3.1 Total Supply

$$S_{total} = 21{,}000{,}000\text{ PSRE}$$

This supply is hard-coded and immutable.

### 3.2 Allocation

| Category | Amount | Notes |
|----------|--------|-------|
| Behavioral Mining Emission Reserve | 12,600,000 (60%) | Not minted at genesis; emitted by RewardEngine over epochs |
| Team & Founders | 4,200,000 (20%) | Minted at genesis to Founder Safe; 4-year Sablier vesting, 1-year cliff |
| Treasury | 4,200,000 (20%) | Minted at genesis to Treasury Safe; used for genesis LP seeding, ecosystem growth, and infrastructure |

Only 8,400,000 PSRE exists at genesis. The remaining 12,600,000 is minted gradually by the RewardEngine as partners generate genuine ecosystem growth. The emission rate decreases asymptotically to zero as the reserve depletes.

### 3.3 Team Vesting

- 1-year cliff
- 4-year linear vesting via Sablier streaming contract
- Held in Founder Safe (`0xc59816CAC94A969E50EdFf7CF49ce727aec1489F`)
- No governance override

### 3.4 Treasury Purpose

Treasury Safe (`0xa9Fde837EBC15BEE101d0D895c41a296Ac2CAfCe`) is reserved for:

- Genesis liquidity seeding (200K PSRE + $20K USDC, Uniswap v3, 1% fee)
- Protocol infrastructure and audits
- Ecosystem grants and partner development
- Emergency liquidity support

Treasury cannot mint additional tokens.

---

## 4. Launch Policy

- No pre-sale
- No private token sale
- No ICO
- No discounted insider allocation

Liquidity seeded solely from treasury allocation. Behavioral mining begins after epoch 0 closes (~7 days post-launch).

---

## 5. Partner Ecosystem Architecture

### 5.1 What a Partner Is

A **partner** is, for example, an ecommerce brand or DTC merchant that participates in Prospereum's commerce rewards infrastructure. Instead of offering customers a percentage discount at checkout, the partner purchases PSRE and distributes it to customers as on-chain purchase rewards.

From the customer's perspective, this is seamless: they receive "X PSRE rewards" credited in the partner's app or storefront. Customers do not need to interact with the blockchain directly. The partner's ecommerce backend (or an integration layer) handles all on-chain interactions on their behalf.

### 5.2 PartnerVault

Each partner holds a single **PartnerVault** — a dedicated smart contract that serves as the partner's on-chain identity for reward accounting. The PartnerVault:

- Receives USDC from the partner's backend and executes PSRE purchases via Uniswap v3
- Tracks the partner's cumulative high-water-mark balance ($\text{cumS}_p$) across its entire vault ecosystem
- Maintains a registry of linked CustomerVaults
- Calls `autoFinalizeEpochs()` on every `buy()` — the protocol self-maintains without requiring a dedicated keeper

**cumS accounting (v3.3):** The cumS high-water-mark only advances through tracked `buy()` flows. Direct ERC-20 transfers to the vault do not affect cumS. This closes a flash-loan manipulation vector identified during the BlockApex security audit: an attacker cannot borrow PSRE, transfer it to a vault, spike cumS, and withdraw — the ratchet only responds to committed, tracked flows.

### 5.3 CustomerVault

For each customer who receives rewards, the partner deploys a lightweight **CustomerVault** contract. Key properties:

- The partner pays all gas costs for CustomerVault deployment and operation
- The CustomerVault is registered to (linked with) the parent PartnerVault at creation
- PSRE held in registered CustomerVaults counts toward the partner's ecosystem balance $S_{eco}$
- Customers interact with their rewards through the partner's app UI
- A CustomerVault can be claimed by the customer at any time by asserting their wallet address

This architecture makes Prospereum **blockchain-agnostic for end customers** while preserving full on-chain verifiability for the protocol.

### 5.4 Vault Lifecycle and Anti-Spam Controls

**Minimum Initial Buy (Entry Cost):** Partners must make an initial PSRE purchase of at least $S_{\min}$ = $500 USDC at vault creation. This earns zero reward — it establishes the baseline. The fee tier used for the USDC→PSRE swap must be from a whitelist of standard Uniswap tiers, and a minimum output floor is enforced to prevent sandwich attacks.

**cumS Permanence:** $\text{cumS}_p$ is permanently tied to the vault's address and never resets. If a partner deregisters and creates a new vault, the new vault starts at cumS = 0.

---

## 6. Behavioral Mining — Proof of Prosperity

### 6.1 Overview

Each partner participates in the Prospereum protocol by maintaining a PartnerVault and a network of linked CustomerVaults (the "partner ecosystem"). The protocol rewards partners based on cumulative net growth in their vault ecosystem's PSRE holdings.

Rewards are based not on gross buying activity, not on absolute holdings, and not on time-weighted retention levels — but on **cumulative high-water-mark growth**. A partner earns reward only when the partner ecosystem balance grows past all prior peaks.

**The ratchet property:** $\text{cumS}_p$ can only increase. If the ecosystem balance drops because customers sell or withdraw PSRE outside the partner ecosystem — the high-water-mark stays at the prior peak. The partner earns nothing until the ecosystem grows past that peak again.

**Wash trading is structurally impossible:**
- Attacker buys PSRE (cumS rises), sells (balance drops, cumS stays at peak)
- To earn any reward, attacker must rebuy past the prior peak — committing more net capital
- Each cycle requires more capital than the last — self-limiting by construction
- The initial buy earns zero reward — the first cycle pays irrecoverable costs with no return

### 6.2 Epoch

The protocol operates in discrete weekly intervals:

$$T_{epoch} = 7\text{ days}$$

All mining activity and rewards are calculated and emitted once per epoch. Epochs finalize lazily — any partner `buy()` or vault creation triggers `autoFinalizeEpochs()`, which finalizes up to 10 pending epochs in one transaction.

### 6.3 Ecosystem Balance

$$S_{eco,p}(t) = \text{PSRE in PartnerVault}_p + \sum_{cv \in \text{registered}(p)} \text{PSRE in }cv$$

PSRE transferred to unregistered addresses is excluded from $S_{eco}$.

**Tracking:** $S_{eco}$ is maintained as an explicit ledger (`ecosystemBalance`) incremented by `buy()` and decremented by `transferOut()` and `reportLeakage()`. The protocol no longer reads live token balances (`balanceOf`) for cumS purposes — only tracked flows count.

### 6.4 Cumulative High-Water-Mark

$$\text{cumS}_p(t) = \max\left(S_{eco,p}(t),\ \text{cumS}_p(t-1)\right)$$

At vault creation (epoch $N$):
$$\text{cumS}_p(N) = S_p(N) = \text{initial buy amount}$$

### 6.5 Reward Calculation and the effectiveCumS Deduction

To ensure that protocol-minted reward PSRE does not itself generate future rewards:

$$\text{effectiveCumS}_p(t) = \text{cumS}_p(t) - \text{cumulativeRewardMinted}_p(t)$$

Per-epoch reward demand:

$$\text{reward}_p(t) = \max\left(0,\ r_{base} \times (\text{effectiveCumS}_p(t) - \text{effectiveCumS}_p(t-1))\right)$$

If the ecosystem did not grow past its prior effectiveCumS peak in epoch $t$, the reward is zero.

### 6.6 First Qualification Condition

The initial buy earns zero reward. The first reward triggers only when:

$$\text{cumS}_p(M) > S_p(N) \quad \text{for some epoch } M > N$$

First reward:
$$\text{reward}_{p,\text{first}} = r_{base} \times \left(\text{effectiveCumS}_p(M) - S_p(N)\right)$$

### 6.7 Total Ecosystem Demand

$$E_{demand}(t) = r_{base} \times \sum_p \max\left(0,\ \text{effectiveCumS}_p(t) - \text{effectiveCumS}_p(t-1)\right)$$

### 6.8 Scarcity-Based Emission Limit

$$x(t) = \frac{T(t)}{S_{emission}}, \quad E_{scarcity}(t) = E_0 \cdot (1-x(t))^k$$

Where $E_0$ = initial weekly ceiling (default: 12,600 PSRE/week), $k$ = 2 (immutable).

### 6.9 Final Emission Budget

$$B(t) = \min\left(E_{demand}(t),\ E_{scarcity}(t),\ S_{emission} - T(t)\right)$$

---

## 7. Individual Reward Calculation

### 7.1 Budget Split

$$B_{partners}(t) = 0.70 \times B(t)$$
$$B_{stakers}(t) = 0.30 \times B(t)$$

### 7.2 Partner Status — Rolling EMA Tier

$$R_p(t) = (1-\theta) \cdot R_p(t-1) + \theta \cdot \Delta\text{effectiveCumS}_p(t)$$

where $\theta = \frac{1}{13}$ (13-epoch exponential moving average ≈ one calendar quarter).

Partner share:
$$s_p(t) = \frac{R_p(t)}{\sum_q R_q(t)}$$

| Tier | Share Threshold | Reward Multiplier |
|------|----------------|-------------------|
| Bronze | < 0.5% | 0.8× |
| Silver | ≥ 0.5% | 1.0× |
| Gold | ≥ 2.0% | 1.2× |

Tier computation uses a two-pass approach: all EMA scores are updated first, then tiers are assigned using the fully settled denominator. This prevents registration-order advantage.

### 7.3 Partner Reward Calculation

$$\text{partnerReward}_p(t) = B_{partners}(t) \times \frac{R_p(t)}{\sum_q R_q(t)} \times M_{tier_p}$$

Rewards are claimable immediately after epoch finalization — no vesting.

### 7.4 Staker and Liquidity Provider Rewards

PSRE stakers and LP stakers earn from a **shared 30% pool**, divided into two independent sub-pools:

| Pool | Asset | Description |
|------|-------|-------------|
| PSRE Staker Pool | PSRE tokens | For users who stake native PSRE tokens |
| LP Staker Pool | PSRE/USDC LP tokens | For users who provide DEX liquidity (deferred at launch) |

The split between pools is a governance parameter (default: 100% PSRE stakers at launch; LP staking enabled in a future upgrade once an ERC-20 LP wrapper is available).

**Passive accrual (Synthetix model):** Stakers earn rewards continuously without any required interaction. The protocol uses a cumulative reward-per-token accumulator:

1. At each epoch finalization, `distributeStakerRewards()` computes `epochRewardPerToken = pool / totalStaked` and adds it to a global running accumulator
2. When a user claims, their share is computed as `balance × (currentAccumulator - userAccumulatorAtLastUpdate) / precision` — a single O(1) subtraction
3. Users who stake once and never touch their position still earn rewards for every subsequent epoch, automatically

Flash-stake resistance is maintained: a user who stakes mid-epoch and immediately claims earns only the fractional accumulator growth since their stake — they cannot retroactively claim historical epochs.

---

## 8. Design Rationale: Anti-Gaming and Commerce Alignment

### 8.1 Why cumS High-Water-Mark Prevents Wash Trading

The cumS ratchet ensures that any capital sold out of the ecosystem permanently raises the bar for future rewards. Wash trading requires monotonically increasing capital commitment — making it self-defeating over any meaningful time horizon.

### 8.2 Why cumS Only Tracks Committed Flows

Beginning with v3.3, cumS advances only through explicitly tracked `buy()` transactions. Direct ERC-20 token transfers to a vault are not counted. This closes a flash-loan inflation vector: an attacker cannot borrow PSRE, transfer it directly to their vault to spike cumS, and then return the borrowed tokens. The ratchet responds only to capital committed through the protocol's own accounting.

### 8.3 Why the Initial Buy Earns No Reward

The initial buy is the structural entry cost for the partner program. It is irrecoverable (fees, slippage, permanent capital commitment) and earns zero reward, making vault spam economically irrational. A spammer who registers hundreds of vaults pays $500 USDC per vault with zero return on each creation transaction.

For legitimate partners, the initial buy can be distributed to customers as purchase rewards — the capital is not wasted, it is deployed into the partner's commerce reward program.

### 8.4 Why No Vesting Schedule

The first qualification condition (cumS must grow past the initial baseline before earning any reward) is strictly stronger than a vesting delay. Vesting only shifts timing; the first qualification condition requires demonstrated genuine growth. An attacker with a static initial buy earns nothing indefinitely, regardless of patience.

### 8.5 Why Rewards Flow with Growth but Stop When Flat

The reward formula rewards only positive effectiveCumS growth. Flat holdings produce no reward — incentivizing active commerce deployment rather than passive capital parking. Slow seasons produce zero reward but do not reset cumS; rewards resume immediately when growth resumes.

---

## 9. Anti-Wash-Trading Design Summary

| Defense | Mechanism | Strength |
|---------|-----------|---------|
| Cumulative high-water-mark | cumS ratchet — selling raises future bar | Primary — structural |
| Un-rewarded initial buy | First cycle earns zero | Registration deterrent |
| First qualification condition | Growth gate — must exceed baseline | Stronger than vesting |
| Registered vault boundary | cumS only counts tracked flows | Closed flash-loan vector |
| Explicit cumS accounting | Only `buy()` advances cumS | No direct-transfer manipulation |
| Scarcity cap | E_scarcity decreases as T grows | Protocol-level emission limit |
| Passive staking model | Accumulator, not cursor | Closes retroactive claim vectors |

---

## 10. Governance

Prospereum governance operates through two **Gnosis Safes** on Base mainnet, each requiring 2-of-3 signatures.

### 10.1 Founder Safe

- Address: `0xc59816CAC94A969E50EdFf7CF49ce727aec1489F`
- Roles: Admin, Pauser, Upgrader on all protocol contracts
- Holds team allocation (4.2M PSRE under Sablier vesting)

### 10.2 Treasury Safe

- Address: `0xa9Fde837EBC15BEE101d0D895c41a296Ac2CAfCe`
- Holds protocol treasury (4.2M PSRE) and LP position

### 10.3 Adjustable Parameters (Timelocked 48 hours)

| Parameter | Default | Range |
|-----------|---------|-------|
| r_base (alphaBase) | 0.10 (10%) | [5%, 15%] |
| E₀ (weekly scarcity ceiling) | 12,600 PSRE/week | [E₀_MIN, E₀_MAX] |
| Partner/staker split | 70/30 | [50/50, 80/20] |
| Tier thresholds | Silver: 0.5%, Gold: 2% | validated bounds |
| Staker pool split (PSRE/LP) | 100/0 at launch | [0, 100] each |

### 10.4 Non-Modifiable (Immutable)

- Total supply cap: 21,000,000 PSRE
- Emission reserve: 12,600,000 PSRE
- Scarcity exponent k = 2
- EMA factor θ = 1/13
- Epoch duration: 7 days
- Minimum vault creation: $500 USDC
- RewardEngine upgrade: 7-day timelock minimum

### 10.5 RewardEngine Upgradeability

RewardEngine is deployed behind a UUPS proxy with a 7-day upgrade timelock. All upgrades must be queued by the Founder Safe and can only execute 7 days later. This gives the community a 7-day window to review any proposed upgrade. No other contract in the protocol is upgradeable.

---

## 11. Why the Reward Mechanism is Non-Inflationary

The effectiveCumS deduction is the key mechanism:

$$\text{effectiveCumS}_p(t) = \text{cumS}_p(t) - \text{cumulativeRewardMinted}_p(t)$$

Reward PSRE minted into the partner's ecosystem increases cumS — but is exactly cancelled by the growing `cumulativeRewardMinted` counter. The partner cannot generate additional rewards from protocol-issued PSRE. Only genuine market buying activity drives effectiveCumS growth.

Combined with the scarcity function:

$$E_{scarcity}(t) = E_0 \cdot (1-x(t))^k$$

...the emission rate decreases permanently as supply depletes. The protocol cannot issue more than 12,600,000 PSRE in total emissions, ever. Monetary supply is fully determined by math at deployment — no human authority can override it.

---

## 12. Security

### 12.1 External Audit

Prospereum was audited by **BlockApex** (April 2–17, 2026) prior to mainnet launch. Two audit phases were conducted.

- **29 total findings** identified (5 Critical, 5 High, 13 Medium, 5 Low, 1 Informational)
- **All 29 findings resolved** before mainnet deployment
- Public report: https://github.com/BlockApex/Audit-Reports/blob/master/Prospereum%20Protocol_Final%20Audit%20Report.pdf

Key architectural improvements arising from the audit:

- **Flash-loan cumS inflation closed:** cumS only advances through tracked `buy()` flows
- **Retroactive staking theft closed:** Synthetix cumulative accumulator auto-initializes new stakers to current state — no historical access
- **StakingVault liveness restored:** Synthetix model ensures passive stakers earn forever without checkpointing
- **Epoch mint-cap DoS closed:** `mintForEpoch()` charges each epoch's mint against its own budget
- **Scarcity ceiling clamping:** batch finalization cannot exceed per-epoch mint cap

### 12.2 Test Coverage

- 249 tests passing (Foundry: unit, integration, invariant fuzz)
- Invariant tests cover: total minted ≤ S_EMISSION, cumS monotonicity, StakingVault solvency, epoch ordering

---

## 13. Deployed Protocol (Live — Base Mainnet)

**Chain:** Base (chainId 8453)
**Launch date:** April 22, 2026

| Contract | Address |
|----------|---------|
| PSRE Token | `0x2fE08f304f1Af799Bc29E3D4E210973291d96702` |
| PartnerVaultFactory | `0xFF84408633f79b8f562314cC5A3bCaedA8f76902` |
| StakingVault | `0x684BEA07e979CB5925d546b2E2099aA1c632ED2D` |
| RewardEngine (proxy) | `0x9Ab37Fc6D01B85491Ed0863B7F832784bE717EF5` |

Full contract list and deployment transactions: https://github.com/wealthhealthai/prospereum-protocol/blob/master/projects/prospereum/deployments.md

---

*Prospereum Whitepaper v3.4 — April 2026*
*WealthHealth AI, Inc. — jason@wealthhealth.ai*
