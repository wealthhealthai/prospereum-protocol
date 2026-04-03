#!/usr/bin/env bash
# Prospereum Epoch Keeper — Option A (OpenClaw cron)
# Calls RewardEngine.finalizeEpoch(epochId) after each 7-day epoch closes.
# Safe to run any time — no-ops if nothing is ready.
#
# Contract semantics (confirmed via on-chain dry-run 2026-04-03):
#   lastFinalizedEpoch = N means "next epoch to finalize is N"
#   Initial value 0 → first call must be finalizeEpoch(0)
#   After epoch 0: lastFinalizedEpoch=1 → call finalizeEpoch(1), etc.
#
# Usage: ./epoch-keeper.sh [--dry-run]

set -euo pipefail

# ── Config ────────────────────────────────────────────────────────────────────

ENV_FILE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/.env"
[[ -f "$ENV_FILE" ]] && source "$ENV_FILE"

REWARD_ENGINE="${REWARD_ENGINE_PROXY:-0xe668fE9DbCE8CBbc8b3590100e8c31aA12F5C697}"
RPC_URL="${BASE_SEPOLIA_RPC:-https://sepolia.base.org}"
PRIVATE_KEY="${DEPLOYER_PK:?ERROR: DEPLOYER_PK not set in .env}"
GAS_LIMIT=6000000
CAST="${HOME}/.foundry/bin/cast"
DRY_RUN="${1:-}"

# ── Helpers ───────────────────────────────────────────────────────────────────

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [keeper] $*"; }
err() { log "ERROR: $*" >&2; exit 1; }

# Strip cast's bracket notation e.g. "604800 [6.048e5]" → "604800"
strip() { awk '{print $1}'; }

# ── Read chain state ──────────────────────────────────────────────────────────

log "Checking RewardEngine @ $REWARD_ENGINE"

NEXT=$("$CAST" call "$REWARD_ENGINE" "lastFinalizedEpoch()(uint256)" \
    --rpc-url "$RPC_URL" 2>/dev/null | strip)
GENESIS=$("$CAST" call "$REWARD_ENGINE" "genesisTimestamp()(uint256)" \
    --rpc-url "$RPC_URL" 2>/dev/null | strip)
EPOCH_DUR=$("$CAST" call "$REWARD_ENGINE" "EPOCH_DURATION()(uint256)" \
    --rpc-url "$RPC_URL" 2>/dev/null | strip)
NOW=$("$CAST" block latest --rpc-url "$RPC_URL" --field timestamp 2>/dev/null | strip)

[[ -z "$GENESIS" || -z "$EPOCH_DUR" || -z "$NOW" ]] && \
    err "Failed to read chain state. Check RPC: $RPC_URL"

log "lastFinalizedEpoch (next to finalize): $NEXT"
log "genesisTimestamp: $GENESIS | EPOCH_DURATION: $EPOCH_DUR | now: $NOW"

# ── Finalize ready epochs ─────────────────────────────────────────────────────

DONE=0
EPOCH_ID=$NEXT

while true; do
    # Epoch EPOCH_ID ends at: genesis + (EPOCH_ID + 1) * duration
    EPOCH_END=$(( GENESIS + (EPOCH_ID + 1) * EPOCH_DUR ))

    if (( NOW < EPOCH_END )); then
        SECS=$(( EPOCH_END - NOW ))
        log "Epoch $EPOCH_ID not yet ended. Closes in ${SECS}s (~$(( SECS / 3600 ))h $(( (SECS % 3600) / 60 ))m)."
        break
    fi

    if [[ "$DRY_RUN" == "--dry-run" ]]; then
        log "[DRY RUN] Would call finalizeEpoch($EPOCH_ID)"
        DONE=$(( DONE + 1 ))
        EPOCH_ID=$(( EPOCH_ID + 1 ))
        continue
    fi

    log "Calling finalizeEpoch($EPOCH_ID)..."
    OUTPUT=$("$CAST" send "$REWARD_ENGINE" \
        "finalizeEpoch(uint256)" "$EPOCH_ID" \
        --rpc-url "$RPC_URL" \
        --private-key "$PRIVATE_KEY" \
        --gas-limit "$GAS_LIMIT" \
        --json 2>&1) || err "finalizeEpoch($EPOCH_ID) failed: $OUTPUT"

    TX=$(echo "$OUTPUT" | python3 -c \
        "import sys,json; print(json.load(sys.stdin).get('transactionHash',''))" 2>/dev/null)

    [[ -z "$TX" ]] && err "No tx hash returned for epoch $EPOCH_ID. Output: $OUTPUT"

    log "✅ Epoch $EPOCH_ID finalized — tx: $TX"
    DONE=$(( DONE + 1 ))
    EPOCH_ID=$(( EPOCH_ID + 1 ))
done

[[ "$DONE" -eq 0 ]] && log "Nothing to finalize." || log "Done — finalized $DONE epoch(s)."
