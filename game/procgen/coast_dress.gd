class_name CoastDress
## The whole island's coast, dressed (owner, 2026-11-27: "our beaches still look empty"). The
## landing beaches have their landmarks and pickings (BeachGen); this fills every other metre
## of sand between them: a wrack line of kelp along the tide mark, shells and pebbles, drift
## logs (some still with a branch), rock clusters, and washed-up boards.
##
## Pure data like BeachProps.parts(), drawn by BeachProps on its own layers, meshes and
## materials (no new material, no new draw-call layer). Decoration only: nothing to gather,
## nothing saved, the server never builds it. Islands only; empty elsewhere.
##
## The coast is walked by bearing from the island's centre (WorldGen.coast_at), one look every
## STEP metres of coast. At each look the beach's cross-section is found (where the sea stops
## and where the sand stops) and things are laid across it by what the sea leaves where: wrack
## and logs at the tide mark, shells and pebbles all over, rocks anywhere, boards up the beach.

const SEED_OFFSET := 7717
const STEP := 3.0 ## metres of coast between looks
const PROBE := 3.0 ## metres between height samples across the beach
const PROBE_SEA := 120.0 ## how far seaward of the coast point the cross-section starts
const PROBE_LAND := 80.0 ## and how far landward it may run
const MIN_WIDTH := 6.0 ## narrower than this (a cliff foot) gets nothing
const LANDING_CLEAR := 2.0 ## metres round a landing kept open (its lantern ring is BeachGen.CLEAR)
const NODE_CLEAR := 1.6 ## metres from a beach picking, so the dressing never hides one

## Chances per look.
const WRACK := 0.55 ## a strip of kelp on the tide mark
const BITS := 6 ## shells and pebbles per look (some rolled away)
const LOG := 0.25 ## a drift log
const ROCKS := 0.2 ## a cluster of rocks
const BOARD := 0.07 ## a washed-up board or two

static var _parts: Array = []
static var _built_for: Dictionary = {}


## Every part on the coast: Array of {layer, xform, color} on BeachProps' layers. Cached per
## world; treat as read-only.
static func parts() -> Array:
	if not WorldGen.is_island():
		return []
	if _parts.is_empty() or _built_for != WorldGen.config():
		_built_for = WorldGen.config()
		_parts = generate()
	return _parts


static func generate() -> Array:
	var out: Array = []
	var rng := RandomNumberGenerator.new()
	rng.seed = int(WorldGen.config().seed) + SEED_OFFSET
	var lands := WorldGen.landings()
	var marks := BeachGen.landmarks()
	var picks := BeachGen.nodes()
	var rays := int(TAU * WorldGen.size_m() * 0.36 / STEP)
	for i in rays:
		var a := TAU * float(i) / rays
		# Every roll for this look is drawn up front, so a skipped look never shifts the next.
		var r := PackedFloat32Array()
		for k in 24:
			r.append(rng.randf())
		var c := WorldGen.coast_at(a)
		if c.is_empty():
			continue
		var cut := cross_section(c.pos, c.sea)
		if cut.is_empty():
			continue
		var sea: Vector2 = c.sea
		var side := Vector2(-sea.y, sea.x)
		var here: Vector2 = cut.water
		var near := _near(here, lands, marks, picks)
		var put := func(layer: String, along: float, up_m: float, basis: Basis, lift: float, color: Color) -> void:
			var q: Vector2 = here - sea * up_m + side * along
			if _blocked(q, near):
				return
			var y := Terrain.height(q.x, q.y)
			if y < Terrain.water_level() + 0.02:
				return
			out.append({"layer": layer, "xform": Transform3D(basis, Vector3(q.x, y + lift, q.y)), "color": color})
		var width: float = cut.width
		var turn := -side.angle() # local +X runs along the coast
		# The wrack line: kelp lying along the tide mark in two or three overlapping strips.
		if r[0] < WRACK:
			var up := 0.8 + r[1] * 1.6
			for k in 2 + int(r[2] * 2.0):
				var b := Basis(Vector3.UP, turn + (r[3 + k] - 0.5) * 0.6) * Basis.from_scale(Vector3(0.7 + r[6 + k], 0.05, 0.16 + r[9 + k] * 0.12))
				put.call("BeachBits", (float(k) - 1.0) * 0.9 + (r[12] - 0.5), up + (r[13 + k] - 0.5) * 0.5, b, 0.02, Palette.KELP.darkened(0.05 + r[16] * 0.1))
		# Shells and pebbles, all over the dry sand, thicker toward the tide mark.
		for k in BITS:
			var u: float = r[17 + k]
			var up := pow(u, 1.6) * width * 0.9 + 0.4
			var along := (r[(k + 5) % 24] - 0.5) * STEP
			var shell := r[(k + 11) % 24] < 0.45
			var s := 0.7 + r[(k + 7) % 24] * 0.6
			var b := Basis(Vector3.UP, u * TAU)
			if shell:
				put.call("BeachBits", along, up, b * Basis.from_scale(Vector3(0.2, 0.07, 0.15) * s), 0.02, Palette.SHELL.lightened(u * 0.08))
			else:
				put.call("BeachBits", along, up, b * Basis.from_scale(Vector3(0.3, 0.16, 0.24) * s), 0.03, Palette.PEBBLE.darkened(u * 0.15))
		# A drift log: grey, lying roughly along the beach, half sunk; some keep a branch.
		if r[21] < LOG:
			var length := 2.2 + r[22] * 3.0
			var thick := 0.22 + r[23] * 0.16
			var up := 1.0 + r[1] * minf(width * 0.6, 14.0)
			var yaw := turn + (r[2] - 0.5) * 1.2
			var lie := Basis(Vector3.UP, yaw) * Basis(Vector3.BACK, PI * 0.5) # cylinder axis along local X
			var col := Palette.DRIFTWOOD.darkened(r[3] * 0.12)
			put.call("BeachPoles", 0.0, up, lie * Basis.from_scale(Vector3(thick, length, thick)), thick * 0.3, col)
			if r[4] < 0.5:
				var stub := Basis(Vector3.UP, yaw) * Basis(Vector3.BACK, PI * 0.5 - 0.7) * Basis(Vector3.RIGHT, 0.5)
				var off := Vector2.from_angle(-yaw) * length * 0.3
				put.call("BeachPoles", off.dot(side), up - off.dot(sea), stub * Basis.from_scale(Vector3(thick * 0.45, length * 0.35, thick * 0.45)), thick * 0.55, col.lightened(0.04))
			if r[5] < 0.35: # a root plate at one end
				var end := Vector2.from_angle(-yaw) * length * 0.5
				put.call("BeachPoles", end.dot(side), up - end.dot(sea), lie * Basis.from_scale(Vector3(thick * 2.6, 0.18, thick * 2.6)), thick * 0.5, col.darkened(0.06))
		# A cluster of rocks: one or two big ones and their small change, half buried.
		if r[6] < ROCKS:
			var up := 0.3 + r[7] * width * 0.8
			var n := 3 + int(r[8] * 5.0)
			for k in n:
				var big := k < 1 + int(r[9] * 2.0)
				var s := (0.9 + r[(k + 10) % 24] * 0.9) if big else (0.25 + r[(k + 14) % 24] * 0.4)
				var ang := TAU * float(k) / n + r[(k + 3) % 24]
				var dist := 0.0 if k == 0 else (0.8 + r[(k + 18) % 24] * 1.6)
				var b := Basis(Vector3.UP, ang * 2.3) * Basis.from_scale(Vector3(1.3, 0.75, 1.0) * s)
				put.call("BeachRocks", cos(ang) * dist, up + sin(ang) * dist, b, s * 0.12, Palette.ROCK.darkened(0.05 + r[(k + 20) % 24] * 0.12).lerp(Palette.KELP, 0.12 if up < 2.0 else 0.0))
		# A washed-up board or two, up the beach.
		if r[10] < BOARD:
			var up := 2.0 + r[11] * width * 0.6
			for k in 1 + int(r[12] * 2.0):
				var b := Basis(Vector3.UP, turn + r[13 + k] * 2.0) * Basis(Vector3.RIGHT, (r[15] - 0.5) * 0.2)
				put.call("BeachPlanks", float(k) * 0.5, up + float(k) * 0.3, b * Basis.from_scale(Vector3(1.6 + r[16] * 0.8, 0.06, 0.24)), 0.03, Palette.PLANK.lerp(Palette.DRIFTWOOD, 0.4 + r[17] * 0.4))
	return out


## The beach across the coast point `p` (sea the unit seaward direction): {water: Vector2, the
## first dry ground walking in from the sea; width: metres of sand from there to the back of
## the beach}, or {} on a cliff or where there's no sand.
static func cross_section(p: Vector2, sea: Vector2) -> Dictionary:
	var wl := Terrain.water_level()
	var water := Vector2.INF
	var back := 0.0
	var d := -PROBE_SEA
	while d < PROBE_LAND:
		var q := p - sea * d
		var h := Terrain.height(q.x, q.y)
		if water == Vector2.INF:
			if h > wl:
				water = q
		elif WorldGen.biome_for(q.x, q.y, h) != "shore" or h > 3.0:
			break
		else:
			back = d
		d += PROBE
	if water == Vector2.INF:
		return {}
	var width := back - (water - p).dot(-sea)
	if width < MIN_WIDTH:
		return {}
	return {"water": water, "width": width}


## What might be in the way near `p`: [[centre: Vector2, clear radius], ...] for the landings,
## landmarks and pickings within reach of one look's parts (so each part checks a few, not all).
static func _near(p: Vector2, lands: Array, marks: Array, picks: Array) -> Array:
	var reach := PROBE_LAND + STEP * 4.0
	var out: Array = []
	for l in lands:
		if p.distance_to(l) < reach + BeachGen.CLEAR + LANDING_CLEAR:
			out.append([l, BeachGen.CLEAR + LANDING_CLEAR])
	for m in marks:
		var r: float = BeachGen.LANDMARKS[m.kind].r + 1.5
		if m.kind == "old_pier":
			r += BeachGen.PIER_LENGTH * 0.5
		var c := Vector2(m.pos.x, m.pos.z)
		if p.distance_to(c) < reach + r:
			out.append([c, r])
	for n in picks:
		var c := Vector2(n.pos.x, n.pos.z)
		if p.distance_to(c) < reach:
			out.append([c, NODE_CLEAR])
	return out


static func _blocked(q: Vector2, near: Array) -> bool:
	for t in near:
		if q.distance_to(t[0]) < float(t[1]):
			return true
	if WorldGen.road_distance(q.x, q.y) < WorldGen.ROAD_HALF_WIDTH:
		return true
	return WorldGen.river_distance(q.x, q.y) < WorldGen.RIVER_HALF_WIDTH + 2.0
