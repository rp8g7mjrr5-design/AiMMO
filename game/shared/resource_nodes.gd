class_name ResourceNodes
## Where the gatherable things in Ashgrove are: ember ash trees, pines, stone outcrops and
## ember-sap seeps. This is the one list of resource nodes. The server will own each node's
## state (depleted or not) and the world stream draws a node prop at each position, so both
## read the same list from here and always agree.
##
## Pure and deterministic: the list depends only on GameConfig.WORLD_SEED and Terrain, so
## every machine builds it identically and nothing is stored in the database.
##
## A node's `id` is its index in the list and is PERMANENT once gathering ships (later
## systems will refer to nodes by id). Never reorder or re-roll the list. To add nodes, add
## a new placement pass that appends after the existing ones. tests/unit/test_gameplay_
## resource_nodes.gd pins a fingerprint of the list so an accidental change is caught.

const PLACEMENT_SEED_OFFSET := 101 ## rng seed = WORLD_SEED + this (Props uses + 7)

## What each kind of node gives. `respawn` is real seconds until a depleted node is back.
## `night_only` nodes can only be gathered at night (used by the gathering system, see
## WorldClock.is_night). Amounts and timers are first guesses, tuned once gathering exists.
const KINDS := {
	"ash": {"label": "Ember ash", "item": "ash_wood", "amount": 2, "respawn": 180.0, "night_only": false},
	"pine": {"label": "Pine", "item": "pine_wood", "amount": 2, "respawn": 180.0, "night_only": false},
	"stone": {"label": "Stone outcrop", "item": "stone", "amount": 2, "respawn": 240.0, "night_only": false},
	"ember_sap": {"label": "Ember-sap seep", "item": "ember_sap", "amount": 1, "respawn": 600.0, "night_only": true},
}
const KIND_ORDER := ["ash", "pine", "stone", "ember_sap"]

## Tier 2 (roadmap Milestone 1 part 3): richer nodes a short walk past the meadow that only
## open at a skill level. A tier-2 node keeps its `kind` (so world draws it as the old ash or
## the rich seam, NodeProps keys its look on kind + "tier") and these values replace the
## kind's own (KINDS) for it. `min_level` is in the skill the kind trains (Skills.KIND_SKILL).
## `seconds_scale` stretches the gather bar (GatherChannel) a little: a bigger tree, a harder
## rock. `charges` replaces Gathering.CHARGES. XP is in Skills (TIER_XP_SCALE).
const TIER2 := {
	"ash": {"label": "Old ember ash", "item": "ember_heartwood", "amount": 2, "respawn": 300.0,
		"night_only": false, "min_level": 5, "charges": 4, "seconds_scale": 1.2},
	"stone": {"label": "Rich stone seam", "item": "veinstone", "amount": 2, "respawn": 360.0,
		"night_only": false, "min_level": 5, "charges": 4, "seconds_scale": 1.2},
}
## The tier-2 ring: alternating old ashes and rich seams around the meadow, past the starter
## ring and the first wild nodes, so the first goal after level 5 is a short walk away and
## other players working toward it pass each other on the way.
const TIER2_SEED_OFFSET := 211 ## its own rng, so the passes before it never change
const TIER2_RING := ["ash", "stone", "ash", "stone", "ash", "stone", "ash", "stone"]
const TIER2_MIN_RADIUS := 48.0
const TIER2_MAX_RADIUS := 80.0
const TIER2_SPACING := 8.0 ## world asked for room: the old ash is 3 m in radius

## How many of each kind the wild placement pass aims for (it stops early if the terrain
## runs out of suitable spots, which the tests check doesn't happen).
const TARGETS := {"ash": 140, "pine": 110, "stone": 110, "ember_sap": 30}

const GATHER_RANGE := 3.0 ## metres from a player to a node's centre to gather it
const MIN_SPACING := 6.0 ## no two nodes closer than this
const SPAWN_CLEAR_RADIUS := 12.0 ## the very centre of Spawn Meadow stays empty
const STARTER_MIN_RADIUS := 16.0 ## the starter ring sits on the meadow's edge
const STARTER_MAX_RADIUS := 34.0
const EDGE_MARGIN := 6.0 ## keep nodes this far inside the world border
const MAX_HEIGHT := 22.0 ## nothing grows on the snowy peaks
const CELL := 32.0 ## spatial index cell size in metres

## The starter ring around Spawn Meadow: two of every kind (one ember-sap seep) so a new
## player finds everything near spawn and gathers alongside other new players.
const STARTER_KINDS := ["ash", "pine", "stone", "ash", "pine", "stone", "ember_sap"]

static var _nodes: Array = []
static var _grid: Dictionary = {}
## The WorldGen config the cached list was built for: a new config rebuilds it.
static var _built_for: Dictionary = {}


## Every node, as an Array of {id: int, kind: String, pos: Vector3, rot: float, scale: float,
## tier: int (1, or 2 for the level-gated ones), skill: String (the skill it trains),
## min_level: int (the level in that skill needed to gather it, 1 for anyone)}.
## Built once and cached; treat it as read-only.
static func all() -> Array:
	if _nodes.is_empty() or _built_for != WorldGen.config():
		_built_for = WorldGen.config()
		_nodes = generate()
		_grid = _index(_nodes)
	return _nodes


## Drops the cached list (the next all() builds it for the current WorldGen config). all()
## also notices a changed config on its own; this is for tests that want a clean start.
static func reset() -> void:
	_nodes = []
	_grid = {}
	_built_for = {}


static func count() -> int:
	return all().size()


## The node with this id, or an empty Dictionary for an unknown id (ids come from clients
## later, so never trust them).
static func get_by_id(id: int) -> Dictionary:
	var list := all()
	if id < 0 or id >= list.size():
		return {}
	return list[id]


## The kind's own values. For one node, use info(): a tier-2 node has its own.
static func kind_info(kind: String) -> Dictionary:
	return KINDS.get(kind, {})


## Everything about gathering one node: KINDS[kind], with TIER2[kind] over it for a tier-2
## node, plus `tier`, `skill` and `min_level`. Empty for an empty (unknown) node.
static func info(node: Dictionary) -> Dictionary:
	if node.is_empty():
		return {}
	var out: Dictionary = KINDS.get(str(node.kind), {}).duplicate()
	var tier := int(node.get("tier", 1))
	if tier >= 2:
		out.merge(TIER2.get(str(node.kind), {}), true)
	out.tier = tier
	out.skill = str(node.get("skill", Skills.skill_for_kind(str(node.kind))))
	out.min_level = int(node.get("min_level", 1))
	return out


static func info_by_id(id: int) -> Dictionary:
	return info(get_by_id(id))


## Nodes whose centre is within `radius` metres of `pos` (horizontal distance), nearest
## first. Pass `kind` to only get that kind.
static func near(pos: Vector3, radius: float, kind: String = "") -> Array:
	all()
	var out: Array = []
	var r2 := radius * radius
	var c0 := _cell(pos.x - radius, pos.z - radius)
	var c1 := _cell(pos.x + radius, pos.z + radius)
	for cx in range(c0.x, c1.x + 1):
		for cz in range(c0.y, c1.y + 1):
			for id in _grid.get(Vector2i(cx, cz), []):
				var n: Dictionary = _nodes[id]
				if kind != "" and n.kind != kind:
					continue
				if _flat_dist2(n.pos, pos) <= r2:
					out.append(n)
	out.sort_custom(func(a, b): return _flat_dist2(a.pos, pos) < _flat_dist2(b.pos, pos))
	return out


## The nearest node to `pos` (optionally of one kind), searching outward up to
## `max_radius`. Empty Dictionary if there is none in range.
static func nearest(pos: Vector3, kind: String = "", max_radius: float = 128.0) -> Dictionary:
	var r := CELL
	while true:
		var found := near(pos, minf(r, max_radius), kind)
		if not found.is_empty():
			return found[0]
		if r >= max_radius:
			return {}
		r *= 2.0
	return {}


## True if a player standing at `player_pos` is close enough to gather node `id`.
static func in_range(id: int, player_pos: Vector3) -> bool:
	var n := get_by_id(id)
	if n.is_empty():
		return false
	return _flat_dist2(n.pos, player_pos) <= GATHER_RANGE * GATHER_RANGE


## Builds the list from scratch for the world WorldGen is configured for. Use all() instead;
## this is public for tests. Ashgrove (gen_version 0) keeps its own three passes and ids
## exactly as before; a generated kingdom takes WorldGen's node spots in their order (index =
## id) and then its own tier-2 ring around the kingdom's spawn.
static func generate() -> Array:
	if WorldGen.is_kingdom():
		return _generate_kingdom()
	var rng := RandomNumberGenerator.new()
	rng.seed = GameConfig.WORLD_SEED + PLACEMENT_SEED_OFFSET
	var out: Array = []
	var grid := {}
	_place_starter_ring(rng, out, grid)
	_place_wild(rng, out, grid)
	var rng2 := RandomNumberGenerator.new()
	rng2.seed = GameConfig.WORLD_SEED + TIER2_SEED_OFFSET
	_place_tier2(rng2, out, grid)
	return out


## Pass 1: the starter ring. Evenly spaced angles with a little jitter, on the flat meadow.
static func _place_starter_ring(rng: RandomNumberGenerator, out: Array, grid: Dictionary) -> void:
	var n := STARTER_KINDS.size()
	for i in n:
		for attempt in 20:
			var ang := TAU * float(i) / n + rng.randf_range(-0.25, 0.25)
			var dist := rng.randf_range(STARTER_MIN_RADIUS, STARTER_MAX_RADIUS)
			var x := cos(ang) * dist
			var z := sin(ang) * dist
			if _too_close(grid, out, x, z):
				continue
			_add(out, grid, STARTER_KINDS[i], x, z, rng)
			break


## Pass 2: the wild. Kind follows the land: ash in the warm lowlands (with the odd ember-sap
## seep among them), pine on higher flat ground, stone on steep slopes and ridges.
static func _place_wild(rng: RandomNumberGenerator, out: Array, grid: Dictionary) -> void:
	var placed := {}
	var want := 0
	for k in KIND_ORDER:
		placed[k] = 0
		want += TARGETS[k]
	var h := WorldGen.half_size() - EDGE_MARGIN
	var tries := 0
	var done := 0
	while done < want and tries < want * 40:
		tries += 1
		var x := rng.randf_range(-h, h)
		var z := rng.randf_range(-h, h)
		var roll := rng.randf()
		if Vector2(x, z).length() < STARTER_MAX_RADIUS + MIN_SPACING:
			continue # the meadow keeps only its starter ring
		var y := Terrain.height(x, z)
		if y < Terrain.water_level() + 1.0 or y > MAX_HEIGHT:
			continue
		var kind := _kind_for(y, _slope(x, z, y), roll)
		if placed[kind] >= TARGETS[kind] or _too_close(grid, out, x, z):
			continue
		_add(out, grid, kind, x, z, rng)
		placed[kind] += 1
		done += 1


## Pass 3 (appended 2026-11-23, Milestone 1 part 3): the tier-2 ring. Each node tries
## angles near its slot and distances from TIER2_MIN_RADIUS outward until it finds dry,
## not too steep ground with TIER2_SPACING of room. Appends only: ids before it never move.
static func _place_tier2(rng: RandomNumberGenerator, out: Array, grid: Dictionary) -> void:
	var n := TIER2_RING.size()
	for i in n:
		var kind: String = TIER2_RING[i]
		for attempt in 60:
			var ang := TAU * (float(i) + 0.5) / n + rng.randf_range(-0.3, 0.3)
			var dist := lerpf(TIER2_MIN_RADIUS, TIER2_MAX_RADIUS, minf(1.0, attempt / 40.0)) + rng.randf_range(0.0, 6.0)
			var x := cos(ang) * dist
			var z := sin(ang) * dist
			var y := Terrain.height(x, z)
			if y < Terrain.water_level() + 1.0 or y > MAX_HEIGHT:
				continue
			if kind == "ash" and _slope(x, z, y) > 0.8:
				continue # an old tree stands on fairly level ground
			if _too_close(grid, out, x, z, TIER2_SPACING):
				continue
			_add(out, grid, kind, x, z, rng, 2)
			break


## A generated kingdom (gen_version 1, Phase 1 part 3): every spot WorldGen hands out, in its
## order (starter ring on the spawn plot first, then the wild), then the tier-2 ring around
## the kingdom's spawn, so "Felling 5 opens the old ashes" is a short walk on every world.
## Ids are permanent per config once a world runs on it: never reorder; append new passes.
static func _generate_kingdom() -> Array:
	var out: Array = []
	var grid := {}
	for spot in WorldGen.node_spots():
		var p: Vector3 = spot.pos
		_append(out, grid, str(spot.kind), p, float(spot.rot), float(spot.scale), 1)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(WorldGen.config().seed) + TIER2_SEED_OFFSET
	var sp := WorldGen.spawn_point()
	var n := TIER2_RING.size()
	for i in n:
		var kind: String = TIER2_RING[i]
		for attempt in 80:
			var ang := TAU * (float(i) + 0.5) / n + rng.randf_range(-0.3, 0.3)
			var dist := lerpf(TIER2_MIN_RADIUS, TIER2_MAX_RADIUS * 1.5, minf(1.0, attempt / 60.0)) + rng.randf_range(0.0, 6.0)
			var x := sp.x + cos(ang) * dist
			var z := sp.z + sin(ang) * dist
			if not _kingdom_ground_ok(x, z, kind):
				continue
			if _too_close(grid, out, x, z, TIER2_SPACING):
				continue
			var rot := rng.randf() * TAU
			var scale := rng.randf_range(0.95, 1.05)
			_append(out, grid, kind, Vector3(x, Terrain.height(x, z), z), rot, scale, 2)
			break
	return out


## Dry land below the snow, off the king's roads and the river, not inside a ruin, inside
## the border: where a tier-2 node may stand on a kingdom.
static func _kingdom_ground_ok(x: float, z: float, kind: String) -> bool:
	var lim := WorldGen.half_size() - EDGE_MARGIN
	if absf(x) > lim or absf(z) > lim:
		return false
	var y := Terrain.height(x, z)
	if y < Terrain.water_level() + 1.0 or y > WorldGen.SNOW_LINE:
		return false
	if kind == "ash" and _slope(x, z, y) > 0.8:
		return false
	if WorldGen.road_distance(x, z) < WorldGen.ROAD_HALF_WIDTH + 2.5:
		return false
	if WorldGen.river_distance(x, z) < WorldGen.RIVER_HALF_WIDTH + 4.0:
		return false
	for s in WorldGen.ruin_sites():
		if Vector2(x - s.pos.x, z - s.pos.z).length() < float(s.radius) + 6.0:
			return false
	return true


static func _kind_for(y: float, slope: float, roll: float) -> String:
	if slope > 1.0 or y > 12.0:
		return "stone"
	if y > 6.0:
		return "pine" if roll < 0.85 else "stone"
	if roll < 0.12:
		return "ember_sap"
	return "ash" if roll < 0.9 else "pine"


static func _slope(x: float, z: float, y: float) -> float:
	return absf(Terrain.height(x + 1.0, z) - y) + absf(Terrain.height(x, z + 1.0) - y)


static func _add(out: Array, grid: Dictionary, kind: String, x: float, z: float, rng: RandomNumberGenerator, tier: int = 1) -> void:
	var id := out.size()
	# rot and scale are rolled in this order for every node, so tier 1 rolls as before.
	var rot := rng.randf() * TAU
	var scale := rng.randf_range(0.85, 1.2) if tier == 1 else rng.randf_range(0.95, 1.05)
	out.append({
		"id": id,
		"kind": kind,
		"pos": Vector3(x, Terrain.height(x, z), z),
		"rot": rot,
		"scale": scale,
		"tier": tier,
		"skill": Skills.skill_for_kind(kind),
		"min_level": int(TIER2.get(kind, {}).get("min_level", 1)) if tier >= 2 else 1,
	})
	var c := _cell(x, z)
	if not grid.has(c):
		grid[c] = []
	grid[c].append(id)


## Adds a node with a known place, turn and size (the kingdom path; _add rolls its own).
static func _append(out: Array, grid: Dictionary, kind: String, pos: Vector3, rot: float, scale: float, tier: int) -> void:
	var id := out.size()
	out.append({
		"id": id, "kind": kind, "pos": pos, "rot": rot, "scale": scale, "tier": tier,
		"skill": Skills.skill_for_kind(kind),
		"min_level": int(TIER2.get(kind, {}).get("min_level", 1)) if tier >= 2 else 1,
	})
	var c := _cell(pos.x, pos.z)
	if not grid.has(c):
		grid[c] = []
	grid[c].append(id)


static func _too_close(grid: Dictionary, out: Array, x: float, z: float, spacing: float = MIN_SPACING) -> bool:
	var p := Vector3(x, 0.0, z)
	var c := _cell(x, z)
	for cx in range(c.x - 1, c.x + 2):
		for cz in range(c.y - 1, c.y + 2):
			for id in grid.get(Vector2i(cx, cz), []):
				if _flat_dist2(out[id].pos, p) < spacing * spacing:
					return true
	return false


static func _index(list: Array) -> Dictionary:
	var grid := {}
	for n in list:
		var c := _cell(n.pos.x, n.pos.z)
		if not grid.has(c):
			grid[c] = []
		grid[c].append(n.id)
	return grid


static func _cell(x: float, z: float) -> Vector2i:
	return Vector2i(floori(x / CELL), floori(z / CELL))


static func _flat_dist2(a: Vector3, b: Vector3) -> float:
	var dx := a.x - b.x
	var dz := a.z - b.z
	return dx * dx + dz * dz


## A short stable text summary of the whole list (or of its first `upto` nodes), used by the
## tests to notice any change.
static func fingerprint(upto: int = -1) -> String:
	var list := all()
	var n_used := list.size() if upto < 0 else mini(upto, list.size())
	var parts := PackedStringArray()
	for i in n_used:
		var n: Dictionary = list[i]
		parts.append("%d:%s:%.2f:%.2f" % [n.id, n.kind, n.pos.x, n.pos.z])
	return "%d-%s" % [n_used, "\n".join(parts).md5_text()]


## Every tier-2 node (Array of nodes), in id order.
static func tier2() -> Array:
	var out: Array = []
	for n in all():
		if int(n.get("tier", 1)) >= 2:
			out.append(n)
	return out


## One line for the server log.
static func describe() -> String:
	var by_kind := {}
	for n in all():
		by_kind[n.kind] = by_kind.get(n.kind, 0) + 1
	var bits := PackedStringArray()
	for k in KIND_ORDER:
		bits.append("%s %d" % [k, by_kind.get(k, 0)])
	return "%d nodes (%s, %d tier 2)" % [count(), ", ".join(bits), tier2().size()]
