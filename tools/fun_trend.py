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

Usage:  tools/fun_trend.sh [--runs 10] [--branch main] [--json]
Needs:  gh (authenticated). Tested by tests/ops/test_fun_trend.py.
"""
import argparse
import json
import re
import subprocess
import sys
from pathlib import Path

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
    return f"{v:.{digits}f}".rstrip("0").rstrip(".") if isinstance(v, (int, float)) else str(v)


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


def gh_api(path: str, raw=False) -> str:
    out = subprocess.run(["gh", "api", path], capture_output=True, text=True)
    if out.returncode != 0:
        raise RuntimeError(f"gh api {path}: {out.stderr.strip()}")
    return out.stdout if raw else json.loads(out.stdout)


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--runs", type=int, default=10, help="how many recent runs (default 10)")
    ap.add_argument("--branch", default="main")
    ap.add_argument("--repo", default=REPO)
    ap.add_argument("--json", action="store_true", help="print one JSON object per run instead of the table")
    a = ap.parse_args(argv)

    runs = gh_api(f"repos/{a.repo}/actions/runs?branch={a.branch}&event=push&status=completed&per_page={a.runs}")
    runs = runs.get("workflow_runs", [])[: a.runs]
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
        if a.json:
            print(json.dumps({"created_at": run.get("created_at"), "sha": run.get("head_sha"),
                              "conclusion": run.get("conclusion"), "summary": summary}))
        else:
            print(format_row(run, summary))
    return 0


if __name__ == "__main__":
    sys.exit(main())
