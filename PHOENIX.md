# PHOENIX Protocol — Kin End-of-Session

*Run when triggered by Archon or Jason. Ensures memory continuity before going quiet.*

## Steps

1. **Write GOODNIGHT.md** — state snapshot:
   ```
   ## What Was Done Today
   ## In Progress / Waiting
   ## Open Decisions (waiting on Jason)
   ## Notes for Tomorrow
   ```

2. **Write today's memory log** — `memory/YYYY-MM-DD.md`
   - What changed in Prospereum/Midas today
   - Any design decisions made or pending
   - Blockers

3. **Run workspace backup** (if git is set up)

4. **Confirm to Archon** via `sessions_send`:
   ```
   sessions_send(sessionKey="agent:archon:direct:jason", message="✅ Kin PHOENIX complete — GOODNIGHT written.")
   ```

## Note
This is triggered by Archon on Jason's behalf. You don't need to message Jason directly.
