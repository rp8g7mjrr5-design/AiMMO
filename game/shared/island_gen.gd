class_name IslandGen
## Generator v2: the island (owner, 2026-11-26: "Lets do an island", 3 km, wash up on a
## random beach with nothing, every place rolls random so it never looks the same).
##
## WorldGen owns the config and the public API; for `gen_version` 2 it hands the layout and
## the land to this file. The layout lives in WorldGen's own `_L` Dictionary with the same keys
## version 1 uses (`half`, `dim`, `pads`, `lakes`, `river_d`, `road_d`, `ruins`, `roads`,
## `spawn`, `wobble`, ...), so WorldGen's shared helpers (pads, rasters, roads, node spots)
## work on both. Version 2 adds `landings`, `rivers` (several) and `road_kinds`.
##
## The island, in order:
## 1. The shape: a ragged island in the middle of the square, sea all round, a few cliff
##    coasts, flat beaches elsewhere. "Inland" runs 0 at the shore to 1 at the island's heart.
## 2. The land in bands: meadows and farmland by the sea, forest and moor in the middle,
##    stone hills and snowy peaks around the heart (which sits a little off centre).
## 3. Rivers from the high ground to the sea (1 on a small island, 2 or 3 on bigger ones),
##    and lakes in the middle band.
## 4. Landings: 4 to 8 beach spots spread round the coast, where new characters wash up.
## 5. Locations from the pool in LOCATIONS: the must-haves first, then a random mix, each
##    only where its rules fit; danger (grade) rises with how far inland it is. Each site gets
##    its own `layout_seed` and `rot`, so the set piece built on it differs every world.
## 6. Roads: a spanning tree over landings and locations (water crossings cost more), plus
##    a loop; links to grade 1 places are tracks, the rest king's roads. Wrecked carts last,
##    on the roads.
## Plain data and pure functions only (the server reads this file). Frozen once a live
## world runs on it: new looks go in a new gen_version.
##
## Version 3 (`L.v` 3, owner 2026-11-28: "The map feels really flat ... We need to have
## different types of biomes ... forests and flatlands and others") keeps every step above
## and changes only the land and the biomes (`_land3`, `_biome3`): meadows stay low and gently
## rolling by the sea, broadleaf forest rolls a little more, **pine hills** rise in patches as
## real 15 to 40 m hills, **marsh** lies flat and wet along stretches of river and lake shore
## with pools in it, the moor rolls in long swells, and the heart's crags stand twice as tall.
## Version 2 islands are untouched (their branches are the old code, line for line).

const SIZE_MIN := 1500.0
const SIZE_MAX := 4000.0
const SIZE_DEFAULT := 3000.0
## Server setting "Map size" (vision, "Server rules").
const SIZES := {"small": 1500.0, "medium": 3000.0, "large": 4000.0}

const ISLAND_RADIUS := 0.84 ## the island's mean radius, as a fraction of the half size
const SEA_DEPTH := -10.0
const BEACH_H := 0.9 ## the flat beach band's height above the sea
const HEART_REACH := 0.62 ## mountains rise within this fraction of the radius from the heart
const LANDING_R := 10.0
const LANDING_BLEND := 24.0
const REF_AREA := 9.0e6 ## counts in LOCATIONS are for a 3 km island (9 km²)
const SPACING := 150.0 ## metres between two locations' edges on a 3 km island
const SPACING_HIGH := 300.0 ## between two grade 3 or 4 locations

## Version 3's land (owner 2026-11-28). Heights in metres.
const V3_BASE_RISE := 8.0 ## how much the land rises from the shore to the heart
const V3_SWELL := Vector2(1.2, 9.0) ## broad swells: this high by the sea, this high at the heart
const V3_HILL_FLOOR := 9.0 ## a pine-hill patch's lowest hill
const V3_HILL_PEAK := 30.0 ## and how much more its tallest crests add
const V3_MOUNT := Vector2(16.0, 46.0) ## the heart: its base lift, and its crags on top
const V3_MARSH_H := 1.0 ## the marsh floor's mean height above the water
const V3_POOL := 2.4 ## how deep the pool noise cuts (anything under the water is a pool)
const V3_MARSH_NEAR := Vector2(30.0, 160.0) ## metres from a river or lake where marsh fades out
const V3_SITE_SLACK := 0.28 ## a site's pad may sit on ground this much (x its radius) more uneven than v2's

## The location pool (the map plan, 2026-11-26). Each entry:
## grade, radius (the flat pad, metres), band (inland range), ground (biomes it may stand on,
## empty = any land), near ("river", "shore" or ""), count (on a 3 km island, scaled by area
## and rolled +-40%), must (at least this many on every island), chance (of appearing at all).
## Data only: a new kind is a new entry here plus a label in Ruins.LABELS.
const LOCATIONS := {
	"fallen_castle": {"grade": 4, "radius": 60.0, "band": [0.55, 0.9], "ground": [], "near": "", "count": 1.0, "must": 1},
	"market_town": {"grade": 3, "radius": 70.0, "band": [0.35, 0.7], "ground": ["farmland", "forest", "moor"], "near": "", "count": 1.0, "must": 1},
	"old_mine": {"grade": 3, "radius": 26.0, "band": [0.5, 0.95], "ground": ["stone_hills"], "near": "", "count": 2.0, "must": 1},
	"walled_abbey": {"grade": 3, "radius": 38.0, "band": [0.45, 0.85], "ground": ["moor", "forest", "farmland"], "near": "", "count": 1.0, "must": 0},
	"garrison_fort": {"grade": 3, "radius": 45.0, "band": [0.55, 0.9], "ground": [], "near": "", "count": 1.0, "must": 0},
	"abandoned_village": {"grade": 2, "radius": 42.0, "band": [0.2, 0.55], "ground": ["farmland", "forest", "moor"], "near": "", "count": 3.0, "must": 1},
	"barber_surgeon": {"grade": 2, "radius": 14.0, "band": [0.12, 0.45], "ground": [], "near": "", "count": 2.0, "must": 1},
	"watermill": {"grade": 2, "radius": 18.0, "band": [0.12, 0.65], "ground": [], "near": "river", "count": 2.0, "must": 0},
	"toll_bridge": {"grade": 2, "radius": 16.0, "band": [0.2, 0.7], "ground": [], "near": "river", "count": 1.0, "must": 0},
	"watchtower": {"grade": 2, "radius": 14.0, "band": [0.25, 0.6], "ground": [], "near": "", "count": 2.0, "must": 0},
	"shepherds_fold": {"grade": 2, "radius": 20.0, "band": [0.3, 0.65], "ground": ["moor"], "near": "", "count": 2.0, "must": 0},
	"burned_farmstead": {"grade": 1, "radius": 22.0, "band": [0.05, 0.35], "ground": ["farmland"], "near": "", "count": 4.0, "must": 1},
	"woodcutters_hut": {"grade": 1, "radius": 12.0, "band": [0.05, 0.45], "ground": ["forest"], "near": "", "count": 3.0, "must": 0},
	"fishers_hut": {"grade": 1, "radius": 10.0, "band": [0.0, 0.14], "ground": [], "near": "shore", "count": 3.0, "must": 0},
	"roadside_shrine": {"grade": 1, "radius": 9.0, "band": [0.05, 0.5], "ground": [], "near": "", "count": 2.0, "must": 0},
	## The old Spawn Meadow, now one more place you might stumble on (owner, 2026-11-26).
	"old_meadow": {"grade": 1, "radius": 30.0, "band": [0.1, 0.45], "ground": ["farmland", "forest"], "near": "", "count": 1.0, "must": 0, "chance": 0.7},
}
## Placed after the roads, on them.
const CART := {"kind": "wrecked_cart", "grade": 1, "radius": 6.0, "count": 4.0}


# ---------------------------------------------------------------------------------------
# Layout

## Fills WorldGen's layout `L` for an island of `size` metres from `seed`. Called once per
## config by WorldGen._build_layout.
static func build(L: Dictionary, seed: int, size: float) -> void:
	var half := size * 0.5
	L.rim = "island"
	L.radius = half * ISLAND_RADIUS
	L.coast_n = _ang_noise(seed + 11)
	L.cliff_n = _ang_noise(seed + 12)
	L.bays = WorldGen._noise(13, 2.2 / size, 2)
	L.landings = []
	L.rivers = []
	L.road_kinds = []
	var rng := RandomNumberGenerator.new()
	rng.seed = seed * 6151 + 29
	L.center = Vector2(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0)) * half * 0.04
	L.heart = L.center + Vector2.from_angle(rng.randf() * TAU) * L.radius * rng.randf_range(0.05, 0.2)
	if int(L.get("v", 2)) >= 3:
		# Own seed offsets (20+), so version 2's noises and rng draws are unchanged.
		L.hills = WorldGen._noise(20, 1.0 / 1000.0, 2) ## where the pine hills are
		L.knolls = WorldGen._noise(21, 1.0 / 200.0, 3) ## the hills themselves
		L.swell = WorldGen._noise(22, 1.0 / 420.0, 2) ## broad rolls everywhere
		L.fen = WorldGen._noise(23, 1.0 / 520.0, 2) ## where the marsh is
		L.pool = WorldGen._noise(24, 1.0 / 38.0, 2) ## the marsh's pools and hummocks
	_place_lakes(L, rng, size)
	_place_rivers(L, rng, size)
	_place_landings(L, rng, size)
	L.spawn = (L.landings[0] as Vector2) if not L.landings.is_empty() else L.center
	L.spawn_ang = ((L.spawn as Vector2) - (L.center as Vector2)).angle()
	_place_locations(L, rng, size)
	_place_roads(L, rng, size)
	_place_carts(L, rng, size)
	WorldGen._index_pads(L)


## Smooth noise around the coast: sample it at (cos a, sin a) for angle a.
static func _ang_noise(s: int) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = s
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = 1.0
	n.fractal_type = FastNoiseLite.FRACTAL_FBM
	n.fractal_octaves = 3
	return n


static func _ang(n: FastNoiseLite, a: float) -> float:
	return n.get_noise_2d(cos(a) * 1.4, sin(a) * 1.4)


# ---------------------------------------------------------------------------------------
# Shape and land

## How far out (x, z) lies: under 1 on the island, over 1 at sea. The square's edge is
## always sea.
static func shape(L: Dictionary, x: float, z: float) -> float:
	var p := Vector2(x, z) - (L.center as Vector2)
	var a := p.angle()
	var r: float = L.radius * (1.0 + 0.26 * _ang(L.coast_n, a)) + L.half * 0.08 * (L.bays as FastNoiseLite).get_noise_2d(x, z)
	var s := p.length() / maxf(r, 1.0)
	var edge := maxf(absf(x), absf(z)) / (L.half as float) / 0.95
	return maxf(s, edge)


## 0 at the shore, 1 at the island's centre (0 at sea).
static func inland(L: Dictionary, x: float, z: float) -> float:
	return clampf(1.0 - shape(L, x, z), 0.0, 1.0)


## 0..1: how much of a cliff the coast is at (x, z).
static func cliff(L: Dictionary, x: float, z: float) -> float:
	var a := (Vector2(x, z) - (L.center as Vector2)).angle()
	return smoothstep(0.18, 0.45, _ang(L.cliff_n, a))


## The land before the flat pads.
static func land(L: Dictionary, x: float, z: float) -> float:
	if int(L.get("v", 2)) >= 3:
		return _land3(L, x, z)
	var s := shape(L, x, z)
	var inl := clampf(1.0 - s, 0.0, 1.0)
	var u := WorldGen._uplift(x, z)
	var road_k := 1.0 - smoothstep(WorldGen.ROAD_HALF_WIDTH, WorldGen.ROAD_SOFT, WorldGen._sample(L.road_d, x, z))
	var soft := 1.0 - 0.85 * road_k
	var detail: float = (L.detail as FastNoiseLite).get_noise_2d(x, z) * (2.5 + 5.0 * u)
	var rr := 1.0 - absf((L.ridge as FastNoiseLite).get_noise_2d(x, z))
	var dh: float = Vector2(x, z).distance_to(L.heart) / (L.radius * HEART_REACH)
	var mount := smoothstep(0.0, 1.0, 1.0 - dh)
	var h := 2.0 + 9.0 * inl + 6.0 * u * inl + mount * (12.0 + 30.0 * rr * rr * rr * (0.5 + 0.7 * u)) * soft + detail * soft
	# The coast: a flat beach band, or a cliff where the cliff noise says so, then the sea.
	var c := cliff(L, x, z)
	var beach := smoothstep(0.93, 0.99, s) * (1.0 - c)
	h = lerpf(h, BEACH_H, beach)
	var sea := smoothstep(0.995, 1.08 - 0.05 * c, s)
	h = lerpf(h, SEA_DEPTH, sea)
	for l in L.lakes:
		var d: float = Vector2(x, z).distance_to(l.center)
		var lr: float = l.radius * (1.0 + (L.wobble as FastNoiseLite).get_noise_2d(x * 2.0, z * 2.0) * 0.15)
		var k := 1.0 - smoothstep(lr * 0.55, lr * 1.15 + 6.0, d)
		if k > 0.0:
			h = lerpf(h, WorldGen.LAKE_BED, k)
	var rd := WorldGen._sample(L.river_d, x, z)
	if rd < WorldGen.RIVER_CAP:
		var bank := clampf(10.0 + 0.5 * maxf(h - WorldGen.KINGDOM_WATER, 0.0), 10.0, 40.0)
		var k := 1.0 - smoothstep(WorldGen.RIVER_HALF_WIDTH, WorldGen.RIVER_HALF_WIDTH + bank, rd)
		h = lerpf(h, minf(h, WorldGen.RIVER_BED), k)
	return h


## The biome at (x, z) with ground height h: water, shore, snow or one of WorldGen.BIOMES.
## Bands by how far inland, broken up by moisture.
static func biome_for(L: Dictionary, x: float, z: float, h: float) -> String:
	if h < WorldGen.KINGDOM_WATER - 0.2:
		return "water"
	if int(L.get("v", 2)) >= 3:
		return _biome3(L, x, z, h)
	var inl := inland(L, x, z) + (L.wobble as FastNoiseLite).get_noise_2d(x * 1.3, z * 1.3) * 0.06
	if h < WorldGen.KINGDOM_WATER + 1.0 or (h < 2.2 and inl < 0.06):
		return "shore"
	if h > WorldGen.SNOW_LINE:
		return "snow"
	var u := WorldGen._uplift(x, z)
	if h > WorldGen.SNOW_LINE - 9.0 or (u > 0.74 and inl > 0.4):
		return "stone_hills"
	var m: float = (L.moist as FastNoiseLite).get_noise_2d(x, z)
	if inl < 0.3:
		return "forest" if m > 0.2 else "farmland"
	if inl < 0.6:
		return "forest" if m > -0.1 else "moor"
	return "moor" if m < 0.05 else "forest"


## How far up an island's beach (x, z) is: 0 out where the sea starts (the outline's 1.07, past
## its 1.0, since the beach runs on beyond it) to 1 at the back of the sand where the "shore"
## biome ends (inland 0.06, with biome_for's wobble).
static func beach_depth(L: Dictionary, x: float, z: float) -> float:
	var inl := 1.0 - shape(L, x, z) + (L.wobble as FastNoiseLite).get_noise_2d(x * 1.3, z * 1.3) * 0.06
	return clampf((inl + 0.07) / 0.13, 0.0, 1.0)


## How far (x, z) with ground height h is past the beach: 0 at the sand's edge (and on it),
## 1 a band inland (about 0.8 m up or about a seventieth of the way to the heart, whichever the edge
## is made of). Same rule and wobble as biome_for's "shore", so the two always agree.
static func sand_margin(L: Dictionary, x: float, z: float, h: float) -> float:
	var inl := inland(L, x, z) + (L.wobble as FastNoiseLite).get_noise_2d(x * 1.3, z * 1.3) * 0.06
	var low := (h - (WorldGen.KINGDOM_WATER + 1.0)) / 0.8
	var coast := maxf((h - 2.2) / 0.8, (inl - 0.06) / 0.014)
	return clampf(minf(low, coast), 0.0, 1.0)


# ---------------------------------------------------------------------------------------
# Version 3: biomes with their own relief (owner 2026-11-28)

## How much of a pine-hill patch (x, z) is in, 0..1: patches of the hills noise, never on the
## coast's first band nor in the heart's crags (which have their own relief).
static func hill_weight(L: Dictionary, x: float, z: float, inl: float, mount: float) -> float:
	var n: float = (L.hills as FastNoiseLite).get_noise_2d(x, z)
	return smoothstep(0.02, 0.24, n) * smoothstep(0.10, 0.30, inl) * (1.0 - mount)


## 0..1: how close the heart is (the crags), as version 2's `mount`.
static func _mount(L: Dictionary, x: float, z: float) -> float:
	var dh: float = Vector2(x, z).distance_to(L.heart) / (L.radius * HEART_REACH)
	return smoothstep(0.0, 1.0, 1.0 - dh)


## How much of a marsh (x, z) is, 0..1: where the fen noise is high, mostly along rivers and
## lake shores, on low ground (not the hills, the heart or the beach).
static func marsh_weight(L: Dictionary, x: float, z: float, inl: float, hill: float, mount: float) -> float:
	var f: float = (L.fen as FastNoiseLite).get_noise_2d(x, z)
	var fen := smoothstep(0.08, 0.30, f)
	if fen <= 0.0:
		return 0.0
	var d := WorldGen._sample(L.river_d, x, z)
	for l in L.lakes:
		d = minf(d, Vector2(x, z).distance_to(l.center) - float(l.radius))
	var near := 1.0 - smoothstep(V3_MARSH_NEAR.x, V3_MARSH_NEAR.y, d)
	# Strong fen marks a marsh even away from water (a fen in a hollow); weak needs a river.
	var w := fen * maxf(near, smoothstep(0.30, 0.45, f) * 0.85)
	w *= smoothstep(0.07, 0.14, inl) * (1.0 - smoothstep(0.45, 0.62, inl))
	return w * (1.0 - hill) * (1.0 - mount)


static func _land3(L: Dictionary, x: float, z: float) -> float:
	var s := shape(L, x, z)
	var inl := clampf(1.0 - s, 0.0, 1.0)
	var u := WorldGen._uplift(x, z)
	var road_k := 1.0 - smoothstep(WorldGen.ROAD_HALF_WIDTH, WorldGen.ROAD_SOFT, WorldGen._sample(L.road_d, x, z))
	var soft := 1.0 - 0.85 * road_k # only the small bumps go: the roads climb the hills, never cut trenches
	var detail: float = (L.detail as FastNoiseLite).get_noise_2d(x, z) * (1.0 + 3.0 * u * inl)
	var swell: float = (L.swell as FastNoiseLite).get_noise_2d(x, z) * lerpf(V3_SWELL.x, V3_SWELL.y, smoothstep(0.05, 0.6, inl))
	var mount := _mount(L, x, z)
	var rr := 1.0 - absf((L.ridge as FastNoiseLite).get_noise_2d(x, z))
	var crags := mount * (V3_MOUNT.x + V3_MOUNT.y * rr * rr * rr * (0.5 + 0.7 * u))
	var hill := hill_weight(L, x, z, inl, mount)
	var hills := 0.0
	if hill > 0.0:
		var b := 1.0 - absf((L.knolls as FastNoiseLite).get_noise_2d(x, z)) # rounded crests
		hills = hill * (V3_HILL_FLOOR + V3_HILL_PEAK * b * b)
	var h := 2.0 + V3_BASE_RISE * inl + swell + hills + crags + detail * soft
	var wet := marsh_weight(L, x, z, inl, hill, mount)
	if wet > 0.0:
		var pool: float = (L.pool as FastNoiseLite).get_noise_2d(x, z)
		h = lerpf(h, V3_MARSH_H + pool * V3_POOL, smoothstep(0.0, 0.7, wet))
	# The coast, the lakes and the rivers, as version 2.
	var c := cliff(L, x, z)
	var beach := smoothstep(0.93, 0.99, s) * (1.0 - c)
	h = lerpf(h, BEACH_H, beach)
	var sea := smoothstep(0.995, 1.08 - 0.05 * c, s)
	h = lerpf(h, SEA_DEPTH, sea)
	for l in L.lakes:
		var d: float = Vector2(x, z).distance_to(l.center)
		var lr: float = l.radius * (1.0 + (L.wobble as FastNoiseLite).get_noise_2d(x * 2.0, z * 2.0) * 0.15)
		var k := 1.0 - smoothstep(lr * 0.55, lr * 1.15 + 6.0, d)
		if k > 0.0:
			h = lerpf(h, WorldGen.LAKE_BED, k)
	var rd := WorldGen._sample(L.river_d, x, z)
	if rd < WorldGen.RIVER_CAP:
		var bank := clampf(10.0 + 0.5 * maxf(h - WorldGen.KINGDOM_WATER, 0.0), 10.0, 40.0)
		var k := 1.0 - smoothstep(WorldGen.RIVER_HALF_WIDTH, WorldGen.RIVER_HALF_WIDTH + bank, rd)
		h = lerpf(h, minf(h, WorldGen.RIVER_BED), k)
	return h


## Version 3's biomes. Water, shore and snow as version 2; then the crags (stone hills), the
## marsh, the pine hills, and the lowland by moisture: meadow ("farmland") by the sea, broadleaf
## forest in the damp, moor further in.
static func _biome3(L: Dictionary, x: float, z: float, h: float) -> String:
	var inl := inland(L, x, z) + (L.wobble as FastNoiseLite).get_noise_2d(x * 1.3, z * 1.3) * 0.06
	if h < WorldGen.KINGDOM_WATER + 1.0 or (h < 2.2 and inl < 0.06):
		# Low ground inland in a marsh is marsh (its hummocks), not beach.
		if inl > 0.08 and h > WorldGen.KINGDOM_WATER - 0.2:
			var i0 := inland(L, x, z)
			var m0 := _mount(L, x, z)
			if marsh_weight(L, x, z, i0, hill_weight(L, x, z, i0, m0), m0) > 0.35:
				return "marsh"
		return "shore"
	var i := inland(L, x, z)
	var mount := _mount(L, x, z)
	if h > WorldGen.SNOW_LINE:
		# Old snow on the heart's peaks only; a pine hill's crest that high is bare rock.
		return "snow" if mount > 0.25 else "stone_hills"
	var u := WorldGen._uplift(x, z)
	if (mount > 0.25 and h > WorldGen.SNOW_LINE - 11.0) or (mount > 0.35 and h > 22.0 + 6.0 * u):
		return "stone_hills"
	var hill := hill_weight(L, x, z, i, mount)
	if marsh_weight(L, x, z, i, hill, mount) > 0.35:
		return "marsh"
	if hill > 0.4:
		return "pine_hills"
	var m: float = (L.moist as FastNoiseLite).get_noise_2d(x, z)
	if inl < 0.32:
		return "forest" if m > 0.22 else "farmland"
	if inl < 0.6:
		return "forest" if m > -0.05 else "moor"
	return "moor" if m < 0.05 else "forest"


# ---------------------------------------------------------------------------------------
# Water

static func _place_lakes(L: Dictionary, rng: RandomNumberGenerator, size: float) -> void:
	var want := clampi(int(round(size * size / REF_AREA * 2.0)) + rng.randi_range(0, 1), 1, 4)
	var tries := 0
	while L.lakes.size() < want and tries < 300:
		tries += 1
		var r := rng.randf_range(26.0, 60.0)
		var p: Vector2 = L.center + Vector2.from_angle(rng.randf() * TAU) * L.radius * rng.randf_range(0.3, 0.75)
		var inl := inland(L, p.x, p.y)
		if inl < 0.25 or inl > 0.65:
			continue
		if land(L, p.x, p.y) > 16.0:
			continue
		var ok := true
		for l in L.lakes:
			if p.distance_to(l.center) < l.radius + r + 120.0:
				ok = false
		if ok:
			L.lakes.append({"center": p, "radius": r})


static func _place_rivers(L: Dictionary, rng: RandomNumberGenerator, size: float) -> void:
	var want := 1 if size < 2000.0 else (2 if size < 3500.0 else 3)
	var base := rng.randf() * TAU
	for i in want:
		var a := base + TAU * float(i) / want + rng.randf_range(-0.5, 0.5)
		var src: Vector2 = L.heart + Vector2.from_angle(a + rng.randf_range(-0.4, 0.4)) * L.radius * rng.randf_range(0.25, 0.4)
		# The mouth: walk out along the angle until the sea.
		var mouth: Vector2 = L.center
		var dir := Vector2.from_angle(a)
		var r: float = L.radius * 0.5
		while r < L.half * 1.4:
			mouth = (L.center as Vector2) + dir * r
			if shape(L, mouth.x, mouth.y) > 1.04:
				break
			r += 8.0
		var length := src.distance_to(mouth)
		var n := maxi(8, int(length / 40.0))
		var d := (mouth - src) / maxf(length, 1.0)
		var side := Vector2(-d.y, d.x)
		var phase := rng.randf() * 1000.0
		var pts := PackedVector2Array()
		for k in n + 1:
			var t := float(k) / n
			var p := src.lerp(mouth, t)
			p += side * (L.wobble as FastNoiseLite).get_noise_2d(phase + t * 900.0, 0.0) * 1.6 * minf(90.0, length * 0.08) * sin(PI * t)
			pts.append(p)
		L.rivers.append(pts)
		WorldGen._stamp(L.river_d, pts, WorldGen.RIVER_CAP)
	L.river = L.rivers[0]


# ---------------------------------------------------------------------------------------
# Landings

static func _place_landings(L: Dictionary, rng: RandomNumberGenerator, size: float) -> void:
	var n := clampi(int(round(size / 450.0)), 4, 8)
	var base := rng.randf() * TAU
	for i in n:
		var best := Vector2.INF
		for attempt in 40:
			var a := base + TAU * (float(i) + rng.randf_range(-0.3, 0.3)) / n
			if attempt >= 12:
				a += rng.randf_range(-0.4, 0.4) * TAU / n
			var p := _beach_on_ray(L, a)
			if p == Vector2.INF:
				continue
			if _landing_ok(L, p):
				best = p
				break
		if best == Vector2.INF:
			continue
		L.landings.append(best)
		L.pads.append({"c": best, "r": LANDING_R, "blend": LANDING_BLEND, "h": maxf(land(L, best.x, best.y), 1.4)})


## The first dry beach spot walking out from the centre along angle `a`, a little inland of
## the waterline, or Vector2.INF if this stretch is a cliff.
static func _beach_on_ray(L: Dictionary, a: float) -> Vector2:
	var dir := Vector2.from_angle(a)
	var r: float = L.radius * 0.6
	var last_dry := Vector2.INF
	var last_r := 0.0
	while r < L.half * 1.4:
		var p: Vector2 = (L.center as Vector2) + dir * r
		var h := land(L, p.x, p.y)
		if h < WorldGen.KINGDOM_WATER + 0.3:
			if shape(L, p.x, p.y) > 0.95:
				break # the sea
			last_dry = Vector2.INF # a river or a lake: keep walking
		elif h < 4.5:
			if last_dry == Vector2.INF or r - last_r > 4.5:
				last_dry = p
			last_r = r
		else:
			last_dry = Vector2.INF
		r += 4.0
	if last_dry == Vector2.INF or r - last_r > 40.0:
		return Vector2.INF # a cliff coast, or no low ground by the water
	return (L.center as Vector2) + dir * maxf(last_r - 14.0, 0.0)


static func _landing_ok(L: Dictionary, p: Vector2) -> bool:
	if cliff(L, p.x, p.y) > 0.25:
		return false
	var h := land(L, p.x, p.y)
	if h < 0.6 or h > 5.0:
		return false
	if WorldGen._water_gap(p) < 30.0:
		return false
	for q in L.landings:
		if p.distance_to(q) < 200.0:
			return false
	return true


# ---------------------------------------------------------------------------------------
# Locations

## The plan: [kind, ...] with the must-haves first (deadliest first), then the random mix
## shuffled. Counts scale with the island's area and roll +-40%.
static func _plan(rng: RandomNumberGenerator, size: float) -> Array:
	var area := size * size / REF_AREA
	var musts: Array = []
	var extra: Array = []
	for g in [4, 3, 2, 1]:
		for kind in LOCATIONS:
			var e: Dictionary = LOCATIONS[kind]
			if int(e.grade) != g:
				continue
			var chance := float(e.get("chance", 1.0))
			var want := int(round(float(e.count) * area * rng.randf_range(0.6, 1.4)))
			if rng.randf() >= chance:
				want = 0
			if kind == "fallen_castle":
				want = 1 if size < 3500.0 else 2
			want = maxi(want, int(e.must))
			for i in want:
				(musts if i < int(e.must) else extra).append(kind)
	# Shuffle the extras with our own rng (Array.shuffle uses the global one).
	for i in range(extra.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = extra[i]
		extra[i] = extra[j]
		extra[j] = t
	return musts + extra


static func _place_locations(L: Dictionary, rng: RandomNumberGenerator, size: float) -> void:
	var spacing := SPACING * clampf(size / SIZE_DEFAULT, 0.6, 1.0)
	var id := 0
	for kind in _plan(rng, size):
		var e: Dictionary = LOCATIONS[kind]
		var site := _find_site(L, rng, kind, e, spacing)
		if site.is_empty():
			continue
		site.id = id
		_add_site(L, site)
		id += 1


static func _find_site(L: Dictionary, rng: RandomNumberGenerator, kind: String, e: Dictionary, spacing: float) -> Dictionary:
	var r := float(e.radius)
	var band: Array = e.band
	var near := str(e.near)
	for attempt in 500:
		var slack := attempt / 500.0 * 0.12 # widen the band a little when it's hard
		var p: Vector2
		if near == "river" and not L.rivers.is_empty():
			var line: PackedVector2Array = L.rivers[rng.randi() % L.rivers.size()]
			var k := rng.randi_range(1, line.size() - 2)
			var along := line[k + 1] - line[k]
			var off := Vector2(-along.y, along.x).normalized() * (r + rng.randf_range(12.0, 30.0)) * (1.0 if rng.randf() < 0.5 else -1.0)
			p = line[k] + off
		else:
			p = (L.center as Vector2) + Vector2.from_angle(rng.randf() * TAU) * L.radius * sqrt(rng.randf()) * 1.05
		var inl := inland(L, p.x, p.y)
		if inl < float(band[0]) - slack or inl > float(band[1]) + slack:
			continue
		if not _site_ok(L, p, r, int(e.grade), near, e.ground, spacing):
			continue
		return {"kind": kind, "grade": int(e.grade), "pos": p, "radius": r,
			"layout_seed": rng.randi() & 0x7FFFFFFF, "rot": rng.randf() * TAU}
	return {}


static func _site_ok(L: Dictionary, p: Vector2, r: float, grade: int, near: String, ground: Array, spacing: float) -> bool:
	var h := land(L, p.x, p.y)
	if h < 1.5 or h > WorldGen.SNOW_LINE - 10.0:
		return false
	if shape(L, p.x, p.y) > 0.97:
		return false
	if not ground.is_empty() and not ground.has(biome_for(L, p.x, p.y, h)):
		return false
	var gap := WorldGen._water_gap(p)
	if near == "river":
		if gap < r + 4.0 or WorldGen._sample(L.river_d, p.x, p.y) > r + 45.0:
			return false
	elif gap < r + 8.0:
		return false
	if near == "shore":
		var sea := false
		for k in 8:
			var q := p + Vector2.from_angle(TAU * k / 8.0) * (r + 40.0)
			if land(L, q.x, q.y) < WorldGen.KINGDOM_WATER:
				sea = true
				break
		if not sea:
			return false
	for pad in L.pads:
		var g := spacing
		if grade >= 3 and int(pad.get("grade", 0)) >= 3:
			g = SPACING_HIGH * spacing / SPACING
		if p.distance_to(pad.c) < pad.r + r + g:
			return false
	var even := 6.0 + r * (0.12 + (V3_SITE_SLACK if int(L.get("v", 2)) >= 3 else 0.0))
	for k in 6:
		var q := p + Vector2.from_angle(TAU * k / 6.0) * r
		if absf(land(L, q.x, q.y) - h) > even:
			return false
	return true


static func _add_site(L: Dictionary, site: Dictionary) -> void:
	var c: Vector2 = site.pos
	var r: float = site.radius
	var ph := land(L, c.x, c.y)
	var blend := clampf(WorldGen._water_gap(c) - r - 2.0, 6.0, r * 0.8 + 14.0)
	L.pads.append({"c": c, "r": r, "blend": blend, "h": ph, "grade": site.grade})
	site.pos = Vector3(c.x, ph, c.y)
	L.ruins.append(site)


# ---------------------------------------------------------------------------------------
# Roads and carts

static func _place_roads(L: Dictionary, rng: RandomNumberGenerator, size: float) -> void:
	var pts: Array = []
	var grades: Array = []
	for q in L.landings:
		pts.append(q)
		grades.append(0)
	for s in L.ruins:
		pts.append(Vector2(s.pos.x, s.pos.z))
		grades.append(int(s.grade))
	var n := pts.size()
	if n < 2:
		return
	var cost := func(a: int, b: int) -> float:
		var pa: Vector2 = pts[a]
		var pb: Vector2 = pts[b]
		var wet := 0
		for k in range(1, 12):
			var q := pa.lerp(pb, k / 12.0)
			if land(L, q.x, q.y) < WorldGen.KINGDOM_WATER + 0.5:
				wet += 1
		return pa.distance_to(pb) * (1.0 + wet * 0.8)
	var linked := {0: true}
	var edges: Array = []
	while linked.size() < n:
		var best := [-1, -1, INF]
		for a in linked.keys():
			for b in n:
				if linked.has(b):
					continue
				var d: float = (pts[a] as Vector2).distance_to(pts[b])
				if d > best[2]:
					continue
				d = cost.call(a, b)
				if d < best[2]:
					best = [a, b, d]
		linked[best[1]] = true
		edges.append([best[0], best[1]])
	# One extra link closes a loop between two grade 2+ places, so the heart has two ways in.
	var extra := [-1, -1, INF]
	for a in n:
		for b in range(a + 1, n):
			if grades[a] < 2 or grades[b] < 2:
				continue
			var used := false
			for e in edges:
				if (e[0] == a and e[1] == b) or (e[0] == b and e[1] == a):
					used = true
			var d: float = (pts[a] as Vector2).distance_to(pts[b])
			if not used and d < extra[2] and d < L.half * 0.6:
				extra = [a, b, d]
	if extra[0] >= 0:
		edges.append([extra[0], extra[1]])
	for e in edges:
		var line := WorldGen._road_line(rng, pts[e[0]], pts[e[1]])
		L.roads.append(line)
		var track: bool = grades[e[0]] == 1 or grades[e[1]] == 1
		L.road_kinds.append("track" if track else "king")
		WorldGen._stamp(L.road_d, line, WorldGen.ROAD_CAP)


static func _place_carts(L: Dictionary, rng: RandomNumberGenerator, size: float) -> void:
	if L.roads.is_empty():
		return
	var want := maxi(1, int(round(float(CART.count) * size * size / REF_AREA * rng.randf_range(0.6, 1.4))))
	var r: float = CART.radius
	var placed := 0
	var id: int = L.ruins.size()
	for attempt in want * 40:
		if placed >= want:
			break
		var line: PackedVector2Array = L.roads[rng.randi() % L.roads.size()]
		var p := line[rng.randi_range(0, line.size() - 1)]
		var h := land(L, p.x, p.y)
		if h < 1.5 or h > WorldGen.SNOW_LINE - 10.0 or inland(L, p.x, p.y) > 0.65:
			continue
		var ok := WorldGen._water_gap(p) > r + 6.0
		for pad in L.pads:
			if ok and p.distance_to(pad.c) < pad.r + r + 80.0:
				ok = false
		if not ok:
			continue
		_add_site(L, {"id": id, "kind": CART.kind, "grade": 1, "pos": p, "radius": r,
			"layout_seed": rng.randi() & 0x7FFFFFFF, "rot": rng.randf() * TAU})
		id += 1
		placed += 1
