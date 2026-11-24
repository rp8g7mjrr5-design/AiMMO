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
        for i in range(int(base["limits"].get("bots_levelled_min", 1))):
            r = row(first=b["first_reward_s_median"], wait=b["longest_wait_s_median"],
                    rpm=b["rewards_per_min_median"], dead=b["longest_dead_s_median"])
            r.update({"first_level_up_s": 100.0, "first_level_up_gather_s": b["first_level_up_gather_s_median"],
                      "gather_s": 45.0, "level_ups": 1, "levels_per_10_min": 3.4,
                      "gather_s_felling": 45.0, "level_gather_s_felling": b["skill_level_gather_s_median"]})
            rows["bot_%d" % i] = r
        self.assertEqual(fun_report.check(fun_report.summarise(rows), base), [])

    def test_dead_time_and_level_up_regressions(self):
        base = json.loads(json.dumps(BASE))
        base["limits"]["longest_dead_s_worst"] = 75
        base["baseline"].update({"longest_dead_s_median": 35.0, "first_level_up_gather_s_median": 35.0})
        base["slack"].update({"longest_dead_s": 10.0, "first_level_up_gather_s": 8.0})

        def lv(gathered, dead=35.0):
            r = row(dead=dead)
            r.update({"first_level_up_s": gathered + 60, "first_level_up_gather_s": gathered, "gather_s": gathered + 5})
            return r
        # Inside 20% + slack (35 -> 44 dead, 35 -> 42 gathering): noise, passes.
        self.assertEqual(fun_report.check(fun_report.summarise({"a": lv(42, dead=44)}), base), [])
        probs = fun_report.check(fun_report.summarise({"a": lv(45, dead=46)}), base)
        self.assertTrue(any("longest_dead_s_median got" in p for p in probs), probs)
        self.assertTrue(any("first_level_up_gather_s_median got" in p for p in probs), probs)
        # One bot idle for 80 s breaks the worst-case limit even with a good median.
        probs = fun_report.check(fun_report.summarise({"a": lv(30), "b": lv(30), "c": lv(30, dead=80)}), base)
        self.assertEqual(probs, ["longest dead time 80 s, limit 75 s"])
        # No bot levelled: the level-up median has no value, which fails against a baseline.
        probs = fun_report.check(fun_report.summarise({"a": row()}), base)
        self.assertTrue(any("first_level_up_gather_s_median: no value" in p for p in probs), probs)

    def test_level_up_limits(self):
        def lv(first_gather, gather_s=60.0):
            r = row()
            r.update({"first_level_up_s": -1 if first_gather < 0 else first_gather + 20,
                      "first_level_up_gather_s": first_gather, "gather_s": gather_s,
                      "level_ups": 0 if first_gather < 0 else 1, "levels_per_10_min": 2.0})
            return r
        base = json.loads(json.dumps(BASE))
        base["limits"].update({"first_level_up_gather_s_worst": 90, "bots_levelled_min": 2})
        s = fun_report.summarise({"a": lv(40), "b": lv(70), "c": lv(-1, gather_s=30)})
        self.assertEqual(s["bots_levelled"], 2)
        self.assertEqual(s["first_level_up_gather_s_worst"], 70)
        self.assertEqual(s["first_level_up_gather_s_median"], 55)
        self.assertEqual(fun_report.check(s, base), [], "a bot that only gathered 30 s may not have levelled yet")
        slow = fun_report.check(fun_report.summarise({"a": lv(40), "b": lv(95)}), base)
        self.assertEqual(len(slow), 1)
        self.assertIn("95 s of gathering", slow[0])
        stuck = fun_report.check(fun_report.summarise({"a": lv(40), "b": lv(50), "c": lv(-1, gather_s=120)}), base)
        self.assertEqual(len(stuck), 1)
        self.assertIn("never levelled up", stuck[0])
        few = fun_report.check(fun_report.summarise({"a": lv(40), "b": lv(-1, gather_s=10)}), base)
        self.assertEqual(len(few), 1)
        self.assertIn("only 1 bot", few[0])
        # Old rows without the skills fields still summarise (no limit is broken by absence).
        s = fun_report.summarise({"a": row()})
        self.assertEqual(s["bots_levelled"], 0)
        self.assertIsNone(s["first_level_up_gather_s_worst"])

    def test_skill_never_levelled_fails_the_per_skill_limit(self):
        rows = {
            "a": dict(row(), gather_s_felling=30.0, level_gather_s_felling=28.0, gather_s_quarrying=70.0, level_gather_s_quarrying=-1),
            "b": dict(row(), gather_s_felling=40.0, level_gather_s_felling=32.0),
        }
        s = fun_report.summarise(rows)
        self.assertEqual(s["skills_levelled"], 2)
        self.assertEqual(s["skill_level_gather_s_median"], 30.0)
        self.assertEqual(s["skill_level_gather_s_worst"], 32.0)
        self.assertEqual(s["skill_unlevelled_gather_s_max"], 70.0)
        self.assertEqual(s["skill_unlevelled_at"], "a quarrying")
        base = {"limits": {"skill_unlevelled_gather_s_worst": 60}}
        problems = fun_report.check(s, base)
        self.assertEqual(len(problems), 1, problems)
        self.assertIn("a quarrying", problems[0])
        base["limits"]["skill_unlevelled_gather_s_worst"] = 75
        self.assertEqual(fun_report.check(s, base), [])

    def test_split_skills_under_the_limit_pass(self):
        # The d9927b3 case: 43.8 s gathered, split over two skills, neither levelled.
        rows = {"a": dict(row(), first_level_up_s=-1, first_level_up_gather_s=-1, gather_s=43.8,
                          gather_s_felling=24.0, level_gather_s_felling=-1, gather_s_quarrying=19.8, level_gather_s_quarrying=-1)}
        s = fun_report.summarise(rows)
        self.assertEqual(s["skill_unlevelled_gather_s_max"], 24.0)
        self.assertEqual(fun_report.check(s, {"limits": {"skill_unlevelled_gather_s_worst": 60}}), [])

    def test_skill_level_regression_against_baseline(self):
        rows = {"a": dict(row(), gather_s_felling=60.0, level_gather_s_felling=55.0)}
        s = fun_report.summarise(rows)
        base = {"baseline": {"skill_level_gather_s_median": 30.0}, "slack": {"skill_level_gather_s": 8.0}}
        self.assertTrue(any("skill_level_gather_s_median" in p for p in fun_report.check(s, base)))
        rows["a"]["level_gather_s_felling"] = 34.0
        self.assertEqual(fun_report.check(fun_report.summarise(rows), base), [])

    def test_old_rows_without_skill_keys_still_summarise(self):
        s = fun_report.summarise({"a": row()})
        self.assertEqual(s["skills_levelled"], 0)
        self.assertIsNone(s["skill_level_gather_s_median"])
        self.assertEqual(s["skill_unlevelled_gather_s_max"], 0.0)

    def test_table_prints_every_bot(self):
        rows = {"bot_1": row(), "bot_2": row(first=-1)}
        t = fun_report.table(rows, fun_report.summarise(rows))
        self.assertIn("bot_1", t)
        self.assertIn("never", t)
        self.assertIn("levelled up", t)


if __name__ == "__main__":
    unittest.main()
