"""Fun metrics report for the bot test (owner direction 1: fun comes first).

Each bot's qa_fun_metrics behaviour (tests/bot_test/fun_metrics.gd) reports:
first_reward_s, longest_dead_s, longest_wait_s (dead time while acting), rewards_per_min,
loops_completed, and for Milestone 1 (skills): first_level_up_s, first_level_up_gather_s
(seconds of gathering before the first level-up), gather_s, level_ups, levels_per_10_min. This module rolls them up
across bots, prints a table, and checks them against tests/bot_test/fun_baseline.json:

- limits: hard ceilings/floors on the worst bot (e.g. every fresh player gets a first reward
  within 90 s). Generous today; tighten them as gameplay and client add feedback.
- first level-up: every bot that levelled up must have done it within
  `first_level_up_gather_s_worst` seconds of gathering, and a bot that gathered longer than
  that without ever levelling up fails too (the roadmap: level 2 inside about a minute).
  `bots_levelled_min` asks for at least that many bots to level up in the run.
- baseline: the medians from a good run. A metric that gets worse than its baseline by more
  than `regression` (20%) *and* by more than its `slack` fails. The slack keeps run-to-run
  noise on small numbers (bot names, and so their routes, change every run) from flaking CI.

Update the baseline when a change makes the game measurably more fun, so the gain is locked in.
Tested by tests/bot_test/test_fun_report.py.
"""
import json
import statistics
from pathlib import Path

BASELINE = Path(__file__).resolve().parent / "fun_baseline.json"

# metric -> (summary key compared, True if higher is better)
COMPARED = {
    "first_reward_s": ("first_reward_s_median", False),
    "longest_dead_s": ("longest_dead_s_median", False),
    "longest_wait_s": ("longest_wait_s_median", False),
    "rewards_per_min": ("rewards_per_min_median", True),
    "first_level_up_gather_s": ("first_level_up_gather_s_median", False),
}


def summarise(rows: dict) -> dict:
    """Roll up per-bot metric dicts ({bot: {...}}) into medians and worst cases."""
    firsts = [r["first_reward_s"] for r in rows.values() if r.get("first_reward_s", -1) >= 0]
    deads = [r["longest_dead_s"] for r in rows.values()]
    waits = [r.get("longest_wait_s", 0.0) for r in rows.values()]
    rpm = [r["rewards_per_min"] for r in rows.values()]
    no_reward = len(rows) - len(firsts)
    lv_gather = [r["first_level_up_gather_s"] for r in rows.values() if r.get("first_level_up_gather_s", -1) >= 0]
    lv_wall = [r["first_level_up_s"] for r in rows.values() if r.get("first_level_up_s", -1) >= 0]
    lpm = [r.get("levels_per_10_min", 0.0) for r in rows.values()]
    # Bots that gathered for longer than any levelled bot needed, and never levelled.
    never = {n: r.get("gather_s", 0.0) for n, r in rows.items() if r.get("first_level_up_s", -1) < 0}
    return {
        "bots": len(rows),
        "bots_without_reward": no_reward,
        "first_reward_s_median": round(statistics.median(firsts), 2) if firsts else None,
        # A bot that never got anything is the worst first reward of all.
        "first_reward_s_worst": None if no_reward or not firsts else round(max(firsts), 2),
        "longest_dead_s_median": round(statistics.median(deads), 2) if deads else None,
        "longest_dead_s_worst": round(max(deads), 2) if deads else None,
        "longest_wait_s_median": round(statistics.median(waits), 2) if waits else None,
        "longest_wait_s_worst": round(max(waits), 2) if waits else None,
        "rewards_per_min_median": round(statistics.median(rpm), 2) if rpm else None,
        "loops_completed": sum(int(r.get("loops_completed", 0)) for r in rows.values()),
        "bots_levelled": len(lv_gather),
        "first_level_up_s_median": round(statistics.median(lv_wall), 2) if lv_wall else None,
        "first_level_up_gather_s_median": round(statistics.median(lv_gather), 2) if lv_gather else None,
        "first_level_up_gather_s_worst": round(max(lv_gather), 2) if lv_gather else None,
        "unlevelled_gather_s_max": round(max(never.values()), 2) if never else 0.0,
        "levels_per_10_min_median": round(statistics.median(lpm), 2) if lpm else None,
    }


def load_baseline(path: Path) -> dict:
    return json.loads(path.read_text()) if path.exists() else {}


def check(summary: dict, baseline: dict) -> list:
    """Returns a list of human-readable problems (empty when the run is fine)."""
    out = []
    limits = baseline.get("limits", {})
    if summary["bots"] == 0:
        return ["no bot reported fun metrics"]
    lim = limits.get("first_reward_s_worst")
    if lim is not None:
        if summary["bots_without_reward"]:
            out.append(f"{summary['bots_without_reward']} bot(s) never got a reward (limit: first reward within {lim:g} s)")
        elif summary["first_reward_s_worst"] > lim:
            out.append(f"slowest first reward {summary['first_reward_s_worst']:g} s, limit {lim:g} s")
    lim = limits.get("longest_dead_s_worst")
    if lim is not None and summary["longest_dead_s_worst"] is not None and summary["longest_dead_s_worst"] > lim:
        out.append(f"longest dead time {summary['longest_dead_s_worst']:g} s, limit {lim:g} s")
    lim = limits.get("longest_wait_s_worst")
    if lim is not None and summary["longest_wait_s_worst"] is not None and summary["longest_wait_s_worst"] > lim:
        out.append(f"longest wait for feedback after acting {summary['longest_wait_s_worst']:g} s, limit {lim:g} s")
    lim = limits.get("first_level_up_gather_s_worst")
    if lim is not None:
        worst = summary.get("first_level_up_gather_s_worst")
        if worst is not None and worst > lim:
            out.append(f"slowest first level-up took {worst:g} s of gathering, limit {lim:g} s")
        stuck = summary.get("unlevelled_gather_s_max") or 0.0
        if stuck > lim:
            out.append(f"a bot gathered for {stuck:g} s and never levelled up, limit {lim:g} s")
    lim = limits.get("bots_levelled_min")
    if lim is not None and summary.get("bots_levelled", 0) < lim:
        out.append(f"only {summary.get('bots_levelled', 0)} bot(s) levelled up, needs at least {lim:g}")
    lim = limits.get("rewards_per_min_median")
    if lim is not None and (summary["rewards_per_min_median"] or 0.0) < lim:
        out.append(f"median rewards per minute {summary['rewards_per_min_median']}, needs at least {lim:g}")

    base = baseline.get("baseline", {})
    allowed = float(baseline.get("regression", 0.2))
    slack = baseline.get("slack", {})
    for metric, (key, higher_better) in COMPARED.items():
        was, now = base.get(key), summary.get(key)
        if was is None:
            continue
        if now is None:
            out.append(f"{key}: no value this run (baseline {was:g})")
            continue
        worse = (was - now) if higher_better else (now - was)
        if worse > abs(was) * allowed and worse > float(slack.get(metric, 0.0)):
            pct = 100.0 * worse / abs(was) if was else float("inf")
            out.append(f"{key} got {pct:.0f}% worse: {now:g} vs baseline {was:g} (allowed {allowed * 100:.0f}%)")
    return out


def table(rows: dict, summary: dict) -> str:
    def f(v):
        return "-" if v is None or v == -1 else f"{v:g}"
    lines = ["[bot-test] fun metrics (per fresh bot)",
             "[bot-test]   %-16s %12s %12s %12s %10s %6s" % ("bot", "1st reward s", "dead max s", "wait max s", "items/min", "loops")]
    for name in sorted(rows):
        r = rows[name]
        lines.append("[bot-test]   %-16s %12s %12s %12s %10s %6s" % (
            name, f(r.get("first_reward_s")), f(r.get("longest_dead_s")), f(r.get("longest_wait_s")), f(r.get("rewards_per_min")),
            f(r.get("loops_completed"))))
    lines.append("[bot-test]   %-16s %12s %12s %12s %10s %6s" % (
        "median", f(summary["first_reward_s_median"]), f(summary["longest_dead_s_median"]),
        f(summary["longest_wait_s_median"]), f(summary["rewards_per_min_median"]), ""))
    lines.append("[bot-test]   %-16s %12s %12s %12s %10s %6s" % (
        "worst", "never" if summary["bots_without_reward"] else f(summary["first_reward_s_worst"]),
        f(summary["longest_dead_s_worst"]), f(summary["longest_wait_s_worst"]), "", f(summary["loops_completed"])))
    lines.append("[bot-test]   %-16s %12s %12s %12s %10s" % ("", "1st level s", "gathered s", "gather s", "lv/10min"))
    for name in sorted(rows):
        r = rows[name]
        lines.append("[bot-test]   %-16s %12s %12s %12s %10s" % (
            name, f(r.get("first_level_up_s")), f(r.get("first_level_up_gather_s")), f(r.get("gather_s")),
            f(r.get("levels_per_10_min"))))
    lines.append("[bot-test]   %-16s %12s %12s %12s %10s" % (
        "median", f(summary.get("first_level_up_s_median")), f(summary.get("first_level_up_gather_s_median")), "",
        f(summary.get("levels_per_10_min_median"))))
    lines.append("[bot-test]   %-16s %12s %12s %12s %10s" % (
        "worst", "", f(summary.get("first_level_up_gather_s_worst")), "", ""))
    lines.append(f"[bot-test]   {summary.get('bots_levelled', 0)} of {summary['bots']} bots levelled up")
    return "\n".join(lines)
