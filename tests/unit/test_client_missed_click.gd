extends TestCase
## A left-click that does nothing (at the sky, at a spent node, while walking) plays a soft
## "nothing there" tick, so a missed click is felt instead of silent. A click that starts a
## gather, a click while chopping, and a click while a start is waiting never tick, and a
## hammered button makes one tick per MISS_GAP, not a buzz.


func _first(kind: String) -> Dictionary:
	for n in ResourceNodes.all():
		if n.kind == kind:
			return n
	return {}


func _a_day() -> float:
	for i in 96:
		var t := i * WorldClock.DAY_SECONDS / 96.0
		if not WorldClock.is_night(t):
			return t
	return 0.0


func _aim(n: Dictionary) -> Array:
	var eye: Vector3 = n.pos + Vector3(0.0, 2.2, 2.6)
	return [eye, (n.pos + Vector3.UP - eye).normalized()]


func test_missed_click_rule() -> void:
	var start := {"op": "start", "node": 3}
	check(GatherPrompt.missed_click(true, {}, false, false), "a click that did nothing is a miss")
	check(not GatherPrompt.missed_click(false, {}, false, false), "no click, no tick")
	check(not GatherPrompt.missed_click(true, start, false, false), "a click that starts a gather is not a miss")
	check(not GatherPrompt.missed_click(true, {}, true, false), "a click while chopping keeps chopping, not a miss")
	check(not GatherPrompt.missed_click(true, {}, false, true), "a click while a start is waiting is not a miss")
	check(not GatherPrompt.missed_click(true, {}, false, false, GatherPrompt.MISS_GAP * 0.5), "hammering: one tick per gap")
	check(GatherPrompt.missed_click(true, {}, false, false, GatherPrompt.MISS_GAP), "after the gap it ticks again")


func test_widget_flags_misses_for_one_frame() -> void:
	var n := _first("stone")
	var a := _aim(n)
	var day := _a_day()
	var w := GatherPrompt.new()
	w.setup(Theme.new())
	w.pack = {"wooden_pickaxe": 1} # stone needs a pickaxe (2026-11-26)
	var now := 50.0
	w.update(0.05, n.pos, day, now, false, false, false, a[0], Vector3.UP, true, true)
	check(w.click_missed, "click at the sky next to an outcrop: a miss")
	now += 0.05
	w.update(0.05, n.pos, day, now, false, false, false, a[0], Vector3.UP, true, false)
	check(not w.click_missed, "holding the button after it is not another miss")
	now += 0.05
	w.update(0.05, n.pos, day, now, false, false, false, a[0], Vector3.UP, false, false)
	w.update(0.0, n.pos, day, now, false, false, false, a[0], Vector3.UP, true, true)
	check(not w.click_missed, "a second click 0.1 s later is inside the gap")
	now += 0.2
	w.update(0.2, n.pos, day, now, false, false, false, a[0], Vector3.UP, true, true)
	check(w.click_missed, "a click after the gap ticks again")
	now += 0.2
	var op := w.update(0.2, n.pos, day, now, false, false, false, a[0], a[1], true, true)
	check_eq(op, {"op": "start", "node": int(n.id)}, "click at the outcrop starts it")
	check(not w.click_missed, "and is not a miss")
	now += 0.3
	w.update(0.3, n.pos, day, now, false, false, false, a[0], a[1], true, true)
	check(not w.click_missed, "a click while the start is unanswered is not a miss")
	w.on_begun(n.id, 2.4, now)
	now += 0.3
	w.update(0.3, n.pos, day, now, false, false, false, a[0], Vector3.UP, true, true)
	check(not w.click_missed, "clicking while chopping is not a miss")
	w.on_ended(n.id, "done")
	var empty := Vector3(9999.0, 0.0, 9999.0)
	now += 0.3
	w.update(0.3, empty, day, now, false, false, false, empty + Vector3.UP, Vector3.FORWARD, true, true)
	check(w.click_missed, "a click with nothing in reach is a miss")
	w.free()


func test_miss_sound_is_short_soft_and_clean() -> void:
	var wav := Sfx.miss()
	var samples := wav.data.size() / 2
	check_near(float(samples) / Sfx.RATE, Sfx.MISS_LENGTH, 0.005, "length")
	var peak := 0
	for i in range(0, wav.data.size(), 2):
		peak = maxi(peak, absi(wav.data.decode_s16(i)))
	check(peak > 1500, "audible (peak %d)" % peak)
	var nope_peak := 0
	var nope := Sfx.nope()
	for i in range(0, nope.data.size(), 2):
		nope_peak = maxi(nope_peak, absi(nope.data.decode_s16(i)))
	check(peak < nope_peak, "softer than a refusal (%d vs %d)" % [peak, nope_peak])
	check(samples < nope.data.size() / 2 / 3, "and much shorter than one")
	check(absi(wav.data.decode_s16(wav.data.size() - 2)) < 200, "ends without a click")
	check(Sfx.miss().data == wav.data, "the same tick every launch")
