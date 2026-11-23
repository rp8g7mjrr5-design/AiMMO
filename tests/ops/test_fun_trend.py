"""Unit tests for tools/fun_trend.py (run: python3 -m unittest discover -s tests/ops -p 'test_*.py').

They feed it CI job logs shaped like GitHub's (timestamp prefix, `##[group]Run` step headers)
so a change to the bot test's output that would blind the director's trend fails here first.
"""
import json
import sys
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO / "tools"))
sys.path.insert(0, str(REPO / "tests" / "bot_test"))
import fun_report  # noqa: E402
import fun_trend  # noqa: E402

TS = "2026-11-23T12:58:21.2598558Z "


def bot(first, dead, wait, rpm, lv_gather=-1, lv_wall=-1, gather=30.0):
    return (f"[bot-test]   qa_fun_metrics: feedback_events=70 first_level_up_gather_s={lv_gather} "
            f"first_level_up_s={lv_wall} first_reward_s={first} gather_s={gather} level_ups=1 "
            f"levels_per_10_min=3.4 longest_dead_s={dead} longest_wait_s={wait} loops_completed=0 "
            f"rewards=26 rewards_per_min={rpm}")


def job_log(*steps):
    """steps: (command, [lines]) -> a log as GitHub serves it."""
    out = [TS + "##[group]Run godot --headless --path game -s tests/unit/run_all.gd", TS + "  ok  something"]
    for cmd, lines in steps:
        out.append(TS + "##[group]Run " + cmd)
        out += [TS + l for l in lines]
    out.append(TS + "##[group]Run tests/client_smoke/run.sh build/client-smoke")
    return "\r\n".join(out) + "\r\n"


CI_RUN = "python3 tests/bot_test/run_bot_test.py --bots 8 --duration 180 --transport websocket --fun-check"
ENET_RUN = "python3 tests/bot_test/run_bot_test.py --bots 8 --duration 45 --transport enet"


class FunTrend(unittest.TestCase):
    def test_per_bot_lines_roll_up_like_ci(self):
        log = job_log((CI_RUN, [bot(5.6, 36.8, 0.14, 8.96, 39.77, 124.2),
                                bot(9.15, 63.8, 0.24, 11.06, 43.76, 149.8),
                                bot(7.0, 10.0, 0.1, 9.0)]))
        s = fun_trend.summary_from_log(log)
        self.assertEqual(s["bots"], 3)
        self.assertEqual(s["first_reward_s_median"], 7.0)
        self.assertEqual(s["first_reward_s_worst"], 9.15)
        self.assertEqual(s["longest_dead_s_worst"], 63.8)
        self.assertEqual(s["bots_levelled"], 2)
        self.assertEqual(s["first_level_up_gather_s_worst"], 43.76)

    def test_only_the_fun_checked_step_counts(self):
        # The 45 s ENet run comes after and prints metrics too; it must not be mixed in.
        log = job_log((CI_RUN, [bot(8.0, 30, 0.1, 9.0)]), (ENET_RUN, [bot(40.0, 99, 5.0, 1.0)]))
        s = fun_trend.summary_from_log(log)
        self.assertEqual(s["bots"], 1)
        self.assertEqual(s["first_reward_s_median"], 8.0)

    def test_summary_line_wins_over_per_bot_lines(self):
        summary = fun_report.summarise({"a": {"first_reward_s": 3.0, "longest_dead_s": 5.0,
                                              "longest_wait_s": 0.1, "rewards_per_min": 12.0}})
        line = "[bot-test] fun summary: " + json.dumps(summary, separators=(",", ":"))
        log = job_log((CI_RUN, [bot(50.0, 99, 9, 1.0), line]))
        self.assertEqual(fun_trend.summary_from_log(log), summary)

    def test_run_without_bot_test_has_no_summary(self):
        log = job_log()
        self.assertIsNone(fun_trend.summary_from_log(log))
        row = fun_trend.format_row({"created_at": "2026-11-23T11:38:20Z", "head_sha": "3d23930abc",
                                    "conclusion": "failure"}, None)
        self.assertIn("3d23930", row)
        self.assertIn("no fun metrics", row)

    def test_row_shows_median_and_worst(self):
        s = fun_trend.summary_from_log(job_log((CI_RUN, [bot(7.92, 34.0, 0.24, 9.57, 36.71, 130),
                                                         bot(9.15, 63.8, 0.1, 9.6, 43.76, 140)])))
        row = fun_trend.format_row({"created_at": "2026-11-23T12:41:19Z", "head_sha": "2a3d9bb999",
                                    "conclusion": "success"}, s)
        self.assertTrue(row.startswith("2026-11-23 12:41  2a3d9bb  success"))
        self.assertIn("8.5 / 9.2", row)   # first reward median / worst
        self.assertIn("2/2", row)         # bots levelled
        self.assertIn("40.2 / 43.8", row)  # first level-up gathering median / worst

    def test_bot_without_reward_shows_never(self):
        s = fun_trend.summary_from_log(job_log((CI_RUN, [bot(-1, 90, 0.1, 0.0), bot(8, 20, 0.1, 9.0)])))
        row = fun_trend.format_row({"created_at": "2026-11-23T12:00:00Z", "head_sha": "abcdef0", "conclusion": "failure"}, s)
        self.assertIn("8 / never", row)

    def test_bot_test_prints_the_summary_line(self):
        # The tool's preferred source must stay in run_bot_test.py.
        src = (REPO / "tests" / "bot_test" / "run_bot_test.py").read_text()
        self.assertIn(fun_trend.SUMMARY_TAG.strip(), src)


if __name__ == "__main__":
    unittest.main()
