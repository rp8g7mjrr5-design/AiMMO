class_name Palette
## Art direction lives here: a soft, low-poly, late-afternoon palette. See design bible.

const SAND := Color(0.86, 0.78, 0.56)
const GRASS := Color(0.40, 0.58, 0.30)
const MEADOW := Color(0.50, 0.65, 0.33)
const FOREST := Color(0.29, 0.50, 0.27)
const ROCK := Color(0.52, 0.49, 0.46)
const SNOW := Color(0.94, 0.95, 0.97)
const LAKEBED := Color(0.40, 0.46, 0.38)
const WATER := Color(0.25, 0.52, 0.68, 0.72)
const TRUNK := Color(0.42, 0.30, 0.20)
const ASH_LEAF := Color(0.86, 0.52, 0.30) ## the ember-leaved ash trees Ashgrove is named for
const PINE := Color(0.16, 0.46, 0.30)


## Stable, pleasant colour for a seed (character tunics, banners...).
static func from_seed(seed_value: int, sat: float = 0.55, val: float = 0.85) -> Color:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return Color.from_hsv(rng.randf(), sat, val)


## Ground colour for a point given its height and slope (0 flat .. 1 vertical).
static func ground(h: float, slope: float, jitter: float) -> Color:
	var c: Color
	if h < Terrain.water_level() + 0.2:
		c = LAKEBED
	elif h < Terrain.water_level() + 1.2:
		c = SAND
	elif h > 17.0:
		c = SNOW
	elif slope > 0.55 or h > 13.0:
		c = ROCK
	elif h > 6.0:
		c = FOREST
	elif h < 1.5:
		c = MEADOW
	else:
		c = GRASS
	return c.lightened(jitter) if jitter > 0.0 else c.darkened(-jitter)
