#!/usr/bin/env python3
"""
validate_daily.py — Schema validation for daily Obsidian notes.

Checks frontmatter, required sections, and Dataview markers.

Usage:
    ./validate_daily.py                           # validate yesterday
    ./validate_daily.py --date 2026-07-08         # validate specific date
    ./validate_daily.py --vault /path/to/vault    # override vault
"""

import argparse
import os
import re
import sys
from datetime import date, timedelta
from pathlib import Path


REQUIRED_MARKERS = ["commits", "issues_done", "sessions"]
REQUIRED_SECTIONS = ["## End of Day Review"]
OPTIONAL_MARKERS = ["mood", "energy"]

# Color output
GREEN = "\033[92m"
YELLOW = "\033[93m"
RED = "\033[91m"
RESET = "\033[0m"


def ok(msg: str):
    print(f"  {GREEN}✓{RESET} {msg}")


def warn(msg: str):
    print(f"  {YELLOW}⚠{RESET} {msg}")


def fail(msg: str):
    print(f"  {RED}✗{RESET} {msg}")


def validate_daily(path: Path) -> bool:
    """Validate a daily note. Returns True if valid, False otherwise."""
    if not path.exists():
        fail(f"File not found: {path}")
        return False

    print(f"\nValidating: {path.name}")
    content = path.read_text()
    valid = True

    # Check frontmatter
    fm_match = re.match(r'^---\n(.*?)\n---', content, re.DOTALL)
    if fm_match:
        ok("Frontmatter found")
        fm = fm_match.group(1)
        # Check optional mood/energy
        for m in OPTIONAL_MARKERS:
            if re.search(rf'^{m}\s*:', fm, re.MULTILINE):
                ok(f"Frontmatter: {m}")
    else:
        warn("No frontmatter")

    # Check required Dataview markers
    for marker in REQUIRED_MARKERS:
        pattern = rf'\[{marker}::\s*\d+\]'
        if re.search(pattern, content):
            ok(f"Marker [{marker}::]")
        else:
            warn(f"Marker [{marker}::] not found")

    # Check required sections
    for section in REQUIRED_SECTIONS:
        if section in content:
            ok(f"Section: {section}")
        else:
            warn(f"Section '{section}' not found")

    # Check End of Day content
    if "## End of Day Review" in content:
        eod_section = content.split("## End of Day Review", 1)[1]
        if re.search(r'> \[!(done|fail|question)\]', eod_section):
            ok("End of Day callouts found")
            # Check for actual content
            if re.search(r'>\s*-\s*\S', eod_section):
                ok("End of Day has content")
            else:
                warn("End of Day callouts exist but empty")
        else:
            warn("End of Day Review section found but no callouts")

    return valid


def main():
    parser = argparse.ArgumentParser(description="Validate daily note structure")
    parser.add_argument("--date", type=str, default="",
                        help="Date YYYY-MM-DD (default: yesterday)")
    parser.add_argument("--vault", type=str, default="",
                        help="Override vault directory")
    args = parser.parse_args()

    vault_path = args.vault or os.environ.get('VAULT_DIR', '')
    if vault_path:
        vault_dir = Path(vault_path)
    else:
        vault_dir = Path.home() / "Obsidian" / "MyVault"

    daily_dir = vault_dir / "daily"
    if not daily_dir.exists():
        print(f"[FATAL] Daily directory not found: {daily_dir}")
        sys.exit(1)

    target_date = args.date or (date.today() - timedelta(days=1)).isoformat()
    path = daily_dir / f"{target_date}.md"

    valid = validate_daily(path)
    sys.exit(0 if valid else 1)


if __name__ == "__main__":
    main()
