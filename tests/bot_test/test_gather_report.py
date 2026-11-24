"""Unit tests for gather_report.py (run: python3 -m unittest discover -s tests/bot_test -p 'test_*.py')."""
import unittest

import gather_report as gr


def bot(completed=2, walked_off=1, stopped=1, shared=1, depleted=()):
    return {"behaviours": {
        "gameplay_gather_v3": {"completed": completed, "walked_off": walked_off, "stopped": stopped},
        "qa_gather_ledger": {"shared_node_max": shared, "depleted": [list(d) for d in depleted], "respawned": []}}}


class GatherReport(unittest.TestCase):
    def good(self):
        rows = {f"b{i}": bot() for i in range(8)}
        rows["b0"] = bot(shared=2, depleted=[(40, 1000.0, 180.0, False)])
        return rows

    def test_good_run_passes(self):
        self.assertEqual(gr.check(self.good(), 180, 8), [])

    def test_short_runs_are_not_checked(self):
        self.assertEqual(gr.check({"b": bot(completed=0)}, 45, 8), [])

    def test_too_few_gatherers(self):
        rows = self.good()
        for k in ["b1", "b2", "b3", "b4", "b5"]:
            rows[k] = bot(completed=0)
        p = gr.check(rows, 180, 8)
        self.assertEqual(len(p), 1)
        self.assertIn("only 3 of 8", p[0])

    def test_each_missing_case_is_named(self):
        rows = {f"b{i}": bot(walked_off=0, stopped=0, shared=1) for i in range(8)}
        text = " | ".join(gr.check(rows, 180, 8))
        for want in ["walking away", "c2s_gather_cancel", "emptied"]:
            self.assertIn(want, text)

    def test_shared_node_by_chance_is_no_longer_required(self):
        rows = {f"b{i}": bot(shared=1) for i in range(8)}
        rows["b0"] = bot(shared=1, depleted=[(40, 1000.0, 180.0, False)])
        self.assertEqual(gr.check(rows, 180, 8), [], "the pair check covers it, not luck")

    @staticmethod
    def pair(a, b):
        return {"pairA": {"behaviours": {"qa_gather_ledger": {"pair": a}}},
                "pairB": {"behaviours": {"qa_gather_ledger": {"pair": b}}}}

    def test_pair_good(self):
        rows = self.pair({"role": "lead", "node": 3, "together": True, "end": "done"},
                         {"role": "follow", "node": 3, "together": True, "end": "depleted"})
        self.assertEqual(gr.check_pair(rows, 2), [])

    def test_pair_not_together(self):
        rows = self.pair({"node": 3, "together": True, "end": "done"},
                         {"node": 3, "together": False, "end": "done"})
        self.assertIn("same time", " ".join(gr.check_pair(rows, 2)))

    def test_pair_different_nodes_and_unpaid(self):
        text = " ".join(gr.check_pair(self.pair({"node": 3, "together": True, "end": "depleted"},
                                                {"node": 4, "together": True, "end": "depleted"}), 2))
        self.assertIn("different nodes", text)
        self.assertIn("paid", text)

    def test_pair_missing_bot(self):
        self.assertIn("expected 2", gr.check_pair({"pairA": {"behaviours": {"qa_gather_ledger": {"pair": {"node": 1}}}}}, 2)[0])
        self.assertIn("expected 3", gr.check_pair({})[0])

    @staticmethod
    def trio(lead_end="done", b_end="done", c_end="done", emptied=True, after="depleted", charges=3):
        common = {"node": 5, "together": True, "charges": charges, "emptied": emptied}
        return {"pairA": {"behaviours": {"qa_gather_ledger": {"pair": dict(common, role="lead", end=lead_end, after=after)}}},
                "pairB": {"behaviours": {"qa_gather_ledger": {"pair": dict(common, role="follow", end=b_end)}}},
                "pairC": {"behaviours": {"qa_gather_ledger": {"pair": dict(common, role="follow", end=c_end)}}}}

    def test_trio_full_node_all_paid_then_depleted(self):
        self.assertEqual(gr.check_pair(self.trio()), [])

    def test_trio_partial_node(self):
        # Two charges left: two paid, the third told "depleted", the extra press refused.
        self.assertEqual(gr.check_pair(self.trio(c_end="depleted")), [])
        # Node not emptied (a charge left after the group): the extra press must begin.
        self.assertEqual(gr.check_pair(self.trio(c_end="depleted", emptied=False, after="began")),
                         ["pair: someone was told 'depleted' but nobody was told the node is empty"])

    def test_trio_paid_every_charge_but_not_emptied(self):
        text = " ".join(gr.check_pair(self.trio(emptied=False, after="began")))
        self.assertIn("nobody was told the node is empty", text)

    def test_trio_more_paid_than_charges(self):
        self.assertIn("3 paid on a node that holds 2", " ".join(gr.check_pair(self.trio(charges=2))))

    def test_trio_after_press_must_match(self):
        self.assertIn("got 'began' but the node was emptied", " ".join(gr.check_pair(self.trio(after="began"))))
        self.assertIn("leader's press", " ".join(gr.check_pair(self.trio(after=""))))

    def test_probe_picks_soonest_due(self):
        rows = {"a": bot(depleted=[(1, 1000.0, 240.0, False), (2, 1010.0, 180.0, False)]),
                "b": bot(depleted=[(2, 1010.4, 180.0, False)])}
        self.assertEqual(gr.pick_probe(rows, now=1100.0), (2, 1190.0))

    def test_probe_uses_latest_emptying(self):
        rows = {"a": bot(depleted=[(2, 1000.0, 180.0, False), (2, 1190.0, 180.0, False)]),
                "b": bot(depleted=[(2, 1189.5, 180.0, False)])}
        self.assertEqual(gr.pick_probe(rows, now=1200.0), (2, 1369.5))

    def test_probe_skips_night_only_and_too_soon(self):
        rows = {"a": bot(depleted=[(7, 1000.0, 600.0, True), (2, 1000.0, 180.0, False)])}
        self.assertIsNone(gr.pick_probe(rows, now=1175.0), "due in 5 s is too soon, the seep is night-only")
        self.assertEqual(gr.pick_probe(rows, now=1100.0), (2, 1180.0))

    def test_summary_mentions_counts(self):
        s = gr.summary(self.good())
        self.assertIn("by 8 bots", s)
        self.assertIn("most_on_one_node=2", s)
        self.assertIn("nodes_emptied=1", s)


if __name__ == "__main__":
    unittest.main()
