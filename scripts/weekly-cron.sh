#!/bin/bash
# weekly-cron.sh — Weekly vault telemetry aggregation.
# Generates weekly review note + refreshes trends.
#
# Timing: Monday 07:00 (after daily cron for Sunday settles).
# Cron: 0 7 * * 1 /path/to/scripts/weekly-cron.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/load_config.sh"

LOG="$LOG_DIR/weekly-cron.log"
LOCK_FILE="$LOG_DIR/weekly-cron.lock"

mkdir -p "$LOG_DIR" "$WEEKLY_DIR"

# --- Lock ---
if ! mkdir "$LOCK_FILE" 2>/dev/null; then
  echo "[$(date -Iseconds)] [LOCK] Another instance running. Exiting." >> "$LOG"
  exit 1
fi
trap 'rm -rf "$LOCK_FILE"' EXIT

# --- Determine current week ---
YEAR=$(date +%Y)
WEEK=$(date -d "last monday" +%V 2>/dev/null || date +%V)
CREATED=$(date +%Y-%m-%d)

{
  echo "=== Weekly Cron W$WEEK ==="
  echo "Start: $(date -Iseconds)"

  python3 "$SCRIPTS_DIR/weekly_fill.py" --week "$WEEK" --year "$YEAR" 2>&1
  PY_EXIT=$?

  if [ $PY_EXIT -eq 0 ]; then
    echo "[OK] Weekly note generated"
  else
    echo "[FAIL] weekly_fill.py failed (exit $PY_EXIT)"
  fi

  # Refresh trend data
  python3 "$SCRIPTS_DIR/trend_feed.py" --weeks 12 --update-dashboard 2>&1
  echo "[OK] Trend data refreshed"

  # Update KPI with weekly marker
  KPI_FILE="$KPI_DIR/$CREATED.md"
  if [ -f "$KPI_FILE" ]; then
    echo "[week_kpi:: W$WEEK]" >> "$KPI_FILE"
    echo "[KPI] Weekly marker appended"
  fi

  echo "End: $(date -Iseconds)"
} >> "$LOG" 2>&1
