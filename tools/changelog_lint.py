#!/usr/bin/env python3
"""Chat is for talking (owner direction 1): patch notes never tell players to type a command.

Checks CHANGELOG.md and every changelog.d/*.md fragment for slash commands such as `/gather`
or "type /bag in chat". Everything players can do lives on keys and windows now, and the
public server answers any "/" line with "Chat is for talking. Press F1 for controls.", so a
patch note that sends players to chat sends them nowhere.

A line that mentions a command to say it is gone ("you never have to type /help again") is
fine. Lines already in CHANGELOG.md when the check was added are listed in
tools/changelog_lint_allow.json; that list only shrinks (CHANGELOG.md is the integrator's, so
the integrator rewords or folds them away, then drops them from the list).

Usage: python3 tools/changelog_lint.py   (exit 1 on a new offending line)
"""
import json
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
ALLOW = REPO / "tools" / "changelog_lint_allow.json"

# "/word" not inside a path or URL: nothing word-like, "/", "." or ":" right before the slash.
COMMAND = re.compile(r"(?<![\w/.:<>~-])/([a-z][a-z0-9_]*)\b")
# Saying a command is gone is allowed: "never have to type /help", "no longer need /bag".
NEGATED = re.compile(r"\b(never|no longer|no more|don't|do not|instead of|without)\b[^.!?/]{0,30}$", re.I)


def offending(line: str) -> list:
    """The slash commands this line tells players to use (empty when none)."""
    found = []
    for m in COMMAND.finditer(line):
        if NEGATED.search(line[:m.start()]):
            continue
        found.append("/" + m.group(1))
    return found


def check_text(label: str, text: str, allowed: set) -> tuple:
    """Returns (problems, still_allowed): new offending lines, and allow-listed lines still present."""
    problems, still = [], set()
    for n, line in enumerate(text.splitlines(), 1):
        cmds = offending(line)
        if not cmds:
            continue
        key = line.strip()
        if key in allowed:
            still.add(key)
            continue
        problems.append(f"{label}:{n}: tells players to type {', '.join(cmds)} (chat is for talking): {key[:90]}")
    return problems, still


def main() -> int:
    allowed = set(json.loads(ALLOW.read_text())["lines"]) if ALLOW.exists() else set()
    files = [REPO / "CHANGELOG.md", *sorted((REPO / "changelog.d").glob("*.md"))]
    problems, still = [], set()
    for f in files:
        if f.name == "README.md" and f.parent.name == "changelog.d":
            continue
        p, s = check_text(str(f.relative_to(REPO)), f.read_text(), allowed)
        problems += p
        still |= s
    for gone in sorted(allowed - still):
        print(f"[changelog-lint] note: allow-listed line is gone, drop it from {ALLOW.name}: {gone[:80]}")
    if still:
        print(f"[changelog-lint] {len(still)} old CHANGELOG.md line(s) still send players to chat (allow-listed, integrator to reword)")
    for p in problems:
        print("[changelog-lint] FAIL " + p)
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
