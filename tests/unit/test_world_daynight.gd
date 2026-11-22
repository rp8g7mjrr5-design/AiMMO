extends TestCase
## World stream: day and night sky.


func test_day_clock_wraps_and_offsets() -> void:
	check_eq(SkyClock.day_fraction(0.0), 0.0)
	check(absf(SkyClock.day_fraction(SkyClock.DAY_LENGTH * 0.5) - 0.5) < 0.0001, "half a day is noon")
	check(absf(SkyClock.day_fraction(SkyClock.DAY_LENGTH * 3.25) - 0.25) < 0.0001, "wraps every day")
	check(absf(SkyClock.day_fraction(0.0, SkyClock.DAY_LENGTH * 0.75) - 0.75) < 0.0001, "offset shifts the clock")
	check(SkyClock.day_fraction(-10.0) >= 0.0, "never negative")


func test_sun_rises_peaks_and_sets() -> void:
	check(SkyClock.sun_height(0.0) < -0.5, "midnight sun is well below")
	check(absf(SkyClock.sun_height(0.25)) < 0.01, "sunrise on the horizon")
	check(SkyClock.sun_height(0.5) > 0.8, "noon sun is high")
	check(absf(SkyClock.sun_height(0.75)) < 0.01, "sunset on the horizon")
	check(absf(SkyClock.sun_direction(0.37).length() - 1.0) < 0.0001, "unit vector")
	check(SkyClock.moon_direction(0.0).y > 0.5, "moon up at midnight")


func test_sky_samples_day_and_night() -> void:
	var noon := SkyClock.sample(0.5)
	var night := SkyClock.sample(0.0)
	check(noon.light_energy > 0.9, "bright noon")
	check(night.light_energy > 0.1 and night.light_energy < 0.3, "dim moonlight")
	check(night.light_dir.y > 0.0, "moonlight comes from above")
	check_eq(noon.stars, 0.0, "no stars at noon")
	check_eq(night.stars, 1.0, "stars at midnight")
	check((night.sky_top as Color).get_luminance() < (noon.sky_top as Color).get_luminance(), "night sky darker")
	check_eq(SkyClock.phase_name(0.5), "Day")
	check_eq(SkyClock.phase_name(0.0), "Night")
	check_eq(SkyClock.phase_name(0.25), "Dawn")
	check_eq(SkyClock.phase_name(0.75), "Dusk")
	# No frame of the day may produce a broken colour or a light pointing up from underground.
	for i in 96:
		var s := SkyClock.sample(i / 96.0)
		check(s.light_dir.y >= 0.0 or s.light_energy < 0.01, "light never from below at %d" % i)
		check(s.ambient_energy >= 0.18, "ambient never pitch black at %d" % i)


func test_day_night_sync_and_pin() -> void:
	DayNight.pinned_fraction = -1.0
	DayNight.sync_to_server(0.6)
	check(absf(DayNight.now_fraction() - 0.6) < 0.001, "synced to the server clock")
	DayNight.pinned_fraction = 0.1
	check_eq(DayNight.now_fraction(), 0.1, "pin freezes time")
	DayNight.pinned_fraction = -1.0
	DayNight.clock_offset = 0.0
	var sh := DayNight.sky_shader()
	check(sh.code.contains("shader_type sky"), "sky shader built in code")
