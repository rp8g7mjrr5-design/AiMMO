class_name Palette
## Art direction lives here (docs/art_bible.md, "Emberlight: grounded"). Earth first: muted,
## lived-in naturals carry the screen; ember is the one rare saturated note.

const SAND := Color(0.68, 0.62, 0.48) ## shore silt and dry sand, not beach-postcard yellow
const GRASS := Color(0.33, 0.41, 0.25) ## olive valley grass: never lime (art bible, "What reads as cheesy")
const MEADOW := Color(0.39, 0.45, 0.27) ## dry autumn meadow, olive going straw
const FOREST := Color(0.25, 0.33, 0.22) ## forest floor under the canopy: dark moss
const ROCK := Color(0.46, 0.44, 0.41) ## weathered grey stone, a touch warm
const SNOW := Color(0.86, 0.87, 0.88) ## old snow: never paper white
const LAKEBED := Color(0.30, 0.33, 0.27)
const WATER := Color(0.20, 0.33, 0.38, 0.80) ## deep cold valley water, not pool blue
const TRUNK := Color(0.32, 0.25, 0.20) ## weathered bark
const ASH_LEAF := Color(0.62, 0.31, 0.17) ## the ember-leaved ash trees Ashgrove is named for: rust, not candy orange
const ASH_LEAF_DRY := Color(0.66, 0.46, 0.25) ## the paler, drier end of an ash crown's range (scatter variety)
const PINE := Color(0.15, 0.27, 0.21) ## dark spruce: pines are the shadows of the forest

# Ground cover (art bible section 11, "Uniform flat terrain facets"): gentle seeded patches
# laid over the grass, meadow and forest floor so the valley reads as real ground, not one
# flat olive. Each stays a muted natural under 0.45 saturation.
const MOSS := Color(0.24, 0.33, 0.20) ## damp cushion moss: hollows, shade and lake margins
const DRY_GRASS := Color(0.50, 0.47, 0.31) ## sun-bleached straw grass on open, sunny ground
const BARE_EARTH := Color(0.38, 0.31, 0.23) ## worn brown earth where the turf has thinned

# Emberlight tokens (docs/art_bible.md, section 2). sRGB, like the rest of this file.
const EMBER := Color("#F2A541") ## the signature glow: anything you can use. Never on plain decoration
const EMBER_CORE := Color("#FFD27A") ## the hot centre of a glow, sparks, the brightest pixel of a vein
const SMOULDER := Color("#B5432A") ## deep ember red: dying embers, danger, the edge of a vein
const COLD_ASH := Color("#6E7A86") ## the Dimming: drained, blue-grey ash
const SOOT := Color("#2B2A2E") ## the darkest value; never pure black anywhere in the world
const SHADE := Color("#4A5878") ## shadow tint: shadows lean blue-violet, never grey or black
const HAZE := Color("#E8C9A0") ## warm golden valley haze by day

# Light and air through the day (SkyClock, Emberlight part 4: golden hour, blue-and-ember nights).
const GOLDEN_LIGHT := Color(1.0, 0.80, 0.56) ## the low sun's key light: the valley's favourite hour
const MOONLIGHT := Color(0.50, 0.60, 1.0) ## the night key: SHADE's blue, bright enough to see by
const NIGHT_HAZE := Color(0.10, 0.13, 0.25) ## valley haze after dark: blue, never black
const MOTE := Color(1.0, 0.66, 0.30) ## a rising ember mote: EMBER, a touch redder so it reads against EMBER_CORE leaves

# Tier-2 resource nodes (NodeProps, Milestone 1): richer looks than the tier-1 props, so a
# player can tell from across the meadow which node is worth levelling toward.
const OLD_ASH_LEAF := Color(0.78, 0.45, 0.20) ## old ember ash crown: brighter, hotter than ASH_LEAF (the veins do the shouting)
const OLD_ASH_BARK := Color(0.42, 0.38, 0.34) ## older, greyer bark than TRUNK
const RICH_STONE := Color(0.45, 0.40, 0.42) ## rich stone seam: a deeper colour than the grey outcrops
const RICH_FLECK := Color(1.0, 0.86, 0.52) ## bright gold flecks: "this rock is rich"

# Grazers (Grazers, Milestone 2 wildlife): warm, earthy herd animals that sit in the golden
# meadow light without glowing (they are alive, not usable: no ember on them).
const GRAZER_COAT := Color(0.62, 0.44, 0.28) ## warm fawn, a little redder than TRUNK so a herd reads against bark
const GRAZER_BELLY := Color(0.88, 0.80, 0.66) ## cream belly and the pale rump you see bounding away
const GRAZER_DARK := Color(0.20, 0.16, 0.14) ## hooves, muzzle and eyes: close to SOOT, never black


# Skill badges (SkillIcons, Milestone 1): one colour per skill, used for the badge disc and
# to tint that skill's toasts, XP bar and window header. Each echoes what the skill works on.
const SKILL_FELLING := Color(0.36, 0.56, 0.32) ## forest green: the trees you fell
const SKILL_QUARRYING := Color(0.42, 0.50, 0.62) ## cool slate blue: cut stone
const SKILL_TAPPING := Color(0.62, 0.24, 0.17) ## sap red-brown, close to SMOULDER: the seeps
const SKILL_TOOLCRAFT := Color(0.66, 0.48, 0.30) ## worked ash-wood: the bench and handles
const SKILL_PLAIN := Color(0.58, 0.56, 0.52) ## a skill with no badge of its own yet
const BADGE_INK := Color(0.16, 0.11, 0.09, 0.55) ## soft dark backing so a badge's emblem pops off its disc
const BADGE_STAR := Color(0.92, 0.88, 0.78) ## the plain badge's pale star

## Cloth a traveller could actually dye in Ashgrove: undyed wool, madder, woad, weld, walnut,
## lichen. Earthy, below 0.45 saturation, never bright primaries (art bible, "Characters").
const CLOTH := [
	Color(0.55, 0.50, 0.42), ## undyed wool
	Color(0.46, 0.24, 0.19), ## madder red
	Color(0.27, 0.33, 0.40), ## woad blue
	Color(0.52, 0.46, 0.27), ## weld yellow, faded
	Color(0.42, 0.32, 0.24), ## walnut brown
	Color(0.33, 0.37, 0.27), ## lichen green
	Color(0.40, 0.34, 0.36), ## sloe, a dusky plum
	Color(0.38, 0.37, 0.35), ## charcoal grey (the darkest cloth: a figure must still read from behind at night)
]


## Travelling gear (characters): what is worn over the dyed cloth.
const LEATHER := Color(0.40, 0.29, 0.20) ## packs, pouches, bracers: oiled brown leather
const LEATHER_DARK := Color(0.22, 0.17, 0.14) ## belts, straps, boots: old, dark leather
const WOOL := Color(0.47, 0.43, 0.37) ## undyed wool: mantles and hoods
const TROUSERS := Color(0.27, 0.25, 0.22) ## heavy wool trousers, faded charcoal-brown
const BEDROLL := Color(0.58, 0.52, 0.42) ## a rolled canvas blanket


## Natural hair (characters): black, browns, auburn, ash blond, grey. Never bright.
const HAIR := [
	Color(0.17, 0.14, 0.12), Color(0.24, 0.17, 0.12), Color(0.33, 0.23, 0.15),
	Color(0.38, 0.20, 0.12), Color(0.55, 0.47, 0.35), Color(0.52, 0.50, 0.48),
]


## Skin from three 0..1 draws: deep brown to fair, never orange and never glowing.
static func skin(a: float, b: float, c: float) -> Color:
	return Color.from_hsv(0.055 + a * 0.03, 0.30 + b * 0.18, 0.36 + c * 0.44)


## A character's tunic for an appearance seed: one of `CLOTH`, with a little seeded wear so two
## travellers in the same dye are not identical. Same seed, same tunic, on every machine.
static func cloth_from_seed(seed_value: int) -> Color:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var c: Color = CLOTH[rng.randi() % CLOTH.size()]
	return c.lightened(rng.randf() * 0.10) if rng.randf() < 0.5 else c.darkened(rng.randf() * 0.12)


## Stable, pleasant colour for a seed (banners, UI accents). Not for world cloth: use `cloth_from_seed`.
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


const COVER_SCALE := 38.0 ## metres: rough width of a moss or dry-grass patch
const EARTH_SCALE := 22.0 ## metres: bare-earth scuffs are smaller
const COVER_MAX := 0.65 ## a patch never fully replaces the ground under it: gentle, not a quilt
const EARTH_MAX := 0.60
static var _cover_noise: FastNoiseLite
static var _earth_noise: FastNoiseLite


## Ground colour at a world point: `ground()` plus ground cover. On grass, meadow and forest
## floor, low-frequency seeded noise lays patches of moss (more in the forest and by water),
## dry straw grass (more on the open valley floor) and small scuffs of bare earth (more on
## slopes). Same world, same patches, on every machine.
static func ground_at(x: float, z: float, h: float, slope: float, jitter: float) -> Color:
	var c := ground(h, slope, jitter)
	var w := cover_weights(x, z, h, slope)
	if w.is_empty():
		return c
	c = c.lerp(_jittered(MOSS, jitter), w.moss)
	c = c.lerp(_jittered(DRY_GRASS, jitter), w.dry)
	return c.lerp(_jittered(BARE_EARTH, jitter), w.earth)


## How much moss, dry grass and bare earth cover a point ({moss, dry, earth}, each 0..max),
## or an empty Dictionary where ground cover doesn't grow (shore, rock, snow).
static func cover_weights(x: float, z: float, h: float, slope: float) -> Dictionary:
	if h < Terrain.water_level() + 1.2 or h > 13.0 or slope > 0.55:
		return {}
	_ensure_cover()
	var n := _cover_noise.get_noise_2d(x, z) # -1..1, patches about COVER_SCALE across
	var forest := smoothstep(5.0, 7.0, h) # 0 on the open valley, 1 under the pines
	var shore := 1.0 - smoothstep(Terrain.water_level() + 1.2, Terrain.water_level() + 4.0, h)
	# The forest floor and the lake margins are damp: moss comes easier, straw harder.
	var moss_bias := 0.18 * forest + 0.15 * shore
	var dry_bias := 0.12 * (1.0 - forest) - 0.25 * forest - 0.15 * shore
	var moss := smoothstep(0.05, 0.70, n + moss_bias) * COVER_MAX
	var dry := smoothstep(0.05, 0.70, -n + dry_bias) * COVER_MAX
	var e := _earth_noise.get_noise_2d(x, z) + clampf((slope - 0.15) * 1.2, 0.0, 0.3)
	var earth := smoothstep(0.30, 0.85, e) * EARTH_MAX
	return {"moss": moss, "dry": dry, "earth": earth}


static func _jittered(c: Color, jitter: float) -> Color:
	return c.lightened(jitter) if jitter > 0.0 else c.darkened(-jitter)


static func _ensure_cover() -> void:
	if _cover_noise != null:
		return
	_cover_noise = FastNoiseLite.new()
	_cover_noise.seed = GameConfig.WORLD_SEED + 7121
	_cover_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_cover_noise.frequency = 1.0 / COVER_SCALE
	_cover_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	_cover_noise.fractal_octaves = 2
	_earth_noise = FastNoiseLite.new()
	_earth_noise.seed = GameConfig.WORLD_SEED + 9343
	_earth_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_earth_noise.frequency = 1.0 / EARTH_SCALE
	_earth_noise.fractal_type = FastNoiseLite.FRACTAL_NONE
