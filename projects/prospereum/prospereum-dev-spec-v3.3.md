# Prospereum Developer Specification v3.3

**Status:** DRAFT — pending Shu + Jason approval
**Date:** 2026-04-09
**Supersedes:** v3.2 (frozen 2026-03-27)
**Changes:** Audit-driven architectural updates (BlockApex, April 2026)

---

## What Changed from v3.2

This document records all changes to the protocol specification arising from the BlockApex security audit (April 2026). All changes are authorized by Shu Li. Jason Li approval required before this spec is frozen.

---

## §2.3.1 — cumS Tracking: Explicit Flows Only (was: live balanceOf scan)

**Old behavior (v3.2):**
`_updateCumS()` synced `ecosystemBalance` with the vault's live PSRE balance via `IERC20(psre).balanceOf()`. Direct ERC-20 transfers to the vault were captured and counted toward cumS.

**New behavior (v3.3):**
`_updateCumS()` only advances the cumS ratchet from the `ecosystemBalance` counter. Direct ERC-20 transfers are **not** counted. cumS grows exclusively through:
- `buy()` — adds `psreOut` to `ecosystemBalance`
- `distributeToCustomer()` — moves PSRE within the ecosystem (ecosystemBalance unchanged)
- `reportLeakage()` / `transferOut()` — decreases `ecosystemBalance`

**Rationale:** Accepting direct transfers created a flash-loan attack vector: borrow PSRE → transfer to vault → trigger `_updateCumS` → inflate cumS → withdraw → cumS stays elevated. This violated the protocol's core principle that cumS reflects genuine committed capital.

**Updated `_updateCumS()` pseudocode:**
```
function _updateCumS() internal:
    // cumS ratchet: only advance from tracked ecosystemBalance
    if ecosystemBalance > cumS:
        cumS = ecosystemBalance
```

---

## §2.4 — StakingVault: Redesigned (was: manual recordStakeTime)

The StakingVault contract is completely redesigned in v3.3. The old `accStakeTime` accumulator model is replaced with epoch-aware Synthetix-style checkpointing.

### Two Sub-Pools within the 30% Staker Allocation

The staker pool is divided into two independent sub-pools:

| Pool | Asset | Default Allocation |
|---|---|---|
| PSRE Staker Pool | PSRE tokens | 50% of staker pool (governance-adjustable) |
| LP Staker Pool | PSRE/USDC LP tokens | 50% of staker pool (governance-adjustable) |

PSRE stakers and LP stakers never compete with each other. Within each pool, reward share is proportional to time-weighted balance. The split is a governance parameter (`psreSplit + lpSplit = 1e18`).

**Rationale:** 1:1 weighting of LP tokens against PSRE created a reward dilution vector (LP tokens typically have different unit value than PSRE). Separate pools eliminate cross-asset comparison entirely.

### Epoch-Aware Checkpointing

The old `recordStakeTime(epochId)` manual step is removed. Time-weighted contributions are tracked automatically via `_checkpoint(user)`, which is called on every `stakePSRE()`, `unstakePSRE()`, `stakeLP()`, `unstakeLP()`, and `claimStake()`.

**`_checkpoint()` behavior:**
1. Computes elapsed time since last checkpoint
2. Attributes `balance × elapsed` to each epoch correctly — if the elapsed period spans multiple epochs, time is split at epoch boundaries
3. Updates `userPSREStakedTime[epoch][user]` and `totalPSREStakedTime[epoch]` (same for LP)
4. Maximum lookback: `MAX_CHECKPOINT_EPOCHS = 52` (gas safety cap)

**Key property:** If an epoch has been snapshotted (`epochSnapshotted[epochId] == true`), `_addContribution()` silently skips it. Contributions to finalized epochs are not accepted. This prevents post-snapshot manipulation.

### Removal of recordStakeTime()

`recordStakeTime()`, `accStakeTime`, `currentEpochTotalStakeTime`, `totalStakeTimeByEpoch`, and `userStakeTimeByEpoch` are all removed. Replaced by:

```solidity
mapping(uint256 => uint256) totalPSREStakedTime;              // epoch → Σ(psreBalance × seconds)
mapping(uint256 => uint256) totalLPStakedTime;                // epoch → Σ(lpBalance × seconds)
mapping(uint256 => mapping(address => uint256)) userPSREStakedTime;
mapping(uint256 => mapping(address => uint256)) userLPStakedTime;
mapping(uint256 => mapping(address => bool)) hasClaimed;
mapping(uint256 => bool) epochSnapshotted;
```

### Reward Claim

`claimStake(epochId)` is now on StakingVault (previously also on RewardEngine). No manual recording step needed:

```
PSRE reward = epochPSREPool[epochId] × userPSREStakedTime[epochId][user] / totalPSREStakedTime[epochId]
LP reward   = epochLPPool[epochId]   × userLPStakedTime[epochId][user]   / totalLPStakedTime[epochId]
total       = PSRE reward + LP reward
```

### Reward Distribution from RewardEngine

When `_finalizeSingleEpoch()` computes the staker pool, it:
1. Calls `stakingVault.snapshotEpoch(epochId)` — freezes the epoch (no more contributions accepted)
2. Approves StakingVault to pull `B_stakers` PSRE
3. Calls `stakingVault.distributeStakerRewards(epochId, B_stakers)` — SV pulls tokens and records `epochPSREPool` and `epochLPPool`

---

## §2.2.1 — PartnerVaultFactory: Fee Tier Whitelist

`createVault()` now validates the `fee` parameter against an allowlist of approved Uniswap V3 fee tiers. Default approved: `100`, `500`, `3000`, `10000` bps. Owner can add/remove tiers via `setAllowedFeeTier(uint24 fee, bool allowed)`.

**Rationale:** Unvalidated fee tier allowed routing through attacker-controlled illiquid pools, bypassing the $500 S_MIN economic gate.

---

## §4.2 — E_scarcity Scaling in autoFinalizeEpochs()

When `autoFinalizeEpochs()` processes a batch of K pending epochs, `_finalizeSingleEpoch()` applies a scaled scarcity ceiling for that batch:

```
scarcityCeiling = E_scarcity × K    (where K = _autoFinalizeCount)
B = min(E_demand, scarcityCeiling, remaining)
```

When `finalizeEpoch()` is called directly (K = 1 by default), behavior is unchanged.

**Rationale:** Without scaling, K compressed epochs had their combined growth capped at a single epoch's E_scarcity limit, causing permanent reward loss. Scaling allows legitimate accrued rewards to be distributed correctly even when finalization is delayed.

---

## §2.3.2 — PartnerVault: Additional Security Fixes

### deregisterCustomerVault()
New function allows vault owner to remove a CustomerVault from `customerVaultList` (swap-and-pop O(1)). Requires the CV's PSRE balance to be zero first (use `reclaimFromCV()` to empty it).

### decommissionVault() (in PartnerVaultFactory)
Admin function to mark a vault as inactive. `activeVaultCount` is decremented. `createVault()` now checks `activeVaultCount < maxPartners` instead of `allVaults.length`. `_finalizeSingleEpoch()` skips inactive vaults.

### transferOut CV guard
`transferOut()` now also checks `factory.isRegisteredCV(to)` in addition to `isRegisteredVault(to)`. Prevents routing PSRE from one partner's vault to another partner's CustomerVault to inflate the receiving vault's cumS.

---

## §6 — Governance: Parameter Queue Guard

Queue functions for `alphaBase`, `E0`, `partnerSplit`, and `tierParams` now require the pending queue to be empty (`pendingParam.readyAt == 0`) before accepting a new value. A `cancelParam()` function is provided for each parameter to explicitly clear a pending update with an event.

---

## §7 — Authorization Control Fix

`claimPartnerReward()` in RewardEngine now queries `IPartnerVault(vault).owner()` directly rather than `factory.partnerOf(vault)`. The static `partnerOf` mapping is not updated on vault ownership transfer, causing the old code to lock out new owners and allow old owners to steal rewards.

---

## Constants Unchanged from v3.2

All emission parameters, tier thresholds, epoch duration, S_MIN, S_TOTAL, S_EMISSION, alphaBase, E0, k, theta, tier multipliers, vault expiry epochs — all unchanged.

---

## Implementation Reference

All changes implemented in commits `303cd2f` through `7c13690` on the `master` branch of `wealthhealthai/prospereum-protocol`. Final audit-ready commit: `7c13690` (234/234 tests passing).

---

*This spec requires Shu + Jason explicit approval before freezing. Pending approval, v3.2 remains the reference spec.*
