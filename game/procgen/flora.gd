class_name Flora
## Biome variety: birch groves on the lake shores, mossy boulders in the pine forests, and
## wildflower patches in the grassy lowlands. All deterministic from the world seed.
##
## This is a second, independent scatter on its own seed, so the existing forest from
## `Props.scatter` is untouched (same trees in the same places). Flora only fills gaps: it
## keeps clear of resource nodes, of the Spawn Meadow, and of decorative trees and rocks.
##
## Split like NodeProps and Lamps: `spots()`, `parts()` and `layout()` are pure data (safe
## headless, in unit tests and bots); `build()` makes the "Flora" node of MultiMeshes.
## Nothing is saved from flora, so changing it never touches player data.

const SEED_OFFSET := 401
const NODE_CLEARANCE := 3.0 ## same as Props: never stand on a resource node
const SPAWN_CLEAR := 11.0 ## outside the lantern ring (9 m) so the meadow stays open
const TREE_CLEARANCE := 2.2 ## don't grow into a decorative tree or rock
const SHORE_PROBE := 9.0 ## a birch needs open water within this many metres
const FOREST_MIN := 6.0 ## pine-forest heights (matches Props and Palette.ground)
const FOREST_MAX := 13.0
const BIRCHES := 260
const BOULDERS := 150
const FLOWER_PATCHES := 220
const FLOWERS_PER_PATCH := 12

const BARK := Color(0.90, 0.88, 0.82) ## birch bark: chalk white, a little warm
const BARK_MARK := Color(0.20, 0.18, 0.17)
const BIRCH_LEAF := Color(0.68, 0.76, 0.36) ## fresh yellow-green, so the shore reads apart from ash orange and pine green
const MOSS := Color(0.36, 0.52, 0.22)
const STEM := Color(0.30, 0.48, 0.22)
## Wildflower colours. Each patch picks one, with a few odd ones mixed in.
const BLOOMS := [Color(0.97, 0.86, 0.38), Color(0.66, 0.50, 0.86), Color(0.96, 0.95, 0.90), Color(0.92, 0.42, 0.30), Color(0.55, 0.70, 0.95)]

const LAYERS := ["BirchBark", "BirchMarks", "BirchCrowns", "MossRocks", "Moss", "FlowerStems", "FlowerBlooms"]

static var _spots: Array = []


## Every flora spot: Array of {kind: "birch"|"boulder"|"flowers", pos: Vector3 (on the ground),
## rot: float, scale: float, tone: float (0..1, small colour variation), bloom: int (flowers)}.
## Built once and cached; treat it as read-only.
static func spots() -> Array:
	if _spots.is_empty():
		_spots = generate()
	return _spots


static func generate() -> Array:
	var blockers := _Grid.new(TREE_CLEARANCE)
	for it in Props.scatter():
		blockers.add(it.pos)
	var out: Array = []
	_scatter(out, "birch", BIRCHES, SEED_OFFSET, blockers, _is_shore)
	_scatter(out, "boulder", BOULDERS, SEED_OFFSET + 1, blockers, _is_forest_floor)
	var mask := FastNoiseLite.new() # where flower meadows are; patches cluster where it is high
	mask.seed = GameConfig.WORLD_SEED + SEED_OFFSET + 3
	mask.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	mask.frequency = 0.018
	_scatter(out, "flowers", FLOWER_PATCHES, SEED_OFFSET + 2, blockers,
		func(x: float, z: float, y: float, slope: float) -> bool: return _is_grassland(x, z, y, slope) and mask.get_noise_2d(x, z) > 0.15)
	return out


static func _scatter(out: Array, kind: String, count: int, seed_offset: int, blockers: _Grid, fits: Callable) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = GameConfig.WORLD_SEED + seed_offset
	var h := GameConfig.WORLD_HALF_SIZE - 4.0
	var placed := 0
	var tries := 0
	while placed < count and tries < count * 60:
		tries += 1
		var x := rng.randf_range(-h, h)
		var z := rng.randf_range(-h, h)
		var rot := rng.randf() * TAU
		var s := rng.randf_range(0.75, 1.3)
		var tone := rng.randf()
		var bloom := rng.randi_range(0, BLOOMS.size() - 1)
		if Vector2(x - GameConfig.SPAWN_POINT.x, z - GameConfig.SPAWN_POINT.z).length() < SPAWN_CLEAR:
			continue
		var y := Terrain.height(x, z)
		var slope := absf(Terrain.height(x + 1.0, z) - y) + absf(Terrain.height(x, z + 1.0) - y)
		if not fits.call(x, z, y, slope):
			continue
		var p := Vector3(x, y, z)
		if not ResourceNodes.near(p, NODE_CLEARANCE).is_empty() or blockers.hit(p):
			continue
		blockers.add(p) # flora doesn't stack on flora either
		out.append({"kind": kind, "pos": p, "rot": rot, "scale": s, "tone": tone, "bloom": bloom})
		placed += 1


## On dry ground just above a lake, with open water close by.
static func _is_shore(x: float, z: float, y: float, slope: float) -> bool:
	if y < Terrain.water_level() + 0.6 or y > Terrain.water_level() + 5.0 or slope > 0.9:
		return false
	for i in 8:
		var a := TAU * i / 8.0
		if Terrain.height(x + cos(a) * SHORE_PROBE, z + sin(a) * SHORE_PROBE) < Terrain.water_level():
			return true
	return false


static func _is_forest_floor(_x: float, _z: float, y: float, slope: float) -> bool:
	return y > FOREST_MIN and y < FOREST_MAX and slope < 1.4


static func _is_grassland(_x: float, _z: float, y: float, slope: float) -> bool:
	return y > Terrain.water_level() + 1.5 and y < FOREST_MIN - 0.5 and slope < 0.5


## Every part of one spot in world space: Array of {layer, xform, color}.
static func parts(spot: Dictionary) -> Array:
	var out: Array = []
	var origin: Vector3 = spot.pos
	var s: float = spot.scale
	var turn := Basis(Vector3.UP, spot.rot)
	var put := func(layer: String, local_pos: Vector3, size: Vector3, color: Color, tilt: Basis = Basis.IDENTITY) -> void:
		out.append({"layer": layer, "xform": Transform3D(turn * tilt * Basis.from_scale(size), origin + turn * local_pos), "color": color})
	var vary := _vary(spot)
	match spot.kind:
		"birch":
			var trunk_h := 4.2 * s
			var lean := Basis(Vector3.RIGHT, vary[0] * 0.10) # birches lean a little toward the light
			put.call("BirchBark", lean * Vector3(0, trunk_h * 0.5 - 0.1, 0), Vector3(0.20, trunk_h, 0.20) * Vector3(s, 1, s), BARK.darkened(spot.tone * 0.08), lean)
			for m in 3: # dark bark marks, the thing that makes a birch a birch
				var mh: float = trunk_h * (0.22 + m * 0.2 + vary[m + 1] * 0.04)
				put.call("BirchMarks", lean * Vector3(0, mh, 0), Vector3(0.215 * s, 0.07, 0.215 * s), BARK_MARK, lean)
			var leaf := BIRCH_LEAF.lerp(Color(0.86, 0.80, 0.40), spot.tone * 0.5)
			put.call("BirchCrowns", lean * Vector3(0, trunk_h * 0.86, 0), Vector3(1.5, 2.4, 1.5) * s, leaf, lean)
			put.call("BirchCrowns", lean * Vector3(0.35 * s, trunk_h * 1.02, -0.2 * s), Vector3(1.0, 1.6, 1.0) * s, leaf.lightened(0.06), lean)
		"boulder":
			var squash := Vector3(1.9, 1.2, 1.6) * s
			put.call("MossRocks", Vector3(0, 0.35 * s, 0), squash, Palette.ROCK.darkened(0.08 + spot.tone * 0.12))
			put.call("Moss", Vector3(0.05 * s, 0.82 * s, 0), Vector3(1.55, 0.45, 1.3) * s, MOSS.lerp(Palette.FOREST, spot.tone * 0.5))
			if spot.tone > 0.5: # some boulders have a smaller companion
				put.call("MossRocks", Vector3(1.3 * s, 0.15 * s, 0.5 * s), Vector3(0.8, 0.6, 0.7) * s, Palette.ROCK.darkened(0.12))
				put.call("Moss", Vector3(1.3 * s, 0.4 * s, 0.5 * s), Vector3(0.62, 0.22, 0.55) * s, MOSS)
		"flowers":
			var base: Color = BLOOMS[spot.bloom]
			for i in FLOWERS_PER_PATCH:
				var a: float = TAU * i / FLOWERS_PER_PATCH + vary[i % 4] * 0.8
				var r: float = (0.3 + 0.9 * fposmod(vary[(i + 1) % 4] * (i + 1) * 1.7, 1.0)) * s
				var off := Vector3(cos(a) * r, 0.0, sin(a) * r)
				var wp := origin + turn * off
				var ground := Terrain.height(wp.x, wp.z) - origin.y # each flower stands on its own patch of ground
				var stem_h: float = 0.32 + 0.18 * fposmod(vary[i % 4] * (i + 3), 1.0)
				put.call("FlowerStems", off + Vector3(0, ground + stem_h * 0.5, 0), Vector3(0.035, stem_h, 0.035), STEM)
				var c: Color = base if i % 5 != 3 else BLOOMS[(spot.bloom + 2) % BLOOMS.size()] # a couple of odd flowers per patch
				put.call("FlowerBlooms", off + Vector3(0, ground + stem_h, 0), Vector3(0.21, 0.13, 0.21), c)
	return out


## Four stable numbers in -1..1 for a spot, from its position, so the look never draws from
## the placement rng.
static func _vary(spot: Dictionary) -> Array:
	var p: Vector3 = spot.pos
	var hsh := hash(Vector2i(int(p.x * 10.0), int(p.z * 10.0)))
	var out: Array = []
	for i in 4:
		out.append(((hsh >> (i * 8)) & 0xff) / 127.5 - 1.0)
	return out


## {layer: Array of [Transform3D, Color]} for every spot.
static func layout(all_spots: Array) -> Dictionary:
	var layers := {}
	for l in LAYERS:
		layers[l] = []
	for spot in all_spots:
		for p in parts(spot):
			layers[p.layer].append([p.xform, p.color])
	return layers


static func count(kind: String) -> int:
	return spots().filter(func(s): return s.kind == kind).size()


## The Flora node WorldBuilder adds.
static func build() -> Node3D:
	var root := Node3D.new()
	root.name = "Flora"
	var lay := layout(spots())
	var meshes := _meshes()
	for l in LAYERS:
		# Chunked by area with per-layer draw distances and shadows (see `Chunks`): flowers
		# stop at 90 m and cast no shadow, as before; now per chunk instead of per world.
		root.add_child(Chunks.build(l, meshes[l], lay[l], layer_material(l)))
	return root


static func _meshes() -> Dictionary:
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.35
	trunk.bottom_radius = 0.5
	trunk.height = 1.0
	trunk.radial_segments = 6
	trunk.rings = 1
	var band := CylinderMesh.new()
	band.top_radius = 0.5
	band.bottom_radius = 0.5
	band.height = 1.0
	band.radial_segments = 6
	band.rings = 1
	var crown := SphereMesh.new() # tall, narrow birch crowns
	crown.radius = 0.5
	crown.height = 1.0
	crown.radial_segments = 6
	crown.rings = 3
	var rock := SphereMesh.new()
	rock.radius = 0.5
	rock.height = 1.0
	rock.radial_segments = 6
	rock.rings = 2
	var moss := SphereMesh.new()
	moss.radius = 0.5
	moss.height = 1.0
	moss.radial_segments = 6
	moss.rings = 2
	moss.is_hemisphere = true
	var stem := CylinderMesh.new()
	stem.top_radius = 0.5
	stem.bottom_radius = 0.5
	stem.height = 1.0
	stem.radial_segments = 4
	stem.rings = 1
	var bloom := SphereMesh.new()
	bloom.radius = 0.5
	bloom.height = 1.0
	bloom.radial_segments = 5
	bloom.rings = 2
	# Baked vertex colours (Emberlight): dark at the foot, lighter up the height. Same
	# vertices, so WorldSolids (which reads these meshes) is unchanged.
	return {
		"BirchBark": Emberlight.bake(trunk, 0.40, 1.6),
		"BirchMarks": Emberlight.bake(band, 0.0),
		"BirchCrowns": Emberlight.bake(crown, 0.30),
		"MossRocks": Emberlight.bake(rock, 0.40, 1.5),
		"Moss": Emberlight.bake(moss, 0.20),
		"FlowerStems": Emberlight.bake(stem, 0.30),
		"FlowerBlooms": bloom,
	}


## Which shared Emberlight material each flora layer uses: all of them share `solid` with the
## scatter forest. (Not `foliage` for the birch crowns yet: its sway is in mesh units, and
## these are unit meshes scaled up, so a 4 m crown would swing about 0.3 m and slide off its
## trunk. See the world backlog follow-up.)
static func layer_material(_layer: String) -> ShaderMaterial:
	return Emberlight.material("solid")


## A tiny flat spatial hash for "is anything within `radius` of here".
class _Grid:
	var radius: float
	var cells := {}

	func _init(r: float) -> void:
		radius = r

	func _key(x: float, z: float) -> Vector2i:
		return Vector2i(floori(x / radius), floori(z / radius))

	func add(p: Vector3) -> void:
		var k := _key(p.x, p.z)
		if not cells.has(k):
			cells[k] = []
		cells[k].append(Vector2(p.x, p.z))

	func hit(p: Vector3) -> bool:
		var k := _key(p.x, p.z)
		var q := Vector2(p.x, p.z)
		for dx in range(-1, 2):
			for dz in range(-1, 2):
				for o in cells.get(k + Vector2i(dx, dz), []):
					if (o as Vector2).distance_to(q) < radius:
						return true
		return false
