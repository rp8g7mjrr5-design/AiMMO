class_name Props
## Deterministic placement of trees and rocks. Same seed, same forest, on every machine.


const NODE_CLEARANCE := 3.0 ## no decorative tree or rock this close to a resource node


## Returns an Array of {pos: Vector3, scale: float, kind: "ash"|"pine"|"rock", rot: float}.
## On a generated kingdom (WorldGen gen_version 1) the forest follows the kingdom's biomes
## instead (`_scatter_kingdom`); Ashgrove keeps this exact code path, tree for tree.
## Worked out once per world and count, then cached (the world builder, flora and the camera's
## solids all ask; on a 3 km island each ask cost about 1.7 s). Treat the result as read-only.
static func scatter(count: int = 1800) -> Array:
	var key := [WorldGen.config(), count]
	if _cache_key != key:
		_cache_key = key
		_cache = _scatter_kingdom(count) if WorldGen.is_kingdom() else _scatter_ashgrove(count)
	return _cache.duplicate()


static var _cache: Array = []
static var _cache_key: Array = []


static func _scatter_ashgrove(count: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = GameConfig.WORLD_SEED + 7
	var out: Array = []
	var h := GameConfig.WORLD_HALF_SIZE - 4.0
	var tries := 0
	while out.size() < count and tries < count * 6:
		tries += 1
		var x := rng.randf_range(-h, h)
		var z := rng.randf_range(-h, h)
		var y := Terrain.height(x, z)
		if Vector2(x, z).length() < 10.0:
			continue # keep the spawn meadow clear
		if y < Terrain.water_level() + 1.0 or y > 15.0:
			continue
		var slope := absf(Terrain.height(x + 1.0, z) - y) + absf(Terrain.height(x, z + 1.0) - y)
		var r := rng.randf()
		var kind := "rock"
		if slope < 0.8:
			if y > 6.0:
				kind = "pine" if r < 0.8 else "rock"
			else:
				kind = "ash" if r < 0.7 else ("pine" if r < 0.85 else "rock")
		if not ResourceNodes.near(Vector3(x, 0.0, z), NODE_CLEARANCE).is_empty():
			continue # all draws for this spot are done, so skipping never shifts the rest of the forest
		out.append({"pos": Vector3(x, y - 0.1, z), "scale": rng.randf_range(0.7, 1.4), "kind": kind, "rot": rng.randf() * TAU})
	return out


# ---------------------------------------------------------------------------------------
# A generated kingdom (WorldGen gen_version 1)

const KINGDOM_SPAWN_CLEAR := 24.0 ## the spawn plot's flat stays open meadow (WorldGen.SPAWN_FLAT 22 m)
const KINGDOM_ROAD_CLEAR := 2.5 ## metres past the road's edge kept free, so the king's roads read as roads
const KINGDOM_RUIN_CLEAR := 4.0 ## metres past a ruin's pad kept free for the ruin kit
const KINGDOM_DENSITY := 0.55 ## share of Ashgrove's trees per square metre (most land is open)
const KINGDOM_MAX := 9000 ## a hard cap on the decorative forest, whatever the size
## How likely a spot is kept, per biome: forests are thick, fields and moor mostly open.
const KINGDOM_KEEP := {"forest": 1.0, "stone_hills": 0.32, "moor": 0.16, "farmland": 0.10}


## How many decorative trees and rocks a world gets for `count` on Ashgrove: the same on
## Ashgrove, scaled by area (and capped) on a kingdom.
static func count_for_world(count: int = 1800) -> int:
	if not WorldGen.is_kingdom():
		return count
	var area := pow(WorldGen.size_m() / WorldGen.ASHGROVE_SIZE, 2.0)
	return mini(int(count * area * KINGDOM_DENSITY), KINGDOM_MAX)


## The kingdom's forest: thick in forest, a few wind-bent pines and boulders on the stone
## hills, lone trees on moor and old fields; never on water, snow, the spawn plot, the king's
## roads or a ruin's pad. Seeded from the world seed, so every machine grows the same one.
static func _scatter_kingdom(count: int) -> Array:
	var target := count_for_world(count)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(WorldGen.config().seed) + 7
	var out: Array = []
	var h := WorldGen.half_size() - 4.0
	var sp := WorldGen.spawn_point()
	var pads := ruin_pads(WorldGen.ruin_sites())
	var tries := 0
	while out.size() < target and tries < target * 10:
		tries += 1
		var x := rng.randf_range(-h, h)
		var z := rng.randf_range(-h, h)
		var keep := rng.randf()
		var r := rng.randf()
		var sc := rng.randf_range(0.7, 1.4)
		var rot := rng.randf() * TAU
		if Vector2(x - sp.x, z - sp.z).length() < KINGDOM_SPAWN_CLEAR:
			continue
		var y := Terrain.height(x, z)
		var biome := WorldGen.biome_for(x, z, y)
		if keep >= float(KINGDOM_KEEP.get(biome, 0.0)):
			continue # water, shore, snow, or an open stretch of field and moor
		# Cheapest looks first (the road, then the ruin pads, then the beach ring, which reads
		# the ground up to 17 times); the order never changes which spots are kept.
		if WorldGen.road_distance(x, z) < WorldGen.ROAD_HALF_WIDTH + KINGDOM_ROAD_CLEAR:
			continue
		if on_pad(x, z, pads):
			continue
		if WorldGen.near_sand(x, z):
			continue # no forest tree or rock at the beach's edge (owner, 2026-11-27); palms grow there (Flora)
		var slope := absf(Terrain.height(x + 1.0, z) - y) + absf(Terrain.height(x, z + 1.0) - y)
		var kind := "rock"
		if slope < 0.8:
			match biome:
				"forest":
					kind = ("pine" if r < 0.8 else "ash") if y > 16.0 else ("ash" if r < 0.6 else ("pine" if r < 0.9 else "rock"))
				"stone_hills":
					kind = "pine" if r < 0.45 else "rock"
				"moor":
					kind = "rock" if r < 0.55 else "pine"
				_:
					kind = "ash" if r < 0.75 else "rock"
		if not ResourceNodes.near(Vector3(x, 0.0, z), NODE_CLEARANCE).is_empty():
			continue
		out.append({"pos": Vector3(x, y - 0.1, z), "scale": sc, "kind": kind, "rot": rot})
	return out


static func _on_ruin(x: float, z: float, ruins: Array) -> bool:
	for site in ruins:
		var c: Vector3 = site.pos
		if Vector2(x - c.x, z - c.z).length() < float(site.radius) + KINGDOM_RUIN_CLEAR:
			return true
	return false


## The ruins' pads as flat numbers (x, z, kept radius, three per ruin) for `on_pad`, which
## answers like `_on_ruin` without reading a Dictionary per ruin: scatters ask it tens of
## thousands of times while a world is built.
static func ruin_pads(ruins: Array) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	for site in ruins:
		var c: Vector3 = site.pos
		out.append(c.x)
		out.append(c.z)
		out.append(float(site.radius) + KINGDOM_RUIN_CLEAR)
	return out


## True when (x, z) is on a ruin's pad: the same answer as `_on_ruin` on the same ruins.
static func on_pad(x: float, z: float, pads: PackedFloat64Array) -> bool:
	var i := 0
	var n := pads.size()
	while i < n:
		var dx := x - pads[i]
		var dz := z - pads[i + 1]
		var r := pads[i + 2]
		if dx * dx + dz * dz < r * r:
			return true
		i += 3
	return false
