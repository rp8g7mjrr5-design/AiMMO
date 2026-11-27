class_name HeldItems
## What you hold: carved meshes for every tool, weapon and the torch, sized to the carved hand
## (Carved, art bible section 3), for the client to hang on a figure's "RightHand" bone.
##
## The same shapes as the pack icons (ItemIcons), so the thing in your hand is the thing in
## your pack: the wooden axe and pickaxe are the stone ones' shapes carved from one piece of
## wood, the stone tier has a grey knapped head lashed on with plant fibre, the club swells into
## a knotted head, the maul is a squared stone block, the spears are long pine shafts (one
## fire-hardened, one with a stone point), and the torch has a wrapped, charred head. About 1.2x
## real size so they read in hand (art bible section 3). Grounded kit, no magic (design bible
## direction 11): the only glow is the torch's flame.
##
## Built like Carved: a few low-poly solids per item with FLAT shading on the shared "carved"
## material (no paint grain), one flat colour per part, all colours worked out from Palette.
## Every item is ONE mesh and one draw call (the torch adds a second surface for its flame on
## the Emberlight "glow" material). A few hundred triangles each.
##
## Item space (the grip): the hand closes round the origin; the haft runs along +Y away from
## the little finger toward the head; +Z is the striking side (the axe's edge, the pick's long
## prong, the maul's face); left is +X. `GRIP` turns item space into the hand bone's space:
## with the arm hanging at rest the haft points forward and the edge down, so with the arm
## raised forward (an overhead chop) the haft points up and the edge faces the swing.
##
## `geometry(id)` is pure (no renderer), for tests and headless runs; `mesh`, `node` and
## `attach` make the resources and nodes.

const MAX_TRIS := 400
const NODE_NAME := "HeldItem" ## the BoneAttachment3D `attach` adds under a figure's skeleton
const BONE := "RightHand"
## The hand bone's space from item space: haft (item +Y) along the hand's +Z, the striking side
## (item +Z) down the hand (-Y), the grip in the curled palm (Carved's palm box is 0.045 to 0.11
## m below the wrist).
const GRIP := Transform3D(Basis(Vector3.RIGHT, PI / 2.0), Vector3(0, -0.078, 0.012))
## Everything that can be held, in the pack's order (Crafting.RECIPE_ORDER).
const IDS := ["wooden_axe", "wooden_pickaxe", "wooden_club", "wooden_spear", "torch",
	"stone_axe", "stone_pickaxe", "stone_maul", "stone_spear"]

## Colours, all from Palette (no literals here; art bible section 8).
static var HANDLE := Palette.WORKED_WOOD.lerp(Palette.DRIFTWOOD, 0.35) ## a pale ash handle, worn by the hand
static var GRIP_WRAP := Palette.LEATHER_DARK ## the grip of a club or maul, a strip of old hide
static var CARVED_HEAD := Palette.WORKED_WOOD.darkened(0.06) ## a carved wooden head, darker than the handle
static var PEG := Palette.WORKED_WOOD.darkened(0.35)
static var HARDENED := Palette.FIRE_LOG ## a fire-hardened point: bark going to char
static var STONE := Palette.ROCK.lightened(0.04) ## a knapped stone head
static var STONE_DARK := Palette.ROCK.darkened(0.18)
static var STONE_EDGE := Palette.ROCK.lightened(0.3) ## a fresh-knapped edge: paler where the flakes came off
static var LASHING := Palette.FIBRE.darkened(0.35) ## plant-fibre lashing, the stone tier's binding
static var WRAP := Palette.LINEN.darkened(0.3) ## a torch's rag wrap, grubby with pitch
static var CHAR := Palette.FIRE_CHAR ## the burned top of the wrap
static var FLAME := Palette.EMBER ## the torch's flame: fire, the one thing that glows


static func has(id: String) -> bool:
	return id in IDS


# ------------------------------------------------------------------ parts
# A part: [arrays (PrimitiveMesh.get_mesh_arrays), colour, Transform3D in item space, glow].

static var _prims := {}


static func _prim(key: String, m: PrimitiveMesh) -> Array:
	if not _prims.has(key):
		_prims[key] = m.get_mesh_arrays()
	return _prims[key]


## A basis whose Y runs along `up`.
static func _along(up: Vector3) -> Basis:
	var y := up.normalized()
	var ref := Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.95 else Vector3.RIGHT
	var x := ref.cross(y).normalized()
	return Basis(x, y, x.cross(y).normalized())


static func _box(out: Array, pos: Vector3, size: Vector3, c: Color, rot := Vector3.ZERO) -> void:
	out.append([_prim("box", BoxMesh.new()), c, Transform3D(Basis.from_euler(rot) * Basis.from_scale(size), pos), false])


## A faceted ball of half widths `r`.
static func _ball(out: Array, pos: Vector3, r: Vector3, c: Color, seg := 6, rings := 4) -> void:
	var m := SphereMesh.new()
	m.radius = 1.0
	m.height = 2.0
	m.radial_segments = seg
	m.rings = rings
	out.append([_prim("ball%d/%d" % [seg, rings], m), c, Transform3D(Basis.from_scale(r), pos), false])


## A tapered prism from a (radius r1) to b (radius r2), `sides` sides, squashed across by
## `width` (item X) and `depth` (the other way); a cone when r2 is 0.
static func _seg(out: Array, a: Vector3, b: Vector3, r1: float, r2: float, c: Color, sides := 6,
		width := 1.0, depth := 1.0, glow := false) -> void:
	var m := CylinderMesh.new()
	m.top_radius = r2
	m.bottom_radius = r1
	m.height = 1.0
	m.radial_segments = sides
	m.rings = 0
	var bs := _along(b - a)
	# Keep "width" on item X where the segment allows it, so flat blades lie the right way.
	if absf((b - a).normalized().dot(Vector3.RIGHT)) < 0.9:
		var y := (b - a).normalized()
		var z := Vector3.RIGHT.cross(y).normalized()
		bs = Basis(y.cross(z).normalized(), y, z)
	var xf := Transform3D(bs * Basis.from_scale(Vector3(width, a.distance_to(b), depth)), (a + b) * 0.5)
	out.append([_prim("seg%d/%.4f/%.4f" % [sides, r1, r2], m), c, xf, glow])


## A haft from the butt (below the hand) to `top`, slightly thicker at the hand.
static func _haft(out: Array, butt: float, top: float, r: float) -> void:
	_seg(out, Vector3(0, -butt, 0), Vector3(0, top, 0), r * 1.08, r * 0.92, HANDLE, 6)
	_seg(out, Vector3(0, -butt - 0.012, 0), Vector3(0, -butt, 0), r * 0.9, r * 1.08, HANDLE.darkened(0.1), 6) # the worn butt


## Two turns of lashing round the haft at height y.
static func _lash(out: Array, y: float, r: float, c: Color) -> void:
	for i in 2:
		_seg(out, Vector3(0, y + i * 0.022 - 0.011, 0), Vector3(0, y + i * 0.022 + 0.007, 0), r * 1.28, r * 1.28, c.darkened(0.06 * i), 6)


## Every part of the item `id` (one of IDS; [] for anything else, e.g. "fists").
static func parts(id: String) -> Array:
	var out: Array = []
	match id:
		"wooden_axe", "stone_axe":
			var stone := id == "stone_axe"
			_haft(out, 0.09, 0.53, 0.022)
			var head := STONE if stone else CARVED_HEAD
			# The wedge: thick where it meets the haft, thin at the edge (+Z), taller than wide.
			_seg(out, Vector3(0, 0.45, -0.035), Vector3(0, 0.44, 0.16), 0.05, 0.016, head, 4, 0.62, 1.55)
			if stone:
				_seg(out, Vector3(0, 0.44, 0.15), Vector3(0, 0.44, 0.172), 0.02, 0.006, STONE_EDGE, 4, 0.5, 1.7)
				_lash(out, 0.405, 0.022, LASHING)
				_lash(out, 0.5, 0.022, LASHING)
			else:
				_box(out, Vector3(0, 0.455, 0.0), Vector3(0.062, 0.018, 0.018), PEG) # the peg through the haft
		"wooden_pickaxe", "stone_pickaxe":
			var stone := id == "stone_pickaxe"
			_haft(out, 0.1, 0.6, 0.022)
			var head := STONE if stone else CARVED_HEAD
			# Two prongs from a collar at the top: the long one forward (+Z), a short one back.
			_seg(out, Vector3(0, 0.575, 0.0), Vector3(0, 0.52, 0.24), 0.034, 0.007, head, 5, 0.85, 1.0)
			_seg(out, Vector3(0, 0.575, 0.0), Vector3(0, 0.535, -0.17), 0.032, 0.009, head, 5, 0.85, 1.0)
			_seg(out, Vector3(0, 0.545, 0), Vector3(0, 0.61, 0), 0.034, 0.03, head.darkened(0.06), 5)
			if stone:
				_box(out, Vector3(0, 0.575, 0), Vector3(0.056, 0.05, 0.05), LASHING, Vector3(0.6, 0, 0))
				_lash(out, 0.52, 0.022, LASHING)
		"wooden_club":
			# A heavy ash club: a grip that swells into a knotted head.
			_seg(out, Vector3(0, -0.09, 0), Vector3(0, 0.26, 0), 0.024, 0.03, HANDLE, 6)
			_seg(out, Vector3(0, 0.26, 0), Vector3(0, 0.6, 0), 0.03, 0.058, CARVED_HEAD, 7)
			_seg(out, Vector3(0, 0.6, 0), Vector3(0, 0.67, 0), 0.058, 0.03, CARVED_HEAD.darkened(0.08), 7)
			_ball(out, Vector3(0.042, 0.5, 0.02), Vector3(0.022, 0.03, 0.022), CARVED_HEAD.darkened(0.14))
			_ball(out, Vector3(-0.03, 0.43, -0.03), Vector3(0.018, 0.026, 0.018), CARVED_HEAD.darkened(0.14))
			_ball(out, Vector3(-0.01, 0.58, 0.05), Vector3(0.02, 0.026, 0.02), CARVED_HEAD.darkened(0.14))
			_seg(out, Vector3(0, -0.06, 0), Vector3(0, 0.07, 0), 0.028, 0.028, GRIP_WRAP, 6)
		"stone_maul":
			# A short handle and a big squared stone head, lashed on crosswise.
			_haft(out, 0.1, 0.62, 0.026)
			_box(out, Vector3(0, 0.6, 0.02), Vector3(0.12, 0.13, 0.28), STONE)
			_box(out, Vector3(0, 0.6, 0.162), Vector3(0.1, 0.11, 0.014), STONE_EDGE) # the striking face, worn pale
			_box(out, Vector3(0, 0.6, -0.122), Vector3(0.1, 0.11, 0.012), STONE_DARK)
			_box(out, Vector3(0, 0.6, 0.02), Vector3(0.128, 0.026, 0.06), LASHING, Vector3(0, 0, 0.0))
			_box(out, Vector3(0, 0.6, 0.02), Vector3(0.06, 0.138, 0.04), LASHING.darkened(0.06))
			_seg(out, Vector3(0, -0.07, 0), Vector3(0, 0.07, 0), 0.03, 0.03, GRIP_WRAP, 6)
		"wooden_spear", "stone_spear":
			# A long pine shaft held a third of the way up: 1.9 m with its point.
			_haft(out, 0.72, 1.06, 0.019)
			if id == "wooden_spear":
				_seg(out, Vector3(0, 1.06, 0), Vector3(0, 1.2, 0), 0.0175, 0.0, HARDENED, 6)
			else:
				_seg(out, Vector3(0, 1.03, 0), Vector3(0, 1.1, 0), 0.006, 0.042, STONE, 4, 1.0, 0.45)
				_seg(out, Vector3(0, 1.1, 0), Vector3(0, 1.24, 0), 0.042, 0.0, STONE, 4, 1.0, 0.45)
				_seg(out, Vector3(0, 1.1, 0), Vector3(0, 1.23, 0), 0.016, 0.0, STONE_EDGE, 4, 1.0, 0.7)
				_lash(out, 1.04, 0.019, LASHING)
			_lash(out, -0.05, 0.019, LASHING.darkened(0.1))
		"torch":
			# A stick with a rag wrapped round the top, charred where it burns, and the flame.
			_seg(out, Vector3(0, -0.13, 0), Vector3(0, 0.4, 0), 0.02, 0.024, HANDLE.darkened(0.08), 6)
			_seg(out, Vector3(0, 0.36, 0), Vector3(0, 0.47, 0), 0.036, 0.04, WRAP, 6)
			_seg(out, Vector3(0, 0.47, 0), Vector3(0, 0.51, 0), 0.04, 0.03, CHAR, 6)
			_lash(out, 0.37, 0.026, LASHING)
			# Three tongues of flame, translucent ember (art bible section 10), not a ball.
			_seg(out, Vector3(0, 0.49, 0), Vector3(0.006, 0.68, 0.01), 0.034, 0.0, FLAME, 5, 1.0, 1.0, true)
			_seg(out, Vector3(0.018, 0.49, -0.01), Vector3(0.03, 0.61, -0.02), 0.02, 0.0, FLAME, 5, 1.0, 1.0, true)
			_seg(out, Vector3(-0.016, 0.49, 0.012), Vector3(-0.026, 0.59, 0.024), 0.018, 0.0, FLAME, 5, 1.0, 1.0, true)
	return out


## The item's triangles as flat-shaded arrays: {"solid": {verts, normals, colors},
## "glow": {...}} (glow is empty for everything but the torch). Pure, for tests.
static func geometry(id: String) -> Dictionary:
	var out := {"solid": _empty(), "glow": _empty()}
	for p in parts(id):
		var a: Array = p[0]
		var pv: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var pn: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
		var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX]
		var xf: Transform3D = p[2]
		var nb := xf.basis.inverse().transposed()
		var glow: bool = p[3]
		# The glow variant reads vertex alpha below 1 as ember (Emberlight): 0 = all flame.
		var lin := (p[1] as Color).srgb_to_linear()
		var col := Color(lin.r, lin.g, lin.b, 0.0 if glow else 1.0)
		var g: Dictionary = out.glow if glow else out.solid
		for t in range(0, idx.size(), 3):
			var v0 := xf * pv[idx[t]]
			var v1 := xf * pv[idx[t + 1]]
			var v2 := xf * pv[idx[t + 2]]
			var fn := (v1 - v0).cross(v2 - v0)
			if fn.length_squared() < 1e-14:
				continue # a pole's sliver
			fn = fn.normalized()
			if fn.dot(nb * (pn[idx[t]] + pn[idx[t + 1]] + pn[idx[t + 2]])) < 0.0:
				fn = -fn
			for v in [v0, v1, v2]:
				g.verts.append(v)
				g.normals.append(fn)
				g.colors.append(col)
	return out


static func _empty() -> Dictionary:
	return {"verts": PackedVector3Array(), "normals": PackedVector3Array(), "colors": PackedColorArray()}


static func triangles(id: String) -> int:
	var g := geometry(id)
	return ((g.solid.verts as PackedVector3Array).size() + (g.glow.verts as PackedVector3Array).size()) / 3


# ------------------------------------------------------------------ resources and nodes

static var _meshes := {}


## The item as one ArrayMesh with its materials set (cached; null for anything not in IDS).
static func mesh(id: String) -> ArrayMesh:
	if not has(id):
		return null
	if _meshes.has(id):
		return _meshes[id]
	var g := geometry(id)
	var m := ArrayMesh.new()
	for layer in ["solid", "glow"]:
		var d: Dictionary = g[layer]
		if (d.verts as PackedVector3Array).is_empty():
			continue
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = d.verts
		arr[Mesh.ARRAY_NORMAL] = d.normals
		arr[Mesh.ARRAY_COLOR] = d.colors
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		m.surface_set_material(m.get_surface_count() - 1, Carved.material() if layer == "solid" else Emberlight.material("glow"))
	m.resource_name = "Held " + id
	_meshes[id] = m
	return m


## A MeshInstance3D of the item in item space (null for anything not in IDS).
static func node(id: String) -> MeshInstance3D:
	var m := mesh(id)
	if m == null:
		return null
	var mi := MeshInstance3D.new()
	mi.name = id
	mi.mesh = m
	return mi


## Put `id` in the right hand of `skeleton` (an AvatarSkeleton, e.g. Carved.skinned's), replacing
## whatever it held; "" (or "fists", or anything not in IDS) empties the hand. Returns the
## BoneAttachment3D, or null when the hand is empty. Calling it again with the same id keeps the
## node as it is, so the client can call it every frame.
static func attach(skeleton: Skeleton3D, id: String) -> BoneAttachment3D:
	var held := skeleton.get_node_or_null(NODE_NAME) as BoneAttachment3D
	if held != null and held.get_meta("item", "") == id and has(id):
		return held
	if held != null:
		skeleton.remove_child(held)
		held.queue_free()
	if not has(id):
		return null
	var ba := BoneAttachment3D.new()
	ba.name = NODE_NAME
	ba.bone_name = BONE
	ba.set_meta("item", id)
	skeleton.add_child(ba)
	var mi := node(id)
	mi.transform = GRIP
	ba.add_child(mi)
	return ba


## Which item `skeleton` holds now ("" for an empty hand).
static func held(skeleton: Skeleton3D) -> String:
	var ba := skeleton.get_node_or_null(NODE_NAME)
	return "" if ba == null else str(ba.get_meta("item", ""))
