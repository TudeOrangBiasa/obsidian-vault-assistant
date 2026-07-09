#!/usr/bin/env python3
"""
weekly_fill.py — Auto-fill weekly review note with KPI, chart, GitHub data.

Data sources (all local):
  - daily/YYYY-MM-DD.md        → commits, issues, sessions, mood, energy
  - _logs/kpi/YYYY-MM-DD.md    → health_score, review_pct, projects_touched
  - _logs/trends/Www.md        → chart data
  - gh CLI (optional, for 🧱+🎯 labels)

Output: weekly/W{WEEK}.md — full weekly review note.

Usage:
    ./weekly_fill.py                          # current week
    ./weekly_fill.py --week 28 --year 2026    # specific week
    ./weekly_fill.py --force                  # overwrite if exists
    ./weekly_fill.py --vault /path/to/vault   # override vault path
"""

import argparse
import json
import os
import re
import subprocess
import sys
from collections import OrderedDict
from datetime import date, datetime, timedelta
from pathlib import Path


# === CONFIG: resolved from env or args ===
def resolve_vault_dir() -> Path:
    """Resolve vault path: arg > env > default."""
    if hasattr(resolve_vault_dir, '_cached'):
        return resolve_vault_dir._cached
    env_vault = os.environ.get('VAULT_DIR', '')
    if env_vault:
        resolve_vault_dir._cached = Path(env_vault)
    else:
        resolve_vault_dir._cached = Path.home() / "Obsidian" / "MyVault"
    return resolve_vault_dir._cached


def resolve_dirs(vault: Path):
    """Return (daily_dir, kpi_dir, trend_dir, review_dir, repo_dir)."""
    log_dir = Path(os.environ.get('LOG_DIR', str(vault / '_logs')))
    return (
        vault / "daily",
        log_dir / "kpi",
        log_dir / "trends",
        vault / "weekly",
        Path(os.environ.get('REPO_DIR', '.')),
    )


KPI_RE = re.compile(r'\[(\w+)::\s*(.+)\]')


def iso_week_range(week: int, year: int) -> tuple:
    """Return (monday, sunday) date for ISO week."""
    jan4 = date(year, 1, 4)
    start = jan4 - timedelta(days=jan4.isocalendar()[2] - 1)
    monday = start + timedelta(weeks=week - 1)
    sunday = monday + timedelta(days=6)
    return (monday, sunday)


def parse_kpi_file(path: Path) -> dict:
    """Extract Dataview markers from a KPI file."""
    if not path.exists():
        return {}
    result = {}
    try:
        for line in path.read_text().splitlines():
            m = KPI_RE.search(line)
            if m:
                key, val = m.group(1), m.group(2)
                try:
                    result[key] = int(val)
                except ValueError:
                    try:
                        result[key] = float(val)
                    except ValueError:
                        result[key] = val.strip()
    except Exception:
        pass
    return result


def parse_daily_note(path: Path) -> dict:
    """Extract structured data from a daily note: commits, issues, sessions, mood, energy."""
    result = {"commits": 0, "issues_done": 0, "sessions": 0, "mood": None, "energy": None}
    if not path.exists():
        return result
    try:
        content = path.read_text()
        for line in content.splitlines():
            m = KPI_RE.search(line)
            if m:
                key, val = m.group(1), m.group(2).strip()
                if key == "commits":
                    try:
                        result["commits"] = int(val)
                    except ValueError:
                        pass
                elif key == "issues_done":
                    try:
                        result["issues_done"] = int(val)
                    except ValueError:
                        pass
            # Mood/energy from frontmatter
            m_mood = re.search(r'^mood:\s*([\d.]+)', line, re.IGNORECASE)
            m_energy = re.search(r'^energy:\s*([\d.]+)', line, re.IGNORECASE)
            if m_mood:
                try:
                    result["mood"] = float(m_mood.group(1))
                except ValueError:
                    pass
            if m_energy:
                try:
                    result["energy"] = float(m_energy.group(1))
                except ValueError:
                    pass
    except Exception:
        pass
    return result


def parse_end_of_day(path: Path) -> dict:
    """Extract End of Day sections from a daily note.

    Returns {done: [str], fail: [str], question: [str]}.
    """
    result = {"done": [], "fail": [], "question": []}
    if not path.exists():
        return result

    content = path.read_text()
    for key, callout in [("done", "done"), ("fail", "fail"),
                          ("question", "question")]:
        pattern = rf'> \[!{callout}\]-?[^\n]*\n(.*?)(?=\n> \[!|\n## |\Z)'
        m = re.search(pattern, content, re.DOTALL)
        if m:
            block = m.group(1)
            for line in block.split("\n"):
                line = line.strip().lstrip("> ")
                if line.startswith("- ") and len(line) > 2:
                    result[key].append(line[2:])
    return result


def format_mood_energy_line(week_start: date, week_end: date) -> str:
    """Aggregate mood/energy from daily notes."""
    total_mood = 0
    total_energy = 0
    mood_days = 0
    energy_days = 0

    current = week_start
    while current <= week_end:
        daily, _, _, _, _ = resolve_dirs(resolve_vault_dir())
        path = daily / f"{current.isoformat()}.md"
        data = parse_daily_note(path)
        if data["mood"] is not None:
            total_mood += data["mood"]
            mood_days += 1
        if data["energy"] is not None:
            total_energy += data["energy"]
            energy_days += 1
        current += timedelta(days=1)

    mood_str = f"{total_mood / mood_days:.1f}/10 ({mood_days} hari)" if mood_days else "—"
    energy_str = f"{total_energy / energy_days:.0f}/10 ({energy_days} hari)" if energy_days else "—"
    return f"Avg Mood: {mood_str} — Avg Energy: {energy_str}"


def aggregate_eod_data(week_start: date, week_end: date) -> dict:
    """Aggregate End of Day data from all daily notes in a week."""
    total = {"done": [], "fail": [], "question": []}
    current = week_start
    while current <= week_end:
        daily, _, _, _, _ = resolve_dirs(resolve_vault_dir())
        path = daily / f"{current.isoformat()}.md"
        eod = parse_end_of_day(path)
        total["done"].extend(eod["done"])
        total["fail"].extend(eod["fail"])
        total["question"].extend(eod["question"])
        current += timedelta(days=1)
    return total


def generate_retro_suggestions(delta: dict, aggregates: dict,
                                blocked_count: int) -> str:
    """Generate retro suggestions based on KPI delta + aggregates."""
    suggestions = {"lanjut": [], "stop": [], "coba": []}

    if delta.get("health_score", 0) >= 0:
        suggestions["lanjut"].append("KPI health 🔥")
    if aggregates["total_commits"] > 20:
        suggestions["lanjut"].append("Commit konsisten 💪")
    if delta.get("review_pct", 0) < -10:
        suggestions["stop"].append("Review rate turun — evaluasi workflow")
    if aggregates.get("issues_done", 0) > 5:
        suggestions["lanjut"].append("Issue tracking aktif 📋")
    if blocked_count > 5:
        suggestions["stop"].append("Terlalu banyak blocker — triage priority")
    if aggregates.get("review_pct", 100) < 50:
        suggestions["coba"].append("Isi End of Day tiap hari ✍️")
    if aggregates.get("sessions", 0) < 3:
        suggestions["coba"].append("Tambah session coding 🖥️")

    # Build table row
    lanjut = "<br>".join(suggestions["lanjut"]) if suggestions["lanjut"] else "—"
    stop = "<br>".join(suggestions["stop"]) if suggestions["stop"] else "—"
    coba = "<br>".join(suggestions["coba"]) if suggestions["coba"] else "—"
    return f"| {lanjut} | {stop} | {coba} |"


def run_gh_query(label: str) -> list:
    """Run gh CLI to get issues with a given label. Returns list of issue dicts."""
    repo = os.environ.get('GH_REPO', '')
    if not repo:
        return []
    try:
        result = subprocess.run(
            ["gh", "search", "issues", "--repo", repo, "--label", label,
             "--state", "open", "--json", "number,title,url", "--limit", "10"],
            capture_output=True, text=True, timeout=15
        )
        if result.returncode == 0:
            return json.loads(result.stdout)
    except (subprocess.TimeoutExpired, json.JSONDecodeError, FileNotFoundError):
        pass
    return []


def format_issue_list(label: str, emoji: str, issues: list,
                       blocked_count: int = 0) -> str:
    """Format a list of issues for the weekly review."""
    if not issues:
        if label == "blocked" and blocked_count > 0:
            return f"> {blocked_count} issues terblock. Cek via `gh`."
        return "_Tidak ada._"
    lines = []
    for issue in issues[:10]:
        title = issue.get("title", "?")
        url = issue.get("url", "")
        lines.append(f"- [{title}]({url})")
    return "\n".join(lines)


def format_kpi_chart(week: int, trend_dashboard: Path) -> str:
    """Generate Obsidian Charts codeblock from trend data."""
    w3, w2, w1 = week - 3, week - 2, week - 1
    chart = (
        "````chart\n"
        f"type: line\n"
        f"title: KPI Trend W{week}\n"
        f"labels: [Week {w3}, Week {w2}, Week {w1}, Week {week}]\n"
        "series:\n"
        "  - title: Health Score\n"
        "    data: [0, 0, 0, 0]\n"
        "  - title: Review %\n"
        "    data: [0, 0, 0, 0]\n"
        "  - title: Projects\n"
        "    data: [0, 0, 0, 0]\n"
        "tension: 0.3\n"
        "width: 80%\n"
        "labelColors: true\n"
        "fill: true\n"
        "beginAtZero: true\n"
        "````"
    )
    try:
        if trend_dashboard.exists():
            content = trend_dashboard.read_text()
            # Extract last 4 data points for each metric
            for metric, key in [("health_score", "Health Score"),
                                 ("review_pct", "Review %"),
                                 ("projects_touched", "Projects")]:
                pattern = rf'\|\s*\d+\s*\|([\d. ]+\|)'
                matches = re.findall(pattern, content)
                # Parse trend table (last 4 rows)
                data_points = []
                for m in matches[-4:]:
                    vals = [v.strip() for v in m.split('|') if v.strip()]
                    for v in vals:
                        try:
                            data_points.append(int(float(v)))
                            break
                        except ValueError:
                            continue
                if data_points:
                    chart = chart.replace("[0, 0, 0, 0]",
                                          str(data_points[-4:]))
    except Exception:
        pass
    return chart


def generate_review(week: int, year: int, force: bool = False,
                     vault_dir: str = "") -> tuple:
    """Generate the weekly review content and return (content, stats).

    Raises FileExistsError if file exists and force=False.
    """
    if vault_dir:
        os.environ['VAULT_DIR'] = vault_dir
        resolve_vault_dir._cached = Path(vault_dir)

    vault = resolve_vault_dir()
    daily_dir, kpi_dir, trend_dir, review_dir, _ = resolve_dirs(vault)
    review_dir.mkdir(parents=True, exist_ok=True)

    filename = f"W{week:02d}.md"
    filepath = review_dir / filename
    if filepath.exists() and not force:
        raise FileExistsError(f"Weekly review already exists: {filepath}")

    mon, sun = iso_week_range(week, year)
    week_start = mon.isoformat()
    week_end = sun.isoformat()

    # --- Aggregate daily notes ---
    aggregates = {"total_commits": 0, "issues_done": 0, "sessions": 0}
    current = mon
    while current <= sun:
        path = daily_dir / f"{current.isoformat()}.md"
        data = parse_daily_note(path)
        aggregates["total_commits"] += data["commits"]
        aggregates["issues_done"] += data["issues_done"]
        aggregates["sessions"] += data["sessions"]
        current += timedelta(days=1)

    # --- KPI aggregation ---
    kpi_totals = {"health_score": 0, "review_pct": 0, "projects_touched": 0}
    kpi_days = 0
    current = mon
    while current <= sun:
        path = kpi_dir / f"{current.isoformat()}.md"
        kpi = parse_kpi_file(path)
        if kpi:
            kpi_days += 1
            for key in kpi_totals:
                if key in kpi:
                    kpi_totals[key] += kpi[key]
        current += timedelta(days=1)
    if kpi_days > 0:
        for key in kpi_totals:
            kpi_totals[key] = round(kpi_totals[key] / kpi_days, 1)

    # --- Previous week KPI for delta ---
    prev_week = week - 1
    prev_year = year
    if prev_week < 1:
        prev_week = 52
        prev_year -= 1
    prev_mon, prev_sun = iso_week_range(prev_week, prev_year)
    prev_kpi = {"health_score": 0, "review_pct": 0, "projects_touched": 0}
    prev_days = 0
    current = prev_mon
    while current <= prev_sun:
        path = kpi_dir / f"{current.isoformat()}.md"
        kpi = parse_kpi_file(path)
        if kpi:
            prev_days += 1
            for key in prev_kpi:
                if key in kpi:
                    prev_kpi[key] += kpi[key]
        current += timedelta(days=1)
    if prev_days > 0:
        for key in prev_kpi:
            prev_kpi[key] = round(prev_kpi[key] / prev_days, 1)

    # --- Delta ---
    delta = {}
    for key in kpi_totals:
        delta[f"delta_{key}"] = round(kpi_totals[key] - prev_kpi.get(key, 0), 1)
    delta_table_lines = [
        "| Metrik | Prev | This Week | Delta |",
        "|--------|------|-----------|-------|",
    ]
    for label, key in [("Health Score", "health_score"),
                        ("Review %", "review_pct"),
                        ("Projects", "projects_touched")]:
        prev_val = prev_kpi.get(key, 0)
        curr_val = kpi_totals.get(key, 0)
        d_val = delta.get(f"delta_{key}", 0)
        delta_table_lines.append(
            f"| {label} | {prev_val} | {curr_val} | {d_val:+.1f} |"
        )
    delta_table = "\n".join(delta_table_lines)

    # --- GitHub issues (blocked/next) ---
    blocked_issues = run_gh_query("blocked")
    next_issues = run_gh_query("next")
    blocked_count = len(blocked_issues)

    # --- End of Day aggregation for catatan ---
    eod = aggregate_eod_data(mon, sun)

    catatan_section = ""
    if eod["done"] or eod["fail"] or eod["question"]:
        lines = ["> [!done]- Done"]
        for item in eod["done"][:10]:
            lines.append(f"> - {item}")
        if eod["fail"]:
            lines.append("")
            lines.append("> [!fail]- Fail")
            for item in eod["fail"][:5]:
                lines.append(f"> - {item}")
        if eod["question"]:
            lines.append("")
            lines.append("> [!question]- Question")
            for item in eod["question"][:5]:
                lines.append(f"> - {item}")
        catatan_section = "\n".join(lines)
    else:
        catatan_section = "> _Tidak ada End of Day catatan minggu ini._"

    # --- Mood/energy ---
    mood_energy = format_mood_energy_line(mon, sun)

    # --- Retro ---
    retro_row = generate_retro_suggestions(delta, aggregates, blocked_count)

    # --- Chart ---
    dashboard = trend_dir / "dashboard.md"
    chart = format_kpi_chart(week, dashboard)

    # --- Build content ---
    stat_table = f"""| Metrik | Value |
|--------|-------|
| Total Commits | {aggregates['total_commits']} |
| Issues Done | {aggregates['issues_done']} |
| Sessions | {aggregates['sessions']} |
| {mood_energy} |"""

    prev_table = ""
    if prev_days > 0 and prev_kpi.get("health_score", 0) > 0:
        prev_row = "| "
        for k in ["health_score", "review_pct", "projects_touched"]:
            prev_row += f"{prev_kpi.get(k, '—')} | "
        prev_table = f"| **Minggu Lalu** | {prev_row} |"

    mentok_items = format_issue_list("blocked", "⛔", blocked_issues, blocked_count)
    next_items = format_issue_list("next", "🎯", next_issues)

    content = f"""---
week: W{week:02d}
created: {date.today().isoformat()}
period: {week_start} — {week_end}
---

## 🚢 Yang Selesai

{stat_table}

## 📈 KPI

{chart}

## ⛔ Yang Mentok

> Issues label:blocked (via gh).

{mentok_items}

---

## 🎯 Minggu Depan

> Issues label:next (via gh).

{next_items}

---

## 📝 Catatan

> Dari End of Day notes.

{catatan_section}
## ♻️ Retro

{retro_row}

### 📊 KPI Delta

{delta_table}
"""

    stats = {
        "total_commits": aggregates["total_commits"],
        "issues_done": aggregates["issues_done"],
        "total_sessions": aggregates["sessions"],
        "blocked_count": blocked_count,
        "next_count": len(next_issues),
        "kpi": kpi_totals,
        "delta": delta,
    }
    return content, stats


def main():
    parser = argparse.ArgumentParser(
        description="Auto-fill weekly review note with KPI, chart, GitHub data"
    )
    parser.add_argument("--week", type=int, default=0,
                        help="ISO week number (default: current)")
    parser.add_argument("--year", type=int, default=0,
                        help="Year (default: current)")
    parser.add_argument("--force", action="store_true",
                        help="Overwrite if weekly note already exists")
    parser.add_argument("--vault", type=str, default="",
                        help="Override vault directory path")
    args = parser.parse_args()

    today = date.today()
    iso = today.isocalendar()
    week = args.week or iso[1]
    year = args.year or iso[0]

    if week < 1 or week > 53:
        print(f"[FAIL] Invalid week: {week}")
        sys.exit(1)

    vault_path = args.vault or os.environ.get('VAULT_DIR', '')
    if vault_path:
        os.environ['VAULT_DIR'] = vault_path
        resolve_vault_dir._cached = Path(vault_path)

    vault = resolve_vault_dir()
    _, _, _, review_dir, _ = resolve_dirs(vault)
    review_dir.mkdir(parents=True, exist_ok=True)

    try:
        content, stats = generate_review(week, year, force=args.force)
    except FileExistsError as e:
        print(f"[SKIP] {e}")
        sys.exit(0)

    filename = f"W{week:02d}.md"
    filepath = review_dir / filename
    filepath.write_text(content)

    mon, sun = iso_week_range(week, year)
    print(f"[OK] Generated: {filepath}")
    print(f"      Week: W{week:02d} ({mon.isoformat()} — {sun.isoformat()})")
    print(f"      Commits: {stats['total_commits']}, Issues: {stats['issues_done']}, Sessions: {stats['total_sessions']}")
    if stats['blocked_count']:
        print(f"      ⛔ Blocked: {stats['blocked_count']}")
    if stats['next_count']:
        print(f"      🎯 Next up: {stats['next_count']}")
    sys.exit(0)


if __name__ == "__main__":
    main()
