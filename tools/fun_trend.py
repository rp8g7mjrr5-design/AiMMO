#!/usr/bin/env python3
"""Fun-metric trend across recent CI runs on main (owner direction: fun comes first).

The director's morning digest asks "is the game more fun than yesterday?". The numbers live
in the 180 s bot test of each CI run, but CI artifact zips sit on a blob host the director's
session can't reach. Job logs can be read through the API, so this reads the "Test" job log of
the last N `main` runs and prints one line per run:

  time (UTC)        sha     ci       1st reward  dead max  wait max  items/min  levelled  1st level-up
  2026-11-23 12:41  2a3d9bb success  7.9 / 9.2   34 / 64   0.24      9.6        8/8       36.7 / 43.8

"a / b" is median / worst bot. "1st level-up" is seconds of gathering before a fresh bot's
first level-up (Milestone 1: level 2 inside about a minute).

Where the numbers come from, best first:
  1. `[bot-test] fun summary: {json}` (run_bot_test.py prints it since ws/qa/fun-trend),
  2. older runs: the per-bot `qa_fun_metrics: key=value ...` lines, rolled up with the same
     fun_report.summarise CI uses.
Only the bot-test step run with --fun-check counts (the 45 s ENet run prints metrics too).

After the table comes one "vs yesterday" line: the median of each metric over the newest
day's runs against the day before (days in America/Chicago, like the budget week), so the
digest can say "first level-up got 4 s faster" without arithmetic:

  vs yesterday: 2026-11-24 (6 runs) vs 2026-11-23 (9 runs): 1st reward 7.7 s (-0.3, better), ...

Usage:  tools/fun_trend.sh [--runs 10] [--since 2026-11-23] [--branch main] [--json]
        --since takes every run created on or after that date (up to --runs, default 100 then).
Needs:  gh (authenticated). Tested by tests/ops/test_fun_trend.py.
"""
import argparse
import json
import re
import subprocess
import statistics
import sys
from datetime import datetime
from pathlib import Path
from zoneinfo import ZoneInfo

REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT / "tests" / "bot_test"))
import fun_report  # noqa: E402

REPO = "rp8g7mjrr5-design/AiMMO"
TIMESTAMP = re.compile(r"^\d{4}-\d\d-\d\dT[\d:.]+Z ?")
STEP = "##[group]Run "
SUMMARY_TAG = "[bot-test] fun summary: "
PER_BOT = re.compile(r"\[bot-test\]\s+qa_fun_metrics:\s+(.*)$")
PAIR = re.compile(r"(\w+)=(\S+)")


def strip_ts(line: str) -> str:
    return TIMESTAMP.sub("", line.rstrip("\r\n"), count=1)


def bot_test_section(log: str) -> list:
    """Lines of the bot-test step that ran with --fun-check (else the first bot-test step)."""
    sections, cur = [], None
    for raw in log.splitlines():
        line = strip_ts(raw)
        if line.startswith(STEP):
            cur = None
            if "run_bot_test.py" in line:
                cur = [line]
                sections.append(cur)
            continue
        if cur is not None:
            cur.append(line)
    for s in sections:
        if "--fun-check" in s[0]:
            return s
    return sections[0] if sections else []


def _num(v: str):
    try:
        return float(v)
    except ValueError:
        return v


def summary_from_log(log: str):
    """The fun summary dict of a CI job log, or None if the log has no fun metrics."""
    lines = bot_test_section(log)
    for line in lines:
        i = line.find(SUMMARY_TAG)
        if i >= 0:
            try:
                return json.loads(line[i + len(SUMMARY_TAG):])
            except json.JSONDecodeError:
                break
    rows = {}
    for line in lines:
        m = PER_BOT.search(line)
        if m:
            rows[f"bot{len(rows)}"] = {k: _num(v) for k, v in PAIR.findall(m.group(1))}
    return fun_report.summarise(rows) if rows else None


def _f(v, digits=1):
    if v is None:
        return "-"
    if not isinstance(v, (int, float)):
        return str(v)
    text = f"{v:.{digits}f}"
    # Trim trailing zeros of the decimals only: 40 must stay "40", not "4".
    return text.rstrip("0").rstrip(".") if "." in text else text


def _pair(s, key, digits=1):
    return f"{_f(s.get(key + '_median'), digits)} / {_f(s.get(key + '_worst'), digits)}"


HEADER = "%-16s  %-7s  %-9s  %-12s  %-11s  %-8s  %-9s  %-8s  %s" % (
    "time (UTC)", "sha", "ci", "1st reward", "dead max", "wait max", "items/min", "levelled", "1st level-up (gathering s)")


def format_row(run: dict, s) -> str:
    when = run.get("created_at", "")[:16].replace("T", " ")
    head = "%-16s  %-7s  %-9s" % (when, run.get("head_sha", "")[:7], run.get("conclusion") or run.get("status", ""))
    if not s:
        return head + "  no fun metrics in this run"
    first = "never" if s.get("bots_without_reward") else _f(s.get("first_reward_s_worst"))
    return head + "  %-12s  %-11s  %-8s  %-9s  %-8s  %s" % (
        f"{_f(s.get('first_reward_s_median'))} / {first}",
        _pair(s, "longest_dead_s", 0),
        _f(s.get("longest_wait_s_worst"), 2),
        _f(s.get("rewards_per_min_median")),
        f"{s.get('bots_levelled', 0)}/{s.get('bots', 0)}",
        _pair(s, "first_level_up_gather_s"),
    )


DAY_TZ = ZoneInfo("America/Chicago")

# (summary key, label, unit, digits, True if higher is better) for the "vs yesterday" line.
DELTAS = [
    ("first_reward_s_median", "1st reward", " s", 1, False),
    ("first_level_up_gather_s_median", "1st level-up", " s of gathering", 1, False),
    ("rewards_per_min_median", "items/min", "", 1, True),
    ("longest_dead_s_median", "dead max", " s", 0, False),
    ("bots_levelled", "levelled", " bots", 1, True),
]


def day_of(created_at: str) -> str:
    """The America/Chicago date of a run's created_at (GitHub's UTC 'Z' timestamp)."""
    t = datetime.fromisoformat(created_at.replace("Z", "+00:00"))
    return t.astimezone(DAY_TZ).strftime("%Y-%m-%d")


def day_medians(runs: list) -> dict:
    """runs: [(created_at, summary or None)] -> {day: {"runs": n, key: median}} over runs with metrics."""
    by_day = {}
    for created_at, s in runs:
        if s and created_at:
            by_day.setdefault(day_of(created_at), []).append(s)
    out = {}
    for day, sums in by_day.items():
        row = {"runs": len(sums)}
        for key, *_ in DELTAS:
            vals = [x[key] for x in sums if isinstance(x.get(key), (int, float))]
            row[key] = statistics.median(vals) if vals else None
        out[day] = row
    return out


def vs_yesterday(runs: list):
    """One line comparing the newest day's medians with the day before, or None with < 2 days."""
    days = day_medians(runs)
    if len(days) < 2:
        return None
    today, before = sorted(days)[-1], sorted(days)[-2]
    t, b = days[today], days[before]
    parts = []
    for key, label, unit, digits, higher_better in DELTAS:
        if t[key] is None or b[key] is None:
            continue
        d = t[key] - b[key]
        if round(d, digits) == 0:
            change = "same"
        else:
            word = "better" if (d > 0) == higher_better else "worse"
            change = f"{'+' if d > 0 else ''}{_f(d, digits)}, {word}"
        parts.append(f"{label} {_f(t[key], digits)}{unit} ({change})")

    def n(day):
        return f"{day} ({days[day]['runs']} run{'' if days[day]['runs'] == 1 else 's'})"
    return f"vs yesterday: {n(today)} vs {n(before)}: " + ", ".join(parts)


def gh_api(path: str, raw=False) -> str:
    out = subprocess.run(["gh", "api", path], capture_output=True, text=True)
    if out.returncode != 0:
        raise RuntimeError(f"gh api {path}: {out.stderr.strip()}")
    return out.stdout if raw else json.loads(out.stdout)


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--runs", type=int, default=None, help="how many recent runs (default 10, or 100 with --since)")
    ap.add_argument("--since", help="only runs created on or after this date (YYYY-MM-DD, UTC)")
    ap.add_argument("--branch", default="main")
    ap.add_argument("--repo", default=REPO)
    ap.add_argument("--json", action="store_true", help="print one JSON object per run instead of the table")
    a = ap.parse_args(argv)

    if a.since:
        datetime.strptime(a.since, "%Y-%m-%d")  # fail early on a bad date
    limit = a.runs or (100 if a.since else 10)
    query = f"branch={a.branch}&event=push&status=completed&per_page={min(limit, 100)}"
    if a.since:
        query += f"&created=%3E%3D{a.since}"
    runs = gh_api(f"repos/{a.repo}/actions/runs?{query}")
    runs = runs.get("workflow_runs", [])[:limit]
    seen = []
    if not a.json:
        print(HEADER)
    for run in runs:
        summary = None
        try:
            jobs = gh_api(f"repos/{a.repo}/actions/runs/{run['id']}/jobs").get("jobs", [])
            test = next((j for j in jobs if j.get("name", "").startswith("Test")), None)
            if test and test.get("conclusion") not in (None, "skipped"):
                summary = summary_from_log(gh_api(f"repos/{a.repo}/actions/jobs/{test['id']}/logs", raw=True))
        except RuntimeError as e:
            print(f"[fun-trend] {run.get('head_sha', '')[:7]}: {e}", file=sys.stderr)
        seen.append((run.get("created_at", ""), summary))
        if a.json:
            print(json.dumps({"created_at": run.get("created_at"), "sha": run.get("head_sha"),
                              "conclusion": run.get("conclusion"), "summary": summary}))
        else:
            print(format_row(run, summary))
    line = vs_yesterday(seen)
    if line and not a.json:
        print(line)
    return 0


if __name__ == "__main__":
    sys.exit(main())
