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
TODAY=$(date +%Y-%m-%d)

# --- Lock ---
if ! mkdir "$LOCK_FILE" 2>/dev/null; then
  echo "[$(date -Iseconds)] [LOCK] Another instance running. Exiting." >> "$LOG"
  exit 1
fi
trap 'rm -rf "$LOCK_FILE"' EXIT

{
  echo "=== Daily Cron ($DATE_YESTERDAY) ==="
  echo "Start: $(date -Iseconds)"
  TOTAL=9

  # Step 1: Ensure today's daily note exists
  echo "[1/$TOTAL] Daily note check..."
  if [ ! -f "$DAILY_DIR/$TODAY.md" ]; then
    if [ -f "$VAULT_DIR/templates/daily.md" ]; then
      cp "$VAULT_DIR/templates/daily.md" "$DAILY_DIR/$TODAY.md"
      sed -i "s/<% tp.date.now(\"YYYY-MM-DD\" ) %>/$TODAY/g; s/<% tp.date.now(\"ww\" ) %>/$(date +%V)/g; s/<% tp.date.now(\"dddd\" ) %>/$(date +%A)/g; s/<% tp.date.now(\"dddd, DD MMMM YYYY\" ) %>/$(date '+%A, %d %B %Y')/g" "$DAILY_DIR/$TODAY.md" 2>/dev/null
      echo "[OK] Created: $TODAY.md"
    else
      # Minimal fallback
      cat > "$DAILY_DIR/$TODAY.md" <<NOTE
---
date: $TODAY
week: $(date +%V)
day: $(date +%A)
type: daily
mood:
energy:
focus:
---

# $(date '+%A, %d %B %Y')

---
## ✅ End of Day

> [!done]- Kelar?
> -

> [!fail]- Mentok?
> -

> [!question]- Besok?
> -
NOTE
      echo "[OK] Created (no template): $TODAY.md"
    fi
  else
    echo "[OK] Already exists: $TODAY.md"
  fi

  # Step 2: Pull vault (git)
  echo "[2/$TOTAL] git pull vault..."
  cd "$VAULT_DIR" 2>/dev/null && git pull --ff-only 2>&1
  echo "[OK] Git pull done"

  # Step 3: KPI feed
  echo "[3/$TOTAL] KPI feed..."
  python3 "$KPI_SCRIPT" --date "$DATE_YESTERDAY" 2>&1
  echo "[OK] KPI feed done"

  # Step 4: Trend feed
  echo "[4/$TOTAL] Trend feed..."
  python3 "$TREND_SCRIPT" --weeks 12 --update-dashboard 2>&1
  echo "[OK] Trend feed done"

  # Step 5: Git push vault
  echo "[5/$TOTAL] git push vault..."
  cd "$VAULT_DIR" 2>/dev/null && {
    git add -A 2>/dev/null
    git diff --cached --quiet || git commit -m "daily: $DATE_YESTERDAY"
    git push 2>&1
  }
  echo "[OK] Git push done"

  # Step 6: Sync issues from GH
  SYNC_SKIP_REASON=""
  if [ ! -f "$SCRIPTS_DIR/github-sync.py" ]; then
    SYNC_SKIP_REASON="script not found"
  elif ! command -v gh &>/dev/null; then
    SYNC_SKIP_REASON="gh CLI not installed"
  elif [ -z "${GH_OWNER:-}" ]; then
    SYNC_SKIP_REASON="GH_OWNER not configured"
  fi
  if [ -z "$SYNC_SKIP_REASON" ]; then
    echo "[6/$TOTAL] GitHub sync..."
    python3 "$SCRIPTS_DIR/github-sync.py" --date "$DATE_YESTERDAY" 2>&1
    echo "[OK] GitHub sync done"
  else
    echo "[6/$TOTAL] GitHub sync — SKIP ($SYNC_SKIP_REASON)"
  fi

  # Step 7: Push repo
  echo "[7/$TOTAL] git push repo..."
  cd "$PROJECT_ROOT" 2>/dev/null && {
    git add -A 2>/dev/null
    git diff --cached --quiet || git commit -m "cron: $DATE_YESTERDAY"
    git push 2>&1
  }
  echo "[OK] Push done"

  # Step 8: Calendar sync (if script exists)
  if [ -f "$SCRIPTS_DIR/calendar_sync.py" ]; then
    echo "[8/$TOTAL] Calendar sync..."
    python3 "$SCRIPTS_DIR/calendar_sync.py" --sync 2>&1
    echo "[OK] Calendar sync done"
  else
    echo "[8/$TOTAL] Calendar sync — SKIP (script not found)"
  fi

  # Step 9: Validate daily note
  echo "[9/$TOTAL] Validate daily..."
  python3 "$VALIDATE_SCRIPT" --date "$DATE_YESTERDAY" 2>&1
  echo "[OK] Validate done"

  echo "End: $(date -Iseconds)"
  echo ""
} >> "$LOG" 2>&1
