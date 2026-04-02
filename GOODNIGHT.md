# GOODNIGHT.md — 2026-04-02 (covers work done 2026-04-01)

## What Was Done Today

- **BlockApex SLA signed** ✅ — April 1, 2026. Shu signed, BlockApex starting April 2.
- **Contract review (2 rounds):**
  - v1: Flagged Section 19 non-compete (too broad) + §4.ii.b payment on initial vs final report
  - v2: All 3 changes made — Section 2 proposal reference added, §4.ii.b fixed to final report, §19 narrowed with avoidance-of-doubt carve-out. Clean. Signed.
- **$2,500 first-half wire:** Shu sending tomorrow (April 2)
- **Audit underway:** BlockApex commit hash `7e96ba9`, 2 SSAs, starting April 2

## Audit Timeline

| Milestone | Date |
|---|---|
| Audit start | April 2 |
| Initial report | ~April 8-9 |
| Fixes submitted | ~April 11 |
| Final report | ~April 13-14 |
| Mainnet deploy | **April 14-16** |

## Open Decisions (waiting on Jason or Shu)

| Decision | Who | Urgency |
|---|---|---|
| Wire $2,500 first payment to BlockApex | Shu | 🔴 April 2 |
| Keeper ops plan for `finalizeEpoch()` | Jason + Shu | 🔴 Resolve during audit window |
| Gnosis Safes created? (Founder + Treasury) | Shu | 🔴 Blocks mainnet deploy script |

## Blockers

- **Keeper decision** — `finalizeEpoch()` needs a reliable caller in prod. Options: cron job from ops wallet, Gelato, Chainlink Automation, or community-run. Need decision before mainnet.
- **Gnosis Safe addresses** — needed before I can finalize mainnet deploy script

## Notes for Tomorrow (During Audit Window)

1. Finalize mainnet deploy script — waiting on Gnosis Safe addresses from Shu
2. Raise keeper decision with Jason + Shu — need resolution this week
3. Plan LP pool setup: PSRE/USDC Uniswap v3 on Base, $40K genesis liquidity, $0.10 launch price
4. Monitor BlockApex — if no communication by April 4, ping Nadir to confirm they're started
