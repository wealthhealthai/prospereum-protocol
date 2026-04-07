# GOODNIGHT.md — 2026-04-07

## What Was Done Today (2026-04-06)

- **BlockApex preliminary audit report received** — 22 findings: 3 Critical, 3 High, 11 Medium, 4 Low, 1 Informational
- **Full triage completed** — categorized every finding as design issue vs. implementation bug, identified fix approach for each
- **Key insight:** StakingVault accounting architecture is fundamentally broken (accStakeTime pattern) — issues #1, #5, #9, #15, #20 all stem from the same root cause. Needs major refactor.
- **Critical flash loan vector (#3):** live balanceOf scanning in _updateCumS must be replaced with explicit deposit tracking

## Audit Fix Plan (prioritized)

### Easy patches (1-5 lines each):
- #1: `require(!epochSnapshotted[epochId])` in recordStakeTime
- #8: `vault.owner()` instead of `factory.partnerOf()` for auth
- #10: `reclaimFromCV()` in PartnerVault
- #14: CV check in transferOut guard
- #16: `require(!psre.paused())` before mint in finalizeEpoch
- #18: `whenNotPaused` on claimPartnerReward + claimStake
- #20: `accStakeTime -= st` instead of `= 0`
- #21: delegate `isQualified()` to RewardEngine

### Significant refactors:
- #3: _updateCumS architecture — explicit deposit tracking only
- #4/#6: createVault slippage — fee tier whitelist + minimum PSRE floor
- #2: finalizeEpoch pagination
- #5/#9/#15: StakingVault full accounting refactor (Synthetix-style)
- #19: Two-pass EMA in finalizeEpoch

## Open Decisions (waiting on Jason or Shu)

| Decision | Who | Urgency |
|---|---|---|
| LP 1:1 weighting (#13) — keep or change? | Jason + Shu | 🔴 Before fixes start |
| Revised mainnet timeline — accept April 18-21? | Jason + Shu | 🔴 This week |
| Notify BlockApex to extend engagement for fix round | Shu | 🔴 Today |
| Gnosis Safes creation | Shu | 🟡 Before mainnet deploy script |

## Notes for Tomorrow

1. **Start easy patches immediately** — #1, #8, #10, #14, #16, #18, #20, #21 can all be done in one HEPHAESTUS run
2. **Design the StakingVault refactor** before touching any code — get Shu/Jason sign-off first
3. **Design the _updateCumS fix** for #3 — explicit deposit tracking approach
4. Mainnet target now **April 18-21 at earliest**
