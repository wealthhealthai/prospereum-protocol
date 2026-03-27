# PHOENIX Protocol — Kin End-of-Session

*Run when Archon sends "Enter PHOENIX protocol."*
*Ensures memory continuity before going quiet.*

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
