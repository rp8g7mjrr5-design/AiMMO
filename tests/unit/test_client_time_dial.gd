extends TestCase
## Client time dial and sky clock wiring: the dial reads the shared clock, the sun and moon
## sit where the sky has them, and the client hands the server's time to DayNight.

const ClientScript := preload("res://client/client.gd")
const D := WorldClock.DAY_SECONDS


func _seconds_at(frac: float, day: int = 1) -> float:
	# World second 0 is sunrise (fraction 0.25) of day 1.
	return (day - 1) * D + (frac - WorldClock.START_FRACTION) * D


func _reset_daynight() -> void:
	DayNight.clear_sync()
	DayNight.pinned_fraction = -1.0


func test_sun_rides_the_rim_by_day() -> void:
	var sunrise := TimeDial.state(_seconds_at(0.25))
	check_eq(sunrise.body, "sun", "sun at sunrise")
	check((sunrise.offset - Vector2(-1, 0)).length() < 0.001, "sunrise on the left horizon, got %s" % str(sunrise.offset))
	var noon := TimeDial.state(_seconds_at(0.5))
	check_eq(noon.body, "sun", "sun at noon")
	check((noon.offset - Vector2(0, -1)).length() < 0.001, "noon at the top, got %s" % str(noon.offset))
	var late := TimeDial.state(_seconds_at(0.7))
	check(late.offset.x > 0.5 and late.offset.y < 0.0, "afternoon sun sinks on the right")


func test_moon_takes_over_at_night() -> void:
	var midnight := TimeDial.state(_seconds_at(0.0, 2))
	check_eq(midnight.body, "moon", "moon at midnight")
	check((midnight.offset - Vector2(0, -1)).length() < 0.001, "midnight moon at the top, got %s" % str(midnight.offset))
	# Whatever the hour, the body shown is above the horizon (y <= 0 in 2D) and on the rim.
	for i in 96:
		var st := TimeDial.state(_seconds_at(i / 96.0, 3))
		check(st.offset.y <= 0.0001, "body above the horizon at step %d (%s)" % [i, st.body])
		check_near(st.offset.length(), 1.0, 0.0001, "on the rim at step %d" % i)
		check_eq(st.body == "sun", WorldClock.sun_elevation(_seconds_at(i / 96.0, 3)) >= 0.0, "sun only when it's up (step %d)" % i)


func test_readout_matches_the_world_clock() -> void:
	var s := _seconds_at(0.5 + 1.0 / 24.0 / 2.0, 3) # 12:30 on day 3
	var st := TimeDial.state(s)
	check_eq(st.text, "Day 3 · 12:30 · Day", "readout")
	check_eq(st.day, WorldClock.day_number(s), "day number")
	check_eq(st.phase, WorldClock.phase(s), "phase")
	check_eq(TimeDial.state(_seconds_at(0.74, 5)).text.ends_with("· Dusk"), true, "dusk label")
	check_eq(TimeDial.state(_seconds_at(0.26, 5)).text.ends_with("· Dawn"), true, "dawn label")
	check_eq(TimeDial.state(_seconds_at(0.9, 5)).text.ends_with("· Night"), true, "night label")
	# Just before midnight never reads 24:00 or 60 minutes.
	var st2 := TimeDial.state(_seconds_at(0.0, 4) - 0.001)
	check(st2.text.contains("23:59"), "23:59 before midnight, got %s" % st2.text)


func test_pinned_sky_and_dial_agree() -> void:
	_reset_daynight()
	DayNight.pinned_fraction = 0.8
	var st := TimeDial.state(TimeDial.current_seconds())
	check_near(st.fraction, 0.8, 0.0001, "dial follows the pinned sky")
	check_eq(st.day, WorldClock.day_number(DayNight.now_world_seconds()), "same day as the clock")
	_reset_daynight()


func test_client_feeds_the_server_clock_to_the_sky() -> void:
	_reset_daynight()
	var c = ClientScript.new()
	var server_seconds := _seconds_at(0.0, 7) # midnight on day 7, far from this machine's clock
	c._on_world_time(server_seconds)
	check(DayNight.is_synced(), "sky synced")
	check(absf(DayNight.now_world_seconds() - server_seconds) < 1.0, "sky uses the server's time")
	check_near(TimeDial.state(TimeDial.current_seconds()).fraction, 0.0, 0.001, "dial shows the server's time")
	c._on_world_time(NAN) # a broken value must not wreck the clock
	check(absf(DayNight.now_world_seconds() - server_seconds) < 1.0, "NaN ignored")
	c.free()
	_reset_daynight()
