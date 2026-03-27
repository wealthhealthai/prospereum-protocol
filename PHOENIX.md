# PHOENIX Protocol — Kin

*Run when Archon sends "Enter PHOENIX protocol."*
*Applies to both the main session and child sessions (Discord channels, etc.).*

---

## Are you a child session or the main session?

- **Main session** (`agent:kin:direct:jason`) → follow the full protocol below
- **Child session** (Discord channel, etc.) → skip to [Child Session Protocol](#child-session-protocol)

---

## Child Session Protocol

If you are a child session (e.g. `agent:kin:discord:channel:*`), do this:

1. **Write an EOD summary file:**
   - Path: `memory/sessions/YYYY-MM-DD-{sanitized-session-key}.md`
   - Sanitize key: replace `:` and `/` with `-`, drop `agent:kin:` prefix
   - Example: `agent:kin:discord:channel:1479357527010578432` → `discord-channel-1479357527010578432`

   Format:
   ```markdown
   ## PHOENIX — {session-key} — {date}

   **Status:** active / quiet / blocked

   **What was done:**
   - [bullet list of work done — contracts touched, decisions made, code written]

   **Open items / blockers:**
   - [anything unresolved or mid-flight]

   **Needs Jason or Shu:**
   - [anything requiring a human decision]
   ```

2. **Commit and push:**
   ```bash
   cd /Users/wealthhealth_admin/.openclaw/workspace-kin
   git add memory/sessions/
   git commit -m "phoenix: {session-name} {date}"
   git push
   ```

3. Done — no need to confirm back to Archon from child sessions.

---

## Main Session Protocol

---

## Steps

### 1. Write today's memory log
Write or append to `memory/YYYY-MM-DD.md`:
- What changed in Prospereum/Midas today
- Any design decisions made or still pending
- Contract state (what's deployed, what's not)
- Blockers — be specific (not "blocked" but "blocked on X because Y")

### 2. Update deployments.md
If anything was deployed to testnet or mainnet today, update `projects/prospereum/deployments.md` immediately. This file is sacred — never let it fall out of sync.

### 3. Update decisions.md
If any protocol decisions were made or revised today, write them to `projects/prospereum/decisions.md`.

### 4. Write GOODNIGHT.md
Overwrite `GOODNIGHT.md` with a state snapshot:

```markdown
# GOODNIGHT.md — [YYYY-MM-DD]

## What Was Done Today
- [bullet list — be specific about what changed]

## In Progress / Waiting
- [anything mid-flight that will need to resume]

## Open Decisions (waiting on Jason or Shu)
- [specific questions that need answers before work can continue]

## Blockers
- [active blockers, how long they've been sitting]

## Notes for Tomorrow
- [top priorities for next session]
```

### 5. Commit and push workspace
```bash
cd /Users/wealthhealth_admin/.openclaw/workspace-kin
git add -A && git commit -m "phoenix: kin $(date +%Y-%m-%d)" && git push
```

### 6. Confirm to Archon
```
sessions_send(sessionKey="agent:archon:direct:jason", message="✅ Kin PHOENIX complete — GOODNIGHT written. [1-2 line summary of today's state]")
```

---

## What NOT to do
- Do not skip writing GOODNIGHT.md — next session boots from this file
- Do not include raw message transcripts in memory logs — summaries only
- Do not skip the git push — your files aren't safe until they're committed
