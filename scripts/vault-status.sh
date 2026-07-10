#!/bin/bash
# vault-status.sh — Aggregate vault system status for AI assistant.
# Outputs JSON consumed by AI agents for proactive greeting + gap detection.
#
# Usage:
#   ./vault-status.sh                # full JSON status
#   ./vault-status.sh --summary      # one-liner for greeting
#   ./vault-status.sh --flush-cache  # clear cache
#
# Cache: results cached 5 min to avoid repeated file reads.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/load_config.sh"

# ===== Cache check =====
SHOW_SUMMARY=0
if [ "${1:-}" = "--summary" ]; then
  SHOW_SUMMARY=1
fi

handle_cache_hit() {
  if [ "$SHOW_SUMMARY" -eq 1 ]; then
    python3 -c "import json,os; print(json.load(open(os.environ['CACHE_FILE']))['summary'])"
  else
    cat "$CACHE_FILE"
  fi
  exit 0
}

if [ $# -eq 0 ] || [ "$1" = "--json" ] || [ "$1" = "--summary" ]; then
  if [ -f "$CACHE_FILE" ]; then
    CACHE_AGE=$(($(date +%s) - $(stat -c %Y "$CACHE_FILE" 2>/dev/null || echo 0)))
    if [ "$CACHE_AGE" -lt "$CACHE_TTL" ] 2>/dev/null; then
      handle_cache_hit
    fi
  fi
fi

if [ "${1:-}" = "--flush-cache" ]; then
  rm -f "$CACHE_FILE"
  echo "[OK] Cache flushed"
  exit 0
fi

# ===== Compute week range =====
WEEK_DATA=$(python3 -c "
from datetime import date, timedelta
today = date.today()
iso = today.isocalendar()
jan4 = date(iso[0], 1, 4)
start = jan4 - timedelta(days=jan4.isocalendar()[2] - 1)
monday = start + timedelta(weeks=iso[1] - 1)
print(f'{monday.isoformat()} {iso[1]}')
" 2>/dev/null) || WEEK_DATA=""
WEEK_START="${WEEK_DATA% *}"
WEEK_NUM="${WEEK_DATA#* }"
TODAY=$(date +%Y-%m-%d)

# ===== 1. Cron health =====
CRON_STATUS="unknown"
CRON_DATE=""
CRON_FAILED=0

# Daily cron
DAILY_LOG="$LOG_DIR/daily-cron.log"
if [ -f "$DAILY_LOG" ]; then
  LAST_RUN=$(tail -1 "$DAILY_LOG" 2>/dev/null | grep -oP '\d{4}-\d{2}-\d{2}' | head -1)
  if [ -n "$LAST_RUN" ] && [ "$LAST_RUN" = "$(date -d yesterday +%Y-%m-%d)" ]; then
    CRON_STATUS="ok"
    CRON_DATE="$LAST_RUN"
  else
    CRON_STATUS="missed"
    CRON_DATE="$LAST_RUN"
  fi

  # Check for failed steps
  FAILED_STEPS=$(grep -c "\[FAIL\]" "$DAILY_LOG" 2>/dev/null || echo 0)
  if [ "$FAILED_STEPS" -gt 0 ]; then
    CRON_STATUS="degraded"
    CRON_FAILED=$FAILED_STEPS
  fi
fi

# ===== 2. EOD unfilled count (this week) =====
EOD_UNFILLED=0
EOD_FILLED=0
EOD_LAST=""
EOD_TOTAL_DAYS=0
d="$WEEK_START"
while [ "$d" != "$(date -d "$TODAY + 1 day" +%Y-%m-%d)" ]; do
  f="$DAILY_DIR/$d.md"
  if [ -f "$f" ]; then
    EOD_TOTAL_DAYS=$((EOD_TOTAL_DAYS + 1))
    HAS_EOD=0
    IN_EOD=0
    while IFS= read -r line; do
      if echo "$line" | grep -qE '^>\s*\[!(done|fail|question)\]'; then
        IN_EOD=1
      elif echo "$line" | grep -qE '^>\s*\[!|^## '; then
        IN_EOD=0
      elif [ $IN_EOD -eq 1 ]; then
        CLEAN=$(echo "$line" | sed 's/^> *- *//;s/^- *//;s/^ *//')
        if [ -n "$CLEAN" ]; then
          HAS_EOD=1
        fi
      fi
    done < "$f"
    if [ $HAS_EOD -eq 1 ]; then
      EOD_FILLED=$((EOD_FILLED + 1))
    else
      EOD_UNFILLED=$((EOD_UNFILLED + 1))
    fi
    EOD_LAST="$d"
  fi
  d=$(date -d "$d + 1 day" +%Y-%m-%d)
  [ "$d" = "$TODAY" ] && break
done

# ===== 3. Blocked count (via gh CLI) =====
BLOCKED_COUNT=0
GH_OWNER="${GH_OWNER:-}"
if [ -z "$GH_OWNER" ] && command -v gh &>/dev/null; then
  GH_OWNER=$(gh api user --jq '.login' 2>/dev/null || echo "")
fi
if command -v gh &>/dev/null && [ -n "$GH_OWNER" ]; then
  BLOCKED_OUTPUT=$(timeout 10 gh search issues --owner "$GH_OWNER" --label=blocked --state=open --json=number --limit=50 2>/dev/null)
  if [ $? -eq 0 ]; then
    BLOCKED_COUNT=$(echo "$BLOCKED_OUTPUT" | python3 -c "import json,sys; print(len(json.load(sys.stdin)))" 2>/dev/null || echo 0)
  fi
fi

# ===== 4. Weekly review status =====
WEEKLY_EXISTS=0
[ -f "$WEEKLY_DIR/W${WEEK_NUM}.md" ] && WEEKLY_EXISTS=1

# ===== 5. Review rate (last 7 days from KPI) =====
TOTAL_REVIEW=0
REVIEW_DAYS=0
for i in 1 2 3 4 5 6 7; do
  KD=$(date -d "$TODAY - $i days" +%Y-%m-%d)
  KF="$KPI_DIR/$KD.md"
  if [ -f "$KF" ]; then
    REVIEW_DAYS=$((REVIEW_DAYS + 1))
    RP=$(grep '\[review_pct::' "$KF" | sed 's/.*review_pct:: *\([0-9]*\).*/\1/')
    if [ -n "$RP" ]; then
      TOTAL_REVIEW=$((TOTAL_REVIEW + RP))
    fi
  fi
done
if [ $REVIEW_DAYS -gt 0 ]; then
  REVIEW_RATE=$((TOTAL_REVIEW / REVIEW_DAYS))
else
  REVIEW_RATE=0
fi

# ===== 6. Next issues count =====
NEXT_COUNT=0
if command -v gh &>/dev/null && [ -n "$GH_OWNER" ]; then
  NEXT_OUTPUT=$(timeout 10 gh search issues --owner "$GH_OWNER" --label=next --state=open --json=number --limit=50 2>/dev/null)
  if [ $? -eq 0 ]; then
    NEXT_COUNT=$(echo "$NEXT_OUTPUT" | python3 -c "import json,sys; print(len(json.load(sys.stdin)))" 2>/dev/null || echo 0)
  fi
fi

# ===== 7. Determine urgent gaps =====
GAPS="[]"
GAP_LIST=()
if [ "$EOD_UNFILLED" -ge 2 ]; then
  GAP_LIST+=("eod_unfilled")
fi
if [ "$BLOCKED_COUNT" -ge 5 ]; then
  GAP_LIST+=("blocked_high")
fi
if [ "$REVIEW_RATE" -lt 70 ] && [ "$REVIEW_DAYS" -ge 3 ]; then
  GAP_LIST+=("review_low")
fi
if [ "$WEEKLY_EXISTS" -eq 0 ]; then
  DOW=$(date +%u)
  if [ "$DOW" -ge 5 ]; then
    GAP_LIST+=("weekly_pending")
  fi
fi
if [ ${#GAP_LIST[@]} -gt 0 ]; then
  GAPS=$(printf '%s\n' "${GAP_LIST[@]}" | python3 -c "import json,sys; print(json.dumps([l.strip() for l in sys.stdin if l.strip()]))")
fi

# ===== 8. Summary line =====
SUMMARY_PARTS=()
if [ "$CRON_STATUS" = "ok" ]; then
  SUMMARY_PARTS+=("✓ Cron")
elif [ "$CRON_STATUS" = "missed" ]; then
  SUMMARY_PARTS+=("✗ Cron missed")
fi
if [ "$EOD_UNFILLED" -gt 0 ]; then
  SUMMARY_PARTS+=("${EOD_UNFILLED} EOD pending")
fi
if [ "$BLOCKED_COUNT" -gt 0 ]; then
  SUMMARY_PARTS+=("${BLOCKED_COUNT} blocked")
fi
if [ "$WEEKLY_EXISTS" -eq 0 ]; then
  SUMMARY_PARTS+=("Weekly: pending")
fi
SUMMARY=$(IFS=" | "; echo "${SUMMARY_PARTS[*]}")
[ -z "$SUMMARY" ] && SUMMARY="✓ Semua OK"

# ===== Output JSON =====
OUTPUT=$(cat <<EOF
{
  "timestamp": "$(date -Iseconds)",
  "week": $WEEK_NUM,
  "week_start": "$WEEK_START",
  "today": "$TODAY",
  "cron": {
    "status": "$CRON_STATUS",
    "last_run": "$CRON_DATE",
    "failed_steps": ${CRON_FAILED:-0}
  },
  "eod": {
    "filled": $EOD_FILLED,
    "unfilled": $EOD_UNFILLED,
    "total_days": $EOD_TOTAL_DAYS,
    "last_filled": "$EOD_LAST"
  },
  "gh": {
    "blocked": $BLOCKED_COUNT,
    "next": $NEXT_COUNT
  },
  "weekly": {
    "exists": $WEEKLY_EXISTS,
    "file": "W${WEEK_NUM}.md"
  },
  "review_rate": $REVIEW_RATE,
  "urgent_gaps": $GAPS,
  "summary": "$SUMMARY"
}
EOF
)

# --- Write cache ---
echo "$OUTPUT" > "$CACHE_FILE"

# --- Output ---
if [ "$SHOW_SUMMARY" -eq 1 ]; then
  echo "$SUMMARY"
else
  echo "$OUTPUT"
fi
