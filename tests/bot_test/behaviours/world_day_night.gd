extends "res://tests/bot_test/bot_behaviour.gd"
## Bot behaviour (world): the sky follows the server's clock.
##
## Each bot feeds every s2c_world_time into DayNight the same way the client does, then
## checks that the sky's time of day matches the server's, that it keeps moving forward in
## step between syncs, and that the colours DayNight would paint are sane.

var syncs := 0
var checks := 0
var last_frac := -1.0
var last_seconds := NAN
var _check_timer := 0.0


func setup(net: Node) -> void:
	DayNight.pinned_fraction = -1.0
	DayNight.clear_sync()
	net.world_time.connect(_on_world_time)


func _on_world_time(world_seconds: float) -> void:
	syncs += 1
	DayNight.set_world_seconds(world_seconds)
	var want := WorldClock.day_fraction(world_seconds)
	var got := DayNight.now_fraction()
	if _frac_gap(got, want) > 0.001:
		fail("sky time %.4f does not match server time %.4f" % [got, want])


func on_play(delta: float) -> void:
	if not DayNight.is_synced():
		return
	_check_timer -= delta
	if _check_timer > 0.0:
		return
	_check_timer = 5.0
	checks += 1
	var secs := DayNight.now_world_seconds()
	if not is_nan(last_seconds) and secs + 0.5 < last_seconds:
		fail("sky clock ran backwards: %.2f after %.2f" % [secs, last_seconds])
	last_seconds = secs
	last_frac = DayNight.now_fraction()
	var s := SkyClock.sample(last_frac)
	for k in ["sky_top", "sky_horizon", "fog", "light_color"]:
		var c: Color = s[k]
		if not (is_finite(c.r) and is_finite(c.g) and is_finite(c.b)):
			fail("sky colour %s is broken at fraction %.4f" % [k, last_frac])
	if not is_finite(s.light_energy) or s.light_energy < 0.0:
		fail("light energy broken at fraction %.4f" % last_frac)


func on_finish() -> void:
	stat("sky_syncs", syncs)
	stat("sky_checks", checks)
	stat("sky_time", WorldClock.describe(last_seconds) if not is_nan(last_seconds) else "")
	if syncs == 0:
		fail("the sky never got the server's time")
	elif checks == 0:
		fail("the sky clock was never checked while playing")


static func _frac_gap(a: float, b: float) -> float:
	var d := absf(a - b)
	return minf(d, 1.0 - d)
