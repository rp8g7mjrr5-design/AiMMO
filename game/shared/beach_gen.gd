class_name BeachGen
## The starting beaches (owner, 2026-11-26: "lets talk our starting beach": landmarks, things
## to collect, a polished ocean). On an island (WorldGen gen_version 2) new characters wash up
## on one of the landings with nothing; this file dresses every landing so each one is its own
## place: a landmark or two rolled from LANDMARKS, things to pick up off the sand (driftwood,
## loose stones, kelp, a smashed crate: real resource nodes, see `nodes()`), shells and wrack
## to look at, tide pools in the wet sand and a far wreck out on the horizon.
##
## What a player feels: you wake on the sand next to a broken hull or an old pier, and within
## a few steps you've pulled planks out of a crate and driftwood off the tideline, enough for a
## wooden pickaxe before you've walked off the beach. Every beach looks and plays differently.
##
## Plain data and pure functions only (the server reads `nodes()`); the look is BeachProps
## (client). Everything comes from the world config and the landing's index through seeded
## RandomNumberGenerators, so every machine dresses every beach the same. It reads the island
## only through WorldGen and Terrain and never changes them: the island's layout, terrain and
## older node ids are untouched (ResourceNodes appends the beach nodes after every older pass).
## Ashgrove and version 1 kingdoms have no beaches (empty lists).
##
## The Zombai stay as they are on the beach (owner left it open, 2026-11-26): no extra walkers
## spawn here, so your first minute is for finding your feet; a dead one slumped in the
## fishing shack and the walkers that rise on their own anywhere outside the world's spawn tell
## you what the island is.

const SEED_OFFSET := 4513 ## rng seed = world seed * 7919 + landing index * 131 + this
const CLEAR := 13.0 ## nothing stands this close to a landing: the lantern ring and the bench live there

## Landmarks: one or two per beach, never the same twice on one beach. `weight` is how often
## it is rolled; `r` its footprint radius in metres (for spacing); `where` where it lies:
## "surf" half in the breaking waves, "sand" on the dry sand, "pier" from the sand out to sea,
## "back" at the back of the beach.
const LANDMARKS := {
	"shipwreck": {"weight": 3.0, "r": 8.0, "where": "surf"},
	"lifeboat": {"weight": 3.0, "r": 3.5, "where": "sand"},
	"old_pier": {"weight": 2.0, "r": 4.0, "where": "pier"},
	"whale_bones": {"weight": 2.0, "r": 7.0, "where": "sand"},
	"fishing_shack": {"weight": 2.0, "r": 5.0, "where": "back"},
}
const LANDMARK_ORDER := ["shipwreck", "lifeboat", "old_pier", "whale_bones", "fishing_shack"]
const TWO_LANDMARKS := 0.45 ## chance a beach gets a second landmark
const PIER_LENGTH := 22.0

## Beach resource nodes per beach (kind: how many). Kinds are ResourceNodes.BEACH_KINDS.
const NODE_PLAN := {"driftwood": 2, "beach_stones": 1, "kelp": 2, "wreck_crate": 1}
const NODE_SPACING := 6.0 ## same as ResourceNodes.MIN_SPACING

const DECO_COUNT := 46 ## shells, pebbles, wrack and sticks scattered per beach
const POOLS := [2, 3] ## tide pools per beach (min, max)
const REACH := 46.0 ## metres along the coast to each side that a beach is dressed

static var _beaches: Array = []
static var _built_for: Dictionary = {}


## Every beach, one per WorldGen.landings() entry in the same order:
## {index, landing: Vector2, sea: Vector2 (unit, seaward), side: Vector2 (along the coast),
##  shore: float (metres from the landing to the waterline straight out),
##  landmarks: [{kind, pos: Vector3, rot, seed}], nodes: [{kind, pos: Vector3, rot, scale}],
##  deco: [{kind, pos: Vector3, rot, scale}], pools: [{pos: Vector3, r}],
##  far: [{pos: Vector3, rot, scale}] (a wreck out on the horizon)}.
static func all() -> Array:
	if not WorldGen.is_island():
		return []
	if _beaches.is_empty() or _built_for != WorldGen.config():
		_built_for = WorldGen.config()
		_beaches = []
		var lands := WorldGen.landings()
		for i in lands.size():
			_beaches.append(_build(i, lands[i]))
	return _beaches


static func reset() -> void:
	_beaches = []
	_built_for = {}


## One beach by landing index, or {} when there is none.
static func beach(i: int) -> Dictionary:
	var list := all()
	if i < 0 or i >= list.size():
		return {}
	return list[i]


## Every beach node on the island, beach by beach: [{kind, pos: Vector3, rot, scale}].
## ResourceNodes appends these (in this order) after its older passes.
static func nodes() -> Array:
	var out: Array = []
	for b in all():
		out.append_array(b.nodes)
	return out


## Every landmark on the island: [{kind, pos, rot, seed, beach}].
static func landmarks() -> Array:
	var out: Array = []
	for b in all():
		for l in b.landmarks:
			var e: Dictionary = l.duplicate()
			e.beach = b.index
			out.append(e)
	return out


## What players read for a landmark kind.
static func label(kind: String) -> String:
	return {"shipwreck": "Shipwreck", "lifeboat": "Lifeboat", "old_pier": "Old Pier",
		"whale_bones": "Whale Bones", "fishing_shack": "Fishing Shack"}.get(kind, kind.capitalize())


# ---------------------------------------------------------------------------------------

static func _build(i: int, lp: Vector2) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(WorldGen.config().seed) * 7919 + i * 131 + SEED_OFFSET
	var sea := seaward(lp)
	var side := Vector2(-sea.y, sea.x)
	var b := {
		"index": i, "landing": lp, "sea": sea, "side": side,
		"shore": waterline(lp, sea), "landmarks": [], "nodes": [], "deco": [], "pools": [], "far": [],
	}
	var taken: Array = [] # [Vector2, radius] footprints so nothing lands on anything else
	for s in WorldGen.node_spots():
		if s.starter and Vector2(s.pos.x, s.pos.z).distance_to(lp) < 90.0:
			taken.append([Vector2(s.pos.x, s.pos.z), 2.0])
	_place_landmarks(b, rng, taken)
	_place_nodes(b, rng, taken)
	_place_pools(b, rng, taken)
	_place_deco(b, rng)
	_place_far(b, rng)
	return b


## The seaward direction at a landing: the way the ground falls to the sea, from the lowest
## average ground in 24 directions at 20 to 50 m out.
static func seaward(lp: Vector2) -> Vector2:
	var best := Vector2.RIGHT
	var best_h := INF
	for k in 24:
		var d := Vector2.from_angle(TAU * k / 24.0)
		var h := 0.0
		for r in [20.0, 35.0, 50.0]:
			h += Terrain.height(lp.x + d.x * r, lp.y + d.y * r)
		if h < best_h:
			best_h = h
			best = d
	# Refine between the neighbours of the best direction.
	var a := best.angle()
	var fine := a
	for k in range(-4, 5):
		var aa := a + k * (TAU / 24.0) / 8.0
		var d := Vector2.from_angle(aa)
		var h := 0.0
		for r in [20.0, 35.0, 50.0]:
			h += Terrain.height(lp.x + d.x * r, lp.y + d.y * r)
		if h < best_h:
			best_h = h
			fine = aa
	return Vector2.from_angle(fine)


## Metres from `p` along `dir` to the waterline (the first ground below the water), up to 120.
static func waterline(p: Vector2, dir: Vector2) -> float:
	var wl := Terrain.water_level()
	var t := 0.0
	while t < 120.0:
		var q := p + dir * t
		if Terrain.height(q.x, q.y) < wl:
			# Halve back to within 10 cm.
			var lo := maxf(t - 1.0, 0.0)
			var hi := t
			for n in 4:
				var m := (lo + hi) * 0.5
				var qm := p + dir * m
				if Terrain.height(qm.x, qm.y) < wl:
					hi = m
				else:
					lo = m
			return hi
		t += 1.0
	return 120.0


## A point on the sand: `along` metres along the coast from the landing, `up` metres inland
## of the waterline there (negative is out in the water).
static func on_beach(b: Dictionary, along: float, up: float) -> Vector2:
	# Start a little inland of where the landing's own waterline is, so the march is short.
	var sea: Vector2 = b.sea
	var p0: Vector2 = (b.landing as Vector2) + (b.side as Vector2) * along + sea * (float(b.shore) - 12.0)
	var w := waterline(p0, sea)
	if w <= 0.0: # the coast bends inland here: back off and look again
		p0 -= sea * 30.0
		w = waterline(p0, sea)
	return p0 + sea * (w - up)


static func _ground(p: Vector2) -> Vector3:
	return Vector3(p.x, Terrain.height(p.x, p.y), p.y)


static func _free(taken: Array, p: Vector2, r: float) -> bool:
	for t in taken:
		if p.distance_to(t[0]) < r + float(t[1]):
			return false
	return true


## Not on a location's pad, a road or a river mouth.
static func _clear_of_world(p: Vector2, r: float) -> bool:
	for s in WorldGen.ruin_sites():
		if p.distance_to(Vector2(s.pos.x, s.pos.z)) < float(s.radius) + r + 6.0:
			return false
	if WorldGen.river_distance(p.x, p.y) < WorldGen.RIVER_HALF_WIDTH + r + 4.0:
		return false
	return true


static func _pick(rng: RandomNumberGenerator, skip: Array) -> String:
	var total := 0.0
	for k in LANDMARK_ORDER:
		if not skip.has(k):
			total += float(LANDMARKS[k].weight)
	var roll := rng.randf() * total
	for k in LANDMARK_ORDER:
		if skip.has(k):
			continue
		roll -= float(LANDMARKS[k].weight)
		if roll <= 0.0:
			return k
	return LANDMARK_ORDER[0]


static func _place_landmarks(b: Dictionary, rng: RandomNumberGenerator, taken: Array) -> void:
	var want := 2 if rng.randf() < TWO_LANDMARKS else 1
	var sides := [1.0 if rng.randf() < 0.5 else -1.0]
	sides.append(-sides[0])
	var kinds: Array = []
	var wl := Terrain.water_level()
	for n in want:
		var kind := _pick(rng, kinds)
		var e: Dictionary = LANDMARKS[kind]
		var r := float(e.r)
		for attempt in 24:
			var along: float = sides[n] * rng.randf_range(CLEAR + r, CLEAR + r + 22.0) + rng.randf_range(-3.0, 3.0) * attempt * 0.2
			var up := 0.0
			match str(e.where):
				"surf":
					up = rng.randf_range(-3.5, -1.0)
				"sand":
					up = rng.randf_range(5.0, 9.0)
				"pier":
					up = 3.0
				"back":
					up = float(b.shore) + rng.randf_range(-2.0, 4.0) # level with the landing, off to one side
			var p := on_beach(b, along, up)
			var lp: Vector2 = b.landing
			if p.distance_to(lp) < CLEAR + r:
				continue
			if not _free(taken, p, r) or not _clear_of_world(p, r):
				continue
			var h := Terrain.height(p.x, p.y)
			if str(e.where) != "surf" and (h < wl + 0.15 or h > 4.5):
				continue
			if str(e.where) == "surf" and h < wl - 2.0:
				continue
			# Facing: a pier runs straight out to sea; a hull lies along the surf a little askew;
			# the rest are turned any way that suits them.
			var sea: Vector2 = b.sea
			var rot := 0.0
			match kind:
				"old_pier":
					rot = atan2(sea.x, sea.y)
				"shipwreck":
					# Driven bow-first up the sand: her keel (BeachProps' local +X) points inland,
					# give or take.
					rot = atan2(sea.x, sea.y) + PI * 0.5 + rng.randf_range(-0.6, 0.6)
				"fishing_shack":
					rot = atan2(sea.x, sea.y) + rng.randf_range(-0.3, 0.3) # its door looks out to sea
				_:
					rot = rng.randf() * TAU
			var lm := {"kind": kind, "pos": _ground(p), "rot": rot, "seed": rng.randi() & 0x7FFFFFFF}
			b.landmarks.append(lm)
			kinds.append(kind)
			taken.append([p, r])
			if kind == "old_pier":
				# Keep the deck's whole length clear.
				for k in range(1, 4):
					taken.append([p + sea * (PIER_LENGTH * k / 3.0), 3.0])
			break


static func _place_nodes(b: Dictionary, rng: RandomNumberGenerator, taken: Array) -> void:
	var wl := Terrain.water_level()
	var placed: Array = []
	# A crate first: inside the wreck or by the lifeboat when the beach has one, so the
	# landmark pays out, else on the tideline.
	for lm in b.landmarks:
		if lm.kind == "shipwreck" or lm.kind == "lifeboat":
			var lp3: Vector3 = lm.pos
			# Beside the boat, off her landward side (her local +Z or -Z, whichever is drier).
			var across := Vector2(sin(float(lm.rot)), cos(float(lm.rot)))
			if across.dot(b.sea) > 0.0:
				across = -across
			var p := Vector2(lp3.x, lp3.z) + across * 2.8
			if lm.kind == "shipwreck":
				# Thrown up on the sand off her stripped side (BeachProps' local +Z), out of the surf.
				var beside := Vector2(lp3.x, lp3.z) + Vector2(sin(float(lm.rot)), cos(float(lm.rot))) * 3.6
				var t := 0.0
				p = beside
				while t < 20.0 and Terrain.height(p.x, p.y) < wl + 0.25:
					t += 0.5
					p = beside - (b.sea as Vector2) * t
			b.nodes.append({"kind": "wreck_crate", "pos": _ground(p), "rot": rng.randf() * TAU, "scale": rng.randf_range(0.95, 1.1)})
			placed.append(p)
			break
	for kind in ["wreck_crate", "driftwood", "beach_stones", "kelp"]:
		var want := int(NODE_PLAN[kind])
		if kind == "wreck_crate":
			want -= placed.size()
		for n in want:
			for attempt in 40:
				var along := rng.randf_range(-REACH * 0.75, REACH * 0.75)
				var up := 0.0
				match kind:
					"kelp":
						up = rng.randf_range(0.6, 2.2) # the wet line, where the tide left it
					"driftwood":
						up = rng.randf_range(2.0, 9.0)
					_:
						up = rng.randf_range(3.0, 12.0)
				var p := on_beach(b, along, up)
				if p.distance_to(b.landing) < CLEAR - 4.0:
					continue
				if not _free(taken, p, 2.0) or not _clear_of_world(p, 2.0):
					continue
				var ok := true
				for q in placed:
					if p.distance_to(q) < NODE_SPACING:
						ok = false
				if not ok:
					continue
				var h := Terrain.height(p.x, p.y)
				if h < wl + 0.05 or h > 4.5:
					continue
				b.nodes.append({"kind": kind, "pos": _ground(p), "rot": rng.randf() * TAU, "scale": rng.randf_range(0.85, 1.15)})
				placed.append(p)
				break
	for q in placed:
		taken.append([q, 1.5])


static func _place_pools(b: Dictionary, rng: RandomNumberGenerator, taken: Array) -> void:
	var want := rng.randi_range(POOLS[0], POOLS[1])
	var wl := Terrain.water_level()
	for n in want:
		for attempt in 20:
			var r := rng.randf_range(1.1, 2.0)
			var p := on_beach(b, rng.randf_range(-REACH, REACH), rng.randf_range(1.5, 4.5))
			if p.distance_to(b.landing) < CLEAR or not _free(taken, p, r + 1.0) or not _clear_of_world(p, r):
				continue
			var h := Terrain.height(p.x, p.y)
			if h < wl + 0.05 or h > 1.6:
				continue
			b.pools.append({"pos": _ground(p), "r": r, "seed": rng.randi() & 0x7FFFFFFF})
			taken.append([p, r + 0.8])
			break


## Small things on the sand that only matter up close: shells, pebbles, dried wrack along the
## tideline and bleached sticks. Bunched toward the tideline, thinner up the beach.
static func _place_deco(b: Dictionary, rng: RandomNumberGenerator) -> void:
	var wl := Terrain.water_level()
	for n in DECO_COUNT:
		var roll := rng.randf()
		var kind := "shell" if roll < 0.32 else ("pebble" if roll < 0.62 else ("wrack" if roll < 0.88 else "stick"))
		var up := absf(rng.randfn(0.0, 4.0)) + (0.3 if kind == "wrack" else 0.6)
		if kind == "wrack":
			up = rng.randf_range(0.4, 2.0)
		var p := on_beach(b, rng.randf_range(-REACH, REACH), up)
		if p.distance_to(b.landing) < 5.0:
			continue
		var h := Terrain.height(p.x, p.y)
		if h < wl + 0.02 or h > 4.5:
			continue
		b.deco.append({"kind": kind, "pos": _ground(p), "rot": rng.randf() * TAU, "scale": rng.randf_range(0.7, 1.3)})


## A wreck far out on the water, a dark shape in the haze: something out there went wrong too.
static func _place_far(b: Dictionary, rng: RandomNumberGenerator) -> void:
	var sea: Vector2 = b.sea
	var side: Vector2 = b.side
	for attempt in 12:
		var p: Vector2 = (b.landing as Vector2) + sea * rng.randf_range(240.0, 380.0) + side * rng.randf_range(-160.0, 160.0)
		if Terrain.height(p.x, p.y) > Terrain.water_level() - 6.0:
			continue # too shallow: that's land or a reef
		b.far.append({"pos": Vector3(p.x, Terrain.water_level(), p.y), "rot": rng.randf() * TAU, "scale": rng.randf_range(0.9, 1.3), "seed": rng.randi() & 0x7FFFFFFF})
		break
