# Prospereum — Epoch Keeper Specification

**Author:** Kin  
**Date:** 2026-03-30  
**Status:** DRAFT — awaiting Jason + Shu review  
**Related contracts:** `RewardEngine` (proxy: `0xe668fE9DbCE8CBbc8b3590100e8c31aA12F5C697`, Base Sepolia)

---

## 1. Purpose

`RewardEngine.finalizeEpoch(epochId)` is **permissionless** — any address can call it once an epoch has ended. The protocol does not require a trusted keeper; it only requires _someone_ to call finalize in a reasonable window after each epoch closes.

In the early phase (pre-DAO), WealthHealth runs an ops keeper to ensure reliable epoch finalization. This document specifies the keeper's design, responsibilities, gas strategy, alerting, and failure modes.

---

## 2. What Happens at Finalization

Each call to `finalizeEpoch(epochId)` executes, in order:

1. Validates: `epochId == lastFinalizedEpoch + 1` and epoch is over (`block.timestamp >= epochEnd`)
2. For each registered active PartnerVault:
   - Calls `vault.snapshotEpoch()` → captures `deltaCumS_p`
   - Computes `effectiveCumS` and `deltaEffectiveCumS` (anti-compounding deduction)
   - Runs first qualification check (marks `qualified[vault] = true` if threshold crossed)
   - Updates EMA tier
   - Computes per-vault reward (`r_base × tieredMultiplier × deltaEffectiveCumS / 1e18`)
   - Accumulates `owedPartner[vault]`
   - Updates `cumulativeRewardMinted[vault]` and `lastEffectiveCumS[vault]`
3. Computes aggregate demand (`E_demand`), applies scarcity cap, mints PSRE
4. Snapshots `stakingRewardAccrued` for StakingVault pull
5. Emits `EpochFinalized(epochId, totalMinted, partnerRewards, stakingRewards)`
6. Increments `lastFinalizedEpoch`

**Key invariant:** Only `epochId == lastFinalizedEpoch + 1` is accepted. Missed epochs must be finalized in order (no skipping).

---

## 3. Epoch Schedule

```
EPOCH_DURATION = 7 days
genesisTimestamp = 1774726994  (2026-03-28, Base Sepolia testnet)

epochId = (block.timestamp - genesisTimestamp) / EPOCH_DURATION

Epoch N ends at:   genesisTimestamp + (N + 1) * EPOCH_DURATION
Epoch N is finalizable when: block.timestamp >= genesisTimestamp + (N + 1) * EPOCH_DURATION
```

| Epoch | Opens | Closes | Earliest finalize |
|---|---|---|---|
| 0 | 2026-03-28 | 2026-04-04 | 2026-04-04 |
| 1 | 2026-04-04 | 2026-04-11 | 2026-04-11 |
| 2 | 2026-04-11 | 2026-04-18 | 2026-04-18 |
| … | … | … | … |

---

## 4. Keeper Responsibilities

### 4.1 Primary Duty
Call `RewardEngine(proxy).finalizeEpoch(epochId)` within **2 hours** of each epoch ending.

**Target latency:** ≤ 30 minutes after epoch close (soft), ≤ 2 hours (hard SLA).  
**Reason:** Partner reward attribution is time-sensitive; stale epochs block reward claims.

### 4.2 Missed Epoch Recovery
If an epoch was not finalized in its window, the keeper must **catch up** by finalizing missed epochs in order before the current one. There is no penalty for latency beyond the SLA window, but partners cannot claim rewards until their epoch is finalized.

Recovery procedure:
1. Read `lastFinalizedEpoch` from RewardEngine
2. Compute current epoch: `(now - genesis) / 7 days`
3. Finalize all epochs from `lastFinalizedEpoch + 1` to `currentEpoch` in sequence
4. Alert after recovery with count of missed epochs and gas spent

### 4.3 What the Keeper Does NOT Do
- Does not deploy or upgrade contracts
- Does not manage admin keys or multisig
- Does not handle partner vault registration
- Does not trigger LP or treasury operations
- Does not call any function other than `finalizeEpoch(epochId)`

---

## 5. Gas Strategy

### 5.1 Gas Cost Estimate
`finalizeEpoch` iterates over all registered active PartnerVaults. Gas scales linearly with vault count.

| Active vaults | Estimated gas | At 0.1 gwei (Base) | At 1 gwei (Base) |
|---|---|---|---|
| 1 | ~150,000 | ~$0.01 | ~$0.10 |
| 10 | ~600,000 | ~$0.04 | ~$0.40 |
| 100 | ~5,500,000 | ~$0.35 | ~$3.50 |
| 500 | ~26,000,000 | ~$1.70 | ~$17.00 |

_Estimates based on ~50,000 gas per vault (snapshotEpoch + effectiveCumS + EMA + reward write). Base L2 fees are very low; these are conservative._

### 5.2 Ops Wallet Funding
- **Ops wallet:** Jason EOA (decided 2026-03-12 — day-to-day keeper/gas wallet)
- **Target balance:** Keep ≥ 0.01 ETH on Base at all times
- **Alert threshold:** < 0.005 ETH → page Jason
- **Refill source:** Treasury Safe → ops wallet top-up as needed

### 5.3 Gas Price Cap
Set a gas price cap on keeper calls to avoid overpaying during spikes:
- **Soft cap:** 5 gwei — try up to 3 times over 30 minutes before escalating
- **Hard cap:** 50 gwei — skip this attempt, alert, retry next hour
- Base L2 fees rarely exceed 0.1 gwei; these caps are very conservative

---

## 6. Implementation Options

Two viable approaches. Recommend **Option A** for launch simplicity.

### Option A — OpenClaw Cron (Recommended for Launch)

Use the existing OpenClaw cron scheduler (Kin's workspace) to trigger a `cast send` call weekly.

**Pros:** Already operational, no new infrastructure, Kin can monitor and adjust  
**Cons:** Dependent on Mac Studio uptime; single point of failure if host goes offline

```
Schedule: cron "0 2 * * 5" (Friday 2 AM PDT, ~2 hours after epoch close assuming genesis alignment)
Command:  cast send <RewardEngine_proxy> "finalizeEpoch(uint256)" <epochId> \
            --rpc-url $BASE_RPC_URL \
            --private-key $OPS_PRIVATE_KEY \
            --gas-limit 6000000
```

Keeper logic (pseudo):
```bash
#!/bin/bash
# epoch-keeper.sh

GENESIS=1774726994
EPOCH_DURATION=604800  # 7 days in seconds
NOW=$(date +%s)
CURRENT_EPOCH=$(( (NOW - GENESIS) / EPOCH_DURATION ))

LAST_FINALIZED=$(cast call $REWARD_ENGINE "lastFinalizedEpoch()(uint256)" --rpc-url $BASE_RPC_URL)

NEXT_TO_FINALIZE=$(( LAST_FINALIZED + 1 ))

if [ $NEXT_TO_FINALIZE -le $CURRENT_EPOCH ]; then
  echo "Finalizing epoch $NEXT_TO_FINALIZE"
  cast send $REWARD_ENGINE "finalizeEpoch(uint256)" $NEXT_TO_FINALIZE \
    --rpc-url $BASE_RPC_URL \
    --private-key $OPS_PRIVATE_KEY \
    --gas-limit 6000000
  
  # Loop to catch up missed epochs
  while [ $(( NEXT_TO_FINALIZE + 1 )) -le $CURRENT_EPOCH ]; do
    NEXT_TO_FINALIZE=$(( NEXT_TO_FINALIZE + 1 ))
    echo "Catching up: finalizing epoch $NEXT_TO_FINALIZE"
    cast send $REWARD_ENGINE "finalizeEpoch(uint256)" $NEXT_TO_FINALIZE \
      --rpc-url $BASE_RPC_URL \
      --private-key $OPS_PRIVATE_KEY \
      --gas-limit 6000000
  done
else
  echo "No epoch to finalize. Current: $CURRENT_EPOCH, Last finalized: $LAST_FINALIZED"
fi
```

### Option B — Gelato Automation (Recommended for Mainnet / Scale)

Use [Gelato Network](https://app.gelato.network) automated tasks on Base.

**Pros:** Decentralized, trustless, survives host downtime, DAO can fund it on-chain  
**Cons:** Costs GELATO credits; requires setup and monitoring of a separate service

Setup:
1. Deploy a thin `KeeperWrapper` contract:
   ```solidity
   function checker() external view returns (bool canExec, bytes memory execPayload) {
       uint256 next = rewardEngine.lastFinalizedEpoch() + 1;
       uint256 epochEnd = genesis + (next + 1) * EPOCH_DURATION;
       canExec = block.timestamp >= epochEnd;
       execPayload = abi.encodeCall(rewardEngine.finalizeEpoch, (next));
   }
   ```
2. Register the task on Gelato with 1Balance funding
3. Gelato monitors `checker()` and submits tx automatically

### Option C — Hybrid (Recommended Long-Term)

Run both: OpenClaw cron as primary, Gelato as backup. Gelato only fires if OpenClaw misses by > 4 hours (detectable via on-chain `lastFinalizedEpoch` staleness).

---

## 7. Alerting & Monitoring

### 7.1 On-Chain Health Check
Simple staleness check — readable by anyone:

```
lastFinalizedEpoch = RewardEngine.lastFinalizedEpoch()
currentEpoch = (block.timestamp - genesis) / EPOCH_DURATION

lag = currentEpoch - lastFinalizedEpoch
```

| `lag` | State | Action |
|---|---|---|
| 0 | ✅ Healthy — current epoch not yet finalizable or just finalized | None |
| 1 | ⚠️ Pending — epoch ended, not yet finalized | Keeper should run within SLA |
| 2 | 🚨 Missed — one epoch behind | Page Jason, run catchup |
| ≥ 3 | 🔴 Critical | Page Jason + Shu, emergency catchup |

### 7.2 Keeper Alerts (via Kin → Discord)
After every finalization run, Kin's cron reports to `#prospereum` Discord channel:
```
[Keeper] ✅ Epoch N finalized — [vault count] vaults, [PSRE minted] PSRE minted, gas: [cost]
```

On failure:
```
[Keeper] 🚨 Epoch N finalization FAILED — [error]. Manual intervention required.
```

On low ops wallet balance:
```
[Keeper] ⚠️ Ops wallet low — [balance] ETH remaining. Top up needed.
```

### 7.3 Dashboard Integration (Future)
Epoch finalization status should surface on the Prospereum dashboard:
- Current epoch ID
- Last finalized epoch
- Time until next epoch
- Recent epoch finalization history

---

## 8. Security Considerations

### 8.1 Permissionless is Safe
Any address can call `finalizeEpoch`. A griefing attack (calling early, gas bombing) is not possible:
- Early call fails: `epochId` is validated against `lastFinalizedEpoch + 1` and `block.timestamp >= epochEnd`
- Replay is impossible: `lastFinalizedEpoch` increments on success; same epoch cannot be finalized twice
- MEV / front-running: finalizing an epoch before the keeper is fine — the result is identical regardless of who calls it

### 8.2 Ops Key Security
- Ops wallet holds **only gas** — no PSRE, no admin roles
- Private key in `.env`, gitignored
- If ops key is compromised: rotate to new EOA, no protocol state is affected
- Ops wallet is NOT the admin, NOT the treasury, NOT the upgrade controller

### 8.3 Catching Up After Extended Downtime
If the keeper is offline for multiple epochs (e.g., host offline for 2+ weeks):
1. `lastFinalizedEpoch` will be stale — easily detectable
2. Catchup is safe: finalize epochs in sequence, each tx is independent
3. Reward calculations are retroactive and correct — cumS values are stored on-chain per epoch snapshot

---

## 9. Open Questions (Pre-Implementation)

| # | Question | Recommendation |
|---|---|---|
| Q1 | Which option (A/B/C) for launch? | A (cron) for testnet; Gelato + cron hybrid for mainnet |
| Q2 | Where should keeper logs/alerts go? | Discord `#prospereum` channel via Kin |
| Q3 | Should `KeeperWrapper` contract be deployed on mainnet? | Yes, even if unused initially — enables Gelato fallback |
| Q4 | What epoch does the mainnet keeper target first? | Epoch 0 close, 7 days post-genesis |
| Q5 | Who funds Gelato 1Balance for mainnet? | Treasury Safe |

---

## 10. Pre-Mainnet Checklist

- [ ] Jason confirms keeper approach (Option A / B / C)
- [ ] Ops wallet ETH funded on Base mainnet (≥ 0.01 ETH)
- [ ] OpenClaw cron job created for `epoch-keeper.sh` (testnet first, then mainnet)
- [ ] `$BASE_RPC_URL` and `$OPS_PRIVATE_KEY` set in `.env` (gitignored)
- [ ] Test run on Base Sepolia — call `finalizeEpoch(0)` when Epoch 0 closes (2026-04-04)
- [ ] Alert routing confirmed (Discord `#prospereum`)
- [ ] (Mainnet) Gelato task registered as backup
- [ ] (Mainnet) `KeeperWrapper` deployed and verified

---

## 11. First Finalization — Base Sepolia Testnet

**Epoch 0 closes:** ~2026-04-04 (7 days after genesis `1774726994`)  
**Target call:** Within 2 hours of close  
**Tx:** `RewardEngine(0xe668fE9DbCE8CBbc8b3590100e8c31aA12F5C697).finalizeEpoch(0)`  
**Expected outcome:** Zero active vaults in epoch 0 → zero PSRE minted → `lastFinalizedEpoch = 0`  
This is a smoke test for the keeper pipeline, not a reward event.
