"""Unit tests for fun_report.py (run: python3 -m unittest discover -s tests/bot_test -p 'test_*.py')."""
import json
import unittest
from pathlib import Path

import fun_report


def row(first=8.0, dead=40.0, wait=0.1, rpm=5.0, loops=0):
    return {"first_reward_s": first, "longest_dead_s": dead, "longest_wait_s": wait,
            "rewards_per_min": rpm, "loops_completed": loops}


BASE = {"limits": {"first_reward_s_worst": 90, "longest_wait_s_worst": 45},
        "regression": 0.2, "slack": {"first_reward_s": 3.0, "longest_wait_s": 2.0, "rewards_per_min": 1.0},
        "baseline": {"first_reward_s_median": 10.0, "longest_wait_s_median": 1.0, "rewards_per_min_median": 5.0}}


class FunReport(unittest.TestCase):
    def test_summary_medians_and_worst(self):
        s = fun_report.summarise({"a": row(first=4), "b": row(first=8, dead=60), "c": row(first=30, loops=2)})
        self.assertEqual(s["first_reward_s_median"], 8)
        self.assertEqual(s["first_reward_s_worst"], 30)
        self.assertEqual(s["longest_dead_s_worst"], 60)
        self.assertEqual(s["loops_completed"], 2)
        self.assertEqual(s["bots_without_reward"], 0)

    def test_healthy_run_passes(self):
        s = fun_report.summarise({"a": row(), "b": row(first=11), "c": row(rpm=4.5)})
        self.assertEqual(fun_report.check(s, BASE), [])

    def test_bot_without_reward_fails_the_limit(self):
        s = fun_report.summarise({"a": row(), "b": row(first=-1)})
        self.assertIsNone(s["first_reward_s_worst"])
        self.assertTrue(any("never got a reward" in p for p in fun_report.check(s, BASE)))

    def test_slow_first_reward_and_long_wait_fail_limits(self):
        s = fun_report.summarise({"a": row(first=95), "b": row(wait=50)})
        probs = fun_report.check(s, BASE)
        self.assertTrue(any("slowest first reward 95" in p for p in probs), probs)
        self.assertTrue(any("wait for feedback" in p for p in probs), probs)

    def test_regression_needs_twenty_percent_and_the_slack(self):
        # 10 -> 12.5 is 25% worse but inside the 3 s slack: noise, passes.
        s = fun_report.summarise({"a": row(first=12.5)})
        self.assertEqual(fun_report.check(s, BASE), [])
        # 10 -> 13.5 is 35% and 3.5 s worse: fails.
        s = fun_report.summarise({"a": row(first=13.5)})
        self.assertTrue(any("first_reward_s_median got 35% worse" in p for p in fun_report.check(s, BASE)))
        # Higher is better for rewards: 5 -> 3.9 is 22% and 1.1 worse.
        s = fun_report.summarise({"a": row(rpm=3.9)})
        self.assertTrue(any("rewards_per_min_median" in p for p in fun_report.check(s, BASE)))
        # Getting better never fails.
        s = fun_report.summarise({"a": row(first=2, wait=0, rpm=30)})
        self.assertEqual(fun_report.check(s, BASE), [])

    def test_shipped_baseline_is_valid_and_lenient_on_itself(self):
        base = fun_report.load_baseline(fun_report.BASELINE)
        for key in base["baseline"]:
            self.assertIn(key, [k for k, _ in fun_report.COMPARED.values()])
        b = base["baseline"]
        rows = {}
        for i in range(8):
            r = row(first=b["first_reward_s_median"], wait=b["longest_wait_s_median"],
                    rpm=b["rewards_per_min_median"], dead=b["longest_dead_s_median"])
            r["gather_s"] = 45.0
            rows["bot_%d" % i] = r
        self.assertEqual(fun_report.check(fun_report.summarise(rows), base), [])

    def test_no_level_metrics_any_more(self):
        # The leveling system is gone (2026-11-26): nothing gates or reports level-ups.
        base = fun_report.load_baseline(fun_report.BASELINE)
        for section in ("limits", "slack", "baseline"):
            for key in base.get(section, {}):
                self.assertNotIn("level", key, f"{section}.{key}")
        s = fun_report.summarise({"a": dict(row(), gather_s=30.0), "b": dict(row(), gather_s=50.0)})
        self.assertFalse([k for k in s if "level" in k], s)
        self.assertEqual(s["gather_s_median"], 40.0)

    def test_dead_time_regressions(self):
        base = json.loads(json.dumps(BASE))
        base["limits"]["longest_dead_s_worst"] = 75
        base["baseline"].update({"longest_dead_s_median": 35.0})
        base["slack"].update({"longest_dead_s": 10.0})
        # Inside 20% + slack (35 -> 44 dead): noise, passes.
        self.assertEqual(fun_report.check(fun_report.summarise({"a": row(dead=44)}), base), [])
        probs = fun_report.check(fun_report.summarise({"a": row(dead=46)}), base)
        self.assertTrue(any("longest_dead_s_median got" in p for p in probs), probs)
        # One bot idle for 80 s breaks the worst-case limit even with a good median.
        probs = fun_report.check(fun_report.summarise({"a": row(dead=30), "b": row(dead=30), "c": row(dead=80)}), base)
        self.assertEqual(probs, ["longest dead time 80 s, limit 75 s"])

    def test_combat_totals_and_old_rows(self):
        a = dict(row(), swings=5, swings_refused=2, swings_hit=3, kills=1)
        b = dict(row(), swings=1)
        s = fun_report.summarise({"a": a, "b": b, "c": row()})
        self.assertEqual((s["swings"], s["swings_refused"], s["swings_hit"], s["kills"]), (6, 2, 3, 1))
        self.assertEqual(s["bots_swung"], 2)
        self.assertEqual(fun_report.check(s, BASE), [], "combat is reported, not gated")
        self.assertIn("combat: 6 swings by 2 bot(s), 3 struck, 2 more presses refused, 1 kill(s)",
                      fun_report.table({"a": a, "b": b}, s))
        old = fun_report.summarise({"a": row()})
        self.assertEqual((old["swings"], old["kills"], old["bots_swung"]), (0, 0, 0))

    def test_table_prints_every_bot(self):
        rows = {"bot_1": row(), "bot_2": row(first=-1)}
        t = fun_report.table(rows, fun_report.summarise(rows))
        self.assertIn("bot_1", t)
        self.assertIn("never", t)
        self.assertIn("gathering: median", t)


if __name__ == "__main__":
    unittest.main()
