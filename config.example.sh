#!/bin/bash
# config.example.sh — Vault Assistant Configuration
# Copy to config.sh and fill in your paths.
#
# Usage:
#   cp config.example.sh config.sh
#   nano config.sh        # edit paths
#   source config.sh      # all scripts will read this

# ===== REQUIRED =====

# Path to your Obsidian vault root (where daily/, weekly/, _logs/ live)
VAULT_DIR=""

# ===== OPTIONAL =====

# Scripts directory (default: directory where config.sh lives)
SCRIPTS_DIR=""

# Log directory (default: $VAULT_DIR/_logs)
LOG_DIR=""

# Cron schedules (cron format: minute hour day month weekday)
DAILY_CRON_TIME="0 6 * * *"     # 06:00 every day
WEEKLY_CRON_TIME="0 7 * * 1"    # 07:00 every Monday

# GitHub blocked/next issue tracking (optional)
# vault-status.sh and weekly_fill.py will search ALL repos under this owner.
# If unset, log in with `gh auth login` and it uses your default owner.
GH_OWNER=""

# Telemetry: KPI directory (default: $VAULT_DIR/_logs/kpi)
KPI_DIR=""

# Trend data directory (default: $VAULT_DIR/_logs/trends)
TREND_DIR=""
