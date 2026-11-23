"""Render budget for the client smoke test (art bible, section 7 "Budgets" and 8 "Checks").

tests/client_smoke/render_stats.gd measures one shot of the real client (noon or night, at
spawn, after the world settles) and writes a JSON per shot. This script rolls the shots into
render_stats.json, prints a table, and fails when:

- a shot is over a ceiling in tests/client_smoke/render_baseline.json ("ceilings"). The art
  bible's own numbers are under "art_bible"; where today's world was already over one when qa
  first measured it, the ceiling is today's number and world brings it down. Ceilings only go
  down.
- draw calls or primitives grow by more than `regression` (20%) over the shot's stored
  baseline (the ratchet), the same way the fun metrics work. Update the baseline in the PR that
  changes it, with a reason.
- a cheaper preset is not cheaper ("cheaper" in the baseline, e.g. {"low": "noon"}: the Low
  Graphics preset against Medium at the same noon spawn). Low must build a lighter world (scene
  triangles at least `min_saving` under) and draw fewer primitives and no more draw calls, so
  picking Low on an old laptop really helps. How much it saves is printed as a note.

Frame time and world build time are reported, not gated: CI renders in software.

  python3 tests/client_smoke/render_budget.py --shot noon=/abs/noon.json --shot night=/abs/night.json \
      --shot low=/abs/low.json --out /abs/render_stats.json

Tested by tests/client_smoke/test_render_budget.py.
"""
import argparse
import json
import sys
from pathlib import Path

BASELINE = Path(__file__).resolve().parent / "render_baseline.json"

# metric -> label for the table
GATED = {
    "draw_calls": "draw calls",
    "primitives": "primitives",
    "materials": "world materials",
    "texture_mem_mb": "texture memory (MB)",
}
RATCHETED = ("draw_calls", "primitives")
REPORTED = {
    "objects": "objects",
    "video_mem_mb": "video memory (MB)",
    "scene_triangles": "scene triangles",
    "world_build_s": "world build (s)",
    "frame_ms_median": "frame (ms, software)",
}


def load_baseline(path: Path = BASELINE) -> dict:
    return json.loads(path.read_text()) if path.exists() else {}


def check(shots: dict, baseline: dict) -> list:
    """Problems (empty when every shot is within budget). `shots` is {name: stats}."""
    out = []
    ceilings = baseline.get("ceilings", {})
    regression = float(baseline.get("regression", 0.2))
    base = baseline.get("baseline", {})
    if not shots:
        return ["no render stats were measured"]
    for name, stats in sorted(shots.items()):
        for k, label in GATED.items():
            if k not in stats:
                out.append(f"{name}: {label} was not measured")
                continue
            if k in ceilings and stats[k] > ceilings[k]:
                out.append(f"{name}: {label} {stats[k]} is over the ceiling {ceilings[k]}")
        for k in RATCHETED:
            was = base.get(name, {}).get(k)
            if was is None or k not in stats:
                continue
            limit = was * (1.0 + regression)
            if stats[k] > limit:
                out.append(
                    f"{name}: {GATED[k]} {stats[k]} is {pct(stats[k], was)} over the baseline {was} "
                    f"(more than {regression:.0%}); slim it, or update render_baseline.json with a reason")
    out += check_cheaper(shots, baseline)
    return out


def check_cheaper(shots: dict, baseline: dict) -> list:
    """Problems for each {cheap: full} pair in baseline["cheaper"] when the cheap shot isn't.

    Only judged when both shots were measured (a missing shot is reported on its own)."""
    out = []
    rules = baseline.get("cheaper", {})
    min_saving = float(baseline.get("min_saving", 0.05))
    for cheap, full in sorted(rules.items()):
        c, f = shots.get(cheap), shots.get(full)
        if c is None or f is None:
            continue
        ct, ft = c.get("scene_triangles"), f.get("scene_triangles")
        if ct is not None and ft:
            if ct > ft * (1.0 - min_saving):
                out.append(
                    f"{cheap}: the world it builds is not lighter than {full}'s: scene triangles {ct} vs {ft} "
                    f"({pct(ct, ft)}, needs {-min_saving:+.0%} or better); does the preset reach the world?")
        cp, fp = c.get("primitives"), f.get("primitives")
        if cp is not None and fp is not None and cp >= fp:
            out.append(f"{cheap}: draws {cp} primitives, not fewer than {full}'s {fp}")
        cd, fd = c.get("draw_calls"), f.get("draw_calls")
        if cd is not None and fd is not None and cd > fd:
            out.append(f"{cheap}: {cd} draw calls is more than {full}'s {fd}")
    return out


def notes(shots: dict, baseline: dict) -> list:
    """Things worth a look that don't fail: over the art bible's target, or a big win to lock in."""
    out = []
    target = baseline.get("art_bible", {})
    regression = float(baseline.get("regression", 0.2))
    base = baseline.get("baseline", {})
    for name, stats in sorted(shots.items()):
        for k, label in GATED.items():
            if k in target and k in stats and stats[k] > target[k]:
                out.append(f"{name}: {label} {stats[k]} is over the art bible's {target[k]} (world owns bringing it down)")
        for k in RATCHETED:
            was = base.get(name, {}).get(k)
            if was and k in stats and stats[k] < was * (1.0 - regression):
                out.append(f"{name}: {GATED[k]} fell to {stats[k]} from {was}: lower the baseline to lock the win in")
        build = stats.get("world_build_s")
        if build is not None and "world_build_s" in target and build > target["world_build_s"]:
            out.append(f"{name}: world build {build} s is over the art bible's {target['world_build_s']} s (reported only)")
    for cheap, full in sorted(baseline.get("cheaper", {}).items()):
        c, f = shots.get(cheap), shots.get(full)
        if c is None or f is None:
            continue
        parts = [f"{GATED[k]} {pct(c[k], f[k])}" for k in RATCHETED if c.get(k) is not None and f.get(k)]
        if c.get("scene_triangles") is not None and f.get("scene_triangles"):
            parts.append(f"scene triangles {pct(c['scene_triangles'], f['scene_triangles'])}")
        if c.get("frame_ms_median") is not None and f.get("frame_ms_median"):
            parts.append(f"frame {pct(c['frame_ms_median'], f['frame_ms_median'])}")
        out.append(f"{cheap} vs {full}: " + ", ".join(parts))
    return out


def pct(now: float, was: float) -> str:
    return f"{(now - was) / was:+.0%}" if was else "n/a"


def table(shots: dict, baseline: dict) -> str:
    names = sorted(shots)
    ceilings = baseline.get("ceilings", {})
    rows = [["measure"] + names + ["ceiling"]]
    for k, label in list(GATED.items()) + list(REPORTED.items()):
        rows.append([label] + [str(shots[n].get(k, "-")) for n in names] + [str(ceilings.get(k, "-"))])
    widths = [max(len(r[i]) for r in rows) for i in range(len(rows[0]))]
    return "\n".join("  ".join(c.ljust(w) for c, w in zip(r, widths)) for r in rows)


def report(shots: dict, baseline: dict) -> dict:
    return {
        "shots": shots,
        "ceilings": baseline.get("ceilings", {}),
        "art_bible": baseline.get("art_bible", {}),
        "baseline": baseline.get("baseline", {}),
        "cheaper": baseline.get("cheaper", {}),
        "problems": check(shots, baseline),
        "notes": notes(shots, baseline),
    }


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--shot", action="append", default=[], help="name=/path/to/stats.json")
    ap.add_argument("--out", required=True, help="where to write render_stats.json")
    ap.add_argument("--baseline", default=str(BASELINE))
    args = ap.parse_args(argv)
    shots = {}
    missing = []
    for s in args.shot:
        name, _, path = s.partition("=")
        p = Path(path)
        if p.exists():
            shots[name] = json.loads(p.read_text())
        else:
            missing.append(f"{name}: no render stats at {path} (did render_stats.gd log in?)")
    baseline = load_baseline(Path(args.baseline))
    rep = report(shots, baseline)
    rep["problems"] = missing + rep["problems"]
    Path(args.out).write_text(json.dumps(rep, indent=2))
    print("render budget (art bible section 7), worst frame of each shot:")
    if shots:
        print(table(shots, baseline))
    for n in rep["notes"]:
        print("  note: " + n)
    for p in rep["problems"]:
        print("  FAIL: " + p)
    print("render budget " + ("FAILED" if rep["problems"] else "ok") + f", details in {args.out}")
    return 1 if rep["problems"] else 0


if __name__ == "__main__":
    sys.exit(main())
