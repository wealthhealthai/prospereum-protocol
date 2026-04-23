# Prospereum Developer Specification v3.4

**Status:** FROZEN — matches mainnet deployment (Base, April 22, 2026)
**Supersedes:** v3.2 (frozen 2026-03-27), v3.3 (draft, never frozen)
**Audit:** BlockApex, April 2026 — all 29 findings resolved

---

## What Changed from v3.2 → v3.4

| Area | v3.2 | v3.4 |
|------|------|------|
| StakingVault accounting | Manual `recordStakeTime()`, `accStakeTime` accumulator | Synthetix-style cumulative accumulator (`_updatePending`, O(1) settlement) |
| StakingVault pools | Single shared pool, LP and PSRE 1:1 | Two independent sub-pools (PSRE staker pool, LP staker pool), 50/50 default |
| LP weighting | 1 LP token = 1 PSRE for stakeTime | Separate pools — no cross-asset comparison |
| cumS tracking | Live `balanceOf()` scanning | Explicit flows only (`buy()` / `distributeToCustomer()` / `reportLeakage()`) |
| PSRE minting | Single `mint(to, amount)` | `mint(to, amount)` + `mintForEpoch(to, amount, epochId)` for epoch-capped batch minting |
| Epoch finalization | Manual keeper only | `autoFinalizeEpochs()` called lazily from `buy()` and `createVault()` |
| Governance | Not specified | Gnosis Safes (Founder + Treasury), 2-of-3 each |
| Deployment | Testnet only | **Mainnet deployed, Base chain ID 8453** |

All other sections from v3.2 are preserved unchanged.

---

## 0. Design Decisions Locked for v3.4

All v3.2 decisions remain in effect. Additional decisions:

- **cumS = explicit buy flows only.** `_updateCumS()` only advances from `ecosystemBalance`. No `balanceOf()` scanning. Direct ERC-20 transfers to vault are invisible to cumS.
- **StakingVault uses two independent sub-pools.** PSRE stakers and LP stakers earn from separate pools within the 30% staker allocation. Default 50/50. No cross-asset comparison.
- **Synthetix cumulative accumulator.** Settlement is O(1) per user per asset. No per-epoch cursor loop. No gas cap.
- **Epoch-aware PSRE minting.** Batch finalization uses `mintForEpoch(to, amount, historicalEpochId)` to charge each epoch's mint against its own per-epoch budget.
- **Lazy finalization.** `autoFinalizeEpochs()` (capped at 10 epochs) is called on every `buy()` and `createVault()`. Dedicated keeper optional but not required.
- **No presale; treasury seeds LP.** Treasury Safe holds 4.2M PSRE. Genesis LP: 200K PSRE + $20K USDC, Uniswap v3 1% fee, ~$0.10 launch price.
- **LP staking deferred at launch.** `psreSplit = 1e18`, `lpSplit = 0` at genesis. LP staking enabled once ERC-20 LP wrapper is deployed (future upgrade).

---

## 1. Constants & Global Parameters

### 1.1 Token Supply

$$S_{total} = 21{,}000{,}000 \times 10^{18}$$

$$S_{emission} = 12{,}600{,}000 \times 10^{18}$$

Genesis allocation (minted at deploy):
- 4,200,000 PSRE → Treasury Safe
- 4,200,000 PSRE → Founder Safe (for Sablier vesting)
- 12,600,000 PSRE → emitted by RewardEngine over epochs

### 1.2 Epoch

```
EPOCH_DURATION   = 7 days
genesisTimestamp = set at deployment (1776829977 on mainnet)
epochId          = (block.timestamp - genesisTimestamp) / EPOCH_DURATION
```

### 1.3 Economic Parameters

```
alphaBase (r_base):   0.10e18 default, bounds [0.05e18, 0.15e18]
E0:                   S_EMISSION / 1000 = 12,600 PSRE/week default
E0_MIN:               S_EMISSION * 5 / 10000
E0_MAX:               S_EMISSION * 2 / 1000 = 25,200 PSRE/week (= MAX_MINT_PER_EPOCH)
k (exponent):         2 (immutable)
theta (EMA factor):   1/13 ≈ 0.0769e18 (immutable)
```

### 1.4 Tier Parameters

| Tier | Min Share | Multiplier |
|------|-----------|------------|
| Bronze | 0% | 0.8× |
| Silver | 0.5% | 1.0× |
| Gold | 2.0% | 1.2× |

### 1.5 Splits

```
PARTNER_SPLIT = 0.70e18   (70% of B)
STAKER_SPLIT  = 0.30e18   (30% of B)

Within staker pool (StakingVault):
PSRE_STAKER_SPLIT = 1.0e18   (100% at genesis — LP staking deferred)
LP_STAKER_SPLIT   = 0.0e18   (0% at genesis)
```

### 1.6 Vault Lifecycle

```
MAX_CUSTOMER_VAULTS = 1000 per PartnerVault
MAX_PARTNERS        = 200 (governance-adjustable, must be >= activeVaultCount)
AUTO_FINALIZE_MAX_EPOCHS = 10
INACTIVITY_THRESHOLD     = 52 epochs
S_MIN                    = 500e6 (USDC, 6 decimals)
```

### 1.7 PSRE Mint Cap

```
MAX_MINT_PER_EPOCH = S_EMISSION * 2 / 1000 = 25,200e18
```

Each epoch's `mintForEpoch()` call is charged against `epochMinted[historicalEpochId]`. Multiple finalized epochs in a batch each have their own budget.

---

## 2. Contracts & Responsibilities

### 2.1 PSRE (ERC-20)

- Standard ERC-20, decimals = 18, 21M hard cap.
- **Two mint paths:**
  - `mint(to, amount)` — charges current wall-clock epoch's mint budget.
  - `mintForEpoch(to, amount, historicalEpochId)` — charges the specified historical epoch's budget. Used by RewardEngine for batch finalization to avoid cross-epoch mint cap collisions.
- `MINTER_ROLE` gated — only RewardEngine holds this role after deployment.
- `PAUSER_ROLE` — Founder Safe.
- `DEFAULT_ADMIN_ROLE` — Founder Safe.
- Immutable logic (no upgrade proxy on PSRE itself).

### 2.2 PartnerVaultFactory

Creates PartnerVaults and maintains the global vault registry.

**Vault creation flow:**
1. Validate: `usdcAmountIn >= S_MIN` (500 USDC)
2. Validate: `fee` is in whitelist `{100, 500, 3000, 10000}` (prevents fee-tier bypass)
3. Validate: `minPsreOut >= usdcAmountIn * MIN_PSRE_FLOOR / PRECISION` (slippage floor)
4. Call `autoFinalizeEpochs()` on RewardEngine (lazy epoch maintenance)
5. Swap USDC → PSRE via Uniswap v3 router
6. Deploy PartnerVault clone, call `factoryInit(psreOut)`
7. Register vault, emit `VaultCreated`

**setRewardEngine(address):** One-time setter, onlyOwner (Founder Safe).

### 2.3 PartnerVault

Per-partner vault. Tracks `ecosystemBalance` and `cumS`.

**cumS update rule (v3.4):**
- `_updateCumS()` advances the cumS ratchet from `ecosystemBalance` only.
- Direct ERC-20 transfers to vault are NOT captured. Only `buy()` flows update `ecosystemBalance`.
- Flash-loan vector closed: attacker cannot manipulate cumS without committing real PSRE through tracked flows.

**Key functions:**
- `buy(usdcIn, minPsreOut, deadline, fee)` — swaps USDC → PSRE, adds to `ecosystemBalance`, calls `autoFinalizeEpochs()`, updates cumS.
- `distributeToCustomer(cv, amount)` — moves PSRE to CustomerVault. `ecosystemBalance` unchanged. cumS unchanged.
- `transferOut(to, amount)` — sends PSRE out. Reduces `ecosystemBalance`. cumS not reduced. Restricted: `to` cannot be a registered vault or CustomerVault.
- `recoverToken(token, to, amount)` — rescue accidentally sent tokens. PSRE rescue limited to surplus above `ecosystemBalance`.

### 2.3a CustomerVault

Lightweight holding contract for end customers.

- `claimVault(newCustomer)` — customer claims ownership. Caller must be `IPartnerVault(parentVault).owner()` (live lookup, not cached) or `intendedCustomer`. **v3.4 fix: live owner lookup prevents stale-partnerOwner exploit.**
- `withdraw(amount)` — customer withdraws PSRE. Calls `reportLeakage()` to update parent's `ecosystemBalance`.
- `reclaimUnclaimed()` — partner can reclaim unclaimed PSRE via `PartnerVault.reclaimFromCV(cv)`.

### 2.4 StakingVault — Synthetix Cumulative Accumulator (v3.4)

**Complete redesign from v3.2.** Replaces accStakeTime + recordStakeTime() with a true Synthetix-style O(1) settlement model.

#### Architecture

Two independent staker sub-pools within the 30% staker allocation:

| Pool | Asset | Default Allocation |
|------|-------|-------------------|
| PSRE Pool | PSRE tokens | `psreSplit` (default 1e18 = 100% at genesis) |
| LP Pool | PSRE/USDC LP token | `lpSplit` (default 0 at genesis) |

Stakers earn from their respective pool only. No cross-asset comparison.

#### Settlement Model

Global running accumulators (updated by `distributeStakerRewards()` per epoch):

```solidity
uint256 public cumulativePSRERewardPerToken; // Σ epochPSRERewardPerToken[e] for all e
uint256 public cumulativeLPRewardPerToken;   // Σ epochLPRewardPerToken[e] for all e
```

Per-user checkpoints (set to current cumulative after each `_updatePending()` call):

```solidity
mapping(address => uint256) public userPSRERewardPerTokenPaid;
mapping(address => uint256) public userLPRewardPerTokenPaid;
mapping(address => uint256) public pendingRewards;
```

Settlement O(1):

```
_updatePending(user):
    psreEarned = psreBalance * (cumulativePSRERewardPerToken - userPSRERewardPerTokenPaid[user]) / REWARD_PRECISION
    lpEarned   = lpBalance   * (cumulativeLPRewardPerToken   - userLPRewardPerTokenPaid[user])   / REWARD_PRECISION
    pendingRewards[user] += psreEarned + lpEarned
    userPSRERewardPerTokenPaid[user] = cumulativePSRERewardPerToken
    userLPRewardPerTokenPaid[user]   = cumulativeLPRewardPerToken
```

`_updatePending()` is called before every balance change (stake/unstake) and before every claim. This guarantees the invariant: at call time, user's stored balance equals their balance during all unsettled epochs (no gas cap, no cursor overflow).

#### New User Auto-Initialization

A brand-new user calling `stakePSRE()`:
1. `_updatePending()` runs with `psreBalance = 0` → earned = 0
2. `userPSRERewardPerTokenPaid` is set to current `cumulativePSRERewardPerToken`
3. Balance is set to `amount`

Result: new user can only claim rewards from epochs after their first stake. Historical epochs are unreachable. Retroactive theft is impossible.

#### Functions

```solidity
stakePSRE(uint256 amount)      // _updatePending → safeTransferFrom → balance++
unstakePSRE(uint256 amount)    // _updatePending → balance-- → safeTransfer
stakeLP(uint256 amount)        // same pattern for LP
unstakeLP(uint256 amount)      // same pattern for LP
claimAll()                     // _updatePending → pay pendingRewards
claimStake(uint256 epochId)    // validates epochSnapshotted[epochId], then claimAll
checkpointUser(address user)   // permissionless keeper compat — calls _updatePending(user)
```

#### RewardEngine Interface

```solidity
snapshotEpoch(uint256 epochId)                                          // onlyRewardEngine
distributeStakerRewards(uint256 epochId, uint256 totalStakerPool)      // onlyRewardEngine
```

`distributeStakerRewards` behavior:
- Splits `totalStakerPool` into `psrePool` (psreSplit fraction) and `lpPool` (lpSplit fraction)
- If zero stakers on both sides: returns early, tokens NOT pulled (no orphaned funds)
- Computes `epochPSRERewardPerToken = psrePool * REWARD_PRECISION / totalPSREStaked`
- Increments `cumulativePSRERewardPerToken += epochPSRERewardPerToken`
- Pulls `totalStakerPool` from RewardEngine via `safeTransferFrom`
- Owner can call `sweepUnclaimedPool(epochId, to)` to recover sub-pools where `rewardPerToken == 0`

#### Constants

```
REWARD_PRECISION = 1e36
EPOCH_DURATION   = 7 days
```

### 2.5 RewardEngine (UUPS Upgradeable Proxy)

Core monetary policy contract. Callable by anyone for `finalizeEpoch` / `autoFinalizeEpochs`.

**Lazy auto-finalization:**

```solidity
function autoFinalizeEpochs() external {
    uint256 batchSize = 0;
    while (batchSize < AUTO_FINALIZE_MAX_EPOCHS && _epochDue()) {
        _finalizeSingleEpoch(lastFinalizedEpoch + 1);
        batchSize++;
    }
}
```

Called by `PartnerVaultFactory.createVault()` and `PartnerVault.buy()` at the start of each transaction. Caps at `AUTO_FINALIZE_MAX_EPOCHS = 10` to bound gas.

**`_finalizeSingleEpoch(epochId)` flow:**

1. Snapshot each registered vault: `vault.snapshotEpoch()` → `deltaCumS_p`
2. Compute `effectiveCumS_p`, `deltaEffectiveCumS_p`
3. Update EMA `R[vault]` (two-pass: compute all R values first, then assign tiers)
4. Compute `E_demand`, `E_scarcity`, `B`
5. **Zero-staker check:** if `stakingVault.epochTotalPSREStaked(epochId) == 0 && epochTotalLPStaked == 0` → set `P_stakers = 0` (no mint for empty staker pool)
6. Compute `P_partners`, `P_stakers`, `mintAmount`
7. Call `psre.mintForEpoch(address(this), mintAmount, epochId)`
8. Distribute partner rewards: `owedPartner[vault] += share`
9. Distribute staker rewards: approve + `stakingVault.distributeStakerRewards(epochId, P_stakers)`

**Scarcity ceiling clamping (v3.4):**

```
scaled          = E_scarcity * (batchSize > 0 ? batchSize : 1)
scarcityCeiling = min(scaled, E0_MAX)   // clamp to per-epoch PSRE mint cap
B = min(E_demand, scarcityCeiling, remaining)
```

Prevents `mintForEpoch` from reverting with "PSRE: epoch mint cap exceeded" during batch finalization.

---

## 3. Storage Layout (RewardEngine)

### Global

```solidity
uint256 public T;                 // cumulative PSRE emitted (never exceeds S_EMISSION)
uint256 public genesisTimestamp;
uint256 public lastFinalizedEpoch;
uint256 public alphaBase;         // r_base, 1e18-scaled
uint256 public E0;                // weekly scarcity ceiling
uint256 public sumR;              // Σ R[vault] across active vaults
uint256 public _autoFinalizeCount; // private: batch size for scarcity scaling
```

### Partner Accounting

```solidity
mapping(address => uint256) public lastEpochCumS;
mapping(address => uint256) public lastEffectiveCumS;
mapping(address => uint256) public cumulativeRewardMinted;
mapping(address => uint256) public R;              // EMA rolling score
mapping(address => bool)    public qualified;
mapping(address => uint256) public initialCumS;
mapping(address => uint256) public lastGrowthEpoch;
mapping(address => bool)    public vaultActive;
mapping(address => uint256) public owedPartner;
```

### Epoch Records

```solidity
mapping(uint256 => bool)    public epochFinalized;
mapping(uint256 => uint256) public epochB;
mapping(uint256 => uint256) public epochPartnersPool;
mapping(uint256 => uint256) public epochStakersPool;
```

---

## 4. Epoch Lifecycle

### 4.1 finalization trigger

Any of:
- `PartnerVault.buy()` → calls `rewardEngine.autoFinalizeEpochs()` at start
- `PartnerVaultFactory.createVault()` → calls `rewardEngine.autoFinalizeEpochs()` at start
- Direct call to `RewardEngine.finalizeEpoch(epochId)` (single epoch, no batch scaling)
- Direct call to `RewardEngine.autoFinalizeEpochs()` (up to 10 epochs)

### 4.2 Epoch algorithm

See `_finalizeSingleEpoch` above. Two-pass EMA:

**Pass 1:** For all active vaults, compute `deltaEffectiveCumS_p`. Accumulate `sumR_new`.

**Pass 2:** For all active vaults, compute partner reward share using settled `sumR_new`.

This prevents order-dependent tier assignments (sliding denominator bug closed).

---

## 5. Algorithms

### 5.1 cumS Update

```
function _updateCumS() internal:
    // Only ecosystemBalance counts — no balanceOf scanning
    if ecosystemBalance > cumS:
        cumS = ecosystemBalance
```

### 5.2 effectiveCumS

```
effectiveCumS_p(t) = cumS_p(t) - cumulativeRewardMinted[vault]
deltaEffectiveCumS = max(0, effectiveCumS_p(t) - lastEffectiveCumS[vault])
```

### 5.3 EMA Update (two-pass)

Pass 1 (compute new R for each vault, accumulate new sumR):
```
R_new[vault] = (R_old * (1 - theta) + deltaEffectiveCumS * theta) / 1e18
tempSumR += R_new[vault]
```

Pass 2 (assign tiers using stable tempSumR):
```
s = R_new[vault] * 1e18 / tempSumR
tier = gold if s >= GOLD_THRESHOLD else silver if s >= SILVER_THRESHOLD else bronze
```

Commit: `R[vault] = R_new[vault]`, `sumR = tempSumR`

### 5.4 Demand Cap

```
E_demand = alphaBase * deltaEffectiveCumSTotal / 1e18
```

### 5.5 Scarcity Cap

```
x          = T * 1e18 / S_EMISSION
omx        = 1e18 - x
E_scarcity = E0 * omx / 1e18 * omx / 1e18     // E0 * (1 - x)^2
```

### 5.6 Final Budget

```
scaled          = E_scarcity * (batchSize > 0 ? batchSize : 1)
scarcityCeiling = min(scaled, E0_MAX)
B               = min(E_demand, scarcityCeiling, S_EMISSION - T)
B_partners      = B * PARTNER_SPLIT / 1e18
B_stakers       = B - B_partners
```

### 5.7 Partner Reward Distribution

```
W = Σ_p (alpha_p * deltaEffectiveCumS_p / 1e18)
for each qualifying vault p:
    raw_p = B_partners * weight_p / W
    owedPartner[vault] += raw_p * M_tier / 1e18
```

### 5.8 Staker Reward Distribution

```
P_stakers = B_stakers
if epochTotalPSREStaked[epochId] == 0 && epochTotalLPStaked[epochId] == 0:
    P_stakers = 0   // no stakers — skip mint, preserve emission budget

mintAmount = P_partners + P_stakers
psre.mintForEpoch(address(this), mintAmount, epochId)
T += mintAmount

if P_stakers > 0:
    PSRE.approve(stakingVault, P_stakers)
    stakingVault.distributeStakerRewards(epochId, P_stakers)
```

---

## 6. Governance

### Founder Safe
- Address: `0xc59816CAC94A969E50EdFf7CF49ce727aec1489F`
- Chain: Base mainnet
- Threshold: 2-of-3
- Roles: `DEFAULT_ADMIN_ROLE` on PSRE, owner of PartnerVaultFactory, StakingVault, RewardEngine
- Authority: parameter updates (timelocked 48h), RewardEngine upgrade (timelocked 7 days), emergency pause, `setSplit()`

### Treasury Safe
- Address: `0xa9Fde837EBC15BEE101d0D895c41a296Ac2CAfCe`
- Chain: Base mainnet
- Threshold: 2-of-3
- Holds: 4.2M PSRE at genesis. LP liquidity.

### Governance-Timelocked Parameters

| Parameter | Timelock | Bounds |
|-----------|----------|--------|
| alphaBase (r_base) | 48 hours | [0.05e18, 0.15e18] |
| E0 (scarcity ceiling) | 48 hours | [E0_MIN, E0_MAX] |
| partnerSplit | 48 hours | [0.50e18, 0.80e18] |
| tierParams (thresholds + multipliers) | 48 hours | validated |
| RewardEngine upgrade | 7 days | new impl required |

---

## 7. Deployed Contracts (Base Mainnet — Chain ID 8453)

| Contract | Address | Deploy Tx |
|----------|---------|-----------|
| PSRE | `0x2fE08f304f1Af799Bc29E3D4E210973291d96702` | `0x80f18bb0...` |
| PartnerVault (impl) | `0xa1BcD31cA51Ba796c73578d1C095c9EE0adb9F18` | `0x97c0b2...` |
| CustomerVault (impl) | `0xAb5906f5a3f03576678416799570d0A0ceEc40f2` | `0xb5bfe7...` |
| PartnerVaultFactory | `0xFF84408633f79b8f562314cC5A3bCaedA8f76902` | `0x98424f...` |
| StakingVault | `0x684BEA07e979CB5925d546b2E2099aA1c632ED2D` | `0x9d88f8...` |
| RewardEngine (impl) | `0xE194EF5ABB93cb62089FB5a3b407B9B7f38F04f5` | `0x1522c0...` |
| RewardEngine (proxy) | `0x9Ab37Fc6D01B85491Ed0863B7F832784bE717EF5` | `0xefd098...` |

**Genesis timestamp:** `1776829977`
**Epoch 0 closes:** ~April 28-29, 2026

---

## 8. Security Audit

**Auditor:** BlockApex (hello@blockapex.io)
**Dates:** April 2–17, 2026 (Phase 1 + re-audit)
**Scope:** All contracts at fixed commit `31eb31384dee7385b14b1f02ac033e2e488e721f`
**Result:** 29 findings — all resolved before mainnet deployment

| Severity | Count | Status |
|----------|-------|--------|
| Critical | 5 (3 original + 2 post-fix) | All Resolved |
| High | 5 (3 original + 2 post-fix) | All Resolved |
| Medium | 13 (11 original + 2 post-fix) | All Resolved |
| Low | 5 (4 original + 1 post-fix) | All Resolved |
| Informational | 1 | Resolved |

**Public report:** https://github.com/BlockApex/Audit-Reports/blob/master/Prospereum%20Protocol_Final%20Audit%20Report.pdf

---

## 9. Anti-Exploitation Constraints

- **Flash-loan cumS:** Closed — cumS only grows via tracked `buy()` flows.
- **Post-snapshot stakeTime injection:** Closed — `snapshotEpoch` locks epoch; contributions after snapshot are ignored.
- **Retroactive staking theft:** Closed — cumulative accumulator auto-initializes new stakers to current cumulative, no historical access.
- **Epoch mint cap DoS:** Closed — `scarcityCeiling` clamped to `E0_MAX` before computing B; batch finalization never exceeds per-epoch budget.
- **Fee-tier sandwich on createVault:** Closed — fee tier whitelist + minPsreOut floor.
- **stale partnerOwner:** Closed — CustomerVault uses live `IPartnerVault(parentVault).owner()` lookup.
- **Zero-staker emission waste:** Closed — RE skips staker mint when snapshot shows zero stakers.

---

## 10. Required Invariants

```
assert T <= S_EMISSION                           // total emission cap
assert cumS_p >= cumS_p_prev                     // ratchet never decreases
assert ecosystemBalance == Σ(CV balances) + PV balance  // accounting integrity
assert pendingRewards[u] <= totalDistributed      // no over-payment
assert cumulativePSRERewardPerToken >= prev       // accumulator monotone
```

---

## 11. Events (Key)

```solidity
// PartnerVault
event PSREPurchased(uint256 psreOut, uint256 newCumS, uint256 epochId)
event TokenRecovered(address token, address to, uint256 amount)

// StakingVault
event PSREStaked(address indexed user, uint256 amount)
event PSREUnstaked(address indexed user, uint256 amount)
event LPStaked(address indexed user, uint256 amount)
event LPUnstaked(address indexed user, uint256 amount)
event StakerRewardsDistributed(uint256 indexed epochId, uint256 psrePool, uint256 lpPool)
event RewardsClaimed(address indexed user, uint256 amount)

// RewardEngine
event EpochFinalized(uint256 indexed epochId, uint256 B, uint256 E_demand, uint256 E_scarcity, ...)
event PartnerRewardMinted(address indexed vault, uint256 amount, uint256 epochId)
```

---

*Prospereum Developer Specification v3.4 — Frozen at mainnet deployment, April 22, 2026*
*For historical context on architectural evolution, see v3.2 (March 2026) and BlockApex audit report.*
