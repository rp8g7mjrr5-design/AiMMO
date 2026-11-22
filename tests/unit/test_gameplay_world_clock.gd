extends TestCase
## The shared day/night clock (game/shared/world_clock.gd) and the server's use of it.

const D := WorldClock.DAY_SECONDS


func test_day_is_forty_minutes() -> void:
	check_near(WorldClock.DAY_SECONDS, 2400.0, 0.001, "one day = 40 real minutes")
	check_near(WorldClock.day_fraction(123.0), WorldClock.day_fraction(123.0 + D), 0.000001, "repeats every day")


func test_world_starts_at_dawn_of_day_one() -> void:
	check_near(WorldClock.day_fraction(0.0), 0.25, 0.000001, "world second 0 is sunrise")
	check_eq(WorldClock.day_number(0.0), 1, "first day is day 1")
	check_near(WorldClock.hour(0.0), 6.0, 0.0001, "sunrise at 06:00")


func test_days_roll_over_at_midnight() -> void:
	var midnight := D * 0.75 # three quarters of a day after sunrise
	check_eq(WorldClock.day_number(midnight - 0.5), 1, "just before midnight")
	check_eq(WorldClock.day_number(midnight + 0.5), 2, "just after midnight")
	check_near(WorldClock.day_fraction(midnight + 0.001), 0.0, 0.0001, "fraction wraps to 0")


func test_phases_cover_the_day() -> void:
	var seen := {}
	for i in 240:
		seen[WorldClock.phase(D * i / 240.0)] = true
	for p in ["dawn", "day", "dusk", "night"]:
		check(seen.has(p), "phase %s happens every day" % p)
	var noon := D * 0.25
	check_eq(WorldClock.phase(noon), "day", "noon is day")
	check_eq(WorldClock.phase(noon + D * 0.5), "night", "midnight is night")
	check(WorldClock.is_night(noon + D * 0.5), "is_night at midnight")
	check(not WorldClock.is_night(noon), "not night at noon")


func test_sun_and_daylight() -> void:
	var noon := D * 0.25
	var midnight := D * 0.75
	check_near(WorldClock.sun_elevation(noon), 1.0, 0.0001, "sun highest at noon")
	check_near(WorldClock.sun_elevation(midnight), -1.0, 0.0001, "sun lowest at midnight")
	check_near(WorldClock.sun_elevation(0.0), 0.0, 0.0001, "sun on the horizon at sunrise")
	check_near(WorldClock.daylight(noon), 1.0, 0.0001, "full daylight at noon")
	check_near(WorldClock.daylight(midnight), 0.0, 0.0001, "dark at midnight")
	var sun := WorldClock.sun_direction(noon)
	check_near(sun.length(), 1.0, 0.0001, "sun direction is a unit vector")
	check(sun.y > 0.9, "noon sun is overhead")
	check(WorldClock.sun_direction(D * 0.05).x > 0.5, "morning sun is in the east")
	check(WorldClock.sun_direction(D * 0.45).x < -0.5, "evening sun is in the west")


func test_negative_time_is_safe() -> void:
	# A client with a badly wrong clock, or time before the epoch, must still give sane values.
	var f := WorldClock.day_fraction(-1000.0)
	check(f >= 0.0 and f < 1.0, "fraction stays in [0, 1)")
	check(["dawn", "day", "dusk", "night"].has(WorldClock.phase(-1000.0)), "phase is valid")


func test_extrapolate() -> void:
	check_near(WorldClock.extrapolate(100.0, 5000, 7500), 102.5, 0.0001, "adds elapsed local time")
	check_near(WorldClock.extrapolate(100.0, 5000, 4000), 100.0, 0.0001, "never runs backwards")


func test_now_is_after_epoch() -> void:
	check(WorldClock.now_seconds() > 0.0, "wall clock is after the Week 00 epoch")
	check_near(WorldClock.now_seconds(600.0) - WorldClock.now_seconds(), 600.0, 1.0, "offset applies")


func test_describe() -> void:
	check_eq(WorldClock.describe(0.0), "Day 1, 06:00 (dawn)")
	check_eq(WorldClock.describe(D * 0.25), "Day 1, 12:00 (day)")


func test_server_clock_offset() -> void:
	var server: Node = load("res://server/server.gd").new()
	server.clock_offset = D * 0.5
	check_near(server.world_seconds() - WorldClock.now_seconds(), D * 0.5, 1.0, "server applies its clock offset")
	server.free()
