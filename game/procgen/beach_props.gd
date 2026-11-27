class_name BeachProps
## The starting beaches, drawn (BeachGen has the layout; the gatherable pickings are
## NodeProps'): every landmark, the shells, pebbles and wrack on the sand, the tide pools and
## the far wreck out on the water. Islands only; empty elsewhere.
##
## Built like the scatter forest: every part is one instance of a few shared meshes on the
## shared Emberlight materials (planks and poles on the painted bark, rocks on the painted
## stone, bone, cloth and small things on the plain solid; tide-pool water on the Sea), chunked
## by area with a draw distance per layer (Chunks). No new material, a handful of draw calls
## per beach in view, and no meshes made while playing.
##
## Split like NodeProps: `parts()` is pure data (tested headless); `build()` makes the nodes.
## Grounded (art bible pillars 1 and 4): tarred timber gone grey, salt-bleached bone, rusted
## iron, sea-faded canvas; things are broken the way the sea breaks them, half sunk in the sand.

const LAYERS := ["BeachPlanks", "BeachPoles", "BeachBone", "BeachRocks", "BeachCloth", "BeachBits", "BeachPools", "BeachFar"]
## Draw distance per layer, metres (0 = no limit): landmarks as far as node stones, small
## things only up close, the far wreck always (it is the horizon).
const RANGES := {
	"BeachPlanks": 240.0, "BeachPoles": 240.0, "BeachBone": 200.0, "BeachRocks": 160.0,
	"BeachCloth": 160.0, "BeachBits": 70.0, "BeachPools": 120.0, "BeachFar": 0.0,
}
const CHUNK := 128.0
const NO_SHADOW := ["BeachBits", "BeachPools", "BeachFar"]



## Every part of every beach on the island: Array of {layer, xform, color}. Pure.
static func parts() -> Array:
	var out: Array = []
	for b in BeachGen.all():
		for lm in b.landmarks:
			out.append_array(landmark_parts(lm, b))
		for p in b.pools:
			out.append_array(_pool(p))
		for d in b.deco:
			out.append_array(_deco(d))
		for f in b.far:
			out.append_array(_far_wreck(f))
	for spot in BeachGen.loot_spots():
		if not bool(spot.drawn):
			out.append_array(loot_parts(spot))
	out.append_array(CoastDress.parts()) # the rest of the coast, between the landing beaches
	return out


## One landmark's parts. `b` is its beach (BeachGen.beach), for which way the sea is.
static func landmark_parts(lm: Dictionary, b: Dictionary) -> Array:
	var out: Array = []
	var rng := RandomNumberGenerator.new()
	rng.seed = int(lm.seed)
	var origin: Vector3 = lm.pos
	var turn := Basis(Vector3.UP, float(lm.rot))
	var put := func(layer: String, local_basis: Basis, local_pos: Vector3, size: Vector3, color: Color) -> void:
		out.append({"layer": layer, "xform": Transform3D(turn * local_basis * Basis.from_scale(size), origin + turn * local_pos), "color": color})
	match str(lm.kind):
		"shipwreck":
			_shipwreck(put, rng)
		"lifeboat":
			_lifeboat(put, rng)
		"old_pier":
			_pier(put, rng, lm, b)
		"whale_bones":
			_whale(put, rng)
		"fishing_shack":
			_shack(put, rng)
	return out


# ---------------------------------------------------------------------------------------
# Landmarks. Local frame: +X along, +Y up, +Z out (for the pier and the shack, +Z is the sea).

## A ship driven bow-first up the beach and broken there: her keel runs inland (local +X), the
## stern out in the surf. One side's planking still stands, curving up from the sand; the other
## side is stripped to the ribs, which stand up like fingers. The stem post rears at the bow,
## the snapped mast and a scrap of sail lie on the sand beside her.
static func _shipwreck(put: Callable, rng: RandomNumberGenerator) -> void:
	var length := rng.randf_range(10.0, 13.0)
	var heel := Basis(Vector3.RIGHT, rng.randf_range(0.18, 0.3)) # heeled onto her stripped side, so the planked side stands up like a wall
	var sink := Vector3(0, -0.5, 0) # the sand has her to the turn of the bilge
	var wood := Palette.HULL_WOOD
	var beam_at := func(x: float) -> float:
		return 2.1 * sqrt(maxf(1.0 - pow(x / (length * 0.56), 2.0), 0.05))
	# The keel, and the stem rearing at the bow.
	put.call("BeachPlanks", heel, sink + heel * Vector3(0, 0.2, 0), Vector3(length, 0.4, 0.42), wood.darkened(0.1))
	put.call("BeachPoles", heel * Basis(Vector3.BACK, -0.5), sink + heel * Vector3(length * 0.5 + 0.55, 1.5, 0), Vector3(0.36, 3.4, 0.36), wood)
	# Ribs: a floor timber out from the keel and a side timber up to the rail, each side; the
	# stripped side (+Z) keeps fewer, some snapped short.
	var frames := 9
	for i in frames:
		var x := lerpf(-length * 0.44, length * 0.4, float(i) / (frames - 1))
		var beam: float = beam_at.call(x)
		var shade := wood.lightened(rng.randf() * 0.1)
		for side in [-1.0, 1.0]:
			var flo := Vector3(x, 0.45, side * beam * 0.45)
			put.call("BeachPlanks", heel * Basis(Vector3.RIGHT, side * 0.45), sink + heel * flo, Vector3(0.2, 0.2, beam * 0.95), shade)
			var up := 2.3 if side < 0.0 else rng.randf_range(1.2, 2.4)
			var sid := Vector3(x, 0.6 + up * 0.5, side * beam * 0.98)
			put.call("BeachPlanks", heel * Basis(Vector3.RIGHT, -side * 0.12), sink + heel * sid, Vector3(0.2, up, 0.2), shade.darkened(0.04))
	# Planking on the -Z side, four strakes up from the bilge, the top one broken off short.
	for k in 4:
		var y := 0.75 + k * 0.5
		var span := length * (0.78 - k * 0.04) * (0.55 if k == 3 else 1.0)
		var x0 := -length * 0.02 + (length * 0.18 if k == 3 else 0.0)
		var z := -(beam_at.call(x0) as float) * 1.02
		put.call("BeachPlanks", heel * Basis(Vector3.RIGHT, 0.12), sink + heel * Vector3(x0, y, z), Vector3(span, 0.48, 0.1), wood.lightened(0.03 * k))
	# On the stripped side one low strake hangs on.
	put.call("BeachPlanks", heel * Basis(Vector3.RIGHT, -0.12) * Basis(Vector3.BACK, 0.05), sink + heel * Vector3(-length * 0.1, 0.85, (beam_at.call(0.0) as float) * 1.0), Vector3(length * 0.45, 0.46, 0.1), wood.lightened(0.05))
	# The snapped mast on the sand beside her bow, a scrap of sail under it, a barrel.
	var mast_turn := Basis(Vector3.UP, rng.randf_range(-0.35, 0.35))
	put.call("BeachPoles", mast_turn * Basis(Vector3.BACK, PI * 0.5), Vector3(length * 0.42, 0.2, -4.0), Vector3(0.32, 6.5, 0.32), wood.lightened(0.12))
	put.call("BeachCloth", Basis(Vector3.UP, 0.2), Vector3(length * 0.5, 0.04, -5.2), Vector3(2.8, 0.06, 1.5), Palette.SAILCLOTH.darkened(0.1))
	put.call("BeachCloth", Basis(Vector3.UP, -0.15) * Basis(Vector3.RIGHT, 0.1), Vector3(length * 0.5 + 1.1, 0.12, -5.7), Vector3(1.5, 0.05, 1.0), Palette.SAILCLOTH.darkened(0.04))
	put.call("BeachPoles", Basis(Vector3.RIGHT, 1.2), Vector3(length * 0.62, 0.3, 2.6), Vector3(0.9, 0.9, 0.9), Palette.PLANK.darkened(0.1))


## A ship's boat beached and left: heeled over, half full of sand, a thwart broken, an oar
## lying by her.
static func _lifeboat(put: Callable, rng: RandomNumberGenerator) -> void:
	var heel := Basis(Vector3.RIGHT, rng.randf_range(0.12, 0.28))
	var wood := Palette.PLANK
	var sink := Vector3(0, -0.12, 0)
	put.call("BeachPlanks", heel, sink + Vector3(0, 0.12, 0), Vector3(4.0, 0.14, 1.1), wood.darkened(0.12))
	for side in [-1.0, 1.0]:
		# Two strakes a side, flaring out, closing in at the bow.
		for k in 2:
			var y := 0.38 + k * 0.32
			var z: float = side * (0.62 + k * 0.12)
			put.call("BeachPlanks", heel * Basis(Vector3.RIGHT, side * (0.35 + k * 0.1)), sink + heel * Vector3(-0.2, y, z), Vector3(3.6, 0.32, 0.07), wood.lightened(0.04 * k))
			put.call("BeachPlanks", heel * Basis(Vector3.UP, side * 0.5) * Basis(Vector3.RIGHT, side * 0.3), sink + heel * Vector3(2.05, y + 0.05, z * 0.5), Vector3(1.4, 0.32, 0.07), wood.lightened(0.04 * k))
		# The gunwale.
		put.call("BeachPlanks", heel, sink + heel * Vector3(-0.1, 0.86, side * 0.84), Vector3(3.4, 0.08, 0.1), wood.darkened(0.2))
	put.call("BeachPlanks", heel, sink + heel * Vector3(-2.05, 0.55, 0), Vector3(0.08, 0.7, 1.55), wood.darkened(0.08)) # the transom
	put.call("BeachPoles", heel * Basis(Vector3.BACK, -0.3), sink + heel * Vector3(2.65, 0.7, 0), Vector3(0.16, 1.0, 0.16), wood.darkened(0.15)) # the stem
	put.call("BeachPlanks", heel, sink + heel * Vector3(0.6, 0.6, 0), Vector3(0.26, 0.06, 1.5), wood.lightened(0.06)) # a thwart
	put.call("BeachPlanks", heel * Basis(Vector3.RIGHT, 0.5), sink + heel * Vector3(-0.8, 0.45, 0.3), Vector3(0.26, 0.06, 0.8), wood.lightened(0.06)) # the broken one
	put.call("BeachRocks", heel, sink + heel * Vector3(-0.4, 0.2, 0), Vector3(3.0, 0.4, 1.0), Palette.SAND.darkened(0.04)) # drifted sand
	# An oar in the sand and a coil of rope.
	var oar := Basis(Vector3.UP, rng.randf_range(0.2, 0.6)) * Basis(Vector3.BACK, PI * 0.5)
	put.call("BeachPoles", oar, Vector3(0.4, 0.05, -1.8), Vector3(0.06, 2.6, 0.06), wood.lightened(0.1))
	put.call("BeachPlanks", Basis(Vector3.UP, rng.randf_range(0.2, 0.6)), Vector3(0.4, 0.04, -1.8) + Basis(Vector3.UP, rng.randf_range(0.2, 0.6)) * Vector3(1.4, 0, 0), Vector3(0.6, 0.03, 0.16), wood.lightened(0.1))
	put.call("BeachPoles", Basis.IDENTITY, Vector3(-1.2, 0.06, 1.5), Vector3(0.7, 0.12, 0.7), Palette.ROPE)


## An old landing stage running out into the sea on pairs of piles, the deck boards grey and
## gapped, the last bays fallen in.
static func _pier(put: Callable, rng: RandomNumberGenerator, lm: Dictionary, b: Dictionary) -> void:
	var origin: Vector3 = lm.pos
	var sea: Vector2 = b.sea
	var bays := int(BeachGen.PIER_LENGTH / 3.0)
	var deck_y := maxf(origin.y + 0.55, Terrain.water_level() + 1.3) - origin.y
	var wood := Palette.DRIFTWOOD.darkened(0.12)
	var fallen_from := bays - rng.randi_range(1, 2)
	for i in bays + 1:
		var z := i * 3.0
		var at := Vector2(origin.x, origin.z) + sea * z
		var ground_y := Terrain.height(at.x, at.y) - origin.y
		var drop := 0.0
		if i > fallen_from:
			drop = 0.9 * (i - fallen_from)
		for side in [-1.0, 1.0]:
			if i > fallen_from and side > 0.0 and rng.randf() < 0.5:
				continue # a pile gone
			var top := deck_y + 0.25 - drop * 0.5
			var bottom := ground_y - 0.4
			put.call("BeachPoles", Basis(Vector3.BACK, rng.randf_range(-0.04, 0.04)), Vector3(side * 1.15, (top + bottom) * 0.5, z), Vector3(0.26, top - bottom, 0.26), wood.darkened(0.12 + rng.randf() * 0.1))
		if i < bays:
			# Stringers and boards over this bay; a fallen bay tips into the water.
			var tip := Basis.IDENTITY
			var y0 := deck_y
			if i >= fallen_from:
				tip = Basis(Vector3.RIGHT, 0.32 + 0.1 * (i - fallen_from))
				y0 = deck_y - 0.55 - 0.7 * (i - fallen_from)
			for side in [-1.0, 1.0]:
				put.call("BeachPlanks", tip, Vector3(side * 1.0, y0 - 0.14, z + 1.5), Vector3(0.14, 0.18, 3.1), wood.darkened(0.08))
			for k in 6:
				if rng.randf() < (0.12 if i < fallen_from else 0.35):
					continue # a missing board
				var zz := z + 0.25 + k * 0.5
				put.call("BeachPlanks", tip * Basis(Vector3.UP, rng.randf_range(-0.03, 0.03)), Vector3(0, y0 + 0.02, zz) + tip * Vector3.ZERO, Vector3(2.5, 0.06, 0.42), wood.lightened(rng.randf() * 0.1))
	# A bollard with a frayed rope, and a coil on the boards.
	put.call("BeachPoles", Basis.IDENTITY, Vector3(-1.0, deck_y + 0.3, 4.5), Vector3(0.3, 0.5, 0.3), Palette.HULL_WOOD)
	put.call("BeachPoles", Basis.IDENTITY, Vector3(0.6, deck_y + 0.09, 2.2), Vector3(0.55, 0.1, 0.55), Palette.ROPE)


## A whale's bones, long picked clean: the spine half buried in a curve, ribs arching up
## like the frame of a burned hall, the great skull at one end, a jawbone fallen flat.
static func _whale(put: Callable, rng: RandomNumberGenerator) -> void:
	var bone := Palette.BONE
	var n := 14
	var curve := rng.randf_range(-0.05, 0.05)
	var spine: Array = []
	for i in n:
		var x := -5.5 + i * 0.8
		var z := curve * x * x
		spine.append(Vector3(x, 0.15, z))
		var w := 0.55 - absf(i - 4.0) * 0.025
		put.call("BeachBone", Basis.IDENTITY, Vector3(x, 0.12, z), Vector3(w, 0.3, w), bone.darkened(0.04 + rng.randf() * 0.06))
	# Ribs: pairs along the front half of the spine, longest in the middle; some fallen.
	for i in range(1, 9):
		var base: Vector3 = spine[i]
		var length := 2.6 - absf(i - 4.0) * 0.22
		for side in [-1.0, 1.0]:
			if rng.randf() < 0.18:
				# Fallen flat on the sand.
				put.call("BeachBone", Basis(Vector3.UP, side * rng.randf_range(0.2, 0.5)) * Basis(Vector3.RIGHT, side * PI * 0.5), base + Vector3(0, 0.05, side * length * 0.55), Vector3(0.12, length, 0.12), bone.darkened(0.06))
				continue
			# Three pieces along a curve: out and up from the spine, then up, then leaning back
			# in over it, so each pair stands like the frame of a burned hall.
			var at: Vector3 = base + Vector3(0, 0.05, 0)
			var seg := length / 3.0
			for k in 3:
				var e: float = deg_to_rad([30.0, 68.0, 104.0][k])
				var dir := Vector3(0, sin(e), side * cos(e))
				var a: float = side * (PI * 0.5 - e)
				put.call("BeachBone", Basis(Vector3.RIGHT, a), at + dir * seg * 0.5, Vector3(0.21 - k * 0.035, seg * 1.08, 0.21 - k * 0.035), bone.lightened(0.02 * k))
				at += dir * seg
	# The skull: a great flattened dome and the snout, ahead of the first vertebra.
	var head: Vector3 = spine[0] + Vector3(-1.9, 0.2, 0)
	put.call("BeachRocks", Basis(Vector3.UP, 0.1), head, Vector3(2.4, 0.85, 2.0), bone.darkened(0.03))
	put.call("BeachBone", Basis(Vector3.BACK, PI * 0.5 + 0.06), head + Vector3(-2.1, 0.0, 0), Vector3(0.45, 2.8, 1.3), bone.darkened(0.05)) # the flat rostrum
	# One jawbone still in place, the other fallen out on the sand.
	put.call("BeachBone", Basis(Vector3.UP, 0.15) * Basis(Vector3.BACK, PI * 0.5), head + Vector3(-1.8, -0.05, 0.6), Vector3(0.18, 4.2, 0.18), bone)
	put.call("BeachBone", Basis(Vector3.UP, -0.7) * Basis(Vector3.BACK, PI * 0.5), head + Vector3(-1.2, -0.08, -2.0), Vector3(0.18, 4.0, 0.18), bone.darkened(0.08))


## A fisher's shack at the back of the beach: plank walls, the door open to the sea, the roof
## half fallen in; nets on a drying rack, a barrel; inside, under a sail, someone who never
## left (a dead Zombai's grey hand out from under the cloth: the island's first warning).
static func _shack(put: Callable, rng: RandomNumberGenerator) -> void:
	var wood := Palette.PLANK.darkened(0.1)
	var w := 3.6
	var d := 3.0
	var h := 2.2
	# Corner posts.
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			put.call("BeachPoles", Basis.IDENTITY, Vector3(sx * w * 0.5, h * 0.5, sz * d * 0.5), Vector3(0.2, h + 0.1, 0.2), wood.darkened(0.15))
	# Walls of horizontal boards: back, two sides, and the front either side of the door.
	for k in 5:
		var y := 0.25 + k * 0.42
		var c := wood.lightened(rng.randf() * 0.08)
		put.call("BeachPlanks", Basis.IDENTITY, Vector3(0, y, -d * 0.5), Vector3(w, 0.38, 0.07), c)
		for sx in [-1.0, 1.0]:
			if not (sx > 0.0 and k == 3): # one board gone
				put.call("BeachPlanks", Basis.IDENTITY, Vector3(sx * w * 0.5, y, 0), Vector3(0.07, 0.38, d), c.darkened(0.04))
			put.call("BeachPlanks", Basis.IDENTITY, Vector3(sx * w * 0.34, y, d * 0.5), Vector3(w * 0.32, 0.38, 0.07), c)
	# The door, hanging open.
	put.call("BeachPlanks", Basis(Vector3.UP, 1.2), Vector3(w * 0.18 + 0.35, 0.95, d * 0.5 + 0.35), Vector3(0.9, 1.8, 0.06), wood.darkened(0.05))
	# Roof: the back slope whole, the front slope sagged and half fallen in.
	put.call("BeachPlanks", Basis(Vector3.RIGHT, -0.32), Vector3(0, h + 0.38, -d * 0.26), Vector3(w + 0.5, 0.08, d * 0.6), Palette.HULL_WOOD.lightened(0.08))
	put.call("BeachPlanks", Basis(Vector3.RIGHT, 0.62) * Basis(Vector3.BACK, 0.12), Vector3(-0.4, h - 0.1, d * 0.25), Vector3(w * 0.6, 0.08, d * 0.55), Palette.HULL_WOOD.lightened(0.04))
	put.call("BeachPlanks", Basis.IDENTITY, Vector3(0, h + 0.62, 0.0), Vector3(w + 0.5, 0.14, 0.16), wood.darkened(0.2)) # ridge
	# The drying rack outside, nets hung over it, a barrel.
	for sx in [-1.0, 1.0]:
		put.call("BeachPoles", Basis.IDENTITY, Vector3(w * 0.5 + 1.6 + sx * 1.0, 0.8, d * 0.5 + 0.8), Vector3(0.1, 1.6, 0.1), wood)
	put.call("BeachPoles", Basis(Vector3.BACK, PI * 0.5), Vector3(w * 0.5 + 1.6, 1.55, d * 0.5 + 0.8), Vector3(0.08, 2.2, 0.08), wood)
	# The net: a mesh of cord hanging over the bar, sagging, its hem dragging.
	var rack := Vector3(w * 0.5 + 1.6, 0.0, d * 0.5 + 0.84)
	for k in 7:
		var x := -0.9 + k * 0.3
		var hang := 0.85 + 0.12 * sin(k * 1.7)
		put.call("BeachBits", Basis(Vector3.BACK, 0.06 * sin(k * 2.3)), rack + Vector3(x, 1.55 - hang * 0.5, 0), Vector3(0.025, hang, 0.025), Palette.ROPE.darkened(0.1))
	for k in 4:
		var y := 1.45 - k * 0.24
		put.call("BeachBits", Basis(Vector3.BACK, 0.03 * k), rack + Vector3(0, y, 0), Vector3(1.85 - k * 0.05, 0.025, 0.025), Palette.ROPE.darkened(0.1))
	put.call("BeachCloth", Basis(Vector3.UP, 0.4), rack + Vector3(0.6, 0.03, 0.5), Vector3(1.0, 0.06, 0.7), Palette.ROPE.darkened(0.15)) # a heap of net
	put.call("BeachPoles", Basis.IDENTITY, Vector3(-w * 0.5 - 0.6, 0.42, d * 0.5 - 0.2), Vector3(0.62, 0.84, 0.62), Palette.PLANK.darkened(0.2))
	put.call("BeachBits", Basis.IDENTITY, Vector3(-w * 0.5 - 0.6, 0.62, d * 0.5 - 0.2), Vector3(0.64, 0.05, 0.64), Palette.IRON_RUST)
	# Inside, against the back wall: a shape under a sail, a hand out from under it.
	put.call("BeachRocks", Basis(Vector3.UP, 0.2), Vector3(0.5, 0.32, -d * 0.5 + 0.55), Vector3(1.5, 0.7, 0.8), Palette.SAILCLOTH.darkened(0.12))
	put.call("BeachCloth", Basis(Vector3.UP, 0.3), Vector3(-0.35, 0.06, -d * 0.5 + 0.95), Vector3(0.18, 0.08, 0.1), Palette.DEAD_FLESH)
	for f in 3:
		put.call("BeachBits", Basis(Vector3.UP, 0.3 + f * 0.25), Vector3(-0.5 - f * 0.03, 0.05, -d * 0.5 + 1.02 + f * 0.04), Vector3(0.12, 0.06, 0.05), Palette.DEAD_FLESH.darkened(0.05))


## What you can search in a landmark (BeachGen.loot_spots), drawn on the very point gameplay
## fills, in the spot's own frame (+Z its front). Salt-worn like the rest of the beach: a
## tarred sea chest with rusted bands half in the sand, a hessian sack, and a body wrapped in
## sailcloth like the one in the shack, a hand out from under it. No glow (direction 11).
static func loot_parts(spot: Dictionary) -> Array:
	var out: Array = []
	var origin: Vector3 = spot.pos
	var turn := Basis(Vector3.UP, float(spot.rot))
	var put := func(layer: String, local_basis: Basis, local_pos: Vector3, size: Vector3, color: Color) -> void:
		out.append({"layer": layer, "xform": Transform3D(turn * local_basis * Basis.from_scale(size), origin + turn * local_pos), "color": color})
	match str(spot.kind):
		"chest":
			var wood := Palette.HULL_WOOD.lightened(0.1)
			var tilt := Basis(Vector3.FORWARD, 0.08) # settled crooked in the sand
			put.call("BeachPlanks", tilt, Vector3(0, 0.2, 0), Vector3(0.9, 0.48, 0.55), wood)
			put.call("BeachPlanks", tilt, Vector3(0, 0.47, 0), Vector3(0.94, 0.09, 0.59), wood.darkened(0.12)) # the lid
			for x in [-0.3, 0.3]:
				put.call("BeachCloth", tilt, Vector3(x, 0.26, 0), Vector3(0.06, 0.56, 0.6), Palette.IRON_RUST)
			put.call("BeachCloth", tilt, Vector3(0, 0.38, 0.29), Vector3(0.12, 0.13, 0.04), Palette.IRON_RUST.darkened(0.15)) # the hasp
		"sack":
			put.call("BeachBits", Basis(Vector3.FORWARD, 0.25), Vector3(0, 0.22, 0), Vector3(0.55, 0.44, 0.45), Palette.BEDROLL)
			put.call("BeachBits", Basis(Vector3.FORWARD, 1.1), Vector3(0.28, 0.36, 0), Vector3(0.18, 0.2, 0.18), Palette.BEDROLL.darkened(0.08))
		"body":
			# Face down, a scrap of sail over the back: a long low shape, the head, the boots.
			put.call("BeachCloth", Basis(Vector3.FORWARD, 0.06), Vector3(0, 0.13, 0), Vector3(0.58, 0.24, 1.2), Palette.SAILCLOTH.darkened(0.12))
			put.call("BeachCloth", Basis(Vector3.UP, 0.25), Vector3(0.05, 0.03, 0.1), Vector3(1.0, 0.04, 0.9), Palette.SAILCLOTH.darkened(0.05)) # the sail's edge on the sand
			put.call("BeachBits", Basis.IDENTITY, Vector3(0, 0.12, 0.74), Vector3(0.26, 0.22, 0.28), Palette.LEATHER_DARK.lightened(0.08)) # the head, hair dark with the sea
			for sx in [-0.12, 0.12]:
				put.call("BeachCloth", Basis.IDENTITY, Vector3(sx, 0.07, -0.86), Vector3(0.12, 0.14, 0.28), Palette.LEATHER_DARK)
			put.call("BeachCloth", Basis(Vector3.UP, 0.4), Vector3(0.42, 0.05, 0.45), Vector3(0.18, 0.08, 0.1), Palette.DEAD_FLESH)
	return out


# ---------------------------------------------------------------------------------------

## A tide pool: a ring of weed-dark rocks round a still disc of water, a shell or two in it.
static func _pool(p: Dictionary) -> Array:
	var out: Array = []
	var rng := RandomNumberGenerator.new()
	rng.seed = int(p.seed)
	var c: Vector3 = p.pos
	var r: float = p.r
	var n := rng.randi_range(6, 9)
	for i in n:
		var a := TAU * i / n + rng.randf_range(-0.2, 0.2)
		var s := rng.randf_range(0.5, 0.95)
		var at := c + Vector3(cos(a) * r, 0.08, sin(a) * r)
		var col := Palette.PEBBLE.darkened(0.1 + rng.randf() * 0.12).lerp(Palette.KELP, 0.25 if i % 3 == 0 else 0.0)
		out.append({"layer": "BeachRocks", "xform": Transform3D(Basis(Vector3.UP, a).scaled(Vector3(s * 1.2, s * 0.55, s)), at), "color": col})
	# Alpha 0.2: a still pool, only a faint wet edge, no surf (Sea reads the instance alpha).
	out.append({"layer": "BeachPools", "xform": Transform3D(Basis.from_scale(Vector3(r * 1.9, 1.0, r * 1.9)), c + Vector3(0, 0.1, 0)), "color": Palette.STILL_WATER})
	for i in 2:
		var a := rng.randf() * TAU
		out.append({"layer": "BeachBits", "xform": Transform3D(Basis(Vector3.UP, a).scaled(Vector3(0.14, 0.05, 0.11)), c + Vector3(cos(a), 0.02, sin(a)) * r * 0.45), "color": Palette.SHELL})
	return out


static func _deco(d: Dictionary) -> Array:
	var s: float = d.scale
	var b := Basis(Vector3.UP, float(d.rot))
	var p: Vector3 = d.pos
	match str(d.kind):
		"shell":
			return [{"layer": "BeachBits", "xform": Transform3D(b.scaled(Vector3(0.16, 0.06, 0.12) * s), p + Vector3(0, 0.02, 0)), "color": Palette.SHELL.lightened(fmod(float(d.rot), 0.1))}]
		"pebble":
			return [{"layer": "BeachBits", "xform": Transform3D(b.scaled(Vector3(0.22, 0.12, 0.17) * s), p + Vector3(0, 0.03, 0)), "color": Palette.PEBBLE.darkened(fmod(float(d.rot), 0.15))}]
		"wrack":
			return [{"layer": "BeachBits", "xform": Transform3D(b.scaled(Vector3(0.9, 0.05, 0.22) * s), p + Vector3(0, 0.02, 0)), "color": Palette.KELP.darkened(0.1)}]
		_:
			return [{"layer": "BeachBits", "xform": Transform3D(b.scaled(Vector3(0.75, 0.05, 0.05) * s), p + Vector3(0, 0.03, 0)), "color": Palette.DRIFTWOOD}]


## A wreck out on the water, far off: a hull's dark back heeled over and a leaning mast.
static func _far_wreck(f: Dictionary) -> Array:
	var out: Array = []
	var s: float = f.scale
	var b := Basis(Vector3.UP, float(f.rot))
	var p: Vector3 = f.pos
	var c := Palette.HULL_WOOD.darkened(0.25)
	out.append({"layer": "BeachFar", "xform": Transform3D(b * Basis(Vector3.RIGHT, 0.5) * Basis.from_scale(Vector3(16.0, 3.2, 4.2) * s), p + Vector3(0, 0.6, 0)), "color": c})
	out.append({"layer": "BeachFar", "xform": Transform3D(b * Basis(Vector3.BACK, 0.12) * Basis(Vector3.RIGHT, 0.45) * Basis.from_scale(Vector3(5.0, 2.0, 3.6) * s), p + b * Vector3(5.5 * s, 1.6, 0)), "color": c})
	out.append({"layer": "BeachFar", "xform": Transform3D(b * Basis(Vector3.RIGHT, 0.55) * Basis.from_scale(Vector3(0.5, 12.0, 0.5) * s), p + b * Vector3(-1.0 * s, 5.2 * s, 2.6 * s)), "color": c.lightened(0.05)})
	return out


# ---------------------------------------------------------------------------------------

static func meshes() -> Dictionary:
	var box := BoxMesh.new()
	var pole := CylinderMesh.new()
	pole.top_radius = 0.5
	pole.bottom_radius = 0.5
	pole.height = 1.0
	pole.radial_segments = 6
	pole.rings = 1
	var bone := CylinderMesh.new()
	bone.top_radius = 0.38
	bone.bottom_radius = 0.5
	bone.height = 1.0
	bone.radial_segments = 6
	bone.rings = 1
	var rock := SphereMesh.new()
	rock.radius = 0.5
	rock.height = 1.0
	rock.radial_segments = 6
	rock.rings = 3
	var bit := SphereMesh.new()
	bit.radius = 0.5
	bit.height = 1.0
	bit.radial_segments = 5
	bit.rings = 2
	var pool := CylinderMesh.new()
	pool.top_radius = 0.5
	pool.bottom_radius = 0.5
	pool.height = 0.02
	pool.radial_segments = 10
	pool.rings = 1
	return {
		"BeachPlanks": Emberlight.bake(box, 0.35),
		"BeachPoles": Emberlight.bake(pole, 0.4, 1.4),
		"BeachBone": Emberlight.bake(bone, 0.3),
		"BeachRocks": Emberlight.bake(rock, 0.4, 1.5),
		"BeachCloth": Emberlight.bake(box, 0.25),
		"BeachBits": Emberlight.bake(bit, 0.2),
		"BeachPools": pool,
		"BeachFar": Emberlight.bake(box, 0.2),
	}


static func layer_material(layer: String) -> Material:
	match layer:
		"BeachPlanks", "BeachPoles":
			return Emberlight.painted("bark")
		"BeachRocks":
			return Emberlight.painted("stone")
		"BeachPools":
			return Sea.material()
		_:
			return Emberlight.material("solid")


## The beaches as one node of chunked layers (empty on a world with no beaches).
static func build() -> Node3D:
	var root := Node3D.new()
	root.name = "Beaches"
	var all := parts()
	if all.is_empty():
		return root
	var by_layer := {}
	for l in LAYERS:
		by_layer[l] = []
	for p in all:
		(by_layer[p.layer] as Array).append([p.xform, p.color])
	var ms := meshes()
	var scale := Chunks.quality_range_scale()
	for l in LAYERS:
		var inst: Array = by_layer[l]
		if inst.is_empty():
			continue
		var layer_node := Node3D.new()
		layer_node.name = l
		var split := Chunks.split(inst, CHUNK)
		var keys := split.keys()
		keys.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y < b.y or (a.y == b.y and a.x < b.x))
		for k in keys:
			var at := Chunks.centre(k, CHUNK)
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_colors = true
			mm.mesh = ms[l]
			var list: Array = split[k]
			mm.instance_count = list.size()
			for i in list.size():
				var t: Transform3D = list[i][0]
				mm.set_instance_transform(i, Transform3D(t.basis, t.origin - at))
				mm.set_instance_color(i, (list[i][1] as Color).srgb_to_linear())
			var mmi := MultiMeshInstance3D.new()
			mmi.name = "c%d_%d" % [k.x, k.y]
			mmi.multimesh = mm
			mmi.material_override = layer_material(l)
			mmi.position = at
			Chunks.set_range(mmi, float(RANGES.get(l, 0.0)), CHUNK, scale)
			if NO_SHADOW.has(l):
				mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			layer_node.add_child(mmi)
		root.add_child(layer_node)
	return root
