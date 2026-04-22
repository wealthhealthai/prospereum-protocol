#!/usr/bin/env bash
# Prospereum Epoch Keeper — Option A (OpenClaw cron)
# Calls RewardEngine.finalizeEpoch(epochId) after each 7-day epoch closes.
# Safe to run any time — no-ops if nothing is ready.
#
# Contract semantics (corrected 2026-04-11 after epoch 1 miss):
#   firstEpochFinalized=false → epoch 0 not done → NEXT=0
#   firstEpochFinalized=true  → last done = lastFinalizedEpoch → NEXT=last+1
#   Initial assumption (NEXT=lastFinalizedEpoch) was wrong after epoch 0.
#
# Usage: ./epoch-keeper.sh [--dry-run]

set -euo pipefail

# ── Config ────────────────────────────────────────────────────────────────────

ENV_FILE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/.env"
[[ -f "$ENV_FILE" ]] && source "$ENV_FILE"

# Network selection: set KEEPER_NETWORK=testnet to use Base Sepolia.
# Default: mainnet (post April 21 deploy).
KEEPER_NETWORK="${KEEPER_NETWORK:-mainnet}"

if [[ "$KEEPER_NETWORK" == "mainnet" ]]; then
  REWARD_ENGINE="${REWARD_ENGINE_MAINNET:-0x9Ab37Fc6D01B85491Ed0863B7F832784bE717EF5}"
  RPC_URL="${BASE_MAINNET_RPC:-https://mainnet.base.org}"
else
  REWARD_ENGINE="${REWARD_ENGINE_PROXY:-0xe668fE9DbCE8CBbc8b3590100e8c31aA12F5C697}"
  RPC_URL="${BASE_SEPOLIA_RPC:-https://sepolia.base.org}"
fi

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

LAST=$("$CAST" call "$REWARD_ENGINE" "lastFinalizedEpoch()(uint256)" \
    --rpc-url "$RPC_URL" 2>/dev/null | strip)
FIRST_DONE=$("$CAST" call "$REWARD_ENGINE" "firstEpochFinalized()(bool)" \
    --rpc-url "$RPC_URL" 2>/dev/null | strip)
GENESIS=$("$CAST" call "$REWARD_ENGINE" "genesisTimestamp()(uint256)" \
    --rpc-url "$RPC_URL" 2>/dev/null | strip)
EPOCH_DUR=$("$CAST" call "$REWARD_ENGINE" "EPOCH_DURATION()(uint256)" \
    --rpc-url "$RPC_URL" 2>/dev/null | strip)
NOW=$("$CAST" block latest --rpc-url "$RPC_URL" --field timestamp 2>/dev/null | strip)

[[ -z "$GENESIS" || -z "$EPOCH_DUR" || -z "$NOW" ]] && \
    err "Failed to read chain state. Check RPC: $RPC_URL"

# Fix (2026-04-11): lastFinalizedEpoch semantics:
#   firstEpochFinalized=false → epoch 0 not yet done → NEXT=0
#   firstEpochFinalized=true  → last done = LAST    → NEXT=LAST+1
if [[ "$FIRST_DONE" == "false" ]]; then
    NEXT=0
else
    NEXT=$(( LAST + 1 ))
fi

log "lastFinalizedEpoch: $LAST | firstEpochFinalized: $FIRST_DONE | nextToFinalize: $NEXT"
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
