"""Unit tests for perf_report.py (run: python3 -m unittest discover -s tests/bot_test -p 'test_*.py')."""
import json
import unittest

import perf_report

STAT = "4242 (godot (headless)) S 1 4242 4242 0 -1 4194304 1000 0 0 0 250 50 0 0 20 0 9 0 100 900000 5000"
SS = """0      0      127.0.0.1:7777  127.0.0.1:50001
\t cubic wscale:7,7 rto:204 bytes_sent:10000 bytes_acked:10001 bytes_received:2000 segs_out:10
0      0      127.0.0.1:7777  127.0.0.1:50002
\t cubic wscale:7,7 rto:204 bytes_acked:5000 bytes_received:700 segs_out:4
"""


def smp(cpu, rss=100.0, conns=None):
    return {"cpu_s": cpu, "rss_mb": rss, "conns": conns}


def run(seconds, cpu_per_s=0.1, rss_per_s=0.0, down_bps=4000, up_bps=500, players=2, tick=20.0):
    """Samples of a steady server: cpu_per_s CPU seconds per second, players at fixed rates."""
    out = []
    for t in range(seconds + 1):
        conns = {f"p{i}": {"sent": down_bps * t, "received": up_bps * t} for i in range(players)}
        out.append([float(t), smp(cpu_per_s * t, 100.0 + rss_per_s * t, conns)])
    return out


BUDGET = {"min_duration_s": 120,
          "max": {"cpu_ms_per_tick": 10, "rss_peak_mb": 400, "down_kbps_per_player_max": 100},
          "min": {"tick_rate_min": 18, "players_measured": 2},
          "baseline": {"cpu_ms_per_tick": 5.0, "down_kbps_per_player_median": 32.0},
          "baseline_gated": ["down_kbps_per_player_median"], "worse_ratio": 1.5}


class Parsing(unittest.TestCase):
    def test_proc_stat_handles_spaces_in_comm(self):
        self.assertAlmostEqual(perf_report.parse_proc_stat(STAT, 100), 3.0)

    def test_rss(self):
        self.assertAlmostEqual(perf_report.parse_rss_mb("Name:\tgodot\nVmRSS:\t  204800 kB\n"), 200.0)
        self.assertEqual(perf_report.parse_rss_mb("Name:\tgodot\n"), 0.0)

    def test_ss_per_connection_with_acked_fallback(self):
        c = perf_report.parse_ss(SS)
        self.assertEqual(c["127.0.0.1:50001"], {"sent": 10000, "received": 2000})
        self.assertEqual(c["127.0.0.1:50002"], {"sent": 5000, "received": 700})

    def test_ss_empty(self):
        self.assertEqual(perf_report.parse_ss(""), {})

    def test_tick_rate_from_config(self):
        self.assertGreater(perf_report.server_tick_rate(), 0)


class Summary(unittest.TestCase):
    def test_steady_server(self):
        s = perf_report.summarise(run(120), 20.0, [19.9, 20.0, 19.5])
        # 0.1 CPU s per s at 20 ticks/s = 5 ms per tick.
        self.assertAlmostEqual(s["cpu_ms_per_tick"], 5.0, places=2)
        self.assertAlmostEqual(s["cpu_ms_per_tick_peak"], 5.0, places=2)
        self.assertEqual(s["tick_budget_ms"], 50.0)
        self.assertEqual(s["down_kbps_per_player_median"], 32.0)
        self.assertEqual(s["up_kbps_per_player_max"], 4.0)
        self.assertEqual(s["players_measured"], 2)
        self.assertEqual(s["tick_rate_min"], 19.5)
        self.assertEqual(s["rss_growth_mb"], 0.0)
        # Warm-up and cool-down are cut: the window is 30 s .. end - 10 s.
        self.assertEqual(s["window_s"], 80.0)

    def test_cpu_spike_shows_in_peak_not_average(self):
        samples = run(120)
        for i in range(60, len(samples)):
            samples[i][1]["cpu_s"] += 1.0  # one CPU second burned between t=59 and t=60
        s = perf_report.summarise(samples, 20.0, [])
        self.assertLess(s["cpu_ms_per_tick"], 6.0)
        self.assertGreater(s["cpu_ms_per_tick_peak"], 10.0)

    def test_memory_growth(self):
        s = perf_report.summarise(run(120, rss_per_s=0.5), 20.0, [])
        self.assertEqual(s["rss_growth_mb"], 40.0)
        self.assertEqual(s["rss_peak_mb"], 160.0)

    def test_short_lived_connection_is_ignored(self):
        samples = run(120)
        for t, s in samples:
            if 50 <= t <= 55:
                s["conns"]["blip"] = {"sent": int(1e9 * t), "received": 0}
        s = perf_report.summarise(samples, 20.0, [])
        self.assertEqual(s["players_measured"], 2)
        self.assertEqual(s["down_kbps_per_player_max"], 32.0)

    def test_no_network_measurement(self):
        samples = run(120)
        for _, s in samples:
            s["conns"] = None
        s = perf_report.summarise(samples, 20.0, [None, None])
        self.assertIsNone(s["down_kbps_per_player_median"])
        self.assertIsNone(s["tick_rate_min"])
        self.assertEqual(s["players_measured"], 0)

    def test_summary_is_json(self):
        json.dumps(perf_report.summarise(run(60), 20.0, [20.0]))


class Check(unittest.TestCase):
    def test_healthy_passes(self):
        s = perf_report.summarise(run(120), 20.0, [20.0])
        problems, notes = perf_report.check(s, BUDGET, True)
        self.assertEqual(problems, [])
        self.assertEqual(notes, [])

    def test_over_cpu_budget_fails(self):
        s = perf_report.summarise(run(120, cpu_per_s=0.4), 20.0, [20.0])
        problems, notes = perf_report.check(s, BUDGET, True)
        self.assertTrue(any("cpu_ms_per_tick 20.0 is over" in p for p in problems), problems)
        # CPU against the baseline is a note only: machines differ.
        self.assertTrue(any("cpu_ms_per_tick" in n and "baseline" in n for n in notes), notes)

    def test_slow_ticks_fail(self):
        s = perf_report.summarise(run(120), 20.0, [20.0, 12.0])
        problems, _ = perf_report.check(s, BUDGET, True)
        self.assertTrue(any("tick_rate_min 12.0 is under" in p for p in problems), problems)

    def test_fatter_snapshots_fail_against_baseline(self):
        s = perf_report.summarise(run(120, down_bps=7000), 20.0, [20.0])
        problems, _ = perf_report.check(s, BUDGET, True)
        self.assertTrue(any("down_kbps_per_player_median 56.0 is more than 1.5x" in p for p in problems), problems)

    def test_much_better_is_a_note(self):
        s = perf_report.summarise(run(120, down_bps=1000), 20.0, [20.0])
        problems, notes = perf_report.check(s, BUDGET, True)
        self.assertEqual(problems, [])
        self.assertTrue(any("re-take" in n for n in notes), notes)

    def test_missing_bandwidth_fails_only_when_needed(self):
        samples = run(120)
        for _, x in samples:
            x["conns"] = None
        s = perf_report.summarise(samples, 20.0, [20.0])
        self.assertEqual(perf_report.check(s, BUDGET, False)[0], [])
        self.assertTrue(any("not measured" in p for p in perf_report.check(s, BUDGET, True)[0]))

    def test_shipped_budget_loads(self):
        b = perf_report.load_budget()
        for key in ("max", "min", "baseline", "worse_ratio"):
            self.assertIn(key, b)


if __name__ == "__main__":
    unittest.main()
