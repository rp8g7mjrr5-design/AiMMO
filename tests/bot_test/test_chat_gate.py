"""The bot test's chat-gate phase reads the gate server's log (run_bot_test.gate_log_problems)."""
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import run_bot_test  # noqa: E402

OFF = "[server] dev commands: off (--dev-commands)\n[server] listening on 1234\n"


class GateLogTest(unittest.TestCase):
    def test_quiet_gate_passes(self):
        log = OFF + "[chat] bot_gate1: hello from bot_gate1 #1\n[server] stopped cleanly\n"
        self.assertEqual(run_bot_test.gate_log_problems(log), [])

    def test_a_command_that_ran_fails(self):
        problems = run_bot_test.gate_log_problems(OFF + "[chat] bot_gate1 ran /gather\n")
        self.assertEqual(len(problems), 1)
        self.assertIn("/gather", problems[0])

    def test_talk_mentioning_ran_is_not_a_command(self):
        self.assertEqual(run_bot_test.gate_log_problems(OFF + "[chat] bot_gate1: I ran /home\n"), [])

    def test_server_with_commands_on_fails(self):
        problems = run_bot_test.gate_log_problems("[server] dev commands: on (local default)\n")
        self.assertIn("did not start with dev commands off", problems[0])


if __name__ == "__main__":
    unittest.main()
