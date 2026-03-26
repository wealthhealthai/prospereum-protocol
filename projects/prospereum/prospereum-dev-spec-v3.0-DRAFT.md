# DRAFT v3.0 — FOR REVIEW BY JASON AND SHU BEFORE IMPLEMENTATION
# Do not implement until explicitly approved.

---

# Prospereum Developer Specification v3.0

PROSPEREUM (PSRE)
Developer Specification v3.0

---

## 0. Design Decisions Locked for v3.0

- Epoch-based emission (weekly), not per-claim.
- Behavioral mining primitive: **net retained PSRE** across the partner vault ecosystem
  (PartnerVault + all linked CustomerVaults), time-weighted over the epoch.
- Gross buy activity (cumBuy) is **no longer** the reward input. It is replaced by
  `netRetained` — PSRE that stays within the registered vault ecosystem.
- PSRE transferred to unregistered addresses is tracked as "leaked" and subtracted from
  retention score.
- PartnerVault SELL to DEX remains disabled. Only distribute() to registered CustomerVaults
  or explicit deregistered-address transfers (which count as leakage) are allowed.
- No price oracle for retention calculation. Retention is denominated in PSRE wei.
  (USD equivalent check for minimum activity uses a lightweight oracle or DAO-set PSRE/USDC rate.)
- Scarcity depends only on $x = T / S_{emission}$. Unchanged.
- 70/30 split: partners/stakers (LP shares staker pool). Unchanged.
- Staker rewards are time-weighted (anti flash-stake). Unchanged.
- Partner status: rolling EMA with tier multipliers — now applied to $TWR_p$ instead of deltaNB.
- Reward vesting: 4-epoch linear vesting before partner rewards are claimable.
- Vault bond: **$500 USDC**, required at PartnerVault creation, returned on deregistration,
  paid to/from the factory contract. *Rationale: A PSRE-denominated bond would become
  prohibitively expensive for legitimate partners as PSRE appreciates. A fixed USDC
  denomination maintains consistent deterrence value regardless of PSRE price and avoids
  the need for a price oracle for bond valuation.*
- Registration fee: ~$50 USDC non-refundable, paid to treasury at vault creation.
- Vault expiry: PartnerVaults with zero qualifying activity for 4 consecutive epochs become inactive.
- CustomerVaults are registered to a parent PartnerVault; PSRE in them counts toward partner retention.
- $E_{demand}(t)$ is based on the **net increase** in TWR per epoch (delta formula), not the
  absolute TWR level. Floor at zero.
- No presale; treasury seeds LP.

---

## 1. Constants & Global Parameters

### 1.1 Token Supply

$$S_{total} = 21{,}000{,}000 \times 10^{18} \text{ wei}$$

$$S_{emission} = 12{,}600{,}000 \times 10^{18} \text{ wei}$$

### 1.2 Epoch

```
EPOCH_DURATION   = 7 days
genesisTimestamp  set at deployment
epochId           = (block.timestamp - genesisTimestamp) / EPOCH_DURATION
```

### 1.3 Economic Parameters (v3.0 defaults + bounds)

All parameters stored in RewardEngine contract.

```
alphaBase = 0.10e18       (r_base; note: 10% default matching whitepaper)
  bounds:  [0.05e18, 0.15e18]

E0 (weekly scarcity ceiling, PSRE wei):
  default: 0.001 * S_EMISSION   (0.1% of emission reserve per week = 12,600 PSRE/week)
  bounds:  [0.0005*S_EMISSION, 0.002*S_EMISSION]

k (scarcity exponent):
  default: 2
  immutable in v3.0

clamp:
  if x >= 1 → E_scarcity = 0
  use fixed-point to avoid rounding errors making it negative

theta (EMA factor, scaled 1e18):
  default: 1/13 ≈ 0.0769230769e18
  immutable in v3.0 (or bounded but recommend immutable)
```

### 1.4 Tier Parameters (share thresholds and multipliers)

Rolling share $s_p$ in 1e18-scaled fixed-point.

Thresholds (defaults):

$$s_{bronze} = 0 \quad \text{(everyone at least Bronze)}$$

$$s_{silver} = 0.005 \times 10^{18} \quad (0.5\%)$$

$$s_{gold} = 0.02 \times 10^{18} \quad (2.0\%)$$

Multipliers (scaled 1e18):

```
M_BRONZE = 1.0e18
M_SILVER = 1.25e18
M_GOLD   = 1.5e18
```

DAO-adjustable (bounded). Recommend bounded.

### 1.5 Splits

$$PARTNER\_SPLIT = 0.70 \times 10^{18}$$

$$STAKER\_SPLIT = 0.30 \times 10^{18}$$

DAO-bounded optional range:

$$\text{partner split} \in [0.60,\ 0.80]$$

### 1.6 Vault Lifecycle Parameters

```
VAULT_BOND          = $500 USDC (fixed denomination; held in factory escrow; returned on
                      deregistration. DAO-adjustable within bounds, USDC-denominated.)
REGISTRATION_FEE    = ~$50 USDC (non-refundable; paid to treasury at vault creation;
                      DAO-adjustable)
MIN_EPOCH_ACTIVITY  = ~$50 USDC equivalent in PSRE buys (DAO-adjustable; requires rate feed)
VAULT_EXPIRY_EPOCHS = 4  (consecutive inactive epochs before auto-expiry)
```

### 1.7 Reward Vesting

```
VESTING_EPOCHS = 4   (partner rewards vest linearly over 4 epochs, 25%/epoch)
```

Rewards earned in epoch $t$ vest as:
- 25% claimable at end of epoch $t+1$
- 25% claimable at end of epoch $t+2$
- 25% claimable at end of epoch $t+3$
- 25% claimable at end of epoch $t+4$

### 1.8 Rounding & Dust Rules

- Compute all rewards with integer division.
- Total partner payouts may be slightly less than $B_{partners}$ due to rounding.
- Rule: do not mint dust. Dust stays unminted (scarcity-positive), or carry forward (more
  complex — recommend leave unminted in v3.0).

### 1.9 When sumR == 0

In early epochs there may be no partners with TWR > 0.

```
if sumR == 0:
    s_p = 0 for all partners
    alpha_p = alpha_base for any partner with TWR_p > 0
```

Or skip status calculation entirely and assign Bronze to all active partners.

### 1.10 When W == 0 (Partner Weight Total is Zero)

```
if W == 0:
    partner pool = 0   (carry forward or leave unminted)
```

### 1.11 Monotonicity Rules

- `leakedPSRE[vault]` is monotonically non-decreasing.
- `totalDistributedToRegistered[vault]` is monotonically non-decreasing.
- `netRetained` can decrease (if PSRE leaks out) but cannot go below 0.

---

## 2. Contracts & Responsibilities

### 2.1 PSRE (ERC-20)

- Standard ERC-20 with decimals=18.
- `mint(to, amount)` callable only by RewardEngine.
- No other mint authority.
- Immutable — no upgrade proxy.

### 2.2 PartnerVaultFactory

- Creates a PartnerVault for a partner address and maintains the mapping between partner
  address and vault.
- `partnerAddress → vaultAddress` mapping
- `vaultAddress → partnerAddress` mapping
- `customerVaultAddress → parentPartnerVault` mapping (global lookup)

The factory allows a partner address to create a single PartnerVault.
The PartnerVault itself is the canonical partner identity for reward accounting.

At creation, the factory:
1. Collects the registration fee (USDC) and forwards to treasury.
2. Collects the vault bond ($500 USDC) and holds in escrow.
3. Deploys the PartnerVault contract.
4. Registers it in the factory mapping.

On deregistration (partner exits cleanly):
- Factory verifies the vault has been inactive for at least 1 epoch (no open vesting tranches
  are outstanding, OR vesting tranches have been claimed).
- Returns the $500 USDC vault bond to the partner address.
- Marks vault as deregistered.

### 2.3 PartnerVault

**Purpose:** Enforce accounting boundary for net retained PSRE within the partner's vault
ecosystem. The PartnerVault address serves as the partner's on-chain identity for reward
accounting. The controlling wallet address (owner) may be updated via `updateOwner()` to
allow wallet migration without losing partner history or reward state.

#### Key Rules

- Only `buy()` adds PSRE to the vault ecosystem.
- `distribute(customerVault, amount)` moves PSRE to a registered CustomerVault — this does
  NOT count as leakage. Net retention is unchanged.
- `transfer(unregisteredAddress, amount)` — if the partner explicitly sends PSRE to an
  address that is not a registered vault, this IS counted as leakage and reduces net retention.
- Vault SELL to DEX: DISABLED in v3.0 (same as v2.x). There is no sell() function.

#### State

```solidity
// Partner identity
address public partnerOwner;
address public rewardEngine;
address public factory;

// Vault bond
uint256 public bondAmount;  // USDC held as bond in factory escrow

// Net retention accounting
uint256 public totalBought;               // cumulative PSRE received via buy(); never decreases
uint256 public totalDistributedToRegistered;  // cumulative PSRE sent to registered CustomerVaults
uint256 public totalLeaked;               // cumulative PSRE sent to unregistered addresses

// Customer vault registry (owned by this PartnerVault)
mapping(address => bool) public registeredCustomerVaults;
address[] public customerVaultList;  // enumerable for off-chain indexing

// Activity tracking
uint256 public lastActiveEpoch;
uint256 public consecutiveInactiveEpochs;

// Time-weighted retention accounting (updated on every vault event within an epoch)
uint256 public lastCheckpointTimestamp;
uint256 public epochAccumulatedTWR;  // accumulates within the current epoch
```

#### Computed Property

```
netRetained() → uint256:
    return totalBought
           + Σ PSRE in all registeredCustomerVaults  // pulled live from each CV
           - totalLeaked
```

**Note:** For gas efficiency, the RewardEngine may use a checkpoint-based approximation
of TWR rather than summing all CustomerVault balances at finalize time. See Section 5.

#### Functions

```solidity
// Execute a PSRE purchase via DEX router
function buy(address router, bytes calldata swapData) external onlyOwner
    → updates totalBought += psreOut
    → updates TWR checkpoint

// Distribute PSRE reward to a registered CustomerVault (no leakage)
function distributeToCustomer(address customerVault, uint256 amount) external onlyOwner
    → require registeredCustomerVaults[customerVault]
    → transfer PSRE to customerVault
    → update totalDistributedToRegistered += amount
    → (net retention unchanged: PSRE stays in ecosystem)

// Transfer PSRE to an unregistered address (counts as leakage)
function transferOut(address to, uint256 amount) external onlyOwner
    → require !registeredCustomerVaults[to]  // cannot use this to bypass distributeToCustomer
    → require !factory.isRegisteredVault(to)  // not any registered vault
    → transfer PSRE
    → totalLeaked += amount
    → update TWR checkpoint (retention just decreased)

// Register a new CustomerVault linked to this PartnerVault
function registerCustomerVault(address customerVault) external onlyOwner
    → verify customerVault is deployed by factory.deployCustomerVault(this)
    → registeredCustomerVaults[customerVault] = true
    → customerVaultList.push(customerVault)

// Update owner (wallet migration)
function updateOwner(address newOwner) external onlyOwner

// TWR checkpoint (called internally on any balance-changing event)
function _checkpoint() internal
    → elapsed = block.timestamp - lastCheckpointTimestamp
    → epochAccumulatedTWR += currentNetRetained() * elapsed
    → lastCheckpointTimestamp = block.timestamp
```

#### Security

- `buy()` must validate `psreOut > 0`.
- Use `ReentrancyGuard` on all state-changing functions.
- Restrict `buy()` router calls to a pre-approved router address set at vault deploy
  (partner-chosen) OR a hardcoded router from factory (safer for v3.0).
- `distributeToCustomer()` requires the target to be in `registeredCustomerVaults`.
- `transferOut()` explicitly blocks registered vaults as targets (forces use of distributeToCustomer).

---

### 2.3a CustomerVault

**Purpose:** Lightweight on-chain escrow for a single customer's PSRE rewards. Linked to
exactly one parent PartnerVault. The customer does not need to interact with the blockchain;
the partner's backend manages deposits on the customer's behalf.

#### Design Principles

- Minimal gas footprint (no complex state, no reward engine interaction).
- Deployed by PartnerVaultFactory on behalf of a PartnerVault (not by the customer directly).
- PSRE received from the parent PartnerVault stays in this vault and counts toward the
  parent's net retention score.
- The customer may claim ownership of their CustomerVault at any time by asserting their
  wallet address (claim flow described below).

#### State

```solidity
address public parentVault;          // the PartnerVault that owns/registered this CV
address public customer;             // initially address(0) until claimed by customer
bool    public customerClaimed;      // whether customer has asserted their wallet
uint256 public psreBalance;          // tracks PSRE held (mirrors ERC-20 balanceOf)
```

#### Functions

```solidity
// Called by parentVault to deposit PSRE rewards
function receiveReward(uint256 amount) external onlyParent
    → accept PSRE transfer
    → psreBalance += amount

// Customer claims ownership of this vault (asserts their wallet address)
// After this, they control withdrawal. Before this, parentVault controls distribution.
function claimVault(address customerWallet) external
    → require customer == address(0)  // can only claim once
    → require msg.sender == customerWallet  // customer must call from their own wallet
    → customer = customerWallet
    → customerClaimed = true

// Customer withdraws PSRE to their wallet (after claiming)
// Note: withdrawal to external address WILL count as leakage in parent's retention score
function withdraw(uint256 amount) external onlyCustomer
    → transfer PSRE to customer
    → notify parentVault of leakage: parentVault.reportLeakage(amount)

// Partner can revoke/reclaim PSRE from an unclaimed CustomerVault
// (e.g., customer account was created in error; only before customer claims)
function reclaimUnclaimed(uint256 amount) external onlyParent
    → require !customerClaimed
    → transfer PSRE back to parentVault
    → (this is NOT leakage; PSRE returns to PartnerVault's retained balance)
```

#### Leakage Reporting

When a customer withdraws PSRE to their external wallet, this reduces the parent
PartnerVault's net retention. The CustomerVault calls `parentVault.reportLeakage(amount)` so
the PartnerVault can update its `totalLeaked` counter and TWR checkpoint accordingly.

**Edge case:** If the customer withdraws after a long delay, the leakage is recorded at
withdrawal time — not retroactively. The partner's historical TWR scores are unaffected; only
future epochs see reduced retention.

#### Gas Notes

CustomerVaults are intended to be long-lived (one per customer). Deployment gas is paid by
the partner. The contract must be minimal — no complex logic, no upgradability.
Recommend using a minimal proxy (EIP-1167 clone) pattern deployed by PartnerVaultFactory
to minimize deployment cost.

---

### 2.4 StakingVault (includes LP staking)

PSRE staking and LP staking are treated equivalently in the staking reward pool. No
weighting multiplier is applied.

- Tracks time-weighted stake per epoch for each user.
- Supports staking PSRE and staking an LP token (e.g., PSRE/USDC LP).
- Single StakingVault with two staking assets:
  - `stakePSRE(amount)`
  - `stakeLP(amount)`
- For reward accounting, both PSRE stake and LP stake contribute
  $\text{stakeTime} = \text{stakeAmount} \times \text{stakingDuration}$, with no weighting multiplier.

**Unchanged from v2.3.**

---

### 2.5 RewardEngine (combined emission + reward vault)

The core monetary policy contract. UUPS upgradeable.

**Responsibilities (v3.0 additions in bold):**

- Track total emitted $T$.
- Maintain epoch state.
- **Compute $TWR_p$ (time-weighted retention) per partner vault per epoch.**
- Compute EMA status (now on $TWR_p$ instead of deltaNB).
- Compute demand cap (now based on $\Delta TWR_{total}$ — the net increase in TWR — instead of gross NB_total).
- Compute scarcity cap, final budget $B$.
- Compute partner rewards and staker rewards.
- **Apply 4-epoch vesting schedule to partner reward tranches.**
- P-based minting rule (mint up to owed payouts subject to budget and reserve).
- **Track vault activity epochs; mark vaults inactive after VAULT_EXPIRY_EPOCHS.**
- Pay rewards.

---

## 3. Storage Layout (RewardEngine)

### Global

```solidity
uint256 public T;                     // cumulative PSRE emitted
uint256 public genesisTimestamp;
uint256 public lastFinalizedEpoch;    // epochId
uint256 public alphaBase;             // 1e18-scaled
uint256 public E0;                    // wei
uint256 public k;                     // uint (immutable in v3.0)
uint256 public theta;                 // 1e18-scaled
uint256 public lastEpochTWRTotal;     // TWR_total from previous epoch (for E_demand delta)
// tier thresholds + multipliers
// split params
// vault lifecycle params
```

### Partner Accounting (by vault address)

```solidity
// TWR-based accounting (replaces cumBuy/creditedNB)
mapping(address => uint256) public lastEpochTWR;      // TWR_p snapshotted at epoch finalize
mapping(address => uint256) public R;                 // EMA rolling score (now tracks TWR)
uint256 public sumR;                                  // sum of all R values

// Vault activity tracking
mapping(address => uint256) public lastActiveEpochId;
mapping(address => uint256) public consecutiveInactiveEpochs;
mapping(address => bool)    public vaultActive;

// Reward vesting ledger
// owedVesting[vault][epochId] = amount earned in that epoch, not yet fully vested
mapping(address => mapping(uint256 => uint256)) public vestingEarned;
mapping(address => uint256) public totalVestingOwed;  // total across all unvested epochs
mapping(address => uint256) public totalClaimed;      // total rewards claimed by vault
```

### Epoch Reward Records

```solidity
mapping(uint256 => bool)    public epochFinalized;
mapping(uint256 => uint256) public epochB;
mapping(uint256 => uint256) public epochPartnersPool;
mapping(uint256 => uint256) public epochStakersPool;
mapping(uint256 => uint256) public epochTWRTotal;     // TWR_total across partners that epoch

// Staker claim tracking (pull-based)
mapping(address => uint256) public owedStaker;
```

---

## 4. Epoch Lifecycle

### 4.1 Functions

#### `finalizeEpoch(uint256 epochId)`

- Callable by anyone after epoch ends.
- Finalizes exactly one epoch at a time: `epochId == lastFinalizedEpoch + 1`.
- For each registered PartnerVault:
  - Reads `TWR_p` from the vault's `epochAccumulatedTWR` and resets it.
  - Updates vault activity tracking.
  - Marks vault inactive if `consecutiveInactiveEpochs >= VAULT_EXPIRY_EPOCHS`.
- Computes $\Delta TWR_{total} = \max(0, TWR_{total}(t) - TWR_{total}(t-1))$ for $E_{demand}$.
- Computes budgets, records pools, computes per-partner `vestingEarned[vault][epochId]`.
- Does NOT make rewards immediately claimable (they vest over next 4 epochs).
- Mints PSRE up to the total vesting payment that becomes claimable this epoch.
- Updates `lastEpochTWRTotal` for use in next epoch's $E_{demand}$ calculation.

#### `claimPartnerVested(address vault)`

- Caller must be vault owner.
- Computes and transfers all vested (fully elapsed) tranches across all epochs.
- Specifically: for each epoch `e` where `lastFinalizedEpoch >= e + VESTING_EPOCHS`,
  release remaining unvested balance from `vestingEarned[vault][e]`.
- Marks tranches as claimed.

#### `claimStake(uint256 epochId)`

- Transfers owed staker reward for epochId (unchanged from v2.3).

---

## 5. Detailed Algorithms

### 5.1 Time-Weighted Retention (TWR) — Per-Vault Per-Epoch

**At epoch finalize:**

The RewardEngine reads $TWR_p$ from each PartnerVault:

```
twrP = PartnerVault(vault).epochAccumulatedTWR()
```

Then calls `vault.resetEpochTWR()` (or reads and marks as consumed) to prepare for the
next epoch.

**Within-epoch checkpoint (called by PartnerVault on every state change):**

$$TWR_p^{acc} \mathrel{+}= NR_p(\tau_{now}) \times (t_{now} - t_{last})$$

In code:

```
elapsed = block.timestamp - lastCheckpointTimestamp
currentNR = totalBought
            + Σ balanceOf(cv) for cv in registeredCustomerVaults
            - totalLeaked

epochAccumulatedTWR += currentNR * elapsed
lastCheckpointTimestamp = block.timestamp
```

**Gas optimization:** Rather than summing all CustomerVault balances in real time, maintain a
running `ecosystemBalance` counter in PartnerVault that is updated on every
`distributeToCustomer()`, `reportLeakage()`, and `buy()`. Then:

```
currentNR = ecosystemBalance - totalLeaked
```

where `ecosystemBalance = totalBought` (since all bought PSRE either stays in PartnerVault,
goes to registered CVs via distributeToCustomer, or goes out via transferOut/withdraw).

### 5.2 Vault Activity Check

At epoch finalize, for each vault:

```
if twrP == 0 or epochBuyVolume[vault] < MIN_EPOCH_ACTIVITY:
    consecutiveInactiveEpochs[vault] += 1
    if consecutiveInactiveEpochs[vault] >= VAULT_EXPIRY_EPOCHS:
        vaultActive[vault] = false
else:
    consecutiveInactiveEpochs[vault] = 0
    lastActiveEpochId[vault] = epochId
```

Inactive vaults are excluded from all reward calculations. Their $500 USDC bond remains
claimable from the factory on deregistration.

### 5.3 Rolling EMA Update (Partner Status)

Input is now $twrP$ instead of $\Delta NB$:

$$R_p^{new} = \frac{R_p^{old} \cdot (1 - \theta) + twrP \cdot \theta}{10^{18}}$$

$$sumR \mathrel{+}= R_p^{new} - R_p^{old}$$

In code:

```
R_old = R[vault]
R_new = (R_old * (1e18 - theta) + twrP * theta) / 1e18
sumR  = sumR - R_old + R_new
R[vault] = R_new
```

Compute share and tier:

```
if sumR > 0:
    s = (R_new * 1e18) / sumR
else:
    s = 0

if s >= GOLD_TH:     m = M_GOLD
elif s >= SILVER_TH: m = M_SILVER
else:                m = M_BRONZE

alpha_p = (alphaBase * m) / 1e18
```

### 5.4 Demand Cap

The demand cap is based on the **net increase** in total time-weighted retention per epoch,
not the absolute level. This ensures that emission rewards genuine growth in ecosystem
retention rather than rewarding static holdings at their absolute size.

$$E_{demand}(t) = \max\left(0,\ \alpha_{base} \times \frac{TWR_{total}(t) - TWR_{total}(t-1)}{T_{epoch}}\right)$$

where:
- $TWR_{total}(t) = \sum_p twrP$ (sum of all active partner TWRs this epoch)
- $TWR_{total}(t-1)$ is stored as `lastEpochTWRTotal` from the previous finalization
- $T_{epoch} = \text{EPOCH\_DURATION}$ in seconds (604,800)
- Floor at zero: if the ecosystem's total retention declined, $E_{demand} = 0$ (not negative)

*Rationale:* This measures the net increase in time-weighted retention per epoch. It rewards
new buying **and** sustained holding that expands the total retention base, while applying zero
reward (not negative) when ecosystem retention decreases.

In code:

```
TWR_total_curr = Σ_p twrP   (for all active vaults)
TWR_total_prev = lastEpochTWRTotal

deltaTWR = 0
if TWR_total_curr > TWR_total_prev:
    deltaTWR = TWR_total_curr - TWR_total_prev

E_demand = alphaBase * deltaTWR / EPOCH_DURATION / 1e18

// Store for next epoch
lastEpochTWRTotal = TWR_total_curr
```

### 5.5 Scarcity Cap

$$E_{scarcity}(t) = E_0 \cdot (1 - x(t))^k, \qquad x(t) = \frac{T(t)}{S_{emission}}$$

In code (fixed-point, $k = 2$):

```
x = (T * 1e18) / S_EMISSION
oneMinusX = max(0, 1e18 - x)
// k=2:
E_scarcity = (E0 * oneMinusX / 1e18) * oneMinusX / 1e18
// If x >= 1e18: E_scarcity = 0
```

### 5.6 Final Budget B

$$B(t) = \min\left(E_{demand}(t),\ E_{scarcity}(t),\ S_{emission} - T(t)\right)$$

In code:

```
B = min(E_demand, E_scarcity, S_EMISSION - T)
```

### 5.7 Split

$$B_{partners}(t) = B(t) \times PARTNER\_SPLIT$$

$$B_{stakers}(t) = B(t) - B_{partners}(t) \quad \text{(avoids rounding drift)}$$

In code:

```
B_partners = B * PARTNER_SPLIT / 1e18
B_stakers  = B - B_partners
```

### 5.8 Partner Reward Distribution & Vesting

Weight per partner:

$$w_p = \frac{\alpha_p \cdot twrP}{10^{18}}, \qquad W = \sum_p w_p$$

Partner epoch reward (pre-vesting):

```
if W == 0:
    reward_p = 0 for all partners
    // B_partners unminted or carried forward
else:
    raw_p = B_partners * w_p / W
```

Record vesting entry:

```
vestingEarned[vault][epochId] = raw_p
totalVestingOwed[vault] += raw_p
```

**Minting:** The RewardEngine mints only the PSRE corresponding to tranches that **become
claimable this epoch** — i.e., 25% of rewards earned in epoch `epochId - VESTING_EPOCHS`.

```
mintable_for_vault = vestingEarned[vault][epochId - VESTING_EPOCHS] (if not already minted)
```

Total mint:

```
P_partners = Σ_vault mintable_for_vault
P_stakers  = ... (unchanged, see 5.9)
P = P_partners + P_stakers
mintAmount = min(P, S_EMISSION - T)
```

This ensures minting only occurs for rewards that have completed their vesting period.

**Claim:**

```
claimPartnerVested(vault):
    claimable = 0
    for each epoch e where lastFinalizedEpoch >= e + VESTING_EPOCHS:
        claimable += unvestedBalance(vault, e)
        mark as claimed
    transfer claimable PSRE to vault.partnerOwner
    totalClaimed[vault] += claimable
    totalVestingOwed[vault] -= claimable
```

### 5.9 Staker Reward Distribution (pull-based)

Unchanged from v2.3:

$$\text{reward}_i = B_{stakers} \times \frac{\text{stakeTime}_i}{\text{totalStakeTime}}$$

StakingVault must expose:
- `totalStakeTime(epochId)`
- `stakeTimeOf(user, epochId)`

If `totalStakeTime == 0`, staker pool is unminted (or carried forward).

---

## 6. Minting

```
// Compute mintable amounts for this epoch finalization
P_partners = sum of vesting tranches that unlock this epoch (epoch - VESTING_EPOCHS)
P_stakers  = B_stakers (if totalStakeTime > 0, else 0)
P          = P_partners + P_stakers

mintAmount = min(P, S_EMISSION - T)
require(T + mintAmount <= S_EMISSION)
mint(RewardEngine, mintAmount)
T += mintAmount
```

Record epoch pools for claims.

---

## 7. StakingVault: Time-Weight Accounting

Unchanged from v2.3.

Each deposit/withdraw updates user accumulator:

$$\text{accStakeTime} \mathrel{+}= \text{balance} \times (t_{now} - t_{last})$$

In code:

```
On any action:
accStakeTime += balance * (now - lastUpdateTimestamp)
lastUpdateTimestamp = now
```

At epoch boundary, snapshot stakeTime for that epoch and reset accumulator.
LP and PSRE staking treated equally. Both contribute $\text{stakeTime} = \text{amount} \times \text{duration}$.

---

## 8. Anti-Exploitation Constraints

- PartnerVault cannot execute DEX sells in v3.0 (no sell() function).
- `totalLeaked` is monotonically non-decreasing (leakage cannot be "un-leaked").
- `totalBought` is monotonically non-decreasing.
- Net retention can decrease (via leakage) but is clamped at 0.
- Only vault-registered CustomerVaults count toward retention. External addresses = leakage.
- `distributeToCustomer()` requires target to be in `registeredCustomerVaults`.
- EMA update uses $TWR_p$ per epoch only (not cumulative TWR).
- One epoch finalized at a time, strictly sequential.
- Time-weighted retention rewards holding duration — burst-and-exit strategies produce low TWR.
- 4-epoch reward vesting eliminates single-epoch hit-and-run profitability.
- Vault bond ($500 USDC) creates economic cost for attacker vault creation, fixed in USD terms
  regardless of PSRE price appreciation.
- Non-refundable registration fee (~$50 USDC) creates per-vault attack cost floor.
- Vault expiry after 4 inactive epochs prevents accumulation of ghost vaults.
- Minimum epoch activity threshold prevents micro-spam.
- Time-weighted staking prevents flash stake on staker pool.
- $E_{demand}$ delta formula: if ecosystem retention does not grow, $E_{demand} = 0$, no new
  emission is unlocked regardless of absolute TWR level.

---

## 9. Governance (DAO / Multisig) Controls

DAO/multisig can adjust (bounded):

```
alphaBase        within [0.05, 0.15]
E0               within [0.0005*S_EMISSION, 0.002*S_EMISSION]
tier thresholds and multipliers (bounded)
split ratio      within [0.60, 0.80]
VAULT_BOND       (USDC-denominated; bounded range TBD by DAO at launch)
MIN_EPOCH_ACTIVITY  (USDC equivalent threshold, bounded)
REGISTRATION_FEE (bounded)
```

DAO/multisig **cannot**:

- Mint outside the finalizeEpoch P-based minting rule.
- Change $S_{total}$, $S_{emission}$, $k$, or the scarcity function form.
- Alter vesting schedule (VESTING_EPOCHS is immutable in v3.0).

A timelock should be applied to any parameter updates.

---

## 10. Events (Required)

Emit events for indexers and audits:

```solidity
EpochFinalized(epochId, B, E_demand, E_scarcity, B_partners, B_stakers, minted, TWRTotal, prevTWRTotal)
PartnerTWRComputed(epochId, vault, twrP, alpha_p, weight, rewardEarned)
PartnerVestingScheduled(epochId, vault, amount, claimableAtEpoch)
PartnerVestingClaimed(vault, amount, claimedEpochs)
StakeClaimed(epochId, user, stakeTime, reward)
PartnerBought(vault, amountIn, psreOut, totalBought)
DistributedToCustomer(vault, customerVault, amount)
PSRELeaked(vault, to, amount, newTotalLeaked)
CustomerVaultRegistered(parentVault, customerVault)
CustomerVaultClaimed(customerVault, customerWallet)
VaultBondDeposited(vault, usdcAmount)
VaultBondReturned(vault, usdcAmount)
VaultMarkedInactive(vault, epochId)
VaultDeregistered(vault)
```

---

## 11. Required Invariants (Assertions)

Always enforce:

$$T \leq S_{emission}$$

$$\text{totalLeaked}[\text{vault}] \leq \text{totalBought}[\text{vault}]$$

$$\text{netRetained}[\text{vault}] \geq 0 \quad \text{(clamped; never negative)}$$

$$B(t) \leq E_{demand}(t) \quad \text{and} \quad B(t) \leq E_{scarcity}(t)$$

$$\text{mintAmount} \leq P$$

$$\text{mintAmount} \leq S_{emission} - T$$

In code:

```
assert T <= S_EMISSION
assert totalLeaked[vault] <= totalBought[vault]
assert netRetained[vault] >= 0   (clamped)
assert B <= E_demand and B <= E_scarcity
assert mintAmount <= P
assert mintAmount <= (S_EMISSION - T)
// sumPartnerVestingOwed <= S_EMISSION - T_at_time_of_award (approximate; enforce on claim)
// sumStakeRewards <= B_stakers (allow dust remainder)
// vestingEarned[vault][e] paid out at most once
// consecutiveInactiveEpochs[vault] correctly reset on activity
```

---

## 12. Gas / Scalability Notes

- Partners are likely limited in count → partner reward computation can be done in finalizeEpoch.
- Stakers can be large → staking rewards must be pull-based using StakingVault snapshots.
- CustomerVaults can be numerous → use EIP-1167 minimal proxy clones (cheap to deploy).
- `ecosystemBalance` counter in PartnerVault avoids iterating all CustomerVaults at finalize time.
- Vesting claim loop is bounded by VESTING_EPOCHS (= 4) per call — predictable gas.
- Vault expiry tracking uses simple per-vault counter — O(1) per epoch per vault.
- Avoid looping over all stakers in RewardEngine.
- `lastEpochTWRTotal` is a single storage slot — negligible overhead for $E_{demand}$ delta.

---

## 13. v3.0 Implementation Checklist

1. **PSRE (ERC-20):** unchanged; mint restricted to RewardEngine.

2. **PartnerVaultFactory:**
   - Registration fee collection (USDC → treasury).
   - Vault bond collection ($500 USDC → factory escrow).
   - PartnerVault deployment.
   - CustomerVault deployment (EIP-1167 clone, linked to parent PartnerVault).
   - Deregistration flow (return $500 USDC bond from factory escrow, mark vault deregistered).

3. **PartnerVault:**
   - `buy()` with TWR checkpoint.
   - `distributeToCustomer()` — registered CVs only, no leakage.
   - `transferOut()` — unregistered addresses only, counts as leakage.
   - `registerCustomerVault()`.
   - `reportLeakage(amount)` — called by CustomerVault on customer withdrawal.
   - `_checkpoint()` — internal, updates `epochAccumulatedTWR`.
   - `resetEpochTWR()` — called by RewardEngine at epoch finalize.
   - `ecosystemBalance` counter maintained on every state change.
   - `updateOwner()`.

4. **CustomerVault (EIP-1167 clone):**
   - `receiveReward()` — accept PSRE from parent vault.
   - `claimVault(address)` — customer asserts ownership.
   - `withdraw(amount)` — customer withdrawal; calls `parentVault.reportLeakage()`.
   - `reclaimUnclaimed(amount)` — partner reclaims from unclaimed vault.

5. **StakingVault:** unchanged from v2.3.

6. **RewardEngine (UUPS upgradeable):**
   - `finalizeEpoch()`: read TWR from all active vaults, update EMAs, compute
     $\Delta TWR_{total}$ for $E_{demand}$ (delta formula), compute budgets,
     record `vestingEarned`, update vault activity, mark inactive vaults, mint vested tranches,
     store `lastEpochTWRTotal`.
   - `claimPartnerVested(vault)`: release fully-vested tranches to partner owner.
   - `claimStake(epochId)`: unchanged.
   - Bounded parameter governance.

7. **Unit Tests:**
   - Net retention accounting: buy → distribute to CV → check retention = bought amount.
   - Leakage accounting: buy → transferOut → check retention decreases.
   - CustomerVault claim flow.
   - Leakage via customer withdrawal → parent vault reportLeakage.
   - TWR computation: hold PSRE for full epoch → check TWR = amount × epoch_duration.
   - TWR computation: hold for half epoch, leak half → check TWR accurately reflects duration.
   - Vesting schedule: rewards earned in epoch t not claimable until epoch t+4.
   - Vesting continuity: partner active 8+ epochs → new tranches unlock each epoch.
   - Vault expiry: zero activity for 4 epochs → vault marked inactive; bond still claimable.
   - Wash trading simulation: buy → immediate leakage → net retention ≈ 0 → reward = 0.
   - EMA update on TWR (not deltaNB).
   - Scarcity function correctness near cap.
   - **E_demand delta formula: growing ecosystem → positive E_demand; shrinking or flat → zero.**
   - **E_demand epoch 0: TWR_total(t-1) = 0, so any positive TWR_total(t) yields positive E_demand.**
   - Time-weight staking anti-flash.
   - Rounding/dust behavior.
   - Registration fee routing to treasury.
   - Bond ($500 USDC) escrow and return on deregistration.
   - Invariant assertions: $T \leq S_{emission}$, netRetained $\geq 0$.

---

## 14. Open Design Questions (For Jason / Shu to Resolve Before Implementation)

1. **Vault Bond Amount:** ~~Default is 1,000 PSRE. Should we start lower at launch (e.g., 500
   PSRE) and let DAO adjust upward as PSRE price discovers? Or lock in 1,000 PSRE at genesis?~~
   **Resolved:** Vault bond is $500 USDC, fixed denomination, held in factory escrow, returned
   on deregistration. DAO may adjust the amount within bounds (USDC-denominated).

2. **MIN_EPOCH_ACTIVITY USD Oracle:** The $50 USDC minimum activity check requires a
   PSRE/USDC rate. Options:
   - Use a Chainlink / Uniswap TWAP oracle (live price, but adds oracle risk).
   - DAO-set a fixed rate refreshed periodically via governance (simpler, less real-time).
   - Skip USD normalization entirely and set minimum in PSRE amount (simplest, but degrades
     as PSRE price changes).
   Recommendation: DAO-set rate with a refresh bound (e.g., rate cannot be stale >30 days).

3. **CustomerVault Leakage on Withdrawal:** When a customer withdraws PSRE to their
   external wallet, this reduces the partner's retention score. Should there be a grace period
   or partial exclusion? Or is this intentional — the partner "knew" the customer might withdraw?
   Current spec: leakage is recorded at withdrawal time; no grace period.

4. **Vesting and Deregistration:** If a partner deregisters while they have unvested rewards,
   what happens? Options:
   - Unvested rewards are forfeited (simplest; discourages exit).
   - Unvested rewards continue to vest and become claimable on schedule (requires vault to
     remain registered for tracking even after "exit").
   - Unvested rewards are immediately released on deregistration (removes vesting penalty
     for legitimate exits; weakens anti-wash protection slightly).
   Recommendation: continue vesting on schedule; deregistered vaults can still claim vested
   tranches. Forfeit any unvested tranches beyond a 4-epoch window (i.e., if deregistered
   during vesting, tranches that would have vested more than 4 epochs in the future are burned).

5. **ecosystemBalance vs. Live CV Enumeration:** The spec recommends a running
   `ecosystemBalance` counter to avoid iterating all CustomerVaults. This requires that
   CustomerVaults always call back to the parent on any balance change. Is this acceptable, or
   should we enumerate CVs at finalize (more expensive but simpler custody model)?

6. **EIP-1167 Clone Initialization:** CustomerVault clones need to be initialized with
   `parentVault` address post-deployment. Confirm the factory initialize-then-register pattern
   is acceptable, and clarify whether CustomerVaults should be upgradeable (recommend: no).

7. **E_demand Epoch 0 Bootstrapping:** At epoch 0, `TWR_total(t-1) = 0`, so any positive
   `TWR_total(0)` yields a positive $E_{demand}$. This is correct behavior (all growth from
   zero is net positive). Confirm this is the intended bootstrap behavior.

8. **E_demand and Sustained Holders:** Under the delta formula, partners who maintain a
   constant NR balance produce $TWR_p(t) = NR_p \times T_{epoch}$ each epoch — which is
   constant if NR_p doesn't change. This means $\Delta TWR_p = 0$ for a partner who neither
   buys nor loses PSRE, so $E_{demand} = 0$ if no partner is growing. Is this intended?
   If partners want to continue earning, they must either buy more PSRE or attract/retain more
   customers — which aligns with the protocol's behavioral mining goals. Confirm this is
   acceptable or discuss whether a floor on E_demand for "maintenance" holding is desired.
