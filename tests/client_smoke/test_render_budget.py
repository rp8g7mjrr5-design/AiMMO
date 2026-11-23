"""Tests for render_budget.py (the render budget maths). Run:
python3 -m unittest discover -s tests/client_smoke -p 'test_*.py'
"""
import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import render_budget as rb  # noqa: E402

BASE = {
    "art_bible": {"draw_calls": 300, "primitives": 600000, "materials": 24, "texture_mem_mb": 32, "world_build_s": 3.0},
    "ceilings": {"draw_calls": 300, "primitives": 2000000, "materials": 45, "texture_mem_mb": 32},
    "regression": 0.2,
    "baseline": {"noon": {"draw_calls": 200, "primitives": 1000000}},
}


def shot(**kw):
    s = {"draw_calls": 200, "primitives": 1000000, "materials": 20, "texture_mem_mb": 9.0, "world_build_s": 1.0}
    s.update(kw)
    return s


class CheckTest(unittest.TestCase):
    def test_healthy_shot_passes(self):
        self.assertEqual(rb.check({"noon": shot()}, BASE), [])

    def test_over_a_ceiling_fails(self):
        p = rb.check({"noon": shot(draw_calls=301)}, BASE)
        self.assertEqual(len(p), 2)  # the ceiling, and +50% over the baseline
        self.assertIn("ceiling 300", p[0])
        p = rb.check({"noon": shot(texture_mem_mb=32.5)}, BASE)
        self.assertEqual(len(p), 1)
        self.assertIn("texture memory", p[0])

    def test_at_the_ceiling_passes(self):
        b = dict(BASE, baseline={})
        self.assertEqual(rb.check({"noon": shot(draw_calls=300, materials=45)}, b), [])

    def test_ratchet_allows_20_percent_but_not_more(self):
        self.assertEqual(rb.check({"noon": shot(primitives=1200000)}, BASE), [])
        p = rb.check({"noon": shot(primitives=1200001)}, BASE)
        self.assertEqual(len(p), 1)
        self.assertIn("+20% over the baseline", p[0])

    def test_ratchet_only_on_draw_calls_and_primitives(self):
        b = dict(BASE, baseline={"noon": {"draw_calls": 200, "primitives": 1000000, "materials": 5}})
        self.assertEqual(rb.check({"noon": shot(materials=30)}, b), [])

    def test_shot_without_baseline_is_only_ceiling_checked(self):
        self.assertEqual(rb.check({"dusk": shot(primitives=1900000)}, BASE), [])

    def test_missing_measure_fails(self):
        s = shot()
        del s["materials"]
        p = rb.check({"noon": s}, BASE)
        self.assertEqual(p, ["noon: world materials was not measured"])

    def test_no_shots_fails(self):
        self.assertEqual(rb.check({}, BASE), ["no render stats were measured"])


class CheaperTest(unittest.TestCase):
    B = dict(BASE, baseline={}, cheaper={"low": "noon"}, min_saving=0.05)

    def pair(self, **low):
        noon = shot(scene_triangles=600000, primitives=435000, draw_calls=270)
        lo = shot(scene_triangles=540000, primitives=432000, draw_calls=268)
        lo.update(low)
        return {"noon": noon, "low": lo}

    def test_lighter_low_passes(self):
        self.assertEqual(rb.check(self.pair(), self.B), [])

    def test_low_that_builds_the_same_world_fails(self):
        # the bug this guards: Low saved in settings, but the world was built on Medium
        p = rb.check(self.pair(scene_triangles=600000, primitives=435000, draw_calls=270), self.B)
        self.assertEqual(len(p), 2)
        self.assertIn("not lighter", p[0])
        self.assertIn("not fewer", p[1])

    def test_min_saving_edge(self):
        self.assertEqual(rb.check(self.pair(scene_triangles=570000), self.B), [])
        p = rb.check(self.pair(scene_triangles=570001), self.B)
        self.assertEqual(len(p), 1)

    def test_more_draw_calls_fails(self):
        p = rb.check(self.pair(draw_calls=271), self.B)
        self.assertEqual(p, ["low: 271 draw calls is more than noon's 270"])

    def test_missing_shot_is_not_judged_twice(self):
        self.assertEqual(rb.check({"noon": shot()}, self.B), [])

    def test_saving_is_a_note(self):
        n = rb.notes(self.pair(), self.B)
        self.assertIn("low vs noon: draw calls -1%, primitives -1%, scene triangles -10%", n[0])


class NotesTest(unittest.TestCase):
    def test_over_art_bible_target_is_a_note_not_a_failure(self):
        s = {"noon": shot(primitives=1100000)}
        self.assertEqual(rb.check(s, BASE), [])
        self.assertTrue(any("art bible's 600000" in n for n in rb.notes(s, BASE)))

    def test_big_win_says_lower_the_baseline(self):
        n = rb.notes({"noon": shot(draw_calls=150)}, BASE)
        self.assertTrue(any("lower the baseline" in x for x in n))

    def test_slow_world_build_is_reported(self):
        n = rb.notes({"noon": shot(world_build_s=3.5)}, BASE)
        self.assertTrue(any("world build 3.5 s" in x for x in n))
        self.assertEqual(rb.check({"noon": shot(world_build_s=3.5)}, BASE), [])


class MainTest(unittest.TestCase):
    def test_writes_render_stats_and_exit_code(self):
        with tempfile.TemporaryDirectory() as d:
            d = Path(d)
            (d / "base.json").write_text(json.dumps(BASE))
            (d / "noon.json").write_text(json.dumps(shot()))
            (d / "night.json").write_text(json.dumps(shot(draw_calls=999)))
            out = d / "render_stats.json"
            args = ["--baseline", str(d / "base.json"), "--out", str(out), "--shot", f"noon={d / 'noon.json'}"]
            self.assertEqual(rb.main(args), 0)
            rep = json.loads(out.read_text())
            self.assertEqual(rep["problems"], [])
            self.assertEqual(rep["shots"]["noon"]["draw_calls"], 200)
            self.assertEqual(rb.main(args + ["--shot", f"night={d / 'night.json'}"]), 1)
            self.assertEqual(rb.main(args + ["--shot", f"dusk={d / 'nope.json'}"]), 1)
            self.assertIn("no render stats", json.loads(out.read_text())["problems"][0])

    def test_stored_baseline_is_consistent(self):
        b = rb.load_baseline()
        for k, v in b["ceilings"].items():
            self.assertIn(k, rb.GATED)
            # ceilings may sit above the art bible only while today's world is over it
            self.assertGreaterEqual(v, 0)
        for name, vals in b["baseline"].items():
            for k, v in vals.items():
                self.assertLessEqual(v, b["ceilings"][k], f"{name} baseline {k} is over its ceiling")
        self.assertEqual(b["cheaper"], {"low": "noon"})
        self.assertTrue(0 < b["min_saving"] < 0.5)


if __name__ == "__main__":
    unittest.main()
