extends TestCase
## The client smoke test's feedback check (tests/client_smoke/feedback_check.gd): every gather
## and craft must answer the press within 100 ms, plus the frames any client needs to draw it.

const Feedback := preload("res://tests/client_smoke/feedback_check.gd")
const NEEDED := ["gather press -> bar (ash)", "craft press -> crafted toast"]


func _s(what: String, ms: float, frames: int = 1) -> Dictionary:
	return {"what": what, "ms": ms, "frames": frames}


func test_median() -> void:
	check_eq(Feedback.median([]), 0.0, "no frames")
	check_eq(Feedback.median([130.0, 10.0, 99.0]), 99.0, "odd count")
	check_eq(Feedback.median([10.0, 20.0, 30.0, 40.0]), 25.0, "even count")


func test_limit_is_budget_plus_two_frames() -> void:
	check_near(Feedback.limit_ms(100.0, 16.7), 133.4, 0.01, "60 fps: 100 ms plus two frames")
	check_near(Feedback.limit_ms(100.0, 130.0), 360.0, 0.01, "CI draws in software: two slow frames")
	check_near(Feedback.limit_ms(100.0, 0.0), 100.0, 0.01, "no frames measured: the bare budget")


func test_real_ci_run_passes() -> void:
	# Measured on 2026-11-23 from a local software-rendered run (median frame 134 ms).
	var run := [_s(NEEDED[0], 238.0, 1), _s("bar full -> haul toast (ash)", 0.0, 0),
		_s("bench press -> window", 144.0, 0), _s("craft press -> working", 1.0, 0), _s(NEEDED[1], 141.0, 1)]
	check_eq(Feedback.verdict(run, 100.0, 134.0, NEEDED).size(), 0, "today's client passes")


func test_catches_slow_and_missing_feedback() -> void:
	var slow := Feedback.verdict([_s(NEEDED[0], 180.0), _s(NEEDED[1], 20.0)], 100.0, 16.7, NEEDED)
	check_eq(slow.size(), 1, "180 ms at 60 fps is too slow")
	check(slow[0].contains("180 ms"), "the problem names the time: %s" % slow[0])
	var never := Feedback.verdict([_s(NEEDED[0], -1.0), _s(NEEDED[1], 20.0)], 100.0, 16.7, NEEDED)
	check(never.size() == 1 and never[0].contains("nothing happened"), "no feedback at all fails")
	var frames := Feedback.verdict([_s(NEEDED[0], 60.0, 4), _s(NEEDED[1], 20.0)], 100.0, 10.0, NEEDED)
	check(frames.size() == 1 and frames[0].contains("4 frames"), "fast frames but a late answer still fails")
	var missing := Feedback.verdict([_s(NEEDED[0], 20.0)], 100.0, 16.7, NEEDED)
	check(missing.size() == 1 and missing[0].contains("never measured"), "a feedback kind that was never tried fails")


func test_report() -> void:
	var r: Dictionary = Feedback.report([_s(NEEDED[0], 50.0), _s(NEEDED[0], 70.0)], 100.0, 20.0, [])
	check_eq(r.ok, true, "no problems is ok")
	check_eq(float(r.worst_ms[NEEDED[0]]), 70.0, "worst per kind")
	check_eq(float(r.limit_ms), 140.0, "limit in the report")
	check_eq(int(r.max_frames), Feedback.MAX_FRAMES, "frame cap in the report")
