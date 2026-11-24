extends TestCase
## World stream: day and night sky, driven by the one shared clock (WorldClock).

const D := WorldClock.DAY_SECONDS


func test_fraction_maps_onto_the_shared_clock() -> void:
	for f in [0.0, 0.1, 0.25, 0.5, 0.75, 0.99]:
		check_near(WorldClock.day_fraction(SkyClock.seconds_for_fraction(f)), f, 0.00001, "round trip at %s" % f)
	check_near(SkyClock.seconds_for_fraction(0.25), 0.0, 0.0001, "sunrise is world second 0")
	check_near(SkyClock.seconds_for_fraction(1.25), 0.0, 0.0001, "fractions wrap")


func test_sun_rises_peaks_and_sets() -> void:
	check(SkyClock.sun_height(0.0) < -0.5, "midnight sun is well below")
	check(absf(SkyClock.sun_height(0.25)) < 0.01, "sunrise on the horizon")
	check(SkyClock.sun_height(0.5) > 0.8, "noon sun is high")
	check(absf(SkyClock.sun_height(0.75)) < 0.01, "sunset on the horizon")
	check(absf(SkyClock.sun_direction(0.37).length() - 1.0) < 0.0001, "unit vector")
	check(SkyClock.moon_direction(0.0).y > 0.5, "moon up at midnight")


func test_sky_sun_matches_world_clock() -> void:
	# The sun you see must be the sun gameplay reasons about.
	for i in 24:
		var s := D * i / 24.0
		var f := WorldClock.day_fraction(s)
		check((SkyClock.sun_direction(f) - WorldClock.sun_direction(s)).length() < 0.0001, "sun dir at %d" % i)
		check_near(SkyClock.sun_height(f), WorldClock.sun_elevation(s), 0.0001, "sun height at %d" % i)
	# Stars come out at night and are gone by day, in step with the clock's phases.
	check_eq(SkyClock.star_alpha(WorldClock.day_fraction(D * 0.25)), 0.0, "no stars at noon")
	check(SkyClock.star_alpha(WorldClock.day_fraction(D * 0.75)) > 0.99, "stars at midnight")


func test_sky_samples_day_and_night() -> void:
	var noon := SkyClock.sample(0.5)
	var night := SkyClock.sample(0.0)
	check(noon.light_energy > 0.9, "bright noon")
	check(night.light_energy > 0.1 and night.light_energy < 0.6, "dim moonlight")
	check(night.light_dir.y > 0.0, "moonlight comes from above")
	check_eq(noon.stars, 0.0, "no stars at noon")
	check_eq(night.stars, 1.0, "stars at midnight")
	check((night.sky_top as Color).get_luminance() < (noon.sky_top as Color).get_luminance(), "night sky darker")
	# No frame of the day may produce a broken colour or a light pointing up from underground.
	for i in 96:
		var s := SkyClock.sample(i / 96.0)
		check(s.light_dir.y >= 0.0 or s.light_energy < 0.01, "light never from below at %d" % i)
		check(s.ambient_energy >= 0.18, "ambient never pitch black at %d" % i)


func test_day_night_reads_the_server_clock() -> void:
	DayNight.pinned_fraction = -1.0
	DayNight.clear_sync()
	check(not DayNight.is_synced(), "starts unsynced")
	check_near(DayNight.now_world_seconds(), WorldClock.now_seconds(), 1.0, "before sync: local wall clock, same epoch")
	# A server whose clock agrees with ours must not make the sky jump.
	var before := DayNight.now_fraction()
	DayNight.set_world_seconds(WorldClock.now_seconds())
	check(DayNight.is_synced(), "synced")
	check(absf(DayNight.now_fraction() - before) < 0.001, "no jump when the clocks agree")
	# A server half a day ahead wins.
	var server := WorldClock.now_seconds() + D * 0.5
	DayNight.set_world_seconds(server)
	check_near(DayNight.now_world_seconds(), server, 0.5, "server time wins")
	check_near(DayNight.now_fraction(), WorldClock.day_fraction(server), 0.001, "fraction from the server time")
	DayNight.set_world_seconds(NAN)
	check_near(DayNight.now_world_seconds(), server, 0.5, "a broken value is ignored")
	DayNight.clear_sync()


func test_pin_wins_over_everything() -> void:
	DayNight.set_world_seconds(123.0)
	DayNight.pinned_fraction = 0.1
	check_eq(DayNight.now_fraction(), 0.1, "pin freezes time")
	DayNight.pinned_fraction = -1.0
	DayNight.clear_sync()
	var sh := DayNight.sky_shader()
	check(sh.code.contains("shader_type sky"), "sky shader built in code")
