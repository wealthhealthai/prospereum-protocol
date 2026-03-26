# DRAFT v3.1 — FOR REVIEW BY JASON AND SHU BEFORE IMPLEMENTATION
# Do not implement until explicitly approved.

---

# Prospereum Developer Specification v3.1

PROSPEREUM (PSRE)
Developer Specification v3.1

---

## 0. Design Decisions Locked for v3.1

- Epoch-based emission (weekly), not per-claim.
- Behavioral mining primitive: **cumulative high-water-mark** of ecosystem balance
  ($\text{cumS}_p$) across the partner vault ecosystem (PartnerVault + all linked
  CustomerVaults).
- **TWR (time-weighted retention) is eliminated.** Replaced by cumS high-water-mark.
- **Vault bond ($500 USDC) is eliminated.** Replaced by un-rewarded initial buy.
- **4-epoch reward vesting is eliminated.** Replaced by first qualification condition.
- **Distribution-to-customer-vaults as reward trigger is eliminated.** Only net ecosystem
  growth (cumS increment) earns reward.
- $S_{eco,p}(t)$ = total PSRE in PartnerVault $p$ + all linked CustomerVaults at epoch $t$.
- $\text{cumS}_p(t) = \max(S_{eco,p}(t),\ \text{cumS}_p(t-1))$ — ratchet, never decreases.
- Reward per epoch: $r_{base} \times \max(0,\ \text{cumS}_p(t) - \text{cumS}_p(t-1))$.
- First qualification: no reward until $\text{cumS}_p(M) > S_p(N)$ (initial buy) for some $M > N$.
  The initial buy earns zero reward — it is the baseline.
- Minimum initial buy $S_{min}$: denominated in USDC (recommended $500 USDC equivalent).
  Factory checks USDC-equivalent input $\geq S_{min}$ before deploying vault.
- Vault expiry: PartnerVaults with zero cumS growth for 4 consecutive epochs become inactive.
  Inactive vaults may reactivate by making a buy; cumS is preserved — never reset.
- cumS is permanently tied to vault address. Deregistered vault cumS is preserved (effectively
  frozen); new vault created by same partner starts at cumS = 0.
- EMA tier system now tracks $\Delta\text{cumS}_p(t)$ increments instead of TWR.
- $E_{demand}(t) = r_{base} \times \sum_p \max(0,\ \text{cumS}_p(t) - \text{cumS}_p(t-1))$.
- Rewards claimable immediately after epoch finalization — no vesting period.
- Scarcity depends only on $x = T / S_{emission}$. Unchanged.
- 70/30 split: partners/stakers (LP shares staker pool). Unchanged.
- Staker rewards are time-weighted (anti flash-stake). Unchanged.
- No presale; treasury seeds LP.

---

## 1. Constants & Global Parameters

### 1.1 Token Supply

$$S_{total} = 21{,}000{,}000 \times 10^{18} \text{ wei}$$

$$S_{emission} = 12{,}600{,}000 \times 10^{18} \text{ wei}$$

### 1.2 Epoch

```
EPOCH_DURATION    = 7 days
genesisTimestamp  = set at deployment
epochId           = (block.timestamp - genesisTimestamp) / EPOCH_DURATION
```

### 1.3 Economic Parameters (v3.1 defaults + bounds)

All parameters stored in RewardEngine contract.

```
r_base = 0.10e18        (base reward rate; 10% default)
  bounds:  [0.05e18, 0.15e18]
  note: named alphaBase in storage for consistency with v3.0 storage layout

E0 (weekly scarcity ceiling, PSRE wei):
  default: 0.001 * S_EMISSION   (12,600 PSRE/week)
  bounds:  [0.0005*S_EMISSION, 0.002*S_EMISSION]

k (scarcity exponent):
  default: 2
  immutable

theta (EMA factor, scaled 1e18):
  default: 1/13 ≈ 0.0769230769e18
  immutable (recommend) or bounded
```

### 1.4 Tier Parameters (cumS increment share thresholds and multipliers)

Rolling share $s_p$ in 1e18-scaled fixed-point. Share is computed on $R_p$ (EMA of
$\Delta\text{cumS}_p$), not on absolute cumS.

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

DAO-adjustable within bounds.

### 1.5 Splits

$$PARTNER\_SPLIT = 0.70 \times 10^{18}$$

$$STAKER\_SPLIT = 0.30 \times 10^{18}$$

DAO-bounded optional range:

$$\text{partner split} \in [0.60,\ 0.80]$$

### 1.6 Vault Lifecycle Parameters

```
S_MIN               = minimum USDC-equivalent for initial buy at vault creation
                      (recommended: $500 USDC equivalent)
                      Denominated in USDC to avoid PSRE price volatility issues.
                      Factory checks: USDC-equivalent of inputToken >= S_MIN before deploying.
                      DAO-adjustable within bounds.

REGISTRATION_FEE    = ~$50 USDC (non-refundable; paid to treasury at vault creation;
                      DAO-adjustable) [optional; may be removed if S_MIN is sufficient deterrent]

VAULT_EXPIRY_EPOCHS = 4  (consecutive epochs with zero cumS growth before auto-expiry)
```

**Eliminated from v3.0:**
- `VAULT_BOND` — removed. Replaced by un-rewarded initial buy.
- `MIN_EPOCH_ACTIVITY` — removed. Activity is now tracked by cumS growth, not buy volume.
- `VESTING_EPOCHS` — removed. Replaced by first qualification condition.

### 1.7 First Qualification Condition

```
// Stored per vault at creation
initialCumS[vault] = S_p(N)   // initial buy amount at epoch N

// No reward is earned until cumS_p(M) > initialCumS[vault] for some M > N.
// The delta that earns first reward = cumS_p(M) - initialCumS[vault]
// Applied at r_base (no tier multiplier on first qualification? — TBD: recommend yes, apply tier)
```

After first qualification, the vault is marked `qualified = true` and the ongoing reward
formula applies to all future epochs.

### 1.8 Rounding & Dust Rules

- Compute all rewards with integer division.
- Total partner payouts may be slightly less than $B_{partners}$ due to rounding.
- Dust stays unminted (scarcity-positive). Do not carry forward in v3.1.

### 1.9 When sumR == 0

In early epochs there may be no partners with $\Delta\text{cumS} > 0$.

```
if sumR == 0:
    s_p = 0 for all partners
    alpha_p = r_base for any partner with deltaCumS_p > 0
```

Or skip status calculation and assign Bronze to all active qualifying partners.

### 1.10 When W == 0 (Partner Weight Total is Zero)

```
if W == 0:
    partner pool = 0   (leave unminted; scarcity-positive)
```

---

## 2. Contracts & Responsibilities

### 2.1 PSRE (ERC-20)

- Standard ERC-20 with `decimals = 18`.
- `mint(to, amount)` callable only by RewardEngine.
- No other mint authority.
- Immutable — no upgrade proxy.

### 2.2 PartnerVaultFactory

Creates PartnerVaults and maintains the global vault registry.

**Mappings:**
```
partnerAddress → vaultAddress
vaultAddress → partnerAddress
customerVaultAddress → parentPartnerVault
```

**Vault creation flow:**

At creation, the factory:
1. Validates USDC-equivalent input amount $\geq S_{min}$. **Revert if insufficient.**
2. Collects the registration fee (USDC) and forwards to treasury (if REGISTRATION_FEE > 0).
3. Deploys the PartnerVault contract (or initializes a minimal proxy).
4. Triggers the initial buy on behalf of the vault: USDC is routed through the DEX, PSRE
   output is deposited into the new PartnerVault.
5. Records `initialCumS[vault] = psreOut` (initial buy amount, in PSRE wei).
6. Sets `cumS[vault] = psreOut`, `S_eco[vault] = psreOut`.
7. Sets `qualified[vault] = false`.
8. Registers vault in factory mappings.
9. Emits `VaultCreated(vault, partner, psreOut, epochId)`.

**No vault bond is collected.** The initial PSRE buy IS the entry cost.

**Deregistration flow:**

On partner-initiated deregistration:
- Mark vault as deregistered. `cumS` is preserved (frozen) for historical record.
- No bond to return.
- If vault had any claimable rewards not yet claimed, allow claim within a grace window (e.g.,
  4 epochs post-deregistration) then forfeit. **(Open question: see Section 14.)**

### 2.3 PartnerVault

**Purpose:** Enforce accounting boundary for the partner's vault ecosystem. Track
$S_{eco,p}$ and $\text{cumS}_p$. Serve as on-chain identity for reward accounting.

The controlling wallet address (owner) may be updated via `updateOwner()` to allow wallet
migration without losing partner history or cumS state.

#### Key Rules

- `buy()` adds PSRE to the vault ecosystem. Updates $S_{eco}$ and cumS (if new balance
  exceeds prior cumS).
- `distributeToCustomer(cv, amount)` moves PSRE to a registered CustomerVault. $S_{eco}$
  is unchanged — PSRE stays within the ecosystem boundary. cumS is unaffected.
- `transferOut(to, amount)` — sends PSRE to an unregistered address. Reduces $S_{eco}$.
  cumS is NOT reduced (ratchet). This means the partner must rebuy past cumS to earn reward.
- Vault SELL to DEX: **DISABLED.** No `sell()` function.

#### State

```solidity
// Partner identity
address public partnerOwner;
address public rewardEngine;
address public factory;

// Ecosystem balance (tracks current total PSRE in ecosystem)
uint256 public ecosystemBalance;
// = PSRE in PartnerVault + Σ PSRE in all registeredCustomerVaults
// Updated on every buy(), distributeToCustomer(), transferOut(), reportLeakage()

// cumS high-water-mark (ratchet — only ever increases)
uint256 public cumS;

// First qualification
bool    public qualified;       // false until cumS_p(M) > initialCumS for some M > N
uint256 public initialCumS;     // set at vault creation = initial buy amount

// Customer vault registry
mapping(address => bool)  public registeredCustomerVaults;
address[]                 public customerVaultList;   // enumerable for off-chain

// Activity tracking (for expiry)
uint256 public lastCumSUpdateEpoch;        // epoch when cumS last grew
uint256 public consecutiveInactiveEpochs;  // epochs without cumS growth
bool    public vaultActive;

// Historical snapshot for RewardEngine
uint256 public lastEpochCumS;   // cumS value snapshotted at last epoch finalization
```

**Note:** `ecosystemBalance` is the running counter for current PSRE in ecosystem.
`cumS = max(ecosystemBalance, cumS)` is updated at every event and at epoch finalization.

#### Computed Properties

```
deltaCumS(t) → uint256:
    return max(0, cumS - lastEpochCumS)
    // computed by RewardEngine at epoch finalize, not stored in vault
```

#### Functions

```solidity
// Execute a PSRE purchase via DEX router
function buy(address router, bytes calldata swapData) external onlyOwner
    → USDC (or approved token) sent to router, psreOut received
    → ecosystemBalance += psreOut
    → _updateCumS()
    → emit PartnerBought(address(this), amountIn, psreOut, ecosystemBalance, cumS)

// Distribute PSRE reward to a registered CustomerVault (ecosystem boundary unchanged)
function distributeToCustomer(address customerVault, uint256 amount) external onlyOwner
    → require registeredCustomerVaults[customerVault]
    → transfer PSRE to customerVault
    → ecosystemBalance unchanged (PSRE stays in ecosystem)
    → emit DistributedToCustomer(address(this), customerVault, amount)

// Transfer PSRE to an unregistered address (exits ecosystem; cumS ratchet holds)
function transferOut(address to, uint256 amount) external onlyOwner
    → require !registeredCustomerVaults[to]
    → require !factory.isRegisteredVault(to)
    → transfer PSRE to `to`
    → ecosystemBalance -= amount
    // cumS is NOT changed — ratchet holds at prior high
    → emit PSREExitedEcosystem(address(this), to, amount, ecosystemBalance, cumS)

// Called by CustomerVault when customer withdraws PSRE externally
// Reduces ecosystemBalance; cumS ratchet holds
function reportLeakage(uint256 amount) external onlyRegisteredCV
    → ecosystemBalance -= amount
    // cumS unchanged
    → emit PSRELeaked(address(this), amount, ecosystemBalance, cumS)

// Register a new CustomerVault linked to this PartnerVault
function registerCustomerVault(address customerVault) external onlyOwner
    → verify customerVault was deployed by factory for this vault
    → registeredCustomerVaults[customerVault] = true
    → customerVaultList.push(customerVault)
    → emit CustomerVaultRegistered(address(this), customerVault)

// Internal: update cumS ratchet after any ecosystem balance change
function _updateCumS() internal
    → if ecosystemBalance > cumS:
          cumS = ecosystemBalance

// Called by RewardEngine at epoch finalize: snapshot and return delta
function snapshotEpoch() external onlyRewardEngine returns (uint256 deltaCumS)
    → deltaCumS = (cumS > lastEpochCumS) ? cumS - lastEpochCumS : 0
    → lastEpochCumS = cumS
    → update vault activity / inactive epoch counters (see Section 5.2)
    → return deltaCumS

// Update owner (wallet migration)
function updateOwner(address newOwner) external onlyOwner
```

#### Security

- `buy()` must validate `psreOut > 0`.
- Use `ReentrancyGuard` on all state-changing functions.
- Restrict `buy()` router calls to factory-approved router addresses.
- `distributeToCustomer()` requires target in `registeredCustomerVaults`.
- `transferOut()` explicitly blocks registered vaults as targets.
- `reportLeakage()` callable only by registered CustomerVaults (`onlyRegisteredCV` modifier).
- `snapshotEpoch()` callable only by RewardEngine (`onlyRewardEngine` modifier).
- `ecosystemBalance` cannot go below zero (SafeMath / explicit require).

---

### 2.3a CustomerVault

**Purpose:** Lightweight on-chain escrow for a single customer's PSRE rewards. Linked to
exactly one parent PartnerVault. Customers do not need to interact with the blockchain;
the partner's backend manages all deposits.

#### Design Principles

- Minimal gas footprint (no complex state, no reward engine interaction).
- Deployed by PartnerVaultFactory on behalf of a PartnerVault.
- PSRE received from parent PartnerVault stays here and counts toward parent's $S_{eco}$.
- Customer may claim ownership at any time by asserting their wallet address.

#### State

```solidity
address public parentVault;       // the PartnerVault that registered this CV
address public customer;          // address(0) until claimed
bool    public customerClaimed;
```

#### Functions

```solidity
// Called by parentVault to deposit PSRE
function receiveReward(uint256 amount) external onlyParent
    → accept PSRE transfer (ERC-20 transferFrom or direct receive)

// Customer asserts ownership
function claimVault(address customerWallet) external
    → require customer == address(0)
    → require msg.sender == customerWallet
    → customer = customerWallet
    → customerClaimed = true
    → emit CustomerVaultClaimed(address(this), customerWallet)

// Customer withdraws PSRE to external wallet
// Note: reduces parent's ecosystemBalance; cumS ratchet holds in parent
function withdraw(uint256 amount) external onlyCustomer
    → transfer PSRE to customer
    → parentVault.reportLeakage(amount)
    → emit CustomerWithdraw(address(this), customer, amount)

// Partner reclaims PSRE from unclaimed vault (e.g., account created in error)
// Returns PSRE to parentVault — ecosystemBalance unchanged
function reclaimUnclaimed(uint256 amount) external onlyParent
    → require !customerClaimed
    → transfer PSRE back to parentVault
    // ecosystemBalance unchanged; cumS unchanged; no leakage
    → emit CustomerVaultReclaimed(address(this), parentVault, amount)
```

#### Gas Notes

Use EIP-1167 minimal proxy (clone) pattern deployed by PartnerVaultFactory. Clones
share the implementation contract bytecode; only storage differs per instance. This
minimizes deployment gas for potentially thousands of CustomerVaults.

Initialization via `initialize(address _parentVault)` called immediately after clone
deployment by factory.

---

### 2.4 StakingVault (includes LP staking)

Unchanged from v3.0. PSRE staking and LP staking are treated equivalently in the staking
reward pool.

- Tracks time-weighted stake per epoch for each user.
- Supports `stakePSRE(amount)` and `stakeLP(amount)`.
- $\text{stakeTime} = \text{amount} \times \text{stakingDuration}$ with no weighting multiplier.

---

### 2.5 RewardEngine (combined emission + reward vault)

The core monetary policy contract. UUPS upgradeable.

**Responsibilities (v3.1 changes in bold):**

- Track total emitted $T$.
- Maintain epoch state.
- **Compute $\Delta\text{cumS}_p$ per partner vault per epoch via `vault.snapshotEpoch()`.**
- **Compute first qualification check: if `!qualified[vault]` and `cumS[vault] > initialCumS[vault]`, mark qualified and compute first reward.**
- Compute EMA status (now on $\Delta\text{cumS}_p$ instead of TWR).
- **Compute demand cap: $E_{demand}(t) = r_{base} \times \sum_p \max(0, \text{cumS}_p(t) - \text{cumS}_p(t-1))$.**
- Compute scarcity cap, final budget $B$.
- Compute partner rewards (no vesting) and staker rewards.
- **Track vault activity (cumS growth epochs); mark vaults inactive after VAULT_EXPIRY_EPOCHS.**
- Mint and pay rewards.
- **No vesting ledger required.** Rewards are claimable immediately.

---

## 3. Storage Layout (RewardEngine)

### Global

```solidity
uint256 public T;                      // cumulative PSRE emitted
uint256 public genesisTimestamp;
uint256 public lastFinalizedEpoch;
uint256 public alphaBase;              // r_base, 1e18-scaled
uint256 public E0;                     // wei
uint256 public k;                      // uint (immutable in v3.1)
uint256 public theta;                  // 1e18-scaled EMA factor
// tier thresholds + multipliers
// split params
// vault lifecycle params
uint256 public S_MIN;                  // minimum initial buy (USDC equivalent, wei)
```

### Partner Accounting (by vault address)

```solidity
// cumS-based accounting
mapping(address => uint256) public lastEpochCumS;      // cumS_p snapshotted at last finalize
mapping(address => uint256) public R;                  // EMA rolling score (tracks deltaCumS)
uint256 public sumR;                                   // sum of all R values

// First qualification
mapping(address => bool)    public qualified;          // false until first cumS > initialCumS
mapping(address => uint256) public initialCumS;        // cumS at vault creation (initial buy)

// Vault activity tracking
mapping(address => uint256) public lastGrowthEpoch;    // last epoch where deltaCumS > 0
mapping(address => uint256) public consecutiveInactive; // epochs without cumS growth
mapping(address => bool)    public vaultActive;

// Reward claim tracking (pull-based, no vesting)
mapping(address => uint256) public owedPartner;        // unclaimed partner rewards
mapping(address => uint256) public totalClaimed;       // lifetime claimed
```

### Epoch Records

```solidity
mapping(uint256 => bool)    public epochFinalized;
mapping(uint256 => uint256) public epochB;
mapping(uint256 => uint256) public epochPartnersPool;
mapping(uint256 => uint256) public epochStakersPool;
mapping(uint256 => uint256) public epochDeltaCumSTotal;  // sum of all deltaCumS this epoch

// Staker claim tracking (pull-based)
mapping(address => uint256) public owedStaker;
```

---

## 4. Epoch Lifecycle

### 4.1 Functions

#### `finalizeEpoch(uint256 epochId)`

Callable by anyone after epoch ends. Finalizes exactly one epoch:
`epochId == lastFinalizedEpoch + 1`.

**For each registered active PartnerVault:**

1. Call `vault.snapshotEpoch()` → returns `deltaCumS_p`.
2. Read `qualified[vault]` and `initialCumS[vault]`.
3. If `!qualified[vault]`:
   - Check if vault's current `cumS > initialCumS[vault]`.
   - If yes: mark `qualified[vault] = true`, and compute first reward:
     `firstReward = r_base * (cumS_current - initialCumS[vault])` (this equals
     `r_base * deltaCumS_p` if cumS just crossed the threshold this epoch, or a
     smaller amount if it crossed on a prior epoch but wasn't yet marked qualified —
     **important: first reward uses entire delta above initialCumS, not just this epoch's increment**).
   - If no: `deltaCumS_p` contribution = 0 (initial buy epoch earns nothing).
4. If `qualified[vault]`: compute `rewardRaw_p = r_p * deltaCumS_p`.
5. Accumulate `deltaCumSTotal += deltaCumS_p`.
6. Update vault activity tracker.

**Compute budgets:**

```
E_demand = alphaBase * deltaCumSTotal / 1e18
E_scarcity = E0 * (1 - x)^k    (see Section 5.5)
B = min(E_demand, E_scarcity, S_EMISSION - T)
B_partners = B * PARTNER_SPLIT / 1e18
B_stakers  = B - B_partners
```

**Distribute partner rewards:**

```
W = Σ_p (alpha_p * deltaCumS_p) / 1e18
if W > 0:
    for each qualifying vault p:
        raw_p = B_partners * (alpha_p * deltaCumS_p / 1e18) / W
        owedPartner[vault] += raw_p
```

**Mint:**

```
P_stakers  = B_stakers (if totalStakeTime > 0, else 0)
P_partners = min(Σ raw_p, B_partners)
mintAmount = min(P_partners + P_stakers, S_EMISSION - T)
mint(RewardEngine, mintAmount)
T += mintAmount
```

**Record epoch:**

```
epochFinalized[epochId] = true
epochB[epochId] = B
epochPartnersPool[epochId] = B_partners
epochStakersPool[epochId] = B_stakers
epochDeltaCumSTotal[epochId] = deltaCumSTotal
lastFinalizedEpoch = epochId
```

#### `claimPartnerReward(address vault)`

- Caller must be vault owner.
- Transfer `owedPartner[vault]` PSRE to vault owner.
- `owedPartner[vault] = 0`.
- `totalClaimed[vault] += claimedAmount`.
- Emit `PartnerRewardClaimed(vault, claimedAmount)`.

No vesting check required. Rewards are immediately claimable after finalization.

#### `claimStake(uint256 epochId)`

Unchanged from v3.0 — transfers owed staker reward for epochId.

---

## 5. Detailed Algorithms

### 5.1 cumS Update — Per-Vault

**Within PartnerVault (on every balance-changing event):**

```solidity
function _updateCumS() internal {
    if (ecosystemBalance > cumS) {
        cumS = ecosystemBalance;
    }
}
```

**Called after:** `buy()`, `reportLeakage()`, `transferOut()` (note: last two reduce
ecosystemBalance but do NOT reduce cumS — the ratchet property is enforced by only
calling `_updateCumS()` after increases, or equivalently by never decreasing cumS).

Implementation note: `_updateCumS()` should only set `cumS = ecosystemBalance` if
`ecosystemBalance > cumS`. It must never decrease cumS.

**At epoch finalize (called by RewardEngine via `snapshotEpoch()`):**

```solidity
function snapshotEpoch() external onlyRewardEngine returns (uint256 deltaCumS) {
    _updateCumS();  // ensure cumS reflects any mid-epoch buys not yet snapshotted
    deltaCumS = (cumS > lastEpochCumS) ? cumS - lastEpochCumS : 0;
    lastEpochCumS = cumS;
    // activity update happens in RewardEngine after receiving deltaCumS
}
```

### 5.2 Vault Activity Check

In RewardEngine, after receiving `deltaCumS_p` from each vault:

```
if deltaCumS_p > 0:
    consecutiveInactive[vault] = 0
    lastGrowthEpoch[vault] = epochId
else:
    consecutiveInactive[vault] += 1
    if consecutiveInactive[vault] >= VAULT_EXPIRY_EPOCHS:
        vaultActive[vault] = false
        emit VaultMarkedInactive(vault, epochId)
```

**Reactivation:** An inactive vault may call `buy()` at any time. On the next
`finalizeEpoch()`, the vault's `deltaCumS_p > 0` (if the buy raised cumS), which resets
`consecutiveInactive[vault] = 0` and sets `vaultActive[vault] = true`.

```
// In finalizeEpoch, before activity check:
if !vaultActive[vault] and deltaCumS_p > 0:
    vaultActive[vault] = true
    emit VaultReactivated(vault, epochId)
```

**cumS preservation on reactivation:** cumS is never reset. The partner must grow past
their historical peak cumS to earn any reward. This is automatically enforced by the ratchet.

### 5.3 First Qualification Check

In RewardEngine at epoch finalize, for each vault where `!qualified[vault]`:

```
currentCumS = lastEpochCumS[vault]   // just updated by snapshotEpoch()
//  (lastEpochCumS was set to vault's cumS after snapshot — i.e., current cumS)

if currentCumS > initialCumS[vault]:
    qualified[vault] = true
    // First reward = r_base * (currentCumS - initialCumS[vault])
    // This is already captured in deltaCumS_p calculation IF the initial epoch
    // was properly excluded. Implementation must ensure:
    //   epoch N (creation): deltaCumS_p = 0 (initialCumS was set = cumS at creation)
    //   epoch M (first growth): deltaCumS_p = cumS_M - initialCumS = first reward basis
    emit VaultFirstQualified(vault, epochId, currentCumS, initialCumS[vault])
```

**Edge case — partial growth across epochs:**

If the vault partially grows in epoch $M_1$ but doesn't cross initialCumS, and crosses in
epoch $M_2$:

- Epoch $M_1$: `cumS_p(M_1) > cumS_p(N)` (N = creation) but `cumS_p(M_1) <= initialCumS`. 
  Hmm — actually `initialCumS == cumS_p(N)`, so any growth above creation amount crosses it.
  
Clarification: `initialCumS[vault] = S_p(N)` (the initial buy PSRE amount). Any epoch
where `cumS > initialCumS` qualifies. The first such epoch is epoch $M$.

The `deltaCumS_p` for epoch $M$ will be `cumS_p(M) - cumS_p(M-1)`. The reward basis for
first qualification is this delta, computed consistently with the ongoing formula. There is no
special "catch-up" for multiple epochs of un-rewarded growth below the threshold — each
epoch's reward is based on that epoch's cumS increment.

**Recommendation:** Store `lastEpochCumS[vault] = initialCumS[vault]` at vault creation,
so that the first epoch where cumS grows past initialCumS, `deltaCumS_p = cumS_p(M) - initialCumS[vault]`,
which correctly reflects the first reward basis.

### 5.4 Rolling EMA Update (Partner Status)

EMA now tracks $\Delta\text{cumS}_p$ (cumS increment per epoch):

$$R_p(t) = (1-\theta) \cdot R_p(t-1) + \theta \cdot \Delta\text{cumS}_p(t)$$

Where $\Delta\text{cumS}_p(t) = \max(0,\ \text{cumS}_p(t) - \text{cumS}_p(t-1))$.

In code:

```
R_old = R[vault]
deltaCumS_p = max(0, currentCumS - lastEpochCumS_before_snapshot)

R_new = (R_old * (1e18 - theta) + deltaCumS_p * theta) / 1e18
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

Unqualified vaults (where `!qualified[vault]`) use `deltaCumS_p = 0` for EMA update —
they accumulate no contribution score until they qualify.

### 5.5 Demand Cap

$$E_{demand}(t) = r_{base} \times \sum_p \max\!\left(0,\ \text{cumS}_p(t) - \text{cumS}_p(t-1)\right)$$

In code:

```
deltaCumSTotal = Σ_p deltaCumS_p   // sum of all qualifying partner increments

E_demand = alphaBase * deltaCumSTotal / 1e18
// no division by EPOCH_DURATION — cumS is denominated in PSRE wei, not PSRE*seconds
```

**Key difference from v3.0:** $E_{demand}$ is now based on $\sum \Delta\text{cumS}_p$
(cumulative high-water-mark growth in PSRE wei), not on $\Delta TWR$ (retention × time).
This removes the EPOCH_DURATION divisor from the demand formula.

### 5.6 Scarcity Cap

$$E_{scarcity}(t) = E_0 \cdot (1 - x(t))^k, \qquad x(t) = \frac{T(t)}{S_{emission}}$$

In code (fixed-point, $k = 2$):

```
x = (T * 1e18) / S_EMISSION
oneMinusX = max(0, 1e18 - x)
E_scarcity = (E0 * oneMinusX / 1e18) * oneMinusX / 1e18
// If x >= 1e18: E_scarcity = 0
```

### 5.7 Final Budget B

$$B(t) = \min\left(E_{demand}(t),\ E_{scarcity}(t),\ S_{emission} - T(t)\right)$$

In code:

```
B = min(E_demand, E_scarcity, S_EMISSION - T)
```

### 5.8 Split

$$B_{partners}(t) = B(t) \times PARTNER\_SPLIT$$

$$B_{stakers}(t) = B(t) - B_{partners}(t)$$

In code:

```
B_partners = B * PARTNER_SPLIT / 1e18
B_stakers  = B - B_partners
```

### 5.9 Partner Reward Distribution (No Vesting)

Per-partner weight:

$$w_p = \frac{\alpha_p \cdot \Delta\text{cumS}_p}{10^{18}}, \qquad W = \sum_p w_p$$

Partner epoch reward:

```
if W == 0:
    reward_p = 0 for all partners
    // B_partners unminted
else:
    for each qualifying vault p:
        raw_p = B_partners * w_p / W
        owedPartner[vault] += raw_p
```

No vesting schedule. `owedPartner[vault]` is immediately claimable by the vault owner via
`claimPartnerReward(vault)`.

### 5.10 Staker Reward Distribution (pull-based)

Unchanged from v3.0:

$$\text{reward}_i = B_{stakers} \times \frac{\text{stakeTime}_i}{\text{totalStakeTime}}$$

StakingVault exposes:
- `totalStakeTime(epochId)`
- `stakeTimeOf(user, epochId)`

If `totalStakeTime == 0`: staker pool is unminted.

---

## 6. Minting

```
P_partners = Σ raw_p (for all qualifying vaults this epoch)
P_stakers  = B_stakers (if totalStakeTime > 0, else 0)
P          = P_partners + P_stakers

mintAmount = min(P, S_EMISSION - T)
require(T + mintAmount <= S_EMISSION)
mint(RewardEngine, mintAmount)
T += mintAmount
```

Record epoch pools for staker claims. Partner amounts added to `owedPartner[vault]` directly.

---

## 7. StakingVault: Time-Weight Accounting

Unchanged from v3.0.

Each deposit/withdraw updates user accumulator:

```
accStakeTime += balance * (now - lastUpdateTimestamp)
lastUpdateTimestamp = now
```

At epoch boundary, snapshot stakeTime for that epoch and reset accumulator.
LP and PSRE staking treated equally. Both contribute $\text{stakeTime} = \text{amount} \times \text{duration}$.

---

## 8. Anti-Exploitation Constraints

- PartnerVault cannot execute DEX sells (no `sell()` function).
- `cumS` is monotonically non-decreasing (ratchet property). Only `_updateCumS()` modifies
  it, and only in the upward direction.
- `ecosystemBalance` can decrease (via leakage/transferOut) but cannot go below zero.
- cumS never decreases when ecosystemBalance decreases.
- Only vault-registered CustomerVaults are within ecosystem boundary. External = not in S_eco.
- `distributeToCustomer()` requires target in `registeredCustomerVaults`.
- `reportLeakage()` requires caller in `registeredCustomerVaults`.
- EMA update uses $\Delta\text{cumS}_p$ per epoch only (not cumulative cumS).
- One epoch finalized at a time, strictly sequential.
- Un-rewarded initial buy: no reward earned until cumS grows past `initialCumS[vault]`.
- cumS ratchet: selling PSRE does not reduce cumS; rebuy must exceed prior peak.
- Vault expiry after 4 inactive epochs (no cumS growth) prevents ghost vault accumulation.
- cumS never resets on reactivation or deregistration; tied permanently to vault address.
- New vault created by same partner address starts at cumS = 0.
- Time-weighted staking prevents flash stake on staker pool.
- $E_{demand}$ is zero if no partner grew their cumS — no emission for flat ecosystem.
- Scarcity cap $E_{scarcity}(t)$ declines monotonically; no demand pressure can exceed it.

---

## 9. Design Rationale: Anti-Gaming and Commerce Alignment

### 9.1 Why cumS High-Water-Mark Prevents Wash Trading

- Selling PSRE does not reduce cumS. The ratchet preserves the high-water-mark.
- To earn any reward after selling, the attacker must rebuy past their prior peak — this is a
  permanent capital commitment: the sold PSRE must be repurchased from the market.
- Each "buy → sell → rebuy" cycle requires more net capital than the last. The strategy is
  self-limiting and cannot be sustained indefinitely with any fixed capital base.

### 9.2 Why Initial Buy Earns No Reward

- The un-rewarded $S_p(N)$ is the natural entry cost — strictly more punitive than a
  refundable bond. A bond is returned; the initial buy incurs irrecoverable fees with zero reward.
- Spammers pay $S_{min}$ per vault with zero return on creation — no economic incentive to
  mass-create vaults.
- Combined with the scarcity cap: mass vault spam cannot generate enough $E_{demand}$ to
  cover the entry costs. Self-defeating at scale.

### 9.3 Why No Vesting Schedule

- Vesting only delays reward extraction; it does not change the profitability math of recurring
  cycles. A patient attacker still profits from vesting — they just wait longer.
- The first qualification condition (cumS > initialCumS) is structurally stronger: it requires
  demonstrated growth, not just elapsed time. No amount of patience earns the first reward
  without genuine ecosystem expansion.

### 9.4 Why Distribution to Customers Earns No Direct Reward

- Distribution to registered CustomerVaults is gameable: a partner controls both the parent
  vault and the customer vaults. A partner could register thousands of fake customer vaults and
  "distribute" to them without any real customers, inflating a distribution-based reward metric.
- Instead, partners are commercially incentivized to distribute because a real growing customer
  base drives more customer buying, which grows $S_{eco}$, which raises cumS, which earns
  reward. The indirect incentive is commerce-aligned and cannot be decoupled from real activity.

### 9.5 Why Rewards Flow with Growth but Stop When Flat

- Flat or declining ecosystem = no new economic value created = no new reward. Rewarding
  flat holdings would incentivize pure capital parking.
- Real partners with growing customer bases naturally grow cumS continuously. Reward flows
  naturally with genuine commerce activity.
- Slow seasons earn zero but do not forfeit past cumS. When growth resumes, rewards resume
  immediately, encouraging long-term program maintenance rather than abandonment.

---

## 10. Governance (DAO / Multisig) Controls

DAO/multisig can adjust (bounded):

```
alphaBase         within [0.05e18, 0.15e18]
E0                within [0.0005*S_EMISSION, 0.002*S_EMISSION]
tier thresholds   (bounded; recommend ±50% of defaults)
tier multipliers  (bounded)
split ratio       within [0.60, 0.80] (partner share)
S_MIN             (USDC-denominated minimum initial buy; bounded range TBD at launch)
REGISTRATION_FEE  (bounded, or set to 0)
```

DAO/multisig **cannot**:

- Mint outside the `finalizeEpoch` P-based minting rule.
- Change $S_{total}$, $S_{emission}$, $k$, or the scarcity function form.
- Decrease cumS of any vault.
- Reset `initialCumS` or `qualified` state of any vault.

A timelock should be applied to all parameter updates (recommend 48-hour minimum).

---

## 11. Events (Required)

```solidity
// Epoch
EpochFinalized(epochId, B, E_demand, E_scarcity, B_partners, B_stakers, minted, deltaCumSTotal)
PartnerCumSSnapshot(epochId, vault, cumS, deltaCumS, alpha_p, weight, rewardEarned)
VaultFirstQualified(vault, epochId, cumS, initialCumS)

// Partner rewards
PartnerRewardAccrued(epochId, vault, amount)
PartnerRewardClaimed(vault, amount)

// Staker
StakeClaimed(epochId, user, stakeTime, reward)

// Vault ops
PartnerBought(vault, amountIn, psreOut, ecosystemBalance, cumS)
DistributedToCustomer(vault, customerVault, amount)
PSREExitedEcosystem(vault, to, amount, ecosystemBalance, cumS)
PSRELeaked(vault, amount, ecosystemBalance, cumS)

// Vault lifecycle
VaultCreated(vault, partner, initialCumS, epochId)
CustomerVaultRegistered(parentVault, customerVault)
CustomerVaultClaimed(customerVault, customerWallet)
CustomerWithdraw(customerVault, customer, amount)
CustomerVaultReclaimed(customerVault, parentVault, amount)
VaultMarkedInactive(vault, epochId)
VaultReactivated(vault, epochId)
VaultDeregistered(vault, epochId)
```

---

## 12. Required Invariants (Assertions)

Always enforce:

$$T \leq S_{emission}$$

$$\text{cumS}_p \geq \text{ecosystemBalance}_p \quad \text{(ratchet: cumS ≥ current balance)}$$

$$\text{cumS}_p(t) \geq \text{cumS}_p(t-1) \quad \text{(monotonically non-decreasing)}$$

$$\text{ecosystemBalance}_p \geq 0$$

$$B(t) \leq E_{demand}(t) \quad \text{and} \quad B(t) \leq E_{scarcity}(t)$$

$$\text{mintAmount} \leq P$$

$$\text{mintAmount} \leq S_{emission} - T$$

$$\text{initialCumS}[\text{vault}] \leq \text{cumS}[\text{vault}] \quad \forall t \geq N$$

In code:

```
assert T <= S_EMISSION
assert cumS[vault] >= ecosystemBalance[vault]   // ratchet invariant
assert cumS[vault] >= cumS_prev[vault]          // monotonicity
assert ecosystemBalance[vault] >= 0
assert B <= E_demand and B <= E_scarcity
assert mintAmount <= P
assert mintAmount <= (S_EMISSION - T)
// qualified[vault] == false only while cumS[vault] == initialCumS[vault]
//   (once qualified = true, never reverts to false)
// owedPartner[vault] correctly zeroed after claim
// VaultExpiry: consecutiveInactive[vault] accurately maintained
```

---

## 13. Gas / Scalability Notes

- Partners are likely limited in count → partner reward computation can be done in
  `finalizeEpoch` with a loop over active vaults.
- Stakers can be large → staking rewards must be pull-based using StakingVault snapshots.
- CustomerVaults can be numerous → use EIP-1167 minimal proxy clones.
- `ecosystemBalance` counter in PartnerVault avoids iterating all CustomerVaults at finalize.
  PartnerVault maintains a running counter updated on every event.
- No vesting ledger — eliminates the per-epoch per-vault vesting storage from v3.0.
  Rewards go directly to `owedPartner[vault]`.
- Vault expiry tracking uses per-vault counter — O(1) per epoch per vault.
- `snapshotEpoch()` is a single external call per vault per epoch — predictable gas.
- Avoid looping over all stakers in RewardEngine.

---

## 14. Open Design Questions (For Jason / Shu to Resolve Before Implementation)

1. **Tier multiplier on first reward:** Does the tier multiplier apply to the first reward
   (when the vault first qualifies)? Or does it only apply from the second epoch onward?
   The EMA will be low for a newly qualified vault (it has zero history), so they'll be Bronze.
   Applying Bronze multiplier to first reward seems natural — but confirm.

2. **Unqualified vault EMA update:** Should `R[vault]` accumulate EMA during the unqualified
   period? Current spec says `deltaCumS_p = 0` for unqualified vaults, so EMA builds from 0.
   Once qualified, the first growth epoch will be a clean EMA input. Confirm this is acceptable
   (vs. retroactively crediting pre-qualification growth to EMA).

3. **Deregistration with outstanding rewards:** If a partner deregisters while `owedPartner[vault] > 0`,
   what is the policy? Options:
   - Allow claim for a grace window after deregistration, then forfeit.
   - Allow claim indefinitely (rewards are already minted and owed).
   - Forfeit immediately on deregistration.
   Recommendation: Allow claim for a fixed grace window (e.g., 4 epochs = 28 days) post-
   deregistration, then allow anyone to reclaim dust to treasury.

4. **$S_{min}$ oracle for USDC equivalent:** The factory must validate that the initial buy
   input token amount is worth $\geq S_{min}$ USDC. Options:
   - Use a Chainlink PSRE/USDC price feed (adds oracle risk and dependency).
   - Use a Uniswap TWAP (same).
   - DAO sets a PSRE-denominated floor that is refreshed via governance when price moves
     significantly (simpler, but requires active governance participation).
   - Denominate S_MIN in input token (USDC directly if partner always buys with USDC — simplest).
   Recommendation: If initial buy is always USDC-in (partner sends USDC, factory routes to DEX
   for PSRE), validate `usdcAmountIn >= S_MIN` directly with no oracle needed.

5. **ecosystemBalance vs. live CustomerVault enumeration:** The running `ecosystemBalance`
   counter requires CustomerVaults to always callback to parent on balance changes
   (`reportLeakage()`). Is this callback model acceptable? Alternative: enumerate all CVs at
   finalize and sum balances (expensive at scale but simpler custody model).

6. **EIP-1167 Clone Initialization:** Confirm factory initialize-then-register pattern for
   CustomerVault clones. CustomerVaults should not be upgradeable.

7. **cumS on deregistration — display/indexing:** Deregistered vault cumS is preserved
   on-chain but the vault is no longer active. Should indexers display it? Should there be
   an event specifically for "cumS frozen at deregistration"? Recommend yes — emit
   `VaultDeregistered(vault, epochId, finalCumS)`.

8. **E_demand epoch 0 bootstrapping:** At epoch 0, `lastEpochCumS[vault] = 0` for all
   vaults, so any initial buy immediately generates `deltaCumS = S_p(N)`. But initial buy
   earns zero reward (vault not yet qualified). So `E_demand(0)` contribution from unqualified
   vaults is correctly zero. Confirm this bootstrap behavior is acceptable — the very first
   epoch likely has E_demand = 0 from partners (all unqualified) but staker pool may still
   receive emission if scarcity cap > 0 and stakers exist.

---

## 15. v3.1 Implementation Checklist

1. **PSRE (ERC-20):** Unchanged. Mint restricted to RewardEngine.

2. **PartnerVaultFactory:**
   - Validate USDC-equivalent input $\geq S_{min}$ before deploying vault.
   - Optional registration fee collection (USDC → treasury).
   - Execute initial buy on behalf of new vault (USDC → DEX → PSRE → PartnerVault).
   - Record `initialCumS[vault] = psreOut` and `lastEpochCumS[vault] = psreOut`.
   - Set `qualified[vault] = false`.
   - Deploy PartnerVault (or initialize EIP-1167 proxy).
   - CustomerVault deployment (EIP-1167 clone, linked to parent PartnerVault).
   - Deregistration flow: mark vault deregistered, emit `VaultDeregistered`.
   - **No vault bond collection/return.**

3. **PartnerVault:**
   - `buy()` with `ecosystemBalance +=` and `_updateCumS()`.
   - `distributeToCustomer()` — registered CVs only; `ecosystemBalance` unchanged.
   - `transferOut()` — unregistered addresses; `ecosystemBalance -=`; cumS unchanged.
   - `registerCustomerVault()`.
   - `reportLeakage(amount)` — called by CustomerVault on withdrawal; `ecosystemBalance -=`.
   - `_updateCumS()` — internal; sets `cumS = ecosystemBalance` if `ecosystemBalance > cumS`.
   - `snapshotEpoch()` — callable by RewardEngine only; returns `deltaCumS`; updates
     `lastEpochCumS = cumS`.
   - `updateOwner()`.
   - `ecosystemBalance` maintained as running counter on every state change.
   - **No TWR accumulator. No resetEpochTWR(). No epochAccumulatedTWR.**

4. **CustomerVault (EIP-1167 clone):**
   - `receiveReward(amount)` — accept PSRE from parent vault.
   - `claimVault(address)` — customer asserts ownership.
   - `withdraw(amount)` — customer withdrawal; calls `parentVault.reportLeakage()`.
   - `reclaimUnclaimed(amount)` — partner reclaims from unclaimed vault; no leakage.

5. **StakingVault:** Unchanged from v3.0.

6. **RewardEngine (UUPS upgradeable):**
   - `finalizeEpoch()`:
     - Call `snapshotEpoch()` on all active vaults → collect `deltaCumS_p`.
     - First qualification check per vault.
     - EMA update on `deltaCumS_p` (not TWR).
     - Compute `E_demand = alphaBase * sum(deltaCumS_p) / 1e18`.
     - Compute scarcity cap, final budget.
     - Compute per-partner rewards; accumulate `owedPartner[vault]`.
     - Update vault activity counters; mark inactive/reactivate as needed.
     - Mint and record epoch data.
   - `claimPartnerReward(vault)`: transfer `owedPartner[vault]` immediately; no vesting.
   - `claimStake(epochId)`: unchanged.
   - Bounded parameter governance.
   - **No vesting ledger. No `vestingEarned`. No `claimPartnerVested`.**

7. **Unit Tests:**
   - Initial buy: cumS set correctly; no reward earned in creation epoch.
   - First qualification: vault earns first reward only when cumS crosses initialCumS.
   - cumS ratchet: buy → ecosystemBalance drops (via transferOut) → cumS unchanged.
   - Rebuy requirement: after ecosystem drop, new reward only when cumS grows past prior peak.
   - Vault expiry: zero cumS growth for 4 epochs → vault marked inactive.
   - Reactivation: inactive vault buys → cumS grows → vault reactivated; prior cumS preserved.
   - EMA update on deltaCumS (not TWR).
   - Scarcity function correctness near cap.
   - **E_demand: all unqualified vaults → E_demand = 0 → no partner emission.**
   - **E_demand: one qualified vault grows cumS → E_demand > 0.**
   - Wash trading: buy → transferOut → cumS unchanged → no reward; rebuy required.
   - Multiple partners: reward split proportional to weighted deltaCumS.
   - Tier assignment on cumS-based EMA.
   - Immediate claim after finalization (no vesting delay).
   - Scarcity cap binding when E_demand >> E_scarcity.
   - ecosystemBalance counter consistency: buy + distribute to CV + reportLeakage.
   - CustomerVault claim + withdraw + reportLeakage flow.
   - Invariants: cumS ≥ ecosystemBalance; cumS monotonically non-decreasing; T ≤ S_EMISSION.
   - S_MIN enforcement: vault creation reverts if initial USDC input < S_MIN.
   - cumS permanence: deregistered vault cumS preserved; new vault starts at 0.
