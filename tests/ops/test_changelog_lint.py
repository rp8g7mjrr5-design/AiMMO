"""Chat is for talking: patch notes never tell players to type a slash command (tools/changelog_lint.py)."""
import json
import subprocess
import sys
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO / "tools"))
import changelog_lint as lint  # noqa: E402


class OffendingTest(unittest.TestCase):
    def test_commands_are_caught(self):
        self.assertEqual(lint.offending("- Type `/bag` in chat to look inside."), ["/bag"])
        self.assertEqual(lint.offending("Walk up and type /gather pine"), ["/gather"])
        self.assertEqual(lint.offending('Try "/who" and /help.'), ["/who", "/help"])
        self.assertEqual(lint.offending("(/craft torch)"), ["/craft"])

    def test_paths_and_urls_are_not_commands(self):
        for line in ("see game/procgen/palette.gd", "https://github.com/x/y", "the ./run.sh script",
                     "1/2 of the nodes", "and/or", "docs/playtest.md", "~/AiMMO", "<a>/b"):
            self.assertEqual(lint.offending(line), [], line)

    def test_saying_a_command_is_gone_is_fine(self):
        self.assertEqual(lint.offending("so you never have to type /help again"), [])
        self.assertEqual(lint.offending("You no longer need /gather: press E."), [])
        self.assertEqual(lint.offending("Press E instead of typing /gather."), [])
        # A negation in an earlier sentence doesn't excuse a new instruction.
        self.assertEqual(lint.offending("Never mind. Type /bag to look."), ["/bag"])

    def test_allow_list_only_covers_exact_lines(self):
        allowed = {"- Type `/bag` in chat."}
        problems, still = lint.check_text("x.md", "- Type `/bag` in chat.\n- Type `/who` too.\n", allowed)
        self.assertEqual(still, allowed)
        self.assertEqual(len(problems), 1)
        self.assertIn("/who", problems[0])
        self.assertIn("x.md:2", problems[0])


class RepoTest(unittest.TestCase):
    def test_changelog_and_fragments_pass(self):
        r = subprocess.run([sys.executable, str(REPO / "tools" / "changelog_lint.py")], capture_output=True, text=True)
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)

    def test_allow_list_only_holds_lines_that_still_offend(self):
        allowed = json.loads((REPO / "tools" / "changelog_lint_allow.json").read_text())["lines"]
        text = (REPO / "CHANGELOG.md").read_text()
        present = {l.strip() for l in text.splitlines()}
        for line in allowed:
            self.assertTrue(lint.offending(line), f"allow-listed line no longer offends, drop it: {line[:60]}")
            # Gone from CHANGELOG.md is only a note (the integrator may reword it before updating the list).
            if line not in present:
                print(f"note: allow-listed line gone from CHANGELOG.md: {line[:60]}")


if __name__ == "__main__":
    unittest.main()
