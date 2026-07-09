#!/bin/bash
# daily-cron.sh — Daily vault telemetry + sync (8 steps).
# Runs every morning to collect KPI data and sync.
#
# Timing: 06:00 daily (processes yesterday's data).
# Cron: 0 6 * * * /path/to/scripts/daily-cron.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/load_config.sh"

LOG="$LOG_DIR/daily-cron.log"
LOCK_FILE="$LOG_DIR/daily-cron.lock"
KPI_SCRIPT="$SCRIPTS_DIR/kpi_feed.py"
TREND_SCRIPT="$SCRIPTS_DIR/trend_feed.py"
VALIDATE_SCRIPT="$SCRIPTS_DIR/validate_daily.py"
DATE_YESTERDAY=$(date -d yesterday +%Y-%m-%d)

# --- Lock ---
if ! mkdir "$LOCK_FILE" 2>/dev/null; then
  echo "[$(date -Iseconds)] [LOCK] Another instance running. Exiting." >> "$LOG"
  exit 1
fi
trap 'rm -rf "$LOCK_FILE"' EXIT

{
  echo "=== Daily Cron ($DATE_YESTERDAY) ==="
  echo "Start: $(date -Iseconds)"
  TOTAL=8

  # Step 1: Pull vault (git)
  echo "[1/$TOTAL] git pull vault..."
  cd "$VAULT_DIR" 2>/dev/null && git pull --ff-only 2>&1
  echo "[OK] Git pull done"

  # Step 2: KPI feed
  echo "[2/$TOTAL] KPI feed..."
  python3 "$KPI_SCRIPT" --date "$DATE_YESTERDAY" 2>&1
  echo "[OK] KPI feed done"

  # Step 3: Trend feed
  echo "[3/$TOTAL] Trend feed..."
  python3 "$TREND_SCRIPT" --weeks 12 --update-dashboard 2>&1
  echo "[OK] Trend feed done"

  # Step 4: Git push vault
  echo "[4/$TOTAL] git push vault..."
  cd "$VAULT_DIR" 2>/dev/null && {
    git add -A 2>/dev/null
    git diff --cached --quiet || git commit -m "daily: $DATE_YESTERDAY"
    git push 2>&1
  }
  echo "[OK] Git push done"

  # Step 5: Sync issues from GH
  SYNC_SKIP_REASON=""
  if [ ! -f "$SCRIPTS_DIR/github-sync.py" ]; then
    SYNC_SKIP_REASON="script not found"
  elif ! command -v gh &>/dev/null; then
    SYNC_SKIP_REASON="gh CLI not installed"
  elif [ -z "${GH_REPO:-}" ]; then
    SYNC_SKIP_REASON="GH_REPO not configured"
  fi
  if [ -z "$SYNC_SKIP_REASON" ]; then
    echo "[5/$TOTAL] GitHub sync..."
    python3 "$SCRIPTS_DIR/github-sync.py" --date "$DATE_YESTERDAY" 2>&1
    echo "[OK] GitHub sync done"
  else
    echo "[5/$TOTAL] GitHub sync — SKIP ($SYNC_SKIP_REASON)"
  fi

  # Step 6: Push repo
  echo "[6/$TOTAL] git push repo..."
  cd "$PROJECT_ROOT" 2>/dev/null && {
    git add -A 2>/dev/null
    git diff --cached --quiet || git commit -m "cron: $DATE_YESTERDAY"
    git push 2>&1
  }
  echo "[OK] Push done"

  # Step 7: Calendar sync (if script exists)
  if [ -f "$SCRIPTS_DIR/calendar_sync.py" ]; then
    echo "[7/$TOTAL] Calendar sync..."
    python3 "$SCRIPTS_DIR/calendar_sync.py" --sync 2>&1
    echo "[OK] Calendar sync done"
  else
    echo "[7/$TOTAL] Calendar sync — SKIP (script not found)"
  fi

  # Step 8: Validate daily note
  echo "[8/$TOTAL] Validate daily..."
  python3 "$VALIDATE_SCRIPT" --date "$DATE_YESTERDAY" 2>&1
  echo "[OK] Validate done"

  echo "End: $(date -Iseconds)"
  echo ""
} >> "$LOG" 2>&1
