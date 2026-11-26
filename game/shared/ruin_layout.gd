class_name RuinLayout
## Where things stand in a ruin set piece, as plain data (Basics 4, landmarks with loot).
##
## Each set piece is laid out from its site alone (`Ruins.all()`: pos, rot, layout_seed), so
## the same island gives the same farmstead on every machine and a new island (a wipe) lays it
## out differently. Art (`RuinKit`) builds its meshes from this plan, and gameplay fills the
## loot spots from it, so what you see and what you can search can never drift apart.
##
## A plan is {pieces: Array, loot: Array}. Positions are local metres on the pad (x, z) before
## the site's `rot`; `to_world()` turns them into ground points.
##   piece: {piece: "house"|"barn"|"well"|"cart"|"fence"|"rubble", pos: Vector2, rot: float,
##           size: Vector2 (house, barn), seed: int, ...piece-specific}
##   loot:  {kind: "crate"|"chest"|"sack"|"body", pos: Vector2, rot: float}
##
## Only the burned farmstead (grade 1) has a plan so far; other kinds return an empty plan.
## Pure and deterministic: safe on the server, in bots and in unit tests.

const KINDS := ["burned_farmstead"] ## ruin kinds with a set piece
const LOOT_KINDS := ["crate", "chest", "sack", "body"]
const FARM_YARD := 19.0 ## metres: everything in a farmstead stands inside this radius (pad is 22)


## True if `kind` has a set piece.
static func has_plan(kind: String) -> bool:
	return kind in KINDS


## The plan for one ruin from `Ruins.all()`. Empty pieces and loot for kinds without one.
static func plan(r: Dictionary) -> Dictionary:
	match str(r.get("kind", "")):
		"burned_farmstead":
			return farmstead(int(r.get("layout_seed", 0)), r.get("pos", Vector3.ZERO))
	return {"pieces": [], "loot": []}


## A local pad point (before the site's rot) as a world point on the ground.
static func to_world(r: Dictionary, local: Vector2) -> Vector3:
	var o: Vector3 = r.pos
	var w := local.rotated(-float(r.get("rot", 0.0))) # Basis(UP, rot) * (x, 0, z), in 2D
	var x := o.x + w.x
	var z := o.z + w.y
	return Vector3(x, Terrain.height(x, z), z)


## Every loot spot of one ruin in world space:
## [{ruin_id, index, kind, pos: Vector3 on the ground, rot: world yaw}], in plan order.
static func loot_spots(r: Dictionary) -> Array:
	var out: Array = []
	var p := plan(r)
	for i in p.loot.size():
		var l: Dictionary = p.loot[i]
		out.append({"ruin_id": int(r.id), "index": i, "kind": str(l.kind),
			"pos": to_world(r, l.pos), "rot": float(r.get("rot", 0.0)) + float(l.rot)})
	return out


## Every loot spot in the world, ruin by ruin in `Ruins.all()` order. Empty on Ashgrove.
static func all_loot_spots() -> Array:
	var out: Array = []
	for r in Ruins.all():
		out.append_array(loot_spots(r))
	return out


## The burned farmstead: a burned stone farmhouse whose chimney still stands (the far
## landmark), a half-fallen timber barn, a well, a cart wreck, a broken fence run and rubble.
## The barn's side, the well, the cart and the fence move round the house per seed, and the
## house's size and which end keeps its chimney change too.
static func farmstead(layout_seed: int, site_pos: Vector3 = Vector3.ZERO) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	# Version 1 kingdoms have no layout_seed (0): fall back to the site's position so two
	# farmsteads on one map still differ. Deterministic either way.
	rng.seed = layout_seed if layout_seed != 0 else hash(Vector2i(int(site_pos.x), int(site_pos.z)))
	var pieces: Array = []
	var loot: Array = []

	# The house sits near the middle of the yard, its front (+z) facing the open side.
	var house_size := Vector2(rng.randf_range(7.4, 9.0), rng.randf_range(5.0, 6.0))
	var house_rot := rng.randf_range(-0.25, 0.25)
	var house_pos := Vector2(rng.randf_range(-1.5, 1.5), rng.randf_range(-1.5, 1.5))
	var chimney_end := -1.0 if rng.randf() < 0.5 else 1.0
	pieces.append({"piece": "house", "pos": house_pos, "rot": house_rot, "size": house_size,
		"chimney_end": chimney_end, "seed": rng.randi()})
	# The chest lies inside by the hearth, under the chimney: worth stepping into the ashes for.
	var hearth_local := Vector2(chimney_end * (house_size.x * 0.5 - 1.3), rng.randf_range(-0.8, 0.8))
	loot.append({"kind": "chest", "pos": house_pos + hearth_local.rotated(-house_rot), "rot": house_rot + chimney_end * PI * 0.5})

	# The barn on one side, the well across the yard from it, the cart between.
	var a_barn := rng.randf() * TAU
	var side := -1.0 if rng.randf() < 0.5 else 1.0
	var barn_size := Vector2(rng.randf_range(6.0, 7.2), rng.randf_range(4.4, 5.2))
	var barn_pos := Vector2.from_angle(a_barn) * rng.randf_range(11.0, 12.0)
	var barn_rot := -a_barn - PI * 0.5 + rng.randf_range(-0.2, 0.2) # its front (+z) faces the house
	pieces.append({"piece": "barn", "pos": barn_pos, "rot": barn_rot, "size": barn_size,
		"standing": rng.randi_range(1, 2), "seed": rng.randi()})
	# A crate against the barn's house-facing wall.
	var crate_local := Vector2(rng.randf_range(-1.5, 1.5), barn_size.y * 0.5 + 0.9)
	loot.append({"kind": "crate", "pos": barn_pos + _house_side(crate_local, barn_rot), "rot": barn_rot + rng.randf_range(-0.4, 0.4)})

	var a_well := a_barn + PI + rng.randf_range(-0.6, 0.6)
	var well_pos := Vector2.from_angle(a_well) * rng.randf_range(8.8, 10.0)
	pieces.append({"piece": "well", "pos": well_pos, "rot": rng.randf() * TAU, "seed": rng.randi()})
	# Someone who didn't make it out, by the well.
	var body_off := Vector2.from_angle(a_well + side * 0.5) * 2.0
	loot.append({"kind": "body", "pos": well_pos + body_off, "rot": rng.randf() * TAU})

	var a_cart := a_barn + side * PI * 0.5 + rng.randf_range(-0.3, 0.3)
	var cart_pos := Vector2.from_angle(a_cart) * rng.randf_range(11.5, 13.5)
	var cart_rot := rng.randf() * TAU
	pieces.append({"piece": "cart", "pos": cart_pos, "rot": cart_rot, "seed": rng.randi()})
	# A sack fallen off the back of the cart.
	loot.append({"kind": "sack", "pos": cart_pos + Vector2(0.0, -2.2).rotated(-cart_rot), "rot": rng.randf() * TAU})

	# A fence run along the far side from the cart: posts every couple of metres, some gone.
	var a_fence := a_cart + PI + rng.randf_range(-0.4, 0.4)
	var fence_r := rng.randf_range(16.0, 17.5)
	var span := rng.randf_range(1.2, 1.7)
	var posts: Array = [] # [Vector2 local, standing: bool, lean: float]
	var n := int(span * fence_r / 2.3)
	for i in n + 1:
		var a := a_fence - span * 0.5 + span * float(i) / float(n)
		var gone := rng.randf() < 0.15
		posts.append({"pos": Vector2.from_angle(a) * fence_r, "standing": not gone,
			"lean": rng.randf_range(-0.25, 0.25) if rng.randf() < 0.3 else 0.0})
	pieces.append({"piece": "fence", "pos": Vector2.from_angle(a_fence) * fence_r, "rot": 0.0, "posts": posts, "seed": rng.randi()})

	# Rubble: stones fallen from the house walls, mostly round the house.
	var stones: Array = []
	for i in rng.randi_range(9, 13):
		var a := rng.randf() * TAU
		var d := Vector2(absf(cos(a)) * house_size.x, absf(sin(a)) * house_size.y).length() * 0.5 + rng.randf_range(0.3, 2.2)
		stones.append({"pos": house_pos + Vector2.from_angle(a) * d, "size": rng.randf_range(0.3, 0.7), "rot": rng.randf() * TAU})
	pieces.append({"piece": "rubble", "pos": house_pos, "rot": 0.0, "stones": stones, "seed": rng.randi()})
	return {"pieces": pieces, "loot": loot}


## A point in a piece's own frame (x along its length, z out of its front) moved to the pad.
static func _house_side(local: Vector2, piece_rot: float) -> Vector2:
	return local.rotated(-piece_rot)
