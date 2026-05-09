# GOODNIGHT.md — 2026-05-09 (EOD May 8)

## What Was Done Today

**Audit: FULLY CLOSED.** Nadir cleared all 6 PSRE-native delta observations. CSV updated. Decision logged.

**Mainnet upgrade: STAGED.** Deploy script + 3-step Safe batch JSONs committed and ready.

| Commit | What |
|---|---|
| `54d0e67` | PSRE-delta #1-#6 added to audit CSV — Nadir cleared all |
| `7a938c4` | MEMORY.md updated, decision logged: audit closed |
| `be00860` | DeployFactoryUpgrade.s.sol + 3 Safe batch JSONs |

## Mainnet Upgrade Plan (PSRE-Native)

**3 steps, 14 days, 0 migration pain (0 partners)**

| Step | When | Action |
|---|---|---|
| 1 | Day 0 (whenever) | Founder Safe: `scheduleUpgrade(newReImpl)` → 7-day timelock |
| 2 | Day 7 | Founder Safe: `executeUpgrade()` + `scheduleSetFactory(newFactory)` → 7-day timelock |
| 3 | Day 14 | Founder Safe: `pause()` + `executeSetFactory()` + `clearVaultScores([])` + `unpause()` |

**Ready to execute Step 1 any time Jason and Shu confirm.**

## Protocol State

- **Epoch 2:** Running — closes **May 13 03:52 UTC** (~91h)
- **setSplit:** Still 50/50 — Shu co-sign still pending (Founder Safe nonce 2)
- **T (total emitted):** 0 | **Partners:** 0

## Open Items

| Item | Who | Urgency |
|---|---|---|
| setSplit co-sign (nonce 2) | Shu | 🔴 Before May 13 |
| Upgrade Step 1: scheduleUpgrade | Jason + Shu | 🟠 Any time |
| Genesis LP pool | Shu | 🟠 |
| Unicrypt LP lock | Shu + Jason | 🟠 After LP pool |
| Sablier vesting | Shu | 🟠 |
| Nadir closing message | Jason | 🟡 |
| Basescan verification | Kin | 🟡 Needs API key |

## Notes for Tomorrow

1. setSplit: 4 days to May 13 — ping Shu
2. Upgrade: confirm timing with Jason — Step 1 can happen any time
3. Keeper fires automatically May 13 05:00 UTC
