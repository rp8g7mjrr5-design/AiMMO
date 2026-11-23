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


func test_tooltip_says_what_comes_next() -> void:
	# 12:00 on day 3: dusk starts at fraction 0.70, night at 0.78.
	var noon := _seconds_at(0.5, 3)
	var t := TimeDial.tooltip_text_at(noon)
	var lines := t.split("\n")
	check_eq(lines.size(), 4, "four lines, got %s" % t)
	check_eq(lines[0], "Day 3, 12:00", "exact time")
	check_eq(lines[1], "Dusk in about %d minutes" % int(round(0.2 * D / 60.0)), "dusk countdown")
	check_eq(lines[2], "Then night in about %d minutes" % int(round(0.28 * D / 60.0)), "night after it")
	check_eq(lines[3], "A day in Ashgrove lasts 40 minutes", "day length")
	# Deep night wraps through midnight to dawn, then day.
	var late := TimeDial.tooltip_text_at(_seconds_at(0.95, 3))
	check(late.contains("\nDawn in about"), "night is followed by dawn: %s" % late)
	check(late.contains("\nThen day in about"), "then day: %s" % late)
	check(late.begins_with("Day 3, 22:48"), "still day 3 before midnight: %s" % late)
	# Every hour of the day: next phase is right and both countdowns are positive and ordered.
	for i in 96:
		var s := _seconds_at(i / 96.0, 4)
		var ls := TimeDial.tooltip_text_at(s).split("\n")
		var nxt: String = TimeDial.PHASE_NAMES[WorldClock.next_phase(s)]
		check(ls[1].begins_with(nxt + " in "), "step %d: %s should start with %s" % [i, ls[1], nxt])
		check(not ls[2].to_lower().contains(nxt.to_lower() + " in"), "step %d: second phase differs from the first" % i)


func test_until_text_rounds_kindly() -> void:
	check_eq(TimeDial.until_text(5.0), "in less than a minute", "seconds")
	check_eq(TimeDial.until_text(59.9), "in less than a minute", "just under a minute")
	check_eq(TimeDial.until_text(80.0), "in about a minute", "one minute")
	check_eq(TimeDial.until_text(540.0), "in about 9 minutes", "nine")
	check_eq(TimeDial.until_text(570.0), "in about 10 minutes", "rounds half up")


func test_readout_warns_before_a_phase_change() -> void:
	# Dusk starts at 0.70; 60 real seconds before is 0.70 - 60/D.
	var before_dusk := _seconds_at(0.70 - 60.0 / D, 2)
	var st := TimeDial.state(before_dusk)
	check_eq(st.soon, "Dusk soon", "warning in the last 90 s of day")
	check_eq(TimeDial.label_text(st), st.text + " · Dusk soon", "label carries the warning")
	check(st.text.ends_with("· Day"), "the readout itself is unchanged: %s" % st.text)
	var before_night := TimeDial.state(_seconds_at(0.78 - 30.0 / D, 2))
	check_eq(before_night.soon, "Night soon", "night warning")
	var midday := TimeDial.state(_seconds_at(0.5, 2))
	check_eq(midday.soon, "", "no warning at noon")
	check_eq(TimeDial.label_text(midday), midday.text, "plain label at noon")
	# The warning shows for exactly SOON_SECONDS of each phase change, never longer.
	var warned := 0
	for i in 2400:
		if TimeDial.state(_seconds_at(0.0, 6) + i).soon != "":
			warned += 1
	check(absi(warned - 4 * int(TimeDial.SOON_SECONDS)) <= 4, "warned %d s across a day (4 changes x %d s)" % [warned, int(TimeDial.SOON_SECONDS)])


func test_hover_area_is_the_dial_and_readout() -> void:
	var dial := TimeDial.new()
	dial.setup(Theme.new())
	dial.size = Vector2(460, 50)
	check_eq(dial.mouse_filter, Control.MOUSE_FILTER_PASS, "hover reaches the dial")
	check(dial._has_point(Vector2(TimeDial.RADIUS, TimeDial.RADIUS)), "the disk")
	check(not dial._has_point(Vector2(455, 45)), "not the empty strip to the right")
	check(dial._get_tooltip(Vector2.ZERO).begins_with("Day "), "tooltip text")
	var tip = dial._make_custom_tooltip("Day 1, 06:00")
	check(tip is PanelContainer, "a styled panel")
	tip.free()
	dial.free()
