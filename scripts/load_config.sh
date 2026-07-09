#!/bin/bash
# load_config.sh — Source this from all scripts to load vault config
#
# Usage:
#   SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
#   source "$SCRIPT_DIR/load_config.sh"

# Find project root (where config.sh lives)
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Load config.sh — user must create this from config.example.sh
CONFIG_FILE="$PROJECT_ROOT/config.sh"
if [ ! -f "$CONFIG_FILE" ]; then
  echo "[FATAL] config.sh not found. Copy config.example.sh to config.sh and fill in your paths."
  echo "  cp \"$PROJECT_ROOT/config.example.sh\" \"$CONFIG_FILE\""
  echo "  nano \"$CONFIG_FILE\""
  exit 1
fi
source "$CONFIG_FILE"

# Validate required vars
if [ -z "$VAULT_DIR" ]; then
  echo "[FATAL] VAULT_DIR not set in config.sh"
  exit 1
fi
if [ ! -d "$VAULT_DIR" ]; then
  echo "[FATAL] VAULT_DIR '$VAULT_DIR' does not exist"
  exit 1
fi

# Derive defaults
SCRIPTS_DIR="${SCRIPTS_DIR:-$PROJECT_ROOT/scripts}"
LOG_DIR="${LOG_DIR:-$VAULT_DIR/_logs}"
KPI_DIR="${KPI_DIR:-$VAULT_DIR/_logs/kpi}"
TREND_DIR="${TREND_DIR:-$VAULT_DIR/_logs/trends}"
WEEKLY_DIR="$VAULT_DIR/weekly"
DAILY_DIR="$VAULT_DIR/daily"
CACHE_FILE="$LOG_DIR/.vault-status.cache"
CACHE_TTL=300

# Export for subprocesses
export VAULT_DIR LOG_DIR KPI_DIR TREND_DIR WEEKLY_DIR DAILY_DIR
export SCRIPTS_DIR CACHE_FILE CACHE_TTL

# Auto-create dirs
mkdir -p "$LOG_DIR" "$KPI_DIR" "$TREND_DIR" "$WEEKLY_DIR" 2>/dev/null
