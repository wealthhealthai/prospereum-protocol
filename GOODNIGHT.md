# GOODNIGHT.md — 2026-04-07

## What Was Done Today

**Major audit fix day.** Surgery day for Jason, but the protocol kept moving.

### Commits
| Commit | Description |
|---|---|
| `303cd2f` | Fix #1 #8 #16 #18 #20 — initial easy patches (Kin, morning) |
| `44f17d8` | Batch 1 full: #1 #8 #10 #14 #16 #18 #20 #21 — all easy patches done |
| `6a3dda8` | StakingVault v2 refactor — fix #3 #5 #9 #15 + cumS explicit tracking |

**Test count: 224 → 234 (all passing)**

### What's Fixed
- ✅ #1 — post-snapshot recordStakeTime drain (CRITICAL)
- ✅ #3 — flash loan cumS inflation via balanceOf (CRITICAL) — explicit tracking only now
- ✅ #5/#9/#15 — cross-epoch stakeTime contamination (HIGH) — Synthetix-style v2
- ✅ #8 — partnerOf stale after ownership transfer
- ✅ #10 — reclaimUnclaimed dead code → reclaimFromCV()
- ✅ #14 — transferOut CV bypass
- ✅ #16 — ghost emission when PSRE paused
- ✅ #18 — claims not gated by pause
- ✅ #20 — accStakeTime blanket reset
- ✅ #21 — qualified flag always false

### What's Still Open
| Finding | Status | Notes |
|---|---|---|
| #2 — O(V×C) gas pagination | 🔄 | Known design issue, long-term |
| #4/#6 — createVault fee tier whitelist | 🔄 | minPsreOut enforced, whitelist pending |
| #13 — LP 1:1 weighting | 🔄 | Spec decision — Jason + Shu |
| #19 — two-pass EMA (sumR in-loop) | 🔄 | Medium priority |

## Codebase State

**v3.2 + audit fixes — 234/234 tests passing**
- Deployed to Base Sepolia: pre-fix bytecode still live (needs redeploy after fixes complete)
- Keeper: cron `3fc22360`, next run April 11 20:00 UTC (Epoch 1)
- BlockApex: reviewing commit `7e96ba9` — need to share updated commit for re-review

## Open Decisions

| Item | Who | Urgency |
|---|---|---|
| LP 1:1 weighting (#13) — keep or change? | Jason + Shu | 🔴 Before re-audit |
| Share updated commit with BlockApex | Shu | 🟠 This week |
| Gnosis Safe creation | Jason + Shu | 🟠 Blocks mainnet deploy script |
| Redeploy to Base Sepolia with fixes | Kin — on signal | 🟠 |
| Fee tier whitelist (#4/#6) | Kin | 🟠 Next |
| Two-pass EMA (#19) | Kin | 🟡 Medium priority |

## Notes for Tomorrow

1. Implement fee tier whitelist (#4/#6) — next code task
2. Implement two-pass EMA (#19)
3. When both done → redeploy to Base Sepolia + share commit with BlockApex for re-review
4. Mainnet target: **April 18–21** — still on track given today's velocity
5. Jason recovers — light session through April 10
