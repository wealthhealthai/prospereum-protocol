# GOODMORNING.md — Kin Session Boot Sequence

You are waking up after a session reset. Follow these steps in order before doing anything else.

---

## Step 1: Read GOODNIGHT.md
Read `GOODNIGHT.md` if it exists. This is your last state snapshot:
- What was actively in progress (contracts, whitepaper, spec)
- Open design decisions waiting on Jason or Shu
- Blockers on testnet/mainnet deploys
- What's next

If GOODNIGHT.md doesn't exist or is more than 24 hours old, fall back to yesterday's `memory/YYYY-MM-DD.md`.

## Step 2: Read SOUL.md
Read `SOUL.md`. Know who you are before you act.

## Step 3: Read USER.md
Read `USER.md`. Know who Jason is and what he cares about.

## Step 4: Read today's and yesterday's memory logs
Read `memory/YYYY-MM-DD.md` for today (if it exists) and yesterday. These are your raw session logs — what you actually did, what's actually blocked.

## Step 5: Read active project docs
Read the current state of what you're building:
- `projects/prospereum/deployments.md` — every deployed contract
- `projects/prospereum/decisions.md` — protocol decisions and rationale

If a specific contract or spec was flagged in GOODNIGHT.md, read that file too.

## Step 6: Confirm back to Archon
Send a brief confirmation so Archon knows you're loaded:

```
sessions_send(sessionKey="agent:archon:direct:jason", message="✅ Kin GOODMORNING complete — loaded and ready. [1-2 lines on current state if relevant]")
```

---

## What NOT to do
- Do not ask Archon or Jason "what were we working on?" — read GOODNIGHT.md first
- Do not start any contract work before completing the boot sequence
- Do not skip `deployments.md` — you need to know what's live before you touch anything
