class_name RuinKit
## The medieval ruin kit and the burned farmstead (Basics 4, grade 1): weathered stone walls and
## rubble, charred and weathered timber frames, collapsed thatch, a well, a fence, a cart wreck,
## and the loot you can search (a crate, a chest, a sack, a body under a cloak).
##
## Built from `RuinLayout.plan()` alone, so every island lays its farmsteads out differently
## and gameplay's loot spots sit exactly on the crate, chest, sack and body drawn here.
##
## The far landmark is the farmhouse's stone chimney and its gable end: they still stand when
## the roof and walls have burned, about 7 m tall, and are drawn out to FAR_RANGE so a player
## on the beach sees a dark stack against the sky and walks to it. Everything else fades in
## at NEAR_RANGE. Grounded: stone, char, old timber and rotten straw, no glow (only fire glows,
## and this fire went out long ago).
##
## Split like Workbench: `parts()` is pure data (safe headless, in unit tests); `build_ruin()`
## makes one ruin's node from shared materials and MultiMesh layers (one per layer and range).

const NODE_NAME := "Ruins"
const LAYERS := ["RuinStone", "RuinWood", "RuinThatch", "RuinRound"]
const FAR_RANGE := 900.0 ## metres: the chimney and gable are seen from across the island
const NEAR_RANGE := 220.0 ## metres: walls, timbers, props (art bible section 7, props ~160 m; a ruin is bigger)
const CHIMNEY_HEIGHT := 7.2 ## metres above the ground: the tallest thing on a farmstead

# Colours: muted naturals from palette.gd (art bible section 2), all under 0.45 saturation.
# Static vars because they are worked out from Palette, which a const can't call.
static var STONE := Palette.ROCK.lightened(0.02) ## field stone walls
static var STONE_DARK := Palette.FIRE_STONE.darkened(0.1) ## the lower courses, damp and old
static var STONE_SOOT := Palette.FIRE_STONE_SOOT ## smoke-blackened stone: the chimney top, the hearth
static var CHAR := Palette.FIRE_CHAR ## burned timber: near soot, never black
static var CHAR_BROWN := Palette.FIRE_LOG.lerp(Palette.FIRE_CHAR, 0.4) ## scorched, not burned through
static var OLD_PLANK := Palette.WORKED_WOOD.lerp(Palette.ROCK, 0.4) ## weathered planks, silvering
static var OLD_TIMBER := OLD_PLANK.darkened(0.15) ## the barn's frame, darker than its planks
static var THATCH_ROT := Palette.SCRUB_DRY.darkened(0.12) ## wet, rotting straw on the barn
static var THATCH_BURNT := Palette.SCRUB_DRY.lerp(Palette.FIRE_CHAR, 0.7) ## the house's fallen, burned thatch
static var CRATE := Palette.WORKED_WOOD.lerp(Palette.BEDROLL, 0.4) ## a nailed crate: weathered pine
static var CHEST := Palette.LEATHER.lerp(Palette.ROCK, 0.3) ## an old oak chest, darker than the crate
static var IRON := Palette.IRON.darkened(0.12) ## bands and hoops: dull, rusting iron
static var SACK := Palette.BEDROLL ## hessian sacking
static var CLOAK := Palette.COAT ## the cloak over the body: dark oiled wool
static var BOOT := Palette.LEATHER_DARK
static var ROPE := Palette.FIBRE


## Every part of one ruin in world space: Array of {name, layer, xform, color, far}.
## Box layers use a unit cube; "RuinRound" a unit cylinder standing on its axis.
static func parts(r: Dictionary) -> Array:
	var out: Array = []
	var p := RuinLayout.plan(r)
	for piece in p.pieces:
		match str(piece.piece):
			"house": _house(out, r, piece)
			"barn": _barn(out, r, piece)
			"well": _well(out, r, piece)
			"cart": _cart(out, r, piece)
			"fence": _fence(out, r, piece)
			"rubble": _rubble(out, r, piece)
	for l in p.loot:
		_loot(out, r, l)
	return out


## {"<layer>" or "<layer>Far": Array of [Transform3D, Color]}, only the ones with parts.
static func layout(r: Dictionary) -> Dictionary:
	var layers := {}
	for part in parts(r):
		var key: String = part.layer + ("Far" if part.far else "")
		if not layers.has(key):
			layers[key] = []
		layers[key].append([part.xform, part.color])
	return layers


## The "Ruins" node the client adds to the world: every set piece on the map (none on Ashgrove).
static func build() -> Node3D:
	var root := Node3D.new()
	root.name = NODE_NAME
	for r in Ruins.all():
		var n := build_ruin(r)
		if n != null:
			root.add_child(n)
	return root


## One ruin's node ("Ruin<id>"), or null for a kind without a set piece.
static func build_ruin(r: Dictionary) -> Node3D:
	if not RuinLayout.has_plan(str(r.kind)):
		return null
	var root := Node3D.new()
	root.name = "Ruin%d" % int(r.id)
	root.set_meta("kind", str(r.kind))
	var meshes := _meshes()
	var lay := layout(r)
	for key in lay:
		var layer: String = key.trim_suffix("Far")
		var mmi := _multimesh(key, meshes[layer], lay[key])
		mmi.visibility_range_end = FAR_RANGE if key.ends_with("Far") else NEAR_RANGE
		mmi.visibility_range_end_margin = 20.0
		mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		root.add_child(mmi)
	return root


# --- parts ------------------------------------------------------------------------------

## Adds one part. `origin` and `rot` are the piece's pad point and yaw (before the site's rot);
## `local` is in the piece's frame, its y in metres above the ground under the part's centre.
static func _put(out: Array, r: Dictionary, origin: Vector2, rot: float, part_name: String, layer: String,
		local: Vector3, size: Vector3, color: Color, tilt: Basis = Basis.IDENTITY, far: bool = false) -> void:
	var pad := origin + Vector2(local.x, local.z).rotated(-rot)
	var g := RuinLayout.to_world(r, pad)
	var turn := Basis(Vector3.UP, float(r.rot) + rot)
	out.append({"name": part_name, "layer": layer, "color": color, "far": far,
		"xform": Transform3D(turn * tilt * Basis.from_scale(size), Vector3(g.x, g.y + local.y, g.z))})


static func _rng(piece: Dictionary) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(piece.get("seed", 0))
	return rng


## The burned farmhouse: low broken stone walls with a door gap, one gable end still standing
## with its chimney, charred posts at the other end, fallen roof beams and burned thatch inside,
## and the hearth under the chimney.
static func _house(out: Array, r: Dictionary, piece: Dictionary) -> void:
	var rng := _rng(piece)
	var o: Vector2 = piece.pos
	var rot: float = piece.rot
	var size: Vector2 = piece.size
	var hx := size.x * 0.5
	var hz := size.y * 0.5
	var ce: float = piece.chimney_end
	var t := 0.55 # wall thickness
	var put := func(n: String, layer: String, local: Vector3, sz: Vector3, c: Color, tilt := Basis.IDENTITY, far := false) -> void:
		_put(out, r, o, rot, n, layer, local, sz, c, tilt, far)

	# Long walls (front +z with a door gap, back -z), broken into blocks of varied height.
	for sz_side in [-1.0, 1.0]:
		var x := -hx + t
		while x < hx - t - 0.1:
			var w := minf(rng.randf_range(0.9, 1.5), hx - t - x)
			var cx := x + w * 0.5
			x += w
			var door: bool = sz_side > 0.0 and absf(cx + ce * 0.8) < 0.7
			if door or rng.randf() < 0.12:
				continue # the doorway, and a few blocks fallen out
			# Walls stand taller toward the chimney end, where the fire burned least.
			var toward := clampf(0.5 + 0.5 * ce * cx / hx, 0.0, 1.0)
			var h := rng.randf_range(0.5, 1.2) + toward * rng.randf_range(0.6, 1.6)
			put.call("wall", "RuinStone", Vector3(cx, h * 0.5 - 0.05, sz_side * (hz - t * 0.5)), Vector3(w - 0.04, h, t),
				STONE.darkened(rng.randf_range(0.0, 0.12)), Basis(Vector3.UP, rng.randf_range(-0.03, 0.03)))
			if h > 1.2: # a darker footing course, so the base reads damp and old
				put.call("footing", "RuinStone", Vector3(cx, 0.25, sz_side * (hz - t * 0.5)), Vector3(w, 0.5, t + 0.06), STONE_DARK)
	# The cold end wall: low and broken.
	var z := -hz
	while z < hz - 0.1:
		var w := minf(rng.randf_range(1.0, 1.6), hz - z)
		var cz := z + w * 0.5
		z += w
		if rng.randf() < 0.2:
			continue
		var h := rng.randf_range(0.4, 1.1)
		put.call("wall", "RuinStone", Vector3(-ce * (hx - t * 0.5), h * 0.5 - 0.05, cz), Vector3(t, h, w - 0.04), STONE.darkened(rng.randf_range(0.04, 0.14)))
	# The gable end that still stands: a full-height wall, then a stepped, broken gable.
	var gx := ce * (hx - t * 0.5)
	var wall_h := 3.0
	put.call("gable_wall", "RuinStone", Vector3(gx, wall_h * 0.5 - 0.05, 0.0), Vector3(t, wall_h, size.y), STONE, Basis.IDENTITY, true)
	var steps := 4
	for i in steps:
		var frac := 1.0 - float(i + 1) / float(steps + 1)
		var sw := size.y * frac
		if i == steps - 1 or rng.randf() < 0.15:
			sw *= rng.randf_range(0.5, 0.8) # the top courses are broken off
		var off := rng.randf_range(-0.3, 0.3) * (1.0 - frac)
		put.call("gable_step", "RuinStone", Vector3(gx, wall_h + 0.42 * i + 0.2, off), Vector3(t, 0.42, sw),
			STONE.darkened(0.03 * i), Basis.IDENTITY, true)
	# The chimney stack on the outside of the gable: wide at the foot, sooted at the top.
	var cx_out := ce * (hx + 0.35)
	put.call("chimney_base", "RuinStone", Vector3(cx_out, 1.3, 0.0), Vector3(1.0, 2.6, 1.5), STONE_DARK, Basis.IDENTITY, true)
	put.call("chimney", "RuinStone", Vector3(cx_out, 2.6 + (CHIMNEY_HEIGHT - 3.4) * 0.5, 0.0), Vector3(0.78, CHIMNEY_HEIGHT - 3.4, 1.0),
		STONE, Basis(Vector3.UP, rng.randf_range(-0.03, 0.03)), true)
	put.call("chimney_top", "RuinStone", Vector3(cx_out, CHIMNEY_HEIGHT - 0.4, 0.0), Vector3(0.86, 0.8, 1.08), STONE_SOOT, Basis.IDENTITY, true)
	# The hearth inside, under the chimney: a sooted stone floor and a lintel.
	var hearth_x := ce * (hx - t - 0.45)
	put.call("hearth", "RuinStone", Vector3(hearth_x, 0.06, 0.0), Vector3(0.9, 0.12, 1.6), STONE_SOOT)
	put.call("lintel", "RuinWood", Vector3(ce * (hx - t - 0.05), 1.25, 0.0), Vector3(0.22, 0.22, 1.5), CHAR)
	# Charred corner posts at the burned end, one leaning.
	for sz_side in [-1.0, 1.0]:
		var h := rng.randf_range(1.2, 2.8)
		var lean := Basis(Vector3.FORWARD, rng.randf_range(-0.3, 0.3)) if rng.randf() < 0.5 else Basis.IDENTITY
		put.call("post", "RuinWood", Vector3(-ce * (hx - 0.3), h * 0.5, sz_side * (hz - 0.3)), Vector3(0.24, h, 0.24), CHAR, lean)
	# Roof beams fallen into the house: long charred timbers, one end on the floor, one on a wall.
	for i in rng.randi_range(2, 3):
		var bx := rng.randf_range(-hx * 0.6, hx * 0.6)
		var length := size.y * rng.randf_range(0.8, 1.15)
		var tilt := Basis(Vector3.UP, rng.randf_range(-0.5, 0.5)) * Basis(Vector3.RIGHT, rng.randf_range(0.12, 0.3))
		put.call("beam", "RuinWood", Vector3(bx, 0.45, rng.randf_range(-0.4, 0.4)), Vector3(0.22, 0.2, length),
			CHAR if i % 2 == 0 else CHAR_BROWN, tilt)
	# The thatch came down burning: dark slumped heaps on the floor and against the walls.
	for i in rng.randi_range(3, 4):
		var tx := rng.randf_range(-hx * 0.7, hx * 0.5) * -ce
		var tz := rng.randf_range(-hz * 0.5, hz * 0.5)
		var w := rng.randf_range(1.6, 2.6)
		var tilt := Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3.RIGHT, rng.randf_range(0.05, 0.35))
		put.call("thatch", "RuinThatch", Vector3(tx, 0.18, tz), Vector3(w, 0.28, w * rng.randf_range(0.6, 0.9)),
			THATCH_BURNT.lightened(rng.randf_range(0.0, 0.08)), tilt)


## The barn: an old timber frame, part still standing with its roof on, the rest fallen in.
static func _barn(out: Array, r: Dictionary, piece: Dictionary) -> void:
	var rng := _rng(piece)
	var o: Vector2 = piece.pos
	var rot: float = piece.rot
	var size: Vector2 = piece.size
	var hx := size.x * 0.5
	var hz := size.y * 0.5
	var standing: int = piece.standing # bays (of 2) still standing
	var post_h := 3.0
	var put := func(n: String, layer: String, local: Vector3, sz: Vector3, c: Color, tilt := Basis.IDENTITY, far := false) -> void:
		_put(out, r, o, rot, n, layer, local, sz, c, tilt, far)
	var xs := [-hx, 0.0, hx]
	# Posts on both long sides; the ones past the standing bays are broken stumps.
	for i in xs.size():
		for sz_side in [-1.0, 1.0]:
			var up := i <= standing
			var h := post_h if up else rng.randf_range(0.6, 1.4)
			put.call("barn_post", "RuinWood", Vector3(xs[i], h * 0.5, sz_side * hz), Vector3(0.26, h, 0.26),
				OLD_TIMBER.darkened(rng.randf_range(0.0, 0.1)), Basis.IDENTITY, up)
	# Wall plates and tie beams over the standing bays.
	var stand_x0: float = xs[0]
	var stand_x1: float = xs[standing]
	var stand_w := stand_x1 - stand_x0
	var stand_c := (stand_x0 + stand_x1) * 0.5
	for sz_side in [-1.0, 1.0]:
		put.call("plate", "RuinWood", Vector3(stand_c, post_h + 0.1, sz_side * hz), Vector3(stand_w + 0.3, 0.22, 0.24), OLD_TIMBER, Basis.IDENTITY, true)
	for i in standing + 1:
		put.call("tie", "RuinWood", Vector3(xs[i], post_h + 0.1, 0.0), Vector3(0.22, 0.2, size.y), OLD_TIMBER.darkened(0.05))
	# The roof over the standing bays: two thatched slopes meeting at a ridge.
	var pitch := 0.62
	var slope := hz / cos(pitch) + 0.4
	for sz_side in [-1.0, 1.0]:
		var tilt := Basis(Vector3.RIGHT, sz_side * pitch) # slopes down to the eaves
		put.call("roof", "RuinThatch", Vector3(stand_c, post_h + 0.25 + hz * tan(pitch) * 0.5, sz_side * hz * 0.5),
			Vector3(stand_w + 0.6, 0.3, slope), THATCH_ROT.darkened(rng.randf_range(0.0, 0.06)), tilt, true)
	put.call("ridge", "RuinWood", Vector3(stand_c, post_h + 0.3 + hz * tan(pitch), 0.0), Vector3(stand_w + 0.7, 0.2, 0.2), OLD_TIMBER.darkened(0.1), Basis.IDENTITY, true)
	# Planks on the back wall of the standing part, a few missing.
	var px := stand_x0 + 0.15
	while px < stand_x1 - 0.1:
		if rng.randf() > 0.2:
			var h := post_h * rng.randf_range(0.75, 1.0)
			put.call("plank", "RuinWood", Vector3(px + 0.15, h * 0.5, -hz - 0.05), Vector3(0.28, h, 0.06), OLD_PLANK.darkened(rng.randf_range(0.0, 0.12)))
		px += 0.3
	# The fallen part: a roof slope slumped to the ground and loose rafters.
	if standing < 2:
		var fx: float = (xs[standing] + xs[2]) * 0.5
		var fw: float = xs[2] - xs[standing]
		put.call("fallen_roof", "RuinThatch", Vector3(fx + 0.3, 0.75, rng.randf_range(-0.5, 0.5)), Vector3(fw + 0.4, 0.3, size.y * 0.8),
			THATCH_ROT.darkened(0.08), Basis(Vector3.FORWARD, rng.randf_range(0.2, 0.32)) * Basis(Vector3.RIGHT, rng.randf_range(-0.15, 0.15)))
		for i in 3:
			put.call("rafter", "RuinWood", Vector3(fx + rng.randf_range(-1.0, 1.0), 0.2, rng.randf_range(-hz, hz)), Vector3(0.14, 0.12, 3.0),
				OLD_TIMBER.darkened(0.08), Basis(Vector3.UP, rng.randf_range(-0.8, 0.8)) * Basis(Vector3.RIGHT, rng.randf_range(0.0, 0.2)))


## The well: a ring of stone, two posts and a cross beam, a rope and a bucket left on the edge.
static func _well(out: Array, r: Dictionary, piece: Dictionary) -> void:
	var rng := _rng(piece)
	var o: Vector2 = piece.pos
	var rot: float = piece.rot
	var put := func(n: String, layer: String, local: Vector3, sz: Vector3, c: Color, tilt := Basis.IDENTITY) -> void:
		_put(out, r, o, rot, n, layer, local, sz, c, tilt)
	var ring := 9
	for i in ring:
		var a := TAU * float(i) / float(ring)
		var h := 0.78 if rng.randf() > 0.15 else 0.45
		put.call("well_stone", "RuinStone", Vector3(cos(a) * 0.85, h * 0.5, sin(a) * 0.85), Vector3(0.62, h, 0.34),
			STONE.darkened(rng.randf_range(0.0, 0.14)), Basis(Vector3.UP, -a + PI * 0.5))
	put.call("well_dark", "RuinStone", Vector3(0.0, 0.02, 0.0), Vector3(1.2, 0.04, 1.2), STONE_SOOT.darkened(0.2))
	for sx in [-1.0, 1.0]:
		put.call("well_post", "RuinWood", Vector3(sx * 1.0, 1.05, 0.0), Vector3(0.16, 2.1, 0.16), OLD_TIMBER)
	put.call("well_beam", "RuinWood", Vector3(0.0, 2.05, 0.0), Vector3(2.3, 0.14, 0.14), OLD_TIMBER.darkened(0.08))
	put.call("rope", "RuinWood", Vector3(0.2, 1.55, 0.0), Vector3(0.03, 1.0, 0.03), ROPE)
	put.call("bucket", "RuinRound", Vector3(1.05, 0.17, 0.55), Vector3(0.34, 0.34, 0.34), OLD_PLANK.darkened(0.1),
		Basis(Vector3.FORWARD, 1.4))
	put.call("bucket_hoop", "RuinRound", Vector3(1.05, 0.17, 0.55), Vector3(0.36, 0.05, 0.36), IRON, Basis(Vector3.FORWARD, 1.4))


## The cart wreck: a tilted bed missing a wheel, the wheel lying beside it, the shafts down.
static func _cart(out: Array, r: Dictionary, piece: Dictionary) -> void:
	var rng := _rng(piece)
	var o: Vector2 = piece.pos
	var rot: float = piece.rot
	var put := func(n: String, layer: String, local: Vector3, sz: Vector3, c: Color, tilt := Basis.IDENTITY) -> void:
		_put(out, r, o, rot, n, layer, local, sz, c, tilt)
	var roll := Basis(Vector3.BACK, 0.22) # down on the side that lost its wheel
	put.call("cart_bed", "RuinWood", Vector3(0.0, 0.55, 0.0), Vector3(1.3, 0.1, 2.3), OLD_PLANK.darkened(0.05), roll)
	for sx in [-1.0, 1.0]:
		put.call("cart_side", "RuinWood", Vector3(sx * 0.62, 0.72 + sx * 0.14, 0.0), Vector3(0.06, 0.35, 2.3), OLD_TIMBER, roll)
	put.call("cart_back", "RuinWood", Vector3(0.0, 0.72, -1.12), Vector3(1.2, 0.35, 0.06), OLD_TIMBER.darkened(0.06), roll)
	# The wheel that held: upright on the high side.
	var wheel := Basis(Vector3.FORWARD, PI * 0.5)
	put.call("wheel", "RuinRound", Vector3(0.75, 0.55, 0.1), Vector3(1.1, 0.08, 1.1), OLD_TIMBER.darkened(0.12), wheel)
	put.call("hub", "RuinRound", Vector3(0.8, 0.55, 0.1), Vector3(0.22, 0.14, 0.22), IRON, wheel)
	# The one that broke off, flat in the grass.
	put.call("wheel", "RuinRound", Vector3(-1.5, 0.04, rng.randf_range(-0.6, 0.6)), Vector3(1.1, 0.08, 1.1), OLD_TIMBER.darkened(0.16))
	for sx in [-1.0, 1.0]:
		put.call("shaft", "RuinWood", Vector3(sx * 0.4, 0.15, 2.0), Vector3(0.09, 0.09, 2.0), OLD_TIMBER,
			Basis(Vector3.RIGHT, 0.12) * Basis(Vector3.UP, sx * 0.08))


## The fence run: posts with two rails between standing neighbours, a few leaning or gone.
static func _fence(out: Array, r: Dictionary, piece: Dictionary) -> void:
	var rng := _rng(piece)
	var posts: Array = piece.posts
	var put := func(n: String, layer: String, at: Vector2, yaw: float, local: Vector3, sz: Vector3, c: Color, tilt := Basis.IDENTITY) -> void:
		_put(out, r, at, yaw, n, layer, local, sz, c, tilt)
	for i in posts.size():
		var p: Dictionary = posts[i]
		if not p.standing:
			continue
		put.call("fence_post", "RuinWood", p.pos, 0.0, Vector3(0.0, 0.6, 0.0), Vector3(0.14, 1.2, 0.14),
			OLD_TIMBER.darkened(rng.randf_range(0.0, 0.12)), Basis(Vector3.FORWARD, p.lean))
		if i + 1 < posts.size() and posts[i + 1].standing:
			var a: Vector2 = p.pos
			var b: Vector2 = posts[i + 1].pos
			var mid := (a + b) * 0.5
			var d := b - a
			var yaw := atan2(d.x, d.y) # the rail's local z runs from a to b (see RuinLayout.to_world)
			for h in [0.45, 0.95]:
				if rng.randf() < 0.12:
					continue
				put.call("fence_rail", "RuinWood", mid, yaw, Vector3(0.0, h, 0.0), Vector3(0.07, 0.1, d.length() + 0.1), OLD_PLANK)
		elif i + 1 < posts.size():
			# The rail that came down with the missing post.
			put.call("fence_rail", "RuinWood", (p.pos as Vector2) + Vector2(0.3, 0.3), rng.randf() * TAU, Vector3(0.0, 0.05, 0.0),
				Vector3(0.07, 0.1, 2.2), OLD_PLANK.darkened(0.08))


## Stones fallen from the house walls.
static func _rubble(out: Array, r: Dictionary, piece: Dictionary) -> void:
	var rng := _rng(piece)
	for s in piece.stones:
		var sz: float = s.size
		_put(out, r, s.pos, s.rot, "rubble", "RuinStone", Vector3(0.0, sz * 0.25, 0.0), Vector3(sz, sz * 0.6, sz * 0.8),
			STONE.darkened(rng.randf_range(0.0, 0.16)), Basis(Vector3.RIGHT, rng.randf_range(-0.3, 0.3)))


## What you can search: drawn on the very spots gameplay fills.
static func _loot(out: Array, r: Dictionary, l: Dictionary) -> void:
	var o: Vector2 = l.pos
	var rot: float = l.rot
	var put := func(n: String, layer: String, local: Vector3, sz: Vector3, c: Color, tilt := Basis.IDENTITY) -> void:
		_put(out, r, o, rot, n, layer, local, sz, c, tilt)
	match str(l.kind):
		"crate":
			put.call("crate", "RuinWood", Vector3(0.0, 0.36, 0.0), Vector3(0.78, 0.72, 0.66), CRATE)
			for y in [0.12, 0.6]:
				put.call("crate_slat", "RuinWood", Vector3(0.0, y, 0.0), Vector3(0.82, 0.08, 0.7), CRATE.darkened(0.18))
		"chest":
			put.call("chest", "RuinWood", Vector3(0.0, 0.26, 0.0), Vector3(0.95, 0.5, 0.56), CHEST)
			put.call("chest_lid", "RuinWood", Vector3(0.0, 0.55, 0.0), Vector3(0.98, 0.1, 0.6), CHEST.darkened(0.08))
			for x in [-0.32, 0.32]:
				put.call("chest_band", "RuinWood", Vector3(x, 0.3, 0.0), Vector3(0.06, 0.6, 0.6), IRON)
			put.call("chest_lock", "RuinWood", Vector3(0.0, 0.45, 0.3), Vector3(0.12, 0.14, 0.04), IRON.darkened(0.1))
		"sack":
			put.call("sack", "RuinRound", Vector3(0.0, 0.22, 0.0), Vector3(0.55, 0.44, 0.45), SACK, Basis(Vector3.FORWARD, 0.25))
			put.call("sack_neck", "RuinRound", Vector3(0.28, 0.36, 0.0), Vector3(0.18, 0.2, 0.18), SACK.darkened(0.08), Basis(Vector3.FORWARD, 1.1))
		"body":
			# Face down under a cloak: a long low shape, a hood, and the boots showing.
			put.call("body_cloak", "RuinThatch", Vector3(0.0, 0.14, 0.0), Vector3(0.55, 0.26, 1.15), CLOAK)
			put.call("body_hood", "RuinRound", Vector3(0.0, 0.13, 0.72), Vector3(0.3, 0.24, 0.32), CLOAK.darkened(0.06), Basis(Vector3.RIGHT, PI * 0.5))
			for sx in [-0.12, 0.12]:
				put.call("body_boot", "RuinThatch", Vector3(sx, 0.07, -0.72), Vector3(0.12, 0.14, 0.3), BOOT)


# --- build --------------------------------------------------------------------------------

static func _meshes() -> Dictionary:
	var box := BoxMesh.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.5
	cyl.bottom_radius = 0.5
	cyl.height = 1.0
	cyl.radial_segments = 8
	cyl.rings = 1
	# Baked like the rest of the world: darker toward each part's foot (art bible section 2).
	return {"RuinStone": Emberlight.bake(box, 0.35, 1.4), "RuinWood": Emberlight.bake(box, 0.25),
		"RuinThatch": Emberlight.bake(box, 0.3), "RuinRound": Emberlight.bake(cyl, 0.25)}


static func _multimesh(node_name: String, mesh: Mesh, instances: Array) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = instances.size()
	for i in instances.size():
		mm.set_instance_transform(i, instances[i][0])
		mm.set_instance_color(i, (instances[i][1] as Color).srgb_to_linear())
	var mmi := MultiMeshInstance3D.new()
	mmi.name = node_name
	mmi.multimesh = mm
	mmi.material_override = Emberlight.material("solid")
	return mmi
