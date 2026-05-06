## PHOENIX — discord-channel-jason — 2026-05-06

**Status:** active

**What was done:**
- **2026-05-04 22:00 PDT:** prospereum-epoch-keeper-mainnet cron ran — returned ANNOUNCE_SKIP (Epoch 1 not yet closeable)
- **2026-05-05 22:00 PDT:** ✅ Epoch 1 finalized on Base Mainnet. Tx: `0xf6dbef4aaadd348e52f1d3978b553a161cd7377821072de62d5d2a090c5a3a9f`. Posted to #prospereum Discord. Epoch 2 now accruing, closes in ~166h.

**Open items / blockers:**
- setSplit deadline (May 6 03:52 UTC) — unclear if Shu co-signed in time; should verify on-chain
- Mainnet Epoch 2 close expected ~May 12

**Needs Jason or Shu:**
- Confirm setSplit was executed (Founder Safe nonce 2) — if not, Epoch 0 staker rewards are still split 50/50 including empty LP pool
