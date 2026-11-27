class_name WorldGen
## The world config and the kingdom generator (Phase 1, "A kingdom from a seed").
##
## A world is named by three numbers: `seed`, `size_m` (edge length in metres) and
## `gen_version`. Server and client run the same pure functions on them, so a server sends
## the config and never terrain.
##
## - `gen_version` 0 is Ashgrove, the hand-tuned 512 m valley the live world runs on. It
##   ignores `seed` and `size_m` and is bit-identical to the terrain before this file existed
##   (Terrain.height keeps its own code path for it). It stays the default.
## - `gen_version` 2 is the island (`IslandGen`, owner 2026-11-26): sea all round, 1.5 to 4 km
##   (3 km by default), beach landings instead of a spawn plot, and locations rolled from a
##   pool with their own layout seeds. It reuses this file's helpers through the same `_L`.
## - `gen_version` 1 is a generated stretch of the fallen kingdom, about 1 to 1.5 km across:
##   a rim of hills (or hills and a coast), a river to the sea or a lake, lakes, forest, moor,
##   wild farmland and stone hills, the king's roads between graded ruin sites, and a flat
##   spawn plot. It also hands out plain placement data (node spots per kind, ruin sites with
##   grades and kinds, roads, rivers, lakes, the spawn point) for gameplay to place things.
##
## Plain data and pure functions only: no visual classes (the server reads this file).
## Everything comes from the seed through seeded RandomNumberGenerator and FastNoiseLite, in a
## fixed order, so the same config always gives the same world. Changing what version 1 makes
## for a seed changes live worlds once one runs on it: from then on, new looks go in a new
## `gen_version` and old versions stay frozen.

const ASHGROVE := 0
const KINGDOM := 1
const ISLAND := 2 ## the island (IslandGen), owner 2026-11-26
const LATEST := ISLAND

const ASHGROVE_SIZE := 512.0
const KINGDOM_SIZE_MIN := 800.0
const KINGDOM_SIZE_MAX := 1600.0
const KINGDOM_SIZE_DEFAULT := 1200.0
## Host settings later (vision, "Size"): small, medium, large.
const SIZES := {"small": 1000.0, "medium": 1200.0, "large": 1500.0}

const KINGDOM_WATER := 0.0 ## sea, lake and river surface on a generated world
const SNOW_LINE := 38.0 ## nothing grows above this; old snow on the rim's peaks

const RIM_START := 0.80 ## fraction of the half size where the rim hills begin to rise
const RIM_HEIGHT := 30.0
const SEA_DEPTH := -9.0
const RIVER_HALF_WIDTH := 5.0
const RIVER_BED := -1.4 ## below the water, so a river reads as water all the way
const LAKE_BED := -3.0
const ROAD_HALF_WIDTH := 3.5
const ROAD_SOFT := 12.0 ## the land's bumps fade out within this many metres of a road
const SPAWN_FLAT := 22.0 ## metres of dead-flat plot around spawn
const SPAWN_BLEND := 70.0 ## metres over which the plot blends back into the land
const SPAWN_CLEAR := 12.0 ## no nodes this close to spawn (same as Ashgrove)
const NODE_SPACING := 6.0 ## no two node spots closer than this (ResourceNodes.MIN_SPACING)
## Metres of grass a tree keeps between its foot and the sand (owner, 2026-11-27: "trees
## shouldn't be on the beach"). One terrain cell (TerrainMesh.CELL) plus a little, so a trunk
## never stands in the strip where the sand colour blends into the grass.
const SAND_CLEAR := 5.0
const SAND_HIGH := 6.0 ## ground this high is never beside sand (cliff tops by the sea are fine)
const SAND_TOP := 2.2 ## the highest ground either generator paints as sand (IslandGen.biome_for)
const OFF_SAND_STEP := 2.5 ## metres per step when an island tree node is walked off the sand
const OFF_SAND_REACH := 40 ## steps (so up to 100 m: a landing's beach can be 70 m deep; about 15 s on foot)
const PAD_CELL := 64.0 ## metres per cell of an island's pad lookup grid
const RASTER_CELL := 4.0 ## metres per cell of the baked river and road distance fields
const RIVER_CAP := 140.0 ## river distances past this are stored as this
const ROAD_CAP := 40.0 ## road distances past this are stored as this

## Ruin kinds by grade (vision, "The map"). Kinds that need water (toll bridge, drowned
## village) wait for a later version that can place them on the river.
const RUIN_KINDS := {
	1: ["burned_farmstead", "roadside_shrine", "woodcutters_hut"],
	2: ["abandoned_village", "watchtower"],
	3: ["old_mine", "walled_abbey"],
	4: ["fallen_castle"],
}
## The flat pad each kind stands on, in metres.
const RUIN_RADIUS := {
	"burned_farmstead": 22.0, "roadside_shrine": 9.0, "woodcutters_hut": 12.0,
	"abandoned_village": 42.0, "watchtower": 14.0,
	"old_mine": 26.0, "walled_abbey": 38.0,
	"fallen_castle": 60.0,
}
## Every world has at least one of these (the first two set pieces, Phase 1).
const RUIN_MUST_HAVE := ["burned_farmstead", "abandoned_village"]
## Ruins per grade on a 1200 m world; scaled by area, never under 1.
const RUIN_COUNTS := {1: 5, 2: 3, 3: 2, 4: 1}
## Distance from spawn by grade, as a fraction of the half size: higher grades lie further
## out, the castle on the far side of the land (vision: "toward the centre or the far side").
const RUIN_BANDS := {1: [0.15, 0.6], 2: [0.45, 0.9], 3: [0.75, 1.2]}
const RUIN_GAP := 0.14 ## fraction of the half size between two ruins' edges

const BIOMES := ["forest", "moor", "farmland", "stone_hills"]
## Which node kinds a biome grows, and how many spots per km² it aims for.
const BIOME_NODES := {
	"forest": {"ash": 0.45, "pine": 0.40, "stone": 0.10, "scrub": 0.05},
	"farmland": {"ash": 0.50, "pine": 0.10, "stone": 0.36, "scrub": 0.04},
	"moor": {"ash": 0.10, "pine": 0.33, "stone": 0.55, "scrub": 0.02},
	"stone_hills": {"ash": 0.02, "pine": 0.25, "stone": 0.73, "scrub": 0.0},
}
const BIOME_DENSITY := {"forest": 1500.0, "farmland": 650.0, "moor": 700.0, "stone_hills": 900.0}
const NODE_KINDS := ["ash", "pine", "stone", "scrub"]
## The ring around spawn: two of every kind and a scrub patch (ResourceNodes.STARTER_KINDS).
const STARTER_KINDS := ["ash", "pine", "stone", "ash", "pine", "stone", "scrub"]
const STARTER_MIN := 16.0
const STARTER_MAX := 34.0

static var _seed: int = GameConfig.WORLD_SEED
static var _size: float = ASHGROVE_SIZE
static var _gen: int = ASHGROVE
static var _L: Dictionary = {} ## the kingdom's layout, built on first use
static var _building := false


# ---------------------------------------------------------------------------------------
# The config

## Sets the world every other call describes. Clamps a kingdom's size into range; Ashgrove
## is always 512 m on the fixed WORLD_SEED. Cheap: the layout is built on first use.
static func configure(seed: int, size_m: float, gen_version: int) -> void:
	var gen := clampi(gen_version, ASHGROVE, LATEST)
	_gen = gen
	if gen == ASHGROVE:
		_seed = GameConfig.WORLD_SEED
		_size = ASHGROVE_SIZE
	elif gen == ISLAND:
		_seed = seed
		_size = clampf(size_m, IslandGen.SIZE_MIN, IslandGen.SIZE_MAX)
	else:
		_seed = seed
		_size = clampf(size_m, KINGDOM_SIZE_MIN, KINGDOM_SIZE_MAX)
	_L = {}


## Back to the default: today's Ashgrove.
static func reset() -> void:
	configure(GameConfig.WORLD_SEED, ASHGROVE_SIZE, ASHGROVE)


static func config() -> Dictionary:
	return {"seed": _seed, "size_m": _size, "gen_version": _gen}


## Applies a config Dictionary as config() returns it (and as the login reply will carry it).
## Missing or bad fields fall back to Ashgrove.
static func apply(cfg: Dictionary) -> void:
	configure(int(cfg.get("seed", GameConfig.WORLD_SEED)), float(cfg.get("size_m", ASHGROVE_SIZE)),
		int(cfg.get("gen_version", ASHGROVE)))


## Parses "seed:gen:size" (the client's `--world=` dev flag and the server's environment).
## "1234:1" means size 1200; "" or junk gives Ashgrove's config.
static func parse(spec: String) -> Dictionary:
	var out := {"seed": GameConfig.WORLD_SEED, "size_m": ASHGROVE_SIZE, "gen_version": ASHGROVE}
	var parts := spec.strip_edges().split(":")
	if parts.size() < 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int():
		return out
	var gen := clampi(int(parts[1]), ASHGROVE, LATEST)
	if gen == ASHGROVE:
		return out
	var island := gen == ISLAND
	var sizes: Dictionary = IslandGen.SIZES if island else SIZES
	var size: float = IslandGen.SIZE_DEFAULT if island else KINGDOM_SIZE_DEFAULT
	if parts.size() >= 3:
		if parts[2].is_valid_float():
			size = float(parts[2])
		elif sizes.has(parts[2]):
			size = sizes[parts[2]]
	if island:
		size = clampf(size, IslandGen.SIZE_MIN, IslandGen.SIZE_MAX)
	else:
		size = clampf(size, KINGDOM_SIZE_MIN, KINGDOM_SIZE_MAX)
	return {"seed": int(parts[0]), "size_m": size, "gen_version": gen}


static func gen_version() -> int:
	return _gen


## True on every generated world (version 1 and up): the callers that ask mean "not Ashgrove".
static func is_kingdom() -> bool:
	return _gen >= KINGDOM


static func is_island() -> bool:
	return _gen == ISLAND


static func size_m() -> float:
	return _size


## The playable world is a square from -half_size() to +half_size() metres.
static func half_size() -> float:
	return _size * 0.5


# ---------------------------------------------------------------------------------------
# The land (gen_version 1; Terrain.height calls this when is_kingdom())

static func water_level() -> float:
	return KINGDOM_WATER


## Ground height in metres on the kingdom. Terrain.height is the public entry point.
static func height(x: float, z: float) -> float:
	_ensure()
	var h := IslandGen.land(_L, x, z) if _gen == ISLAND else _land(x, z)
	return _pads(x, z, h)


## The biome at (x, z): "water", "shore", "snow", or one of BIOMES. The spawn plot reads as
## "farmland" (an old field gone to meadow).
static func biome_at(x: float, z: float) -> String:
	return biome_for(x, z, height(x, z))


## biome_at() for a point whose height you already have (map painting, placement passes).
static func biome_for(x: float, z: float, h: float) -> String:
	_ensure()
	if _gen == ISLAND:
		return IslandGen.biome_for(_L, x, z, h)
	if h < KINGDOM_WATER - 0.2:
		return "water"
	if h < KINGDOM_WATER + 1.0:
		return "shore"
	if h > SNOW_LINE:
		return "snow"
	if _flat_dist(x, z, _L.spawn) < SPAWN_FLAT + 20.0:
		return "farmland"
	var u := _uplift(x, z)
	if u > 0.72 or h > SNOW_LINE - 8.0:
		return "stone_hills"
	var m: float = _L.moist.get_noise_2d(x, z)
	if m > 0.08:
		return "forest"
	if m < -0.22:
		return "moor"
	return "farmland"


## True when beach sand or water lies within `r` metres of (x, z) on a generated world: where
## no tree belongs (palms are the beach's own trees, Flora). Always false on Ashgrove, whose
## shores are hand-tuned and stay as they are. Cheap on high ground.
static func near_sand(x: float, z: float, r: float = SAND_CLEAR) -> bool:
	if _gen == ASHGROVE:
		return false
	_ensure()
	var h := height(x, z)
	if h > SAND_HIGH:
		return false
	# Sand and water are all below SAND_TOP: skip the ring when the ground can't fall that far
	# within r at its local slope (with room for the slope to steepen).
	var g := Vector2(height(x + 1.0, z) - h, height(x, z + 1.0) - h).length()
	if h - (g * 1.5 + 0.3) * r > SAND_TOP:
		return false
	if _sandy(x, z, h):
		return true
	for ring: float in [0.5, 1.0]:
		var n: int = 6 if ring < 1.0 else 10
		for i in n:
			var q: Vector2 = Vector2(x, z) + Vector2.from_angle(TAU * (float(i) + 0.5 * ring) / n) * r * ring
			if _sandy(q.x, q.y, height(q.x, q.y)):
				return true
	return false


static func _sandy(x: float, z: float, h: float) -> bool:
	var b := biome_for(x, z, h)
	return b == "shore" or b == "water"


## 0 at the edge of an island's beach sand, rising to 1 a short band inland (IslandGen.sand_margin);
## 1 on other worlds.
static func sand_margin(x: float, z: float, h: float) -> float:
	if _gen != ISLAND:
		return 1.0
	_ensure()
	return IslandGen.sand_margin(_L, x, z, h)


## How far up an island's beach (x, z) is, 0 at the sea side to 1 at the back of the sand
## (IslandGen.beach_depth); 0 on other worlds.
static func beach_depth(x: float, z: float) -> float:
	if _gen != ISLAND:
		return 0.0
	_ensure()
	return IslandGen.beach_depth(_L, x, z)


## 0 at an island's shore, 1 at its heart (IslandGen.inland). 1 on other worlds, which have no
## sea all round.
static func inland(x: float, z: float) -> float:
	if _gen != ISLAND:
		return 1.0
	_ensure()
	return IslandGen.inland(_L, x, z)


## Where the sea beach is along bearing `a` (radians) from an island's centre:
## {pos: Vector2 (the middle of the beach band), sea: Vector2 (unit, seaward)}, or {} on a
## world with no sea all round. Cheap (outline maths only), for dressing the coast.
static func coast_at(a: float) -> Dictionary:
	if _gen != ISLAND:
		return {}
	_ensure()
	var c: Vector2 = _L.center
	var dir := Vector2.from_angle(a)
	var r: float = _L.radius * 0.6
	while r < float(_L.half) * 1.4:
		var p := c + dir * r
		if IslandGen.shape(_L, p.x, p.y) >= 0.96:
			return {"pos": p, "sea": dir}
		r += 4.0
	return {}


## The spawn point, on the ground in the middle of the spawn plot.
static func spawn_point() -> Vector3:
	if _gen == ASHGROVE:
		return GameConfig.SPAWN_POINT
	_ensure()
	var s: Vector2 = _L.spawn
	return Vector3(s.x, height(s.x, s.y), s.y)


## Ruin sites: [{id, kind, grade (1 to 4), pos: Vector3, radius}], castle first, then by
## grade. Empty on Ashgrove.
static func ruin_sites() -> Array:
	if _gen == ASHGROVE:
		return []
	_ensure()
	return _L.ruins


## The king's roads: Array of PackedVector2Array polylines (x, z), each linking two sites
## (spawn or ruins). Every ruin is reachable from spawn along them. Empty on Ashgrove.
static func roads() -> Array:
	if _gen == ASHGROVE:
		return []
	_ensure()
	return _L.roads


## Rivers as polylines from source to mouth. Empty on Ashgrove.
static func rivers() -> Array:
	if _gen == ASHGROVE:
		return []
	_ensure()
	if _gen == ISLAND:
		return _L.rivers
	return [_L.river]


## Where new characters wash up: beach spots round an island's coast (Vector2 x, z), the first
## being spawn_point(). A version 1 kingdom has one: its spawn plot. Empty on Ashgrove.
static func landings() -> Array:
	if _gen == ASHGROVE:
		return []
	_ensure()
	if _gen == ISLAND:
		return _L.landings
	return [_L.spawn]


## A landing picked by `key` (an account's name hash, a respawn roll), on the ground. Spreads
## a crowd over every beach. Ashgrove and version 1 always give spawn_point().
static func landing_for(key: int) -> Vector3:
	var all := landings()
	if all.size() <= 1:
		return spawn_point()
	var p: Vector2 = all[absi(key) % all.size()]
	return Vector3(p.x, height(p.x, p.y), p.y)


## "king" or "track" for each of roads(), in the same order. Version 1's are all king's roads.
static func road_kinds() -> Array:
	if _gen == ASHGROVE:
		return []
	_ensure()
	if _gen == ISLAND:
		return _L.road_kinds
	var out: Array = []
	for r in _L.roads:
		out.append("king")
	return out


## Lakes: [{center: Vector2, radius}]. Empty on Ashgrove.
static func lakes() -> Array:
	if _gen == ASHGROVE:
		return []
	_ensure()
	return _L.lakes


## "coast" (hills on three sides, the sea on one) or "highland" (hills all round).
static func rim() -> String:
	if _gen == ASHGROVE:
		return "valley"
	_ensure()
	return _L.rim


## Where resource nodes go: an ordered Array of {kind, pos: Vector3, rot, scale, starter}.
## Stable for a config, so gameplay can use the index as the node id. Starter ring first.
## Empty on Ashgrove (ResourceNodes keeps its own list there).
static func node_spots() -> Array:
	if _gen == ASHGROVE:
		return []
	_ensure()
	if not _L.has("nodes"):
		_L.nodes = _place_nodes()
	return _L.nodes


## Everything gameplay needs to populate a world, in one Dictionary.
static func placement() -> Dictionary:
	return {
		"config": config(), "spawn": spawn_point(), "ruins": ruin_sites(), "roads": roads(),
		"rivers": rivers(), "lakes": lakes(), "nodes": node_spots(), "rim": rim(),
		"landings": landings(), "road_kinds": road_kinds(),
	}


## Distance in metres from (x, z) to the nearest king's road (capped at ROAD_CAP).
static func road_distance(x: float, z: float) -> float:
	_ensure()
	return _sample(_L.road_d, x, z)


## Distance in metres from (x, z) to the river's centre line (capped at RIVER_CAP).
static func river_distance(x: float, z: float) -> float:
	_ensure()
	return _sample(_L.river_d, x, z)


# ---------------------------------------------------------------------------------------
# Layout: built once per config, in a fixed order (rim, spawn, lakes, river, ruins, roads)

static func _ensure() -> void:
	if not _L.is_empty() or _building:
		return
	_building = true
	_build_layout()
	_building = false


static func _noise(seed_off: int, freq: float, octaves: int) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = _seed + seed_off
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = freq
	if octaves > 1:
		n.fractal_type = FastNoiseLite.FRACTAL_FBM
		n.fractal_octaves = octaves
	else:
		n.fractal_type = FastNoiseLite.FRACTAL_NONE
	return n


static func _build_layout() -> void:
	var L := {}
	_L = L
	var half := half_size()
	L.half = half
	L.detail = _noise(1, 0.006, 4)
	L.ridge = _noise(2, 0.0025, 1)
	L.uplift = _noise(3, 0.0016, 2)
	L.moist = _noise(4, 0.0032, 2)
	L.wobble = _noise(5, 0.004, 2)
	var dim := int(ceil(_size / RASTER_CELL)) + 1
	L.dim = dim
	L.river_d = _blank_raster(dim, RIVER_CAP)
	L.road_d = _blank_raster(dim, ROAD_CAP)
	L.lakes = []
	L.pads = [] ## [{c: Vector2, r: float, blend: float, h: float}]
	L.river = PackedVector2Array()
	L.roads = []
	L.ruins = []
	L.spawn = Vector2.ZERO
	if _gen == ISLAND:
		IslandGen.build(L, _seed, _size)
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed * 7919 + 17
	# 1. The rim: a coast on one side (most worlds) or hills all round.
	L.rim = "coast" if rng.randf() < 0.6 else "highland"
	var coast_ang := rng.randf() * TAU
	L.coast_dir = Vector2.from_angle(coast_ang) if L.rim == "coast" else Vector2.ZERO
	# 2. Spawn: inland on one side, a quarter turn from the coast, on calm, dry ground.
	var spawn_ang := coast_ang + (PI * 0.5 if rng.randf() < 0.5 else -PI * 0.5) + rng.randf_range(-0.4, 0.4)
	L.spawn = _pick_spawn(rng, spawn_ang, half)
	L.spawn_ang = (L.spawn as Vector2).angle()
	var sp: Vector2 = L.spawn
	L.pads.append({"c": sp, "r": SPAWN_FLAT, "blend": SPAWN_BLEND, "h": maxf(_land(sp.x, sp.y), KINGDOM_WATER + 2.0)})
	# 3. Lakes, away from spawn, in low ground.
	_place_lakes(rng, half)
	# 4. The river: from a spring in the rim hills to the sea or the biggest lake.
	_place_river(rng, half)
	# 5. Ruins: the castle on the far side first, then grades 3, 2, 1.
	_place_ruins(rng, half)
	# 6. The king's roads between spawn and every ruin.
	_place_roads(rng, half)


static func _pick_spawn(rng: RandomNumberGenerator, ang: float, half: float) -> Vector2:
	var best := Vector2.from_angle(ang) * half * 0.6
	var best_score := INF
	for i in 24:
		var a := ang + rng.randf_range(-0.9, 0.9)
		var r := half * rng.randf_range(0.5, 0.64)
		var p := Vector2.from_angle(a) * r
		var h := _land(p.x, p.y)
		if h < KINGDOM_WATER + 2.0 or h > 16.0 or _sea(p.x, p.y) > 0.0:
			continue
		var rough := 0.0
		for k in 8:
			var q := p + Vector2.from_angle(TAU * k / 8.0) * 40.0
			rough += absf(_land(q.x, q.y) - h)
		if rough < best_score:
			best_score = rough
			best = p
	return best


static func _place_lakes(rng: RandomNumberGenerator, half: float) -> void:
	var L := _L
	var sp: Vector2 = L.spawn
	var want := rng.randi_range(1, 2) if L.rim == "coast" else rng.randi_range(2, 3)
	var tries := 0
	while L.lakes.size() < want and tries < 200:
		tries += 1
		var big: bool = L.lakes.is_empty() and L.rim == "highland"
		var r := rng.randf_range(48.0, 70.0) if big else rng.randf_range(22.0, 42.0)
		var p := Vector2(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0)) * half * (0.45 if big else 0.7)
		if p.distance_to(sp) < 150.0 + r or _sea(p.x, p.y) > 0.0:
			continue
		if _land(p.x, p.y) > KINGDOM_WATER + 12.0:
			continue
		var ok := true
		for l in L.lakes:
			if p.distance_to(l.center) < l.radius + r + 60.0:
				ok = false
		if ok:
			L.lakes.append({"center": p, "radius": r})


static func _place_river(rng: RandomNumberGenerator, half: float) -> void:
	var L := _L
	var sp: Vector2 = L.spawn
	var src: Vector2
	var mouth: Vector2
	if L.rim == "coast":
		var ca: float = (L.coast_dir as Vector2).angle()
		src = Vector2.from_angle(ca + PI + rng.randf_range(-0.8, 0.8)) * half * 0.78
		mouth = Vector2.from_angle(ca + rng.randf_range(-0.35, 0.35)) * half * 0.82
	else:
		var lake: Dictionary = L.lakes[0]
		mouth = lake.center
		src = Vector2.from_angle(mouth.angle() + PI + rng.randf_range(-0.9, 0.9)) * half * 0.78
		if src.distance_to(sp) < half * 0.5:
			src = Vector2.from_angle(sp.angle() + PI * 0.6) * half * 0.78
	var length := src.distance_to(mouth)
	var n := maxi(8, int(length / 40.0))
	var dir := (mouth - src) / length
	var side := Vector2(-dir.y, dir.x)
	var pts := PackedVector2Array()
	var phase := rng.randf() * 1000.0
	for i in n + 1:
		var t := float(i) / n
		var p := src.lerp(mouth, t)
		var off: float = L.wobble.get_noise_2d(phase + t * 900.0, 0.0) * 1.6 * 70.0 * sin(PI * t)
		p += side * off
		# Keep the river off the spawn plot.
		var away := p - sp
		var keep := SPAWN_FLAT + SPAWN_BLEND + RIVER_HALF_WIDTH + 10.0 # clear of the plot's blend
		if away.length() < keep:
			p = sp + away.normalized() * keep
		pts.append(p)
	L.river = pts
	_stamp(L.river_d, pts, RIVER_CAP)


static func _place_ruins(rng: RandomNumberGenerator, half: float) -> void:
	var L := _L
	var sp: Vector2 = L.spawn
	var area := (_size * _size) / (KINGDOM_SIZE_DEFAULT * KINGDOM_SIZE_DEFAULT)
	var plan: Array = [] # [grade, kind]
	for g in [4, 3, 2, 1]:
		var count := maxi(1, int(round(RUIN_COUNTS[g] * area)))
		var pool: Array = RUIN_KINDS[g]
		for i in count:
			var kind: String = pool[i % pool.size()] if i < pool.size() else pool[rng.randi() % pool.size()]
			plan.append([g, kind])
	var id := 0
	for entry in plan:
		var g: int = entry[0]
		var kind: String = entry[1]
		var r: float = RUIN_RADIUS[kind]
		var site := {}
		for attempt in 400:
			var p: Vector2
			if g == 4:
				var spread := 0.7 + attempt / 400.0 * 0.9 # widen if the far side is all water
				var a: float = L.spawn_ang + PI + rng.randf_range(-spread, spread)
				p = Vector2.from_angle(a) * half * rng.randf_range(0.3, 0.6)
			else:
				var band: Array = RUIN_BANDS[g]
				var slack := 1.0 + attempt / 200.0 * 0.25 # widen a little if it's hard
				var d := half * rng.randf_range(band[0] / slack, band[1] * slack)
				p = sp + Vector2.from_angle(rng.randf() * TAU) * d
			if _site_ok(p, r, half):
				site = {"id": id, "kind": kind, "grade": g, "pos": p, "radius": r}
				break
		if site.is_empty():
			continue
		var c: Vector2 = site.pos
		var ph := _land(c.x, c.y)
		# The blend stops short of water, so a pad never fills a river or a lake.
		var blend := clampf(_water_gap(c) - r - 2.0, 6.0, r * 0.8 + 14.0)
		L.pads.append({"c": c, "r": r, "blend": blend, "h": ph})
		site.pos = Vector3(c.x, ph, c.y)
		L.ruins.append(site)
		id += 1


static func _site_ok(p: Vector2, r: float, half: float) -> bool:
	var L := _L
	if maxf(absf(p.x), absf(p.y)) > half * RIM_START - r - 20.0:
		return false
	if _sea(p.x, p.y) > 0.0:
		return false
	var h := _land(p.x, p.y)
	if h < KINGDOM_WATER + 1.5 or h > SNOW_LINE - 10.0:
		return false
	# Room for the pad and at least a short blend before the river or a lake.
	if _water_gap(p) < r + 8.0:
		return false
	for pad in L.pads:
		if p.distance_to(pad.c) < pad.r + r + half * RUIN_GAP:
			return false
	# Not on a cliff: the pad's edge may not sit far above or below its centre.
	for k in 6:
		var q := p + Vector2.from_angle(TAU * k / 6.0) * r
		if absf(_land(q.x, q.y) - h) > 6.0 + r * 0.12:
			return false
	return true


## Metres from p to the nearest river bank or lake shore (capped by RIVER_CAP).
static func _water_gap(p: Vector2) -> float:
	var gap := _sample(_L.river_d, p.x, p.y) - RIVER_HALF_WIDTH - 4.0
	for l in _L.lakes:
		gap = minf(gap, p.distance_to(l.center) - l.radius * 1.15 - 6.0)
	return gap


## Roads: a minimum spanning tree over spawn and the ruins (nearest links first), plus the
## shortest extra link that closes a loop, so a band has two ways home from somewhere.
static func _place_roads(rng: RandomNumberGenerator, half: float) -> void:
	var L := _L
	var sites: Array = [L.spawn]
	for s in L.ruins:
		sites.append(Vector2(s.pos.x, s.pos.z))
	var n := sites.size()
	var linked := {0: true}
	var edges: Array = []
	while linked.size() < n:
		var best := [-1, -1, INF]
		for a in linked.keys():
			for b in n:
				if linked.has(b):
					continue
				var d: float = (sites[a] as Vector2).distance_to(sites[b])
				if d < best[2]:
					best = [a, b, d]
		linked[best[1]] = true
		edges.append([best[0], best[1]])
	var extra := [-1, -1, INF]
	for a in n:
		for b in range(a + 1, n):
			var used := false
			for e in edges:
				if (e[0] == a and e[1] == b) or (e[0] == b and e[1] == a):
					used = true
			var d: float = (sites[a] as Vector2).distance_to(sites[b])
			if not used and d < extra[2] and d < half * 0.9:
				extra = [a, b, d]
	if extra[0] >= 0:
		edges.append([extra[0], extra[1]])
	for e in edges:
		var line := _road_line(rng, sites[e[0]], sites[e[1]])
		L.roads.append(line)
		_stamp(L.road_d, line, ROAD_CAP)


static func _road_line(rng: RandomNumberGenerator, a: Vector2, b: Vector2) -> PackedVector2Array:
	var L := _L
	var length := a.distance_to(b)
	var n := maxi(2, int(length / 24.0))
	var dir := (b - a) / maxf(length, 0.001)
	var side := Vector2(-dir.y, dir.x)
	var phase := rng.randf() * 1000.0
	var pts := PackedVector2Array()
	for i in n + 1:
		var t := float(i) / n
		var p := a.lerp(b, t)
		var off: float = L.wobble.get_noise_2d(0.0, phase + t * length * 0.5) * 1.4 * minf(40.0, length * 0.08) * sin(PI * t)
		p += side * off
		for l in L.lakes:
			var away: Vector2 = p - l.center
			var keep: float = l.radius * 1.2 + 12.0
			if away.length() < keep:
				p = l.center + away.normalized() * keep
		pts.append(p)
	return pts


# ---------------------------------------------------------------------------------------
# Height field pieces

## 0..1: low farmland and meadows near 0, stone hills near 1.
static func _uplift(x: float, z: float) -> float:
	return clampf((_L.uplift as FastNoiseLite).get_noise_2d(x, z) * 0.85 + 0.5, 0.0, 1.0)


## 0..1: how far into the sea (x, z) lies (0 on land). Always 0 on a highland world.
static func _sea(x: float, z: float) -> float:
	var L := _L
	if L.rim != "coast":
		return 0.0
	var t: float = (L.coast_dir as Vector2).dot(Vector2(x, z)) / L.half + (L.wobble as FastNoiseLite).get_noise_2d(x * 0.7, z * 0.7) * 0.06
	return smoothstep(0.55, 0.8, t)


## The land before the flat pads: hills, rim, sea, lakes, river, softened along roads.
static func _land(x: float, z: float) -> float:
	var L := _L
	var half: float = L.half
	var u := _uplift(x, z)
	var detail: float = (L.detail as FastNoiseLite).get_noise_2d(x, z) * (3.0 + 6.0 * u)
	var r := 1.0 - absf((L.ridge as FastNoiseLite).get_noise_2d(x, z))
	var ridge := r * r * r * 24.0 * smoothstep(0.5, 0.85, u)
	var road_k := 1.0 - smoothstep(ROAD_HALF_WIDTH, ROAD_SOFT, _sample(L.road_d, x, z))
	var h := 3.0 + 6.0 * u + (detail + ridge) * (1.0 - 0.85 * road_k)
	# The rim: a rounded square, wobbled, rising to hills.
	var ax := absf(x) / half
	var az := absf(z) / half
	var m := pow(ax * ax * ax * ax + az * az * az * az, 0.25) + (L.wobble as FastNoiseLite).get_noise_2d(x, z) * 0.04
	var e := smoothstep(RIM_START, 0.98, m)
	var sea := _sea(x, z)
	h += e * e * RIM_HEIGHT * (1.0 - sea)
	h = lerpf(h, SEA_DEPTH, sea)
	for l in L.lakes:
		var d: float = Vector2(x, z).distance_to(l.center)
		var rr: float = l.radius * (1.0 + (L.wobble as FastNoiseLite).get_noise_2d(x * 2.0, z * 2.0) * 0.15)
		var k := 1.0 - smoothstep(rr * 0.55, rr * 1.15 + 6.0, d)
		if k > 0.0:
			h = lerpf(h, LAKE_BED, k)
	var rd := _sample(L.river_d, x, z)
	if rd < RIVER_CAP:
		var bank := clampf(10.0 + 0.5 * maxf(h - KINGDOM_WATER, 0.0), 10.0, 40.0)
		var k := 1.0 - smoothstep(RIVER_HALF_WIDTH, RIVER_HALF_WIDTH + bank, rd)
		h = lerpf(h, minf(h, RIVER_BED), k)
	return h


## Flattens the spawn plot and the ruin pads (each to the height its centre had).
static func _pads(x: float, z: float, h: float) -> float:
	if _L.has("pad_grid"): # an island: only the pads that reach this cell, in the same order
		var cell: Vector2i = Vector2i(int(floor(x / PAD_CELL)), int(floor(z / PAD_CELL)))
		for i in _L.pad_grid.get(cell, []):
			var pad: Dictionary = _L.pads[i]
			var d: float = Vector2(x, z).distance_to(pad.c)
			var k := 1.0 - smoothstep(pad.r, pad.r + pad.blend, d)
			if k > 0.0:
				h = lerpf(h, pad.h, k)
		return h
	for pad in _L.pads:
		var d: float = Vector2(x, z).distance_to(pad.c)
		var k := 1.0 - smoothstep(pad.r, pad.r + pad.blend, d)
		if k > 0.0:
			h = lerpf(h, pad.h, k)
	return h


static func _flat_dist(x: float, z: float, p: Vector2) -> float:
	return Vector2(x, z).distance_to(p)


# ---------------------------------------------------------------------------------------
# Distance rasters (river and roads), stamped segment by segment

static func _blank_raster(dim: int, cap: float) -> PackedFloat32Array:
	var a := PackedFloat32Array()
	a.resize(dim * dim)
	a.fill(cap)
	return a


static func _stamp(raster: PackedFloat32Array, line: PackedVector2Array, cap: float) -> void:
	var dim: int = _L.dim
	var half: float = _L.half
	for i in line.size() - 1:
		var a := line[i]
		var b := line[i + 1]
		var x0 := clampi(int(floor((minf(a.x, b.x) - cap + half) / RASTER_CELL)), 0, dim - 1)
		var x1 := clampi(int(ceil((maxf(a.x, b.x) + cap + half) / RASTER_CELL)), 0, dim - 1)
		var z0 := clampi(int(floor((minf(a.y, b.y) - cap + half) / RASTER_CELL)), 0, dim - 1)
		var z1 := clampi(int(ceil((maxf(a.y, b.y) + cap + half) / RASTER_CELL)), 0, dim - 1)
		var ab := b - a
		var len2 := maxf(ab.length_squared(), 0.0001)
		for gz in range(z0, z1 + 1):
			var pz := gz * RASTER_CELL - half
			for gx in range(x0, x1 + 1):
				var p := Vector2(gx * RASTER_CELL - half, pz)
				var t := clampf((p - a).dot(ab) / len2, 0.0, 1.0)
				var d := p.distance_to(a + ab * t)
				var idx := gz * dim + gx
				if d < raster[idx]:
					raster[idx] = d


static func _sample(raster: PackedFloat32Array, x: float, z: float) -> float:
	var dim: int = _L.dim
	var half: float = _L.half
	var fx := clampf((x + half) / RASTER_CELL, 0.0, dim - 1.001)
	var fz := clampf((z + half) / RASTER_CELL, 0.0, dim - 1.001)
	var ix := int(fx)
	var iz := int(fz)
	var tx := fx - ix
	var tz := fz - iz
	var i := iz * dim + ix
	var top := lerpf(raster[i], raster[i + 1], tx)
	var bot := lerpf(raster[i + dim], raster[i + dim + 1], tx)
	return lerpf(top, bot, tz)


# ---------------------------------------------------------------------------------------
# Resource node spots

static func _place_nodes() -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed * 31 + 101
	var out: Array = []
	var grid := {}
	var sp: Vector2 = _L.spawn
	if _gen == ISLAND:
		_place_landing_rings(out, grid, rng)
	else:
		# The starter ring, on the spawn plot's edge.
		for i in STARTER_KINDS.size():
			for attempt in 30:
				var a := TAU * float(i) / STARTER_KINDS.size() + rng.randf_range(-0.25, 0.25)
				var p := sp + Vector2.from_angle(a) * rng.randf_range(STARTER_MIN, STARTER_MAX)
				if _crowded(grid, p):
					continue
				_add_spot(out, grid, STARTER_KINDS[i], p, rng, true)
				break
	# The wild: a jittered grid; each biome grows its own mix at its own density.
	var half := half_size()
	var step := 12.0
	var cells := int(_size / step)
	for gz in cells:
		for gx in cells:
			var p := Vector2(-half + (gx + rng.randf()) * step, -half + (gz + rng.randf()) * step)
			var roll := rng.randf()
			var pick := rng.randf()
			var biome := biome_at(p.x, p.y)
			if not BIOME_DENSITY.has(biome):
				continue
			# spots per cell = density per km² * cell area
			if roll > BIOME_DENSITY[biome] * step * step / 1000000.0:
				continue
			if not _spot_ok(p, sp):
				continue
			var kind := _pick_kind(BIOME_NODES[biome], pick)
			if kind == "" or _crowded(grid, p):
				continue
			_add_spot(out, grid, kind, p, rng, false)
	if _gen == ISLAND:
		_trees_off_sand(out, grid)
	return out


## An island's tree nodes walked off the beach (owner, 2026-11-27): every ash or pine spot
## within SAND_CLEAR of sand moves to the nearest dry, free ground at most 100 m away, keeping
## its place in the list, its kind and its looks. Spots are only ever moved, never added or
## dropped, so node ids stay what they were. Stones and scrub may stay on the sand (rocks and
## beach grass belong there). Draws nothing from the placement rng.
static func _trees_off_sand(out: Array, grid: Dictionary) -> void:
	for s in out:
		if s.kind != "ash" and s.kind != "pine":
			continue
		var p := Vector2(s.pos.x, s.pos.z)
		if not near_sand(p.x, p.y):
			continue
		var to := _off_sand_spot(p, grid)
		if to == Vector2.INF:
			continue
		_ungrid(grid, p)
		var c := Vector2i(int(floor(to.x / NODE_SPACING)), int(floor(to.y / NODE_SPACING)))
		if not grid.has(c):
			grid[c] = []
		grid[c].append(to)
		s.pos = Vector3(to.x, height(to.x, to.y), to.y)


## The nearest spot to `p` (rings of OFF_SAND_STEP, 16 bearings each) that is clear of the
## sand, other nodes, roads, rivers, locations and the snow; Vector2.INF if none within reach.
static func _off_sand_spot(p: Vector2, grid: Dictionary) -> Vector2:
	var half := half_size() - 8.0
	for step in range(1, OFF_SAND_REACH + 1):
		for i in 16:
			var q := p + Vector2.from_angle(TAU * float(i) / 16.0) * OFF_SAND_STEP * step
			if maxf(absf(q.x), absf(q.y)) > half:
				continue
			var h := height(q.x, q.y)
			if h < KINGDOM_WATER + 1.0 or h > SNOW_LINE or near_sand(q.x, q.y):
				continue
			if _crowded_but(grid, q, p):
				continue
			if _sample(_L.road_d, q.x, q.y) < ROAD_HALF_WIDTH + 2.5 or _sample(_L.river_d, q.x, q.y) < RIVER_HALF_WIDTH + 4.0:
				continue
			var on_site := false
			for site in _L.ruins:
				if q.distance_to(Vector2(site.pos.x, site.pos.z)) < site.radius + 6.0:
					on_site = true
			if not on_site:
				return q
	return Vector2.INF


## `_crowded`, ignoring the spot at `self_p` (the one being moved).
static func _crowded_but(grid: Dictionary, p: Vector2, self_p: Vector2) -> bool:
	var c := Vector2i(int(floor(p.x / NODE_SPACING)), int(floor(p.y / NODE_SPACING)))
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			for q in grid.get(c + Vector2i(dx, dz), []):
				if q != self_p and p.distance_to(q) < NODE_SPACING:
					return true
	return false


static func _ungrid(grid: Dictionary, p: Vector2) -> void:
	var c := Vector2i(int(floor(p.x / NODE_SPACING)), int(floor(p.y / NODE_SPACING)))
	var cell: Array = grid.get(c, [])
	cell.erase(p)


static func _spot_ok(p: Vector2, sp: Vector2) -> bool:
	var half := half_size()
	if maxf(absf(p.x), absf(p.y)) > half - 8.0:
		return false
	if _gen == ISLAND:
		for q in _L.landings:
			if p.distance_to(q) < SPAWN_CLEAR + STARTER_MAX:
				return false
	elif p.distance_to(sp) < SPAWN_CLEAR + STARTER_MAX:
		return false
	if _sample(_L.road_d, p.x, p.y) < ROAD_HALF_WIDTH + 2.5:
		return false
	if _sample(_L.river_d, p.x, p.y) < RIVER_HALF_WIDTH + 4.0:
		return false
	for s in _L.ruins:
		if p.distance_to(Vector2(s.pos.x, s.pos.z)) < s.radius + 6.0:
			return false
	var h := height(p.x, p.y)
	return h > KINGDOM_WATER + 1.0 and h < SNOW_LINE


static func _pick_kind(weights: Dictionary, roll: float) -> String:
	var acc := 0.0
	for k in NODE_KINDS:
		acc += float(weights.get(k, 0.0))
		if roll < acc:
			return k
	return ""


static func _crowded(grid: Dictionary, p: Vector2) -> bool:
	var c := Vector2i(int(floor(p.x / NODE_SPACING)), int(floor(p.y / NODE_SPACING)))
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			for q in grid.get(c + Vector2i(dx, dz), []):
				if p.distance_to(q) < NODE_SPACING:
					return true
	return false


static func _add_spot(out: Array, grid: Dictionary, kind: String, p: Vector2, rng: RandomNumberGenerator, starter: bool) -> void:
	var c := Vector2i(int(floor(p.x / NODE_SPACING)), int(floor(p.y / NODE_SPACING)))
	if not grid.has(c):
		grid[c] = []
	grid[c].append(p)
	out.append({
		"kind": kind, "pos": Vector3(p.x, height(p.x, p.y), p.y),
		"rot": rng.randf() * TAU, "scale": rng.randf_range(0.85, 1.2), "starter": starter,
	})


## An island's starter rings: two of each basic kind and a scrub patch just inland of every landing,
## so whoever washes up can start gathering at once.
static func _place_landing_rings(out: Array, grid: Dictionary, rng: RandomNumberGenerator) -> void:
	for q in _L.landings:
		var lp: Vector2 = q
		var inward := ((_L.center as Vector2) - lp).angle()
		for i in STARTER_KINDS.size():
			for attempt in 30:
				var a := inward + (float(i) / (STARTER_KINDS.size() - 1) - 0.5) * PI * 1.1 + rng.randf_range(-0.2, 0.2)
				var p := lp + Vector2.from_angle(a) * rng.randf_range(STARTER_MIN, STARTER_MAX + attempt)
				var h := height(p.x, p.y)
				if h < KINGDOM_WATER + 1.0 or h > SNOW_LINE or _crowded(grid, p):
					continue
				_add_spot(out, grid, STARTER_KINDS[i], p, rng, true)
				break


## A lookup grid of which pads reach each PAD_CELL cell (pad indices in order), so height()
## reads two or three pads instead of every one. Built once the layout's pads are final.
static func _index_pads(L: Dictionary) -> void:
	var grid := {}
	for i in L.pads.size():
		var pad: Dictionary = L.pads[i]
		var reach: float = pad.r + pad.blend
		var c: Vector2 = pad.c
		for cz in range(int(floor((c.y - reach) / PAD_CELL)), int(floor((c.y + reach) / PAD_CELL)) + 1):
			for cx in range(int(floor((c.x - reach) / PAD_CELL)), int(floor((c.x + reach) / PAD_CELL)) + 1):
				var key := Vector2i(cx, cz)
				if not grid.has(key):
					grid[key] = []
				grid[key].append(i)
	L.pad_grid = grid
