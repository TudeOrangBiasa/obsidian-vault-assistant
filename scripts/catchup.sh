#!/bin/bash
# catchup.sh — Catch-up on wake/login.
# Syncs vault + sessions after the system resumes from sleep.
#
# Usage:
#   ./catchup.sh                    # full catchup
#   ./catchup.sh --quick            # only OV sync, skip daily check

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/load_config.sh"

CATCHUP_LOG="$LOG_DIR/catchup.log"
LOCK_FILE="$LOG_DIR/catchup.lock"
QUICK="${1:-}"

# --- Lock ---
if ! mkdir "$LOCK_FILE" 2>/dev/null; then
  echo "[$(date -Iseconds)] [LOCK] Another catchup running. Exiting." >> "$CATCHUP_LOG"
  exit 1
fi
trap 'rm -rf "$LOCK_FILE"' EXIT

{
  echo "=== Catchup ($(date -Iseconds)) ==="

  # Pull vault
  echo "[1/4] git pull vault..."
  cd "$VAULT_DIR" 2>/dev/null && git pull --ff-only 2>&1
  echo "[OK] Vault pulled"

  if [ "$QUICK" != "--quick" ]; then
    # Check if today's daily note exists
    TODAY=$(date +%Y-%m-%d)
    if [ ! -f "$DAILY_DIR/$TODAY.md" ]; then
      echo "[2/4] Today's daily note missing — suggest create"
    else
      echo "[2/4] Daily note exists ✓"
    fi

    # Check if daily-cron already ran today
    DAILY_LOG="$LOG_DIR/daily-cron.log"
    if [ -f "$DAILY_LOG" ]; then
      LAST_RUN=$(tail -1 "$DAILY_LOG" 2>/dev/null | grep -oP '\d{4}-\d{2}-\d{2}' | head -1)
      if [ "$LAST_RUN" = "$(date -d yesterday +%Y-%m-%d)" ]; then
        echo "[3/4] Daily cron already ran for yesterday ✓"
      else
        echo "[3/4] Daily cron missed — run manually: bash $SCRIPTS_DIR/daily-cron.sh"
      fi
    fi

    # Check weekly review window (Fri-Sun)
    DOW=$(date +%u)
    WEEK=$(date +%V)
    if [ "$DOW" -ge 5 ] && [ ! -f "$WEEKLY_DIR/W${WEEK}.md" ]; then
      echo "[4/4] Weekly review W$WEEK not generated yet"
      echo "      Run: bash $SCRIPTS_DIR/weekly-cron.sh"
    else
      echo "[4/4] All checks passed ✓"
    fi
  fi

  echo "End: $(date -Iseconds)"
} >> "$CATCHUP_LOG" 2>&1

# Show summary to user
tail -3 "$CATCHUP_LOG"
