# Vault Assistant Skill

Proactive Obsidian vault AI assistant. Auto-detects gaps (unfilled EOD, blocked issues, low review rate) and suggests actions.

## Session Start Protocol

At session start (configured via AGENTS.md):

1. **Load this skill** — `skill vault`
2. **Check OpenViking** — `openviking_find "pref:vault greeting"`:
   - `greeting_disabled` → skip greeting
   - OV offline → continue silently
3. **Run status check** — `bash /path/to/scripts/vault-status.sh --summary`
4. **Parse JSON** → extract `summary` + `urgent_gaps[0]`
5. **Show 1-line status + 1 action offer**

## Proactive Patterns

### Session Greeting

```
✓ Cron OK | 3 EOD pending | 50 blocked
3 hari EOD belum diisi. Mau catat sekarang?
```

**Rules:**
- Greeting once per session
- User says "vault quiet" / "skip" → suppress for this session + store in OpenViking
- Offer 1 action — the most urgent (`urgent_gaps[0]`)
- No gaps → "Mau hari ini: catat daily? review? cek blocked?"

### Gap Detection

| Condition | Action |
|-----------|--------|
| `eod_unfilled` ≥2 | Offer fill End of Day |
| `blocked_high` ≥5 | Offer triage blocked issues |
| `review_low` <70% | Nudge End of Day (review rate low) |
| `weekly_pending` + Fri-Sun | Offer generate weekly review |

**Rules:**
- 1 nudge per session. If rejected, don't repeat.
- User says "nanti" or "skip" → store in OpenViking, no repeat for 24h.

### End of Day Wrap

When user ends session ("selesai", "eod", "done"), offer to fill End of Day.

## Requirements

- Bash 4+, Python 3.8+
- [gh CLI](https://cli.github.com/) (optional, for blocked/next tracking)
- [OpenCode](https://opencode.ai/) with OpenViking (optional, for proactive greeting)

## Installation

```bash
git clone https://github.com/TudeOrangBiasa/obsidian-vault-assistant.git
cd obsidian-vault-assistant
bash install.sh
```

See README.md for full installation and usage.
