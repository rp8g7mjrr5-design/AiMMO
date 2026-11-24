"""The bot test's player-cap phase reads the capped server's log (run_bot_test.cap_log_problems)."""
import re
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import run_bot_test  # noqa: E402

REPO = Path(__file__).resolve().parents[2]
CAP = run_bot_test.CAP_PLAYERS
STAYERS = [f"cap{i}" for i in range(2, CAP + 1)]


def log(*lines: str) -> str:
    return "\n".join([f"[server] player cap: {CAP}", "[server] listening on port 1 via websocket, protocol v7", *lines]) + "\n"


AWAY = f"[server] turned a login away: the world is full ({CAP} / {CAP})"
LEFT = "[server] cap1 (peer 11) left, saved at (1, 2, 3)"
JOINED = "[server] capwait logged in as peer 20 (new) at (0, 0, 0)"


def problems(text: str) -> list:
    return run_bot_test.cap_log_problems(text, CAP, "cap1", "capwait", STAYERS)


class CapLogTest(unittest.TestCase):
    def test_refused_then_let_in_after_one_left_passes(self):
        self.assertEqual(problems(log(AWAY, AWAY, LEFT, JOINED, "[server] cap2 (peer 12) left, saved at (0, 0, 0)")), [])

    def test_no_cap_fails(self):
        text = log(AWAY, LEFT, JOINED).replace(f"player cap: {CAP}", "player cap: none")
        self.assertIn("did not start with a cap", problems(text)[0])

    def test_never_turned_away_fails(self):
        self.assertTrue(any("turned away" in p for p in problems(log(LEFT, JOINED))))

    def test_let_in_before_anyone_left_fails(self):
        self.assertTrue(any("before cap1 left" in p for p in problems(log(AWAY, JOINED, LEFT))))

    def test_never_let_in_fails(self):
        self.assertTrue(any("never got in" in p for p in problems(log(AWAY, LEFT))))

    def test_a_stayer_dropped_before_the_waiter_got_in_fails(self):
        text = log(AWAY, "[server] cap5 (peer 15) left, saved at (0, 0, 0)", LEFT, JOINED)
        self.assertTrue(any("cap5 left before capwait" in p for p in problems(text)))

    def test_cap_matches_the_railway_image(self):
        m = re.search(r"\bMAX_PLAYERS=(\d+)\b", (REPO / "Dockerfile").read_text())
        self.assertIsNotNone(m, "the Dockerfile sets no MAX_PLAYERS")
        self.assertEqual(int(m.group(1)), CAP, "the bot test's capped phase must play the cap Railway runs")


if __name__ == "__main__":
    unittest.main()
