"""The bot test's night phase: the clock offset that makes it midnight, and what its server log must say."""
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import run_bot_test as r  # noqa: E402

GOOD = "\n".join([
    "[server] world clock: Day 214, 00:00 (night)",
    "[server] gloam: on: walkers rise near players, 1 each by day, 3 at night, at most 24",
    "[gloam] walker 3 grabbed botx_night1 for 15",
    "[gloam] botx_night2 put walker 4 down",
]) + "\n"


def fraction(unix: float, offset: float) -> float:
    return ((unix - r.WORLD_EPOCH_UNIX + offset) / r.DAY_SECONDS + r.START_FRACTION) % 1.0


class NightClock(unittest.TestCase):
    def test_offset_lands_on_midnight(self):
        for unix in (r.WORLD_EPOCH_UNIX, r.WORLD_EPOCH_UNIX + 1234.5, 1796000000.0, 1800000123.0):
            off = r.night_clock_offset(unix)
            self.assertGreaterEqual(off, 0.0)
            self.assertLess(off, r.DAY_SECONDS)
            f = fraction(unix, off)
            self.assertAlmostEqual(min(f, 1.0 - f), 0.0, places=6)

    def test_midnight_leaves_the_phase_in_the_dark(self):
        # Night ends at 0.22 of the day (WorldClock.DAWN_START): the phase must fit before it.
        self.assertGreater(0.22 * r.DAY_SECONDS, r.NIGHT_PLAY + 120)


class NightLog(unittest.TestCase):
    def test_a_good_night(self):
        self.assertEqual(r.night_log_problems(GOOD), [])

    def test_walkers_off(self):
        text = GOOD.replace("gloam: on: walkers rise", "gloam: off (no walkers rise")
        self.assertIn("the night server did not start with walkers rising", r.night_log_problems(text))

    def test_daytime(self):
        text = GOOD.replace("00:00 (night)", "12:00 (day)")
        self.assertIn("the night server's clock is not at night", r.night_log_problems(text))

    def test_no_grab_and_no_down(self):
        text = "\n".join(l for l in GOOD.splitlines() if not l.startswith("[gloam]"))
        p = r.night_log_problems(text)
        self.assertIn("no walker grabbed anyone all night", p)
        self.assertIn("nobody put a walker down all night", p)


if __name__ == "__main__":
    unittest.main()
