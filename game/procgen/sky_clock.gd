class_name SkyClock
## The colour side of day and night: what colour the sky, fog, and light should be, and how
## bright the stars are, for a given time of day. No nodes here, so it is fully unit-tested
## headless. `DayNight` applies these values to the world.
##
## Time itself (day length, sun path, phases) belongs to the one shared clock, `WorldClock`
## in game/shared/world_clock.gd, which the server owns. This file only maps the sun's
## height to colours, so the sky can never disagree with gameplay about what time it is.
##
## Time of day is a fraction: 0.0 midnight, 0.25 sunrise, 0.5 noon, 0.75 sunset.

## Sky keys by sun height (sine of elevation). Each: [height, top, horizon, fog/ground, light].
## Day keeps the late-afternoon palette from the design bible; dusk leans on the ember orange.
const KEYS := [
	[-1.00, Color(0.02, 0.03, 0.08), Color(0.06, 0.08, 0.16), Color(0.06, 0.07, 0.12), Color(0.55, 0.65, 0.95)],
	[-0.22, Color(0.03, 0.05, 0.12), Color(0.10, 0.12, 0.22), Color(0.09, 0.10, 0.16), Color(0.55, 0.65, 0.95)],
	[-0.06, Color(0.12, 0.14, 0.30), Color(0.62, 0.36, 0.30), Color(0.32, 0.25, 0.26), Color(0.90, 0.55, 0.40)],
	[0.06, Color(0.26, 0.38, 0.66), Color(0.98, 0.62, 0.38), Color(0.72, 0.56, 0.46), Color(1.00, 0.70, 0.48)],
	[0.30, Color(0.36, 0.55, 0.82), Color(0.93, 0.78, 0.62), Color(0.85, 0.78, 0.70), Color(1.00, 0.92, 0.80)],
	[1.00, Color(0.32, 0.54, 0.86), Color(0.82, 0.84, 0.86), Color(0.82, 0.83, 0.84), Color(1.00, 0.98, 0.94)],
]


## World seconds that land on this day fraction on day 1 (inverse of
## WorldClock.day_fraction). Lets a pinned fraction (screenshots, tests) reuse the shared
## clock's sun maths.
static func seconds_for_fraction(frac: float) -> float:
	return (fposmod(frac, 1.0) - WorldClock.START_FRACTION) * WorldClock.DAY_SECONDS


## Unit vector pointing from the ground towards the sun, straight from the shared clock.
static func sun_direction(frac: float) -> Vector3:
	return WorldClock.sun_direction(seconds_for_fraction(frac))


## Sun height: +1 at noon, 0 at sunrise and sunset, -1 at midnight (WorldClock.sun_elevation).
static func sun_height(frac: float) -> float:
	return WorldClock.sun_elevation(seconds_for_fraction(frac))


## The moon rides opposite the sun, so somebody is always lighting the valley.
static func moon_direction(frac: float) -> Vector3:
	return -sun_direction(frac)


## 0 in daylight, 1 in full night; stars fade in through dusk.
static func star_alpha(frac: float) -> float:
	return clampf(inverse_lerp(-0.02, -0.20, sun_height(frac)), 0.0, 1.0)


## Everything the world needs for one moment: colours, light direction, and energies.
static func sample(frac: float) -> Dictionary:
	var h := sun_height(frac)
	var top: Color
	var horizon: Color
	var fog: Color
	var light: Color
	for i in range(1, KEYS.size()):
		var lo: Array = KEYS[i - 1]
		var hi: Array = KEYS[i]
		if h <= hi[0] or i == KEYS.size() - 1:
			var t := clampf(inverse_lerp(lo[0], hi[0], h), 0.0, 1.0)
			top = (lo[1] as Color).lerp(hi[1], t)
			horizon = (lo[2] as Color).lerp(hi[2], t)
			fog = (lo[3] as Color).lerp(hi[3], t)
			light = (lo[4] as Color).lerp(hi[4], t)
			break
	var sun_up := h > 0.0
	# The light follows the sun by day and the moon by night, dimming to nothing as either
	# crosses the horizon so the swap is never visible.
	var light_dir := sun_direction(frac) if sun_up else moon_direction(frac)
	var lift := clampf(absf(h) / 0.12, 0.0, 1.0)
	var energy := lerpf(0.0, 1.0, lift) if sun_up else lerpf(0.0, 0.22, lift)
	var ambient := lerpf(0.18, 0.5, clampf(inverse_lerp(-0.2, 0.3, h), 0.0, 1.0))
	return {
		"frac": frac,
		"sun_height": h,
		"sky_top": top,
		"sky_horizon": horizon,
		"fog": fog,
		"light_color": light,
		"light_dir": light_dir,
		"light_energy": energy,
		"ambient_energy": ambient,
		"stars": star_alpha(frac),
		"sun_dir": sun_direction(frac),
		"moon_dir": moon_direction(frac),
	}
