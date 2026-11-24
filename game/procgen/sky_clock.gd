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

## Grounded (art bible section 5): a dusty, high-altitude blue by day, never a postcard
## cyan, with a hazy warm horizon, so the sky frames the world instead of competing with it.
## Sky keys by sun height (sine of elevation). Each: [height, top, horizon, fog/ground, light].
## Emberlight part 4 (art bible section 5, "golden-hour bias"): the warm keys reach far up the
## sky, so the sun spends most of the day in golden light and only the top of the arc is
## noon, which is short and still warm. Nights are moonlit `SHADE` blue with blue haze, never
## black, so the ember glow carries the light.
const KEYS := [
	[-1.00, Color(0.03, 0.05, 0.15), Color(0.08, 0.12, 0.26), Palette.NIGHT_HAZE, Palette.MOONLIGHT],
	[-0.22, Color(0.04, 0.07, 0.18), Color(0.12, 0.15, 0.30), Palette.NIGHT_HAZE, Palette.MOONLIGHT],
	[-0.06, Color(0.12, 0.14, 0.32), Color(0.66, 0.36, 0.28), Color(0.34, 0.26, 0.30), Color(0.92, 0.52, 0.36)],
	[0.06, Color(0.24, 0.32, 0.52), Color(0.92, 0.56, 0.34), Color(0.70, 0.52, 0.40), Color(1.00, 0.66, 0.42)],
	[0.30, Color(0.30, 0.42, 0.62), Color(0.88, 0.70, 0.50), Palette.HAZE, Palette.GOLDEN_LIGHT],
	[0.65, Color(0.27, 0.43, 0.66), Color(0.76, 0.76, 0.70), Palette.HAZE, Color(1.00, 0.88, 0.72)],
	[1.00, Color(0.25, 0.42, 0.68), Color(0.70, 0.76, 0.80), Color(0.74, 0.77, 0.78), Color(1.00, 0.93, 0.84)],
]

const DAY_LIGHT := 1.3 ## sun energy by day: strong enough for crisp shadows and lit faces that read at a glance (owner, 2026-11-24: the test camp)
const DAY_AMBIENT := 0.36 ## sky fill by day: lower than the key, so shadows keep their shape and the meadow never glows
const DAY_SKY_SHARE := 0.65 ## by day most of the fill is the sky's own colours
const NIGHT_SKY_SHARE := 0.25 ## at night most of it is a flat moonlit blue (the sky is nearly black)
const NIGHT_LIGHT := 0.55 ## moonlight energy at full night: dim, but you can see the meadow by it
const NIGHT_AMBIENT := 0.6 ## sky fill at full night: moody and dark, but the meadow still reads (never black)


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


## 0 by day, 1 at full night: how far the world's paint leans to night colours (Emberlight's
## `ember_night`: the ground drains of green and shadows go bluer, so the moon reads blue and
## every ember glow pops). Starts in the blue hour, a little after the lamps are lit.
static func night_amount(frac: float) -> float:
	return smoothstep(0.02, -0.25, sun_height(frac))


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
	var energy := lerpf(0.0, DAY_LIGHT, lift) if sun_up else lerpf(0.0, NIGHT_LIGHT, lift)
	var ambient := lerpf(NIGHT_AMBIENT, DAY_AMBIENT, clampf(inverse_lerp(-0.2, 0.3, h), 0.0, 1.0))
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
		# The flat part of the fill (the rest comes from the sky): moonlit SHADE blue at night,
		# the warm horizon by day, so a figure turned away from the moon is a blue-grey shape,
		# never a black hole (art bible, "Light by time of day").
		"ambient_color": Palette.MOONLIGHT.lerp(horizon, clampf(inverse_lerp(-0.1, 0.2, h), 0.0, 1.0)),
		# How much of the fill comes from the sky's own colours: most by day, little at night,
		# when the near-black sky would otherwise leave the fill at nothing.
		"ambient_sky_share": lerpf(NIGHT_SKY_SHARE, DAY_SKY_SHARE, clampf(inverse_lerp(-0.1, 0.2, h), 0.0, 1.0)),
		"stars": star_alpha(frac),
		"night": night_amount(frac),
		"sun_dir": sun_direction(frac),
		"moon_dir": moon_direction(frac),
	}
