# Prospereum v3.2 — Shu Review Incorporated


------------------------------------------------------------------------

# Prospereum --- Whitepaper v3.2

------------------------------------------------------------------------

PROSPEREUM Protocol (PSRE) Proof of Prosperity White Paper v3.2 (March
2026)

------------------------------------------------------------------------

## 1. Abstract

Prospereum is a decentralized behavioral mining protocol that aligns
economic demand with progressive scarcity.

Unlike Proof-of-Work (Bitcoin) or Proof-of-Stake (Ethereum), Prospereum
introduces:

**Proof of Prosperity**

Token issuance is unlocked only when provable, sustained on-chain demand
for PSRE is generated --- measured not by gross purchasing activity or
time-weighted retention levels, but by **cumulative net growth** in
ecosystem PSRE holdings. Issuance is permanently constrained by an
asymptotic scarcity function tied solely to emitted supply.

Prospereum is neutral infrastructure built for commerce rewards. It does
not encode moral judgment. Partners --- for example, ecommerce brands
and DTC merchants --- define aligned economic activity by distributing
PSRE to their customers as purchase rewards. The protocol measures only
cumulative net growth in retained PSRE across the partner's vault
ecosystem.

Wash trading is rendered economically impossible: any PSRE bought and
then sold resets progress toward the cumulative high-water-mark without
reducing it. To earn any reward after selling, an attacker must rebuy
past their previous peak --- permanently committing more capital with
each cycle. This is self-limiting by construction.

------------------------------------------------------------------------

## 2. Vision

Bitcoin demonstrated decentralized scarcity. Ethereum demonstrated
programmable coordination. Prospereum unifies both principles:

- Scarcity discipline
- Behavioral alignment

It is designed to:

- Reward real economic contribution --- partners who genuinely grow
  their PSRE ecosystem
- Prevent inflationary farming and wash trading through structural, not
  punitive, mechanisms
- Eliminate discretionary mint authority
- Transition naturally from growth incentives to scarcity dominance

------------------------------------------------------------------------

## 3. Supply Model

### 3.1 Total Supply

$$S_{total} = 21,000,000\text{ PSRE}$$

This supply is immutable.

### 3.2 Allocation

  -----------------------------------------------------------------------
  Category          \%                Amount            Comments
  ----------------- ----------------- ----------------- -----------------
  Behavioral Mining 60%               12,600,000        Not minted at
  Emission Reserve                                      genesis; reserved
                                                        for future
                                                        emission

  Team & Founders   20%               4,200,000         Minted at genesis
                                                        to a vesting
                                                        contract

  Ecosystem Growth  8%                1,680,000         Minted at genesis
                                                        to Treasury
                                                        Wallet (SAFE)

  DAO Treasury      7%                1,470,000         Minted at genesis
                                                        to Treasury
                                                        Wallet (SAFE)

  Bootstrap         5%                1,050,000         Minted at genesis
  Liquidity                                             to Treasury
                                                        Wallet (SAFE)
  -----------------------------------------------------------------------

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

------------------------------------------------------------------------

## 4. Launch Policy

- No pre-sale
- No private token sale
- No ICO
- No discounted insider allocation

Liquidity seeded solely from treasury allocation. Behavioral mining
begins only after first full epoch.

------------------------------------------------------------------------

## 5. Partner Ecosystem Architecture

### 5.1 What a Partner Is

A **partner** is, for example, an ecommerce brand or DTC merchant that
participates in Prospereum's commerce rewards infrastructure. Instead of
offering customers a percentage discount at checkout, the partner
purchases PSRE and distributes it to customers as on-chain purchase
rewards.

From the customer's perspective, this is seamless: they receive "X PSRE
rewards" credited in the partner's app or storefront. Customers do not
need to interact with the blockchain directly. The partner's ecommerce
backend (or an integration layer) handles all on-chain interactions on
their behalf.

### 5.2 PartnerVault

Each partner holds a single **PartnerVault** --- a dedicated smart
contract that serves as the partner's on-chain identity for reward
accounting. The PartnerVault:

- Receives USDC from the partner's backend and executes PSRE purchases
  via a DEX
- Tracks the partner's cumulative high-water-mark balance
  ($\text{cumS}_{p}$) across its entire vault ecosystem
- Maintains a registry of linked CustomerVaults
- Is the canonical accounting boundary for reward calculations

### 5.3 CustomerVault

For each customer who receives rewards, the partner deploys a
lightweight **CustomerVault** contract. Key properties:

- The partner pays all gas costs for CustomerVault deployment and
  operation
- The CustomerVault is registered to (linked with) the parent
  PartnerVault at creation
- PSRE held in registered CustomerVaults counts toward the partner's
  ecosystem balance $S_{eco}$
- Customers interact with their rewards through the partner's app UI,
  not the blockchain directly
- A CustomerVault can be claimed by the customer at any time by
  asserting their wallet address

This architecture makes Prospereum **blockchain-agnostic for end
customers** while preserving full on-chain verifiability for the
protocol.

### 5.4 Vault Lifecycle and Anti-Spam Controls

To prevent vault spam and maintain registry integrity, the following
lifecycle rules apply:

**Minimum Initial Buy (Entry Cost)**

Partners must make an initial PSRE purchase of at least $S_{\min}$ at
the time of PartnerVault creation. $S_{\min}$ is denominated in USDC:
the minimum is **\$500 USDC**. The factory contract validates that the
USDC input satisfies `usdcAmountIn >= S_MIN` before deploying the vault,
protecting against price volatility manipulation.

Critically, **this initial buy earns zero reward** --- it establishes
the baseline high-water-mark $\text{cumS}_{p}(N) = S_{p}(N)$ and serves
as the natural entry cost for the partner program. The initial buy is
not refundable and not rewarded, making it strictly an irrecoverable
cost, although can be used by the partner to reward his customers. The
initial buy replaces any separate vault bond mechanism; there is no
returnable bond.

$_{}$ **cumS Permanence**

$\text{cumS}_{p}$ is permanently tied to the vault's address and never
resets. If a partner deregisters and creates a new vault, the new vault
starts with $\text{cumS} = 0$. This discourages vault churn as a tactic
to reset the high-water-mark.

------------------------------------------------------------------------

## 6. Behavioral Mining --- Proof of Prosperity

### 6.1 Overview

Each partner participates in the Prospereum protocol by maintaining a
PartnerVault and a network of linked CustomerVaults (the "partner
ecosystem"). The protocol rewards partners based on cumulative net
growth in their vault ecosystem's PSRE holdings.

This is the core mechanism of the Prospereum protocol: rewards are based
not on gross buying activity, not on absolute holdings, and not on
time-weighted retention levels --- but on **cumulative high-water-mark
growth**. A partner earns reward only when the partner ecosystem balance
grows past all prior peaks.

**The ratchet property:** The cumulative high-water-mark
$\text{cumS}_{p}$ can only ever increase. If the ecosystem balance drops
--- because customers sell or withdraw PSRE outside of the partner
ecosystem --- the high-water-mark stays at the prior peak. The partner
earns nothing until the ecosystem grows past that peak again.

**Wash trading is structurally impossible under this model:** - An
attacker buys PSRE (cumS rises to peak), then sells (balance drops, cumS
stays at peak) - To earn any reward, the attacker must rebuy past their
prior peak --- committing more net capital than before - Each "cycle"
requires more capital than the last. The strategy is self-limiting and
cannot be sustained indefinitely without permanently increasing capital
commitment - The initial buy earns zero reward, so the first cycle pays
irrecoverable costs with no return to spammers.

**Real partners are naturally rewarded:** - Partner grows their customer
base, distributes PSRE to new CustomerVaults - Ecosystem balance grows,
cumS grows, reward is generated - In slow seasons, the ecosystem may go
flat --- zero reward, but no forfeiture of prior cumS - When growth
resumes, rewards resume immediately. If customers elect to use their
PSRE to buy goods from the partner, the partner is incentivized
automatically to receive the tokens in his Prospereum protocol partner
vault.

### 6.2 Epoch

The protocol operates in discrete time intervals called **epochs**.

$$T_{epoch} = 7\text{ days}$$

All mining activity and rewards are calculated and emitted once per
epoch.

### 6.3 Ecosystem Balance

Let $S_{eco,p}(t)$ be the total PSRE held within partner $p$'s vault
ecosystem at epoch $t$:

$$S_{eco,p}(t) = \text{PSRE in PartnerVault}_{p} + \sum_{cv \in \text{registered}(p)}^{}\text{PSRE in }cv$$

This is the total PSRE within the registered vault boundary
(PartnerVault + all linked CustomerVaults). PSRE transferred to
unregistered addresses is excluded from $S_{eco}$.

### 6.4 Cumulative High-Water-Mark

The reward metric is the cumulative high-water-mark of ecosystem
balance:

$$\text{cumS}_{p}(t) = max\left( S_{eco,p}(t),\ \text{cumS}_{p}(t - 1) \right)$$

$\text{cumS}_{p}$ is a ratchet: it can only increase. It is recorded at
each epoch finalization. At vault creation (epoch $N$):

$$\text{cumS}_{p}(N) = S_{p}(N) = \text{initial buy amount}$$

### 6.5 Reward Calculation and the effectiveCumS Deduction

To ensure that reward PSRE minted by the protocol does not itself
generate future rewards, the protocol computes rewards using an
**effective** cumulative high-water-mark that excludes all previously
minted reward PSRE:

$$\text{effectiveCumS}_{p}(t) = \text{cumS}_{p}(t) - \text{cumulativeRewardMinted}_{p}(t)$$

where $\text{cumulativeRewardMinted}_{p}(t)$ is a running total of all
PSRE ever minted as rewards for partner $p$, accumulated across all
epochs (incremented at each epoch finalization, never decreasing). This
ensures that reward PSRE minted by the protocol does not itself generate
future rewards, keeping emission strictly proportional to genuine market
buying activity.

The per-epoch reward formula is:

$$\text{reward}_{p}(t) = max\left( 0,\ r_{base} \times (\text{effectiveCumS}_{p}(t) - \text{effectiveCumS}_{p}(t - 1)) \right)$$

If the ecosystem did not grow past its prior effectiveCumS peak in epoch
$t$, the reward is zero. Reward PSRE deposited into the vault increases
$\text{cumS}$ but is exactly cancelled by the deduction, preventing any
compounding feedback loop.

### 6.6 First Qualification Condition

The initial buy $S_{p}(N)$ earns **zero reward** --- it establishes the
baseline, not a reward trigger. The first reward is issued only when the
ecosystem grows past the initial baseline:

$$\text{cumS}_{p}(M) > S_{p}(N)\quad\text{for some epoch }M > N$$

First reward amount:

$$\text{reward}_{p,\text{first}} = r_{base} \times \left( \text{effectiveCumS}_{p}(M) - S_{p}(N) \right)$$

There is no fixed time window. $M$ can be any epoch after $N$. The
qualification condition is growth, not patience.

After first qualification, the ongoing formula (Section 6.5) applies to
all subsequent epochs.

### 6.7 Total Ecosystem Demand

The aggregate reward demand from all partners in epoch $t$ is:

$$E_{demand}(t) = r_{base} \times \sum_{p}^{}\max\left( 0,\ \text{effectiveCumS}_{p}(t) - \text{effectiveCumS}_{p}(t - 1) \right)$$

This is the sum of all positive effectiveCumS growth increments across
all partners in the epoch. Partners with flat or declining ecosystem
balances contribute zero to $E_{demand}$.

### 6.8 Scarcity-Based Emission Limit

To enforce long-term scarcity, emission is also limited by the remaining
emission reserve.

Let:

$$S_{emission} = 12,600,000\text{ PSRE}\quad\text{(total emission reserve)}$$

$$x(t) = \frac{T(t)}{S_{emission}}$$

where $T(t)$ is the cumulative PSRE already emitted. The scarcity-based
emission cap is:

$$E_{scarcity}(t) = E_{0} \cdot (1 - x(t))^{k}$$

where:

- $E_{0}$ = initial weekly emission ceiling (default: 0.1% of
  $S_{emission}$, i.e., 12,600 PSRE/week)
- $k$ = scarcity exponent (default: 2, immutable)

As the reserve is depleted, emission decreases smoothly toward zero.

### 6.9 Final Emission Budget

$$B(t) = min\left( E_{demand}(t),\ E_{scarcity}(t),\ S_{emission} - T(t) \right)$$

------------------------------------------------------------------------

## 7. Individual Reward Calculation

### 7.1 Budget Split

The total emission budget for epoch $t$ is divided into two pools:

$$B_{partners}(t) = 0.70 \times B(t)$$

$$B_{stakers}(t) = 0.30 \times B(t)$$

### 7.2 Partner Status --- Rolling EMA Tier

The protocol maintains a rolling contribution score for each partner
based on their effectiveCumS growth increments:

$$R_{p}(t) = (1 - \theta) \cdot R_{p}(t - 1) + \theta \cdot \Delta\text{effectiveCumS}_{p}(t)$$

where:

$$\Delta\text{effectiveCumS}_{p}(t) = max\left( 0,\ \text{effectiveCumS}_{p}(t) - \text{effectiveCumS}_{p}(t - 1) \right)$$

$$\theta = \frac{1}{13} \approx 0.0769\quad\text{(13-epoch exponential moving average} \approx \text{one calendar quarter)}$$

The partner's percentage share of ecosystem contribution is:

$$s_{p}(t) = \frac{R_{p}(t)}{\sum_{q}^{}R_{q}(t)}$$

Based on this share, the partner is assigned a tier:

  -----------------------------------------------
  Tier     Contribution Share
  -------- --------------------------------------
  Bronze   $$s_{p} < s_{silver}$$

  Silver   $$s_{silver} \leq s_{p} < s_{gold}$$

  Gold     $$s_{p} \geq s_{gold}$$
  -----------------------------------------------

Default thresholds:

$$s_{silver} = 0.005\quad(0.5\%),\quad\quad s_{gold} = 0.020\quad(2.0\%)$$

### 7.3 Tier Reward Rate

  ----------------------------------------------------
  Tier     Base Rate         Effective Rate (at
           Multiplier        $r_{base} = 10\%$)
  -------- ----------------- -------------------------
  Bronze   0.8×              8%

  Silver   1.0×              10%

  Gold     1.2×              12%
  ----------------------------------------------------

If total raw rewards demanded by partners exceed the protocol's emission
budget for that epoch, reward rates are proportionally scaled down so
that total rewards remain within the allowed emission.

### 7.4 Partner Reward Calculation

Let $r_{p}(t)$ be the effective reward rate for partner $p$ in epoch $t$
(tier-adjusted).

Per-partner reward entitlement:

$$\text{reward}_{p,\text{raw}}(t) = r_{p}(t) \times \Delta\text{effectiveCumS}_{p}(t)$$

Total reward demand:

$$D(t) = \sum_{p}^{}\text{reward}_{p,\text{raw}}(t)$$

If $D(t) \leq B_{partners}(t)$, partners receive the full reward.

If $D(t) > B_{partners}(t)$, rewards are scaled proportionally:

$$\lambda = \frac{B_{partners}(t)}{D(t)},\quad\quad\text{reward}_{p}(t) = \lambda \times \text{reward}_{p,\text{raw}}(t)$$

Rewards are claimable immediately upon epoch finalization --- there is
no vesting schedule. The first qualification condition (Section 6.6)
serves as the sole behavioral gate.

### 7.5 Staker and Liquidity Provider (LP) Rewards

Participants may earn rewards from the staking pool by locking PSRE
tokens or providing liquidity. Two forms of staking are supported:

**PSRE Staking** Users lock PSRE tokens in the staking contract for a
minimum duration. This reduces circulating supply and aligns long-term
participants with the protocol.

**Liquidity Provider Staking** Users who provide liquidity to PSRE
trading pools may stake their LP tokens to earn rewards. This encourages
deeper market liquidity and lower trading slippage.

Both forms of staking share the same reward pool and are treated
equivalently with no weighting multiplier. Rewards are distributed
according to time-weighted stake:

$$\text{StakeTime}_{p}(t) = \int_{t - 1}^{t}S_{p}(\tau)\, d\tau$$

$$\text{TotalStakeTime}(t) = \sum_{p}^{}\text{StakeTime}_{p}(t)$$

$$\text{Reward}_{staker,p}(t) = B_{stakers}(t) \times \frac{\text{StakeTime}_{p}(t)}{\text{TotalStakeTime}(t)}$$

------------------------------------------------------------------------

## 8. Design Rationale: Anti-Gaming and Commerce Alignment

### 8.1 Why cumS High-Water-Mark Prevents Wash Trading

The cumulative high-water-mark is the protocol's primary structural
defense against manipulation:

- **Selling PSRE does not reset the clock.** When an attacker sells
  PSRE, the ecosystem balance drops but $\text{cumS}_{p}$ stays at the
  prior peak. The attacker receives no benefit from the sell --- they
  simply move further from their reward threshold.
- **Rebuy requires exceeding the peak.** To earn any reward after
  selling, the attacker must repurchase PSRE past their prior high. This
  means each "sell-and-rebuy" cycle requires permanently committing more
  capital than the last.
- **Self-limiting by construction.** Each cycle demands a higher capital
  commitment than the cycle before it. No fixed capital amount can
  sustain infinite reward extraction. The strategy degrades
  monotonically.

This contrasts with time-weighted retention models, where a
sophisticated attacker could construct schedules that satisfy holding
requirements without permanent capital commitment. The high-water-mark
eliminates this entirely: only genuine net new ecosystem growth earns
reward.

### 8.2 Why the Initial Buy Earns No Reward

The un-rewarded $S_{p}(N)$ is the structural entry cost for the partner
program:

- **More punitive** **to spammers than any refundable bond.** A bond is
  locked but eventually returned; the initial buy pays DEX fees,
  slippage, and irrecoverable opportunity cost with zero reward. There
  is no returnable bond in Prospereum --- the initial buy IS the entry
  cost. However, for legitimate partners, they can use the initial buy
  to reward their customers, therefore productive use of capital.
- **No spam incentive.** A spammer who registers hundreds of vaults pays
  $S_{\min}$ (\$500 USDC) per vault with zero reward on each initial
  buy. Combined with the need to exceed cumS before earning anything,
  mass vault creation is never economically rational.
- **Natural deterrence scaling.** As PSRE appreciates in value,
  $S_{\min}$ (denominated in USDC) represents a smaller PSRE quantity
  --- but the irrecoverable nature on the initial buy remains stable in
  dollar terms, maintaining consistent deterrence regardless of token
  price.

### 8.3 Why No Vesting Schedule

Earlier versions of Prospereum used a 4-epoch vesting delay to prevent
hit-and-run participation. The first qualification condition is a
strictly stronger mechanism:

- **Vesting only delays reward extraction.** An attacker who earns a
  reward in epoch $t$ still earns that reward --- they simply cannot
  extract it for 4 epochs. The profitability math is unchanged; only the
  timing shifts.
- **First qualification requires demonstrated growth.** An attacker
  cannot earn any first reward without genuinely growing their cumS past
  the initial buy baseline. Patience alone --- sitting on an un-moved
  initial buy --- produces zero reward indefinitely.
- **Eliminates the vesting cliff attack.** With a vesting schedule, an
  attacker can plan around the 4-epoch window. The first qualification
  condition has no fixed window: it requires growth, not time elapsed.

### 8.4 Why Distribution to Customers Earns No Direct Reward

In earlier protocol designs, distributing PSRE to registered
CustomerVaults was considered as a direct reward trigger. This was
removed because:

- **Partners control vault registration.** A partner could create
  thousands of fake CustomerVaults and "distribute" to them, inflating
  their retention score without any real customers. This vector is
  closed by making distribution neutral --- it moves PSRE within the
  ecosystem without changing $S_{eco}$.
- **The indirect incentive is commerce-aligned.** Partners are
  commercially motivated to distribute PSRE to real customers because a
  larger customer base drives more customer buying, which grows
  $S_{eco}$, which grows $\text{cumS}_{p}$, which generates reward. The
  incentive to distribute is already embedded in the growth metric ---
  no separate reward trigger is necessary or safe.
- **Cannot be decoupled from real commerce.** The only path to
  increasing cumS through customer activity is for real customers to
  hold and retain PSRE --- which requires a genuine commerce
  relationship.

### 8.5 Why Rewards Flow with Growth but Stop When Flat

The reward formula rewards only $\Delta\text{effectiveCumS}_{p} > 0$:

- **Flat ecosystem = no new value created.** If the ecosystem balance
  neither grows nor shrinks, no new economic participation is occurring.
  Rewarding flat holdings would incentivize parking capital rather than
  deploying it toward genuine commerce activity.
- **Real growing commerce naturally grows effectiveCumS.** A partner
  with an active and expanding customer base will continuously acquire
  new customers, distribute PSRE, and grow their ecosystem balance.
  Their effectiveCumS grows continuously. Reward flows naturally.
- **Slow seasons are accommodated without penalty.** A partner whose
  ecosystem goes flat during a slow season earns zero reward --- but
  their effectiveCumS does not reset. When growth resumes, rewards
  resume immediately. Long-term program maintenance is encouraged
  without requiring continuous growth.

------------------------------------------------------------------------

## 9. Anti-Wash-Trading Design Summary

Prospereum v3.2 introduces a structurally self-reinforcing defense
against gaming:

### 9.1 Cumulative High-Water-Mark (Primary Defense)

The $\text{cumS}_{p}$ ratchet ensures that any capital sold out of the
ecosystem permanently raises the bar for future rewards. Wash trading
requires monotonically increasing capital commitment --- making it
self-defeating over any meaningful time horizon.

### 9.2 Un-Rewarded Initial Buy (Registration Deterrent)

The initial buy at vault creation earns zero reward. The minimum is
\$500 USDC, denominated in USDC to maintain stable deterrence value
independent of PSRE market price. There is no separate returnable bond
--- the initial buy is the sole entry cost. Vault spammers pay
irrecoverable costs (fees, slippage, and the opportunity cost of the
initial buy) per vault with zero return on the creation transaction.
This is strictly more punitive than a refundable bond.

### 9.3 First Qualification Condition (Growth Gate)

No reward is issued until the ecosystem grows past the initial buy
baseline. Patience does not qualify --- growth does. This eliminates the
"plant and wait" attack.

### 9.4 Registered Vault Ecosystem Boundary

Only PSRE held in registered vaults (PartnerVault + registered
CustomerVaults) counts toward $S_{eco}$. PSRE transferred to
unregistered addresses leaves the ecosystem and is excluded. Partners
cannot game this by sending to self-owned unregistered wallets --- the
leakage is permanent (the PSRE must be repurchased from the market,
raising cumS further).

### 

### 9.6 Scarcity Cap (Protocol-Level Defense)

Total emission is bounded by
$E_{scarcity}(t) = E_{0} \cdot (1 - x(t))^{2}$, which declines
monotonically as the emission reserve is consumed. No amount of demand
pressure can bypass the scarcity ceiling.

### 9.7 Time-Weighted Staking

Flash-stake attacks on the staking pool are prevented by the
time-weighted staking model.

------------------------------------------------------------------------

## 10. Governance

The Prospereum protocol is governed by a decentralized autonomous
organization (DAO) responsible for maintaining operational parameters
while preserving the protocol's core monetary policy.

### 10.1 Adjustable Parameters

**Base Reward Rate**

$$0.05 \leq r_{base} \leq 0.15$$

**Partner Tier Thresholds** Contribution-share thresholds for
Bronze/Silver/Gold may be adjusted within bounds.

**Reward Pool Allocation** Default: 70% partners / 30% stakers. DAO may
adjust within:

$$60\% \leq B_{partners} \leq 80\%,\quad\quad 20\% \leq B_{stakers} \leq 40\%$$

**Initial Weekly Emission Ceiling**

$$0.0005 \times S_{emission} \leq E_{0} \leq 0.002 \times S_{emission}$$

For PSRE: lower bound ≈ 6,300 PSRE/week; upper bound ≈ 25,200 PSRE/week.

**Minimum Initial Buy (**$S_{\min}$**)** DAO may adjust the minimum
initial buy requirement within predefined bounds (denominated in USDC to
maintain stable deterrence value).

### 10.2 Non-Modifiable Parameters

The following are permanently fixed and cannot be modified by
governance:

  --------------------------------------------------------------------------------------------------
  Parameter                           Value
  ----------------------------------- --------------------------------------------------------------
  Maximum Supply                      $$S_{total} = 21,000,000$$

  Emission Reserve                    $$S_{emission} = 12,600,000$$

  Scarcity Function Form              $$E_{scarcity}(t) = E_{0} \cdot (1 - x(t))^{k}$$

  Scarcity Exponent                   $$k = 2$$

  Minting Rule                        $$B(t) = min(E_{demand},\ E_{scarcity},\ S_{emission} - T)$$

  cumS Ratchet Direction              $\text{cumS}_{p}$ is monotonically non-decreasing
  --------------------------------------------------------------------------------------------------

The DAO cannot mint tokens outside the minting rule.

### 10.3 Monetary Policy Integrity

The immutable supply cap, scarcity function, and emission reserve ensure
that Prospereum's monetary policy remains predictable and resistant to
discretionary inflation. Governance is limited to adjusting operational
parameters while the fundamental token issuance model remains fixed.

------------------------------------------------------------------------

## 11. Why the Reward Mechanism is Non-Inflationary

A common question about behavioral mining protocols is whether reward
emission creates inflationary pressure on the token. The Prospereum
design is specifically constructed to be non-inflationary in both supply
and circulating terms.

### 11.1 The Scarcity Cap is Always the Binding Constraint

The actual emission in any epoch is bounded by:

$$B(t) = min\left( E_{demand}(t),\ E_{scarcity}(t),\ S_{emission} - T(t) \right)$$

The scarcity cap $E_{scarcity}(t) = E_{0} \cdot (1 - x(t))^{2}$ is
always active and declines monotonically as $x(t)$ increases. At
genesis, the maximum possible emission is:

$$E_{scarcity}(0) = E_{0} = 0.001 \times S_{emission} = 12,600\text{ PSRE/week}$$

This ceiling declines toward zero as the emission reserve is consumed.
Regardless of how much demand partners generate, emission **cannot
exceed this ceiling**. Total emission over the protocol's entire
lifetime is absolutely bounded at:

$$\sum_{t = 0}^{\infty}B(t) \leq S_{emission} = 12,600,000\text{ PSRE}$$

### 11.2 Partner Buying Creates Net Deflationary Pressure on Circulating Supply

Partners must purchase PSRE from the open market to grow their ecosystem
balance and earn rewards. For every 100 PSRE a partner ecosystem grows
(raising effectiveCumS by 100 PSRE):

- **100 PSRE is removed from circulating supply** (bought from market,
  held in vault ecosystem)
- **Only \~8--12 PSRE of new supply is emitted as reward** (at
  tier-adjusted rates of 8--12% applied to $\Delta\text{effectiveCumS}$)
- That reward PSRE **also enters the vault ecosystem** --- it is
  distributed to CustomerVaults, not sold, and the effectiveCumS
  deduction ensures it generates zero additional reward

The net circulating supply effect per epoch of partner ecosystem growth
is approximately **−88% to −92%**: for every 100 PSRE of effectiveCumS
growth, only 8--12 PSRE of new supply is created, and both the purchased
PSRE and the reward enter the vault ecosystem rather than circulating.

### 11.3 Reward PSRE Does Not Circulate (and Does Not Compound)

Reward PSRE minted by the RewardEngine is deposited into the
PartnerVault and distributed to registered CustomerVaults. It does not
enter the open market. It only becomes potentially circulating if a
customer explicitly withdraws their CustomerVault balance to an external
address --- and that withdrawal reduces $S_{eco}$. If this causes the
ecosystem balance to drop below cumS (which remains at the prior peak),
no reward is earned until the ecosystem grows past cumS again.

Furthermore, the effectiveCumS deduction ensures that reward PSRE
deposited into the vault does not generate additional future rewards.
Even if reward PSRE remains in the vault indefinitely, it contributes
zero to future effectiveCumS growth.

This creates a strong economic incentive for partners to retain
customers and discourage withdrawals --- not through protocol penalty,
but through direct commercial self-interest.

### 11.4 Absolute Supply Cap

Total emission over the protocol's lifetime cannot exceed
$S_{emission} = 12,600,000$ PSRE by construction of the minting rule.
The DAO cannot mint additional PSRE, cannot override the scarcity
function, and cannot increase $S_{emission}$.

------------------------------------------------------------------------

## 12. Conclusion

Prospereum v3.2 refines **Proof of Prosperity** with a cleaner, more
structurally sound reward mechanism: the cumulative high-water-mark,
augmented by the effectiveCumS deduction.

Where v3.0 rewarded time-weighted retention, v3.1 and v3.2 reward only
cumulative net ecosystem growth --- the delta between an ecosystem's
current effective balance and its all-time effective peak. The
effectiveCumS deduction in v3.2 closes the final loop: reward PSRE
deposited into the vault cannot itself generate further rewards,
ensuring that emission is always proportional to genuine market buying
activity.

The result is a protocol that is:

**Demand-Bounded ∩ Scarcity-Controlled ∩ Growth-Verified ∩
Governance-Limited ∩ Non-Compounding**

Prospereum bridges Bitcoin's scarcity discipline with Ethereum's
programmable ecosystem model, and extends both with a commerce-native
reward layer that aligns the interests of ecommerce brands, their
customers, and the protocol's long-term sustainability.

The cumS ratchet is not merely an anti-gaming measure --- it is a direct
expression of the protocol's thesis: that genuine economic value, once
created within a commerce ecosystem, should be recognized permanently
and rewarded only when it grows further. The effectiveCumS deduction is
the mathematical proof of that commitment: only new market demand
counts.
