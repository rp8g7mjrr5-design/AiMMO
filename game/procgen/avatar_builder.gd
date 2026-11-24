class_name AvatarBuilder
## Builds a low-poly traveller from an appearance seed: a lean adult in dyed cloth and survival
## gear, with a hood or hair, arms and legs the walk cycle swings, and a name tag. Faces local +Z, feet at y = 0.
##
## Limbs are bare `Node3D` pivots named ArmL, ArmR, LegL, LegR, direct children of the root,
## with the pivot at the shoulder or hip and the meshes hanging below it, so the client's
## WalkAnim can swing them with rotation.x. The Label3D name tag is a direct child of the root.
## Left is +X (the avatar's own left when it faces +Z).
##
## `parts()` and `rig()` are the pure halves of `build()`: they never touch the renderer, so
## unit tests and bots can check the shape on a headless machine, where mesh instances and
## labels log engine errors.

const LIMBS := ["ArmL", "ArmR", "LegL", "LegR"]
## Lean adult proportions (art bible section 3, "Characters"): about 1.78 m and 7 heads tall,
## shoulders at 1.44 m, hips at 0.92 m, hands reaching mid-thigh.
const LIMB_PIVOTS := {
	"ArmL": Vector3(0.235, 1.42, 0), "ArmR": Vector3(-0.235, 1.42, 0), # shoulders
	"LegL": Vector3(0.095, 0.92, 0), "LegR": Vector3(-0.095, 0.92, 0), # hips
}
const UPPER_ARM := 0.31
const FOREARM := 0.27
const ARM_LENGTH := 0.63 ## shoulder to fingertips
const ARM_SPLAY := 0.09 ## radians the arms hang out from the body at rest
const ARM_RADIUS := 0.058 ## the sleeve at the shoulder, the widest part of the arm
const THIGH := 0.46
const SHIN := 0.4
const LEG_LENGTH := 0.92 ## hip to sole
const HEIGHT := 1.78 ## m, crown of the head
const HEAD_RADIUS := 0.11 ## m across; the head is about 0.25 m tall, a seventh of the body
const HEAD_HEIGHT := 0.25
const HEAD_Y := HEIGHT - HEAD_HEIGHT * 0.5 ## the head's centre
const CHEST_TOP := 1.47 ## the shoulder line, where the neck starts
const WAIST_Y := 1.02
const CHEST_DEPTH := 0.68 ## the chest is this much as deep as it is wide
const PART_AO := 0.14 ## baked shade at the bottom of each part, so limbs and the body read as round
const PACK_WIDTH := 0.27 ## narrow enough to stay inside the swinging arms
const PACK_BACK := 0.21 ## the pack's centre behind the body's centre (the chest is about 0.14 deep)
const LEATHER := Palette.LEATHER ## kept for callers that name it


static func build(display_name: String, appearance_seed: int, is_self: bool) -> Node3D:
	var root := rig()
	# One mesh for the body and one per limb (5 draw calls an avatar, not one per part): every
	# part's colour is in its vertices and they share one material, so merging costs nothing and
	# a crowd of travellers stays inside the render budget (art bible section 7).
	var groups := {}
	for p in parts(appearance_seed):
		if not groups.has(p.limb):
			groups[p.limb] = []
		groups[p.limb].append(p)
	for limb in groups:
		var parent: Node3D = root if limb == "" else root.get_node(limb)
		var mi := MeshInstance3D.new()
		mi.name = "Mesh"
		mi.mesh = merged(groups[limb])
		mi.material_override = material()
		parent.add_child(mi)

	var tag := Label3D.new()
	tag.text = display_name
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.position = Vector3(0, 2.2, 0)
	tag.font_size = 40
	tag.pixel_size = 0.006
	tag.outline_size = 8
	tag.modulate = Color(1.0, 0.95, 0.7) if is_self else Color.WHITE
	tag.no_depth_test = false
	root.add_child(tag)
	return root


## The root with its four empty limb pivots, and nothing else.
static func rig() -> Node3D:
	var root := Node3D.new()
	for limb in LIMBS:
		var n := Node3D.new()
		n.name = limb
		n.position = LIMB_PIVOTS[limb]
		root.add_child(n)
	return root


## Every mesh of the avatar as {limb, mesh, color, pos, rot, scl}: `limb` is "" for parts on the
## root, else the pivot it hangs from, and `pos` is relative to that parent. `scl` squashes a
## round primitive into a lean, flattened body part (a chest is wider than it is deep).
## Deterministic.
##
## The traveller (art bible section 3, "Characters"): a lean adult about 1.78 m and 7 heads
## tall, shoulders wider than hips, long legs, layered survival gear over dyed cloth. Read
## from the back first, because that is what the action camera sees all game: hood or hair,
## a wool mantle on the shoulders, a bedroll on a framed pack, a belt with a pouch and a knife.
static func parts(appearance_seed: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = appearance_seed
	var tunic := Palette.cloth_from_seed(appearance_seed) # earthy dyed cloth, never bright primaries
	var skin := skin_tone(rng.randf(), rng.randf(), rng.randf())
	var style := rng.randi() % 3 # hood, cap or bare-headed: the same draw as always
	var hair := hair_colour(appearance_seed)
	var wool := Palette.WOOL.lerp(tunic, 0.25) # the mantle and hood: undyed wool with a touch of the tunic's dye
	var trousers := Palette.TROUSERS
	var leather := Palette.LEATHER
	var dark_leather := Palette.LEATHER_DARK
	var out: Array = []

	# Torso: one smooth lofted body from the hips to the neck, shoulders wider than the waist,
	# a chest that is deeper than the belly, flatter front to back. Index 0 is the tunic and
	# index 1 the head, as they have always been. Each ring: [y, half width, half depth, z].
	out.append(_p("", loft([
		[0.84, 0.10, 0.07, 0.0], [0.88, 0.145, 0.10, 0.0], [0.96, 0.158, 0.105, 0.0],
		[WAIST_Y, 0.148, 0.098, 0.0], [1.12, 0.158, 0.108, 0.008], [1.24, 0.182, 0.122, 0.012],
		[1.33, 0.192, 0.118, 0.006], [1.40, 0.18, 0.105, 0.0], [1.445, 0.145, 0.088, 0.0],
		[CHEST_TOP, 0.085, 0.065, 0.0], [CHEST_TOP + 0.01, 0.055, 0.05, 0.0],
	]), tunic, Vector3.ZERO))
	# Head: an egg a little narrower than it is deep, with a jaw that tapers to the chin.
	out.append(_p("", loft([
		[-0.125, 0.012, 0.012, 0.02], [-0.118, 0.045, 0.05, 0.03], [-0.09, 0.075, 0.085, 0.015],
		[-0.04, 0.092, 0.105, 0.005], [0.02, 0.1, 0.112, 0.0], [0.07, 0.094, 0.104, -0.006],
		[0.105, 0.07, 0.08, -0.008], [0.125, 0.02, 0.025, -0.008],
	], 12), skin, Vector3(0, HEAD_Y, 0.0)))

	out.append(_p("", loft([[-0.07, 0.05, 0.048, 0.0], [0.0, 0.046, 0.044, 0.0], [0.07, 0.05, 0.05, 0.005]], 8), skin.darkened(0.06), Vector3(0, CHEST_TOP + 0.04, 0)))
	out.append(_p("", _ball(0.016, 6), skin.darkened(0.04), Vector3(0, HEAD_Y - 0.008, 0.108), Vector3(-0.3, 0, 0), Vector3(0.75, 1.4, 1.0))) # nose
	var socket := skin.darkened(0.5)
	for x in [-0.036, 0.036]:
		out.append(_p("", _ball(0.014, 6), socket, Vector3(x, HEAD_Y + 0.018, 0.097), Vector3.ZERO, Vector3(1.4, 0.75, 0.6)))

	# Head: a hood pulled up, or hair (and a felt cap on top of it).
	if style == 0:
		out.append(_p("", _ball(HEAD_RADIUS + 0.028, 12), wool.darkened(0.12), Vector3(0, HEAD_Y + 0.02, -0.06), Vector3(-0.15, 0, 0), Vector3(1.0, 1.15, 1.0))) # set back, so the face shows in its opening
	else:
		out.append(_p("", _ball(HEAD_RADIUS + 0.014, 12), hair, Vector3(0, HEAD_Y + 0.05, -0.05), Vector3(-0.35, 0, 0), Vector3(1.0, 0.9, 0.98))) # back and crown of the head: the face stays clear
		if style == 1:
			out.append(_p("", loft([[0.0, 0.112, 0.124, 0.0], [0.035, 0.105, 0.115, 0.0], [0.06, 0.07, 0.08, 0.0], [0.07, 0.01, 0.01, 0.0]], 12), tunic.darkened(0.3), Vector3(0, HEAD_Y + 0.045, -0.012), Vector3(-0.12, 0, 0)))

	# The tunic's skirt to mid-thigh, flaring a little, belted at the waist.
	out.append(_p("", loft([[0.0, 0.162, 0.112, 0.0], [-0.12, 0.175, 0.122, 0.0], [-0.24, 0.19, 0.13, 0.0], [-0.25, 0.17, 0.11, 0.0]]), tunic.darkened(0.08), Vector3(0, WAIST_Y + 0.0, 0)))
	out.append(_p("", loft([[-0.028, 0.158, 0.108, 0.0], [0.028, 0.158, 0.108, 0.0]]), dark_leather, Vector3(0, WAIST_Y, 0)))
	# Gear on the belt: a pouch on the left hip, a knife on the right.
	out.append(_p("", _ball(0.05, 8), leather, Vector3(0.13, WAIST_Y - 0.07, 0.085), Vector3(0, 0.5, 0), Vector3(0.95, 1.05, 0.65)))
	out.append(_p("", loft([[-0.1, 0.008, 0.012, 0.0], [-0.08, 0.02, 0.026, 0.0], [0.1, 0.02, 0.026, 0.0]], 6), dark_leather, Vector3(-0.165, WAIST_Y - 0.11, 0.02), Vector3(0, 0, 0.18)))

	# A strap across the chest to the pack, and a wool mantle over the shoulders: the layers
	# that make a traveller read as someone who sleeps outdoors.
	out.append(_p("", loft([[-0.26, 0.022, 0.008, 0.0], [0.26, 0.022, 0.008, 0.0]], 6), dark_leather, Vector3(0.0, 1.24, 0.128), Vector3(0, 0, 0.62)))
	out.append(_p("", loft([[-0.13, 0.215, 0.135, -0.005], [-0.09, 0.21, 0.132, 0.0], [-0.03, 0.185, 0.12, 0.0], [0.0, 0.14, 0.1, 0.0], [0.025, 0.075, 0.07, 0.0], [0.03, 0.055, 0.055, 0.0]]), wool, Vector3(0, CHEST_TOP - 0.015, 0)))

	# Back: a soft canvas pack and the bedroll strapped on top of it, inside the arms' swing.
	out.append(_p("", loft([[-0.19, 0.08, 0.04, 0.0], [-0.17, 0.125, 0.065, 0.0], [0.12, 0.13, 0.07, 0.0], [0.19, 0.1, 0.05, 0.0], [0.2, 0.03, 0.02, 0.0]], 10), leather, Vector3(0, 1.17, -PACK_BACK)))
	out.append(_p("", loft([[-PACK_WIDTH * 0.5 - 0.01, 0.045, 0.045, 0.0], [-PACK_WIDTH * 0.5, 0.06, 0.06, 0.0], [PACK_WIDTH * 0.5, 0.06, 0.06, 0.0], [PACK_WIDTH * 0.5 + 0.01, 0.045, 0.045, 0.0]], 8), Palette.BEDROLL, Vector3(0, 1.4, -PACK_BACK - 0.01), Vector3(0, 0, PI * 0.5)))

	# Arms: a rounded shoulder, a sleeve that narrows to the elbow, a leather bracer on the
	# forearm, and a hand. Hanging to mid-thigh. Upper arm and forearm are separate pieces, so
	# a skeleton can bend them at the elbow later.
	for a in ["ArmL", "ArmR"]:
		var side := 1.0 if a == "ArmL" else -1.0
		out.append(_p(a, loft([[-UPPER_ARM, 0.046, 0.05, 0.0], [-0.2, 0.054, 0.057, 0.0], [-0.06, 0.062, 0.064, 0.0], [0.0, 0.06, 0.062, 0.0], [0.04, 0.03, 0.03, 0.0]], 8), tunic.darkened(0.1), Vector3(side * 0.004, 0, 0)))
		out.append(_p(a, loft([[-ARM_LENGTH + 0.08, 0.034, 0.036, 0.01], [-UPPER_ARM - 0.1, 0.046, 0.048, 0.008], [-UPPER_ARM + 0.01, 0.048, 0.05, 0.0]], 8), leather.darkened(0.1), Vector3.ZERO))
		out.append(_p(a, _ball(0.046, 8), skin, Vector3(0, -ARM_LENGTH + 0.05, 0.012), Vector3.ZERO, Vector3(0.75, 1.25, 1.0)))
	# Arms hang a little away from the body, not glued to its sides like a mannequin's: each
	# arm part turns about its shoulder pivot (the walk cycle still swings the pivot).
	for p in out:
		if p.limb == "ArmL" or p.limb == "ArmR":
			var tilt := Basis(Vector3.BACK, ARM_SPLAY * (1.0 if p.limb == "ArmL" else -1.0))
			p.pos = tilt * (p.pos as Vector3)
			p.rot = (tilt * Basis.from_euler(p.rot)).get_euler()
	# Legs: a thigh that tapers to the knee, a calf that swells and narrows to the ankle, a
	# tall boot with a rounded toe. Thigh and shin are separate pieces (a knee, later).
	for l in ["LegL", "LegR"]:
		out.append(_p(l, loft([[-THIGH - 0.02, 0.058, 0.064, 0.0], [-THIGH * 0.6, 0.072, 0.08, 0.0], [-0.06, 0.085, 0.092, 0.0], [0.02, 0.08, 0.085, 0.0]], 8), trousers, Vector3.ZERO))
		out.append(_p(l, loft([[-LEG_LENGTH + 0.24, 0.054, 0.06, 0.0], [-THIGH - 0.12, 0.062, 0.07, -0.006], [-THIGH + 0.01, 0.058, 0.064, 0.0]], 8), trousers.darkened(0.08), Vector3.ZERO))
		out.append(_p(l, loft([[-LEG_LENGTH + 0.03, 0.058, 0.07, 0.0], [-LEG_LENGTH + 0.12, 0.06, 0.066, 0.0], [-LEG_LENGTH + 0.27, 0.07, 0.074, 0.0], [-LEG_LENGTH + 0.28, 0.062, 0.066, 0.0]], 8), dark_leather, Vector3.ZERO))
		out.append(_p(l, _ball(0.06, 8), dark_leather.darkened(0.15), Vector3(0, -LEG_LENGTH + 0.038, 0.05), Vector3.ZERO, Vector3(0.85, 0.65, 2.0)))
	return out


## A smooth tube through `rings` (each [y, half width, half depth, z offset], bottom to top),
## closed at both ends, with smooth normals: the organic low-poly body parts (art bible
## section 3, "Characters"). `segments` around. Rings far narrower than their neighbours make
## rounded ends. Pure maths, safe headless.
static func loft(rings: Array, segments: int = 10) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := rings.size()
	for r in rings:
		for k in segments:
			var a := TAU * k / segments
			st.add_vertex(Vector3(sin(a) * float(r[1]), float(r[0]), float(r[3]) + cos(a) * float(r[2])))
	var bottom := n * segments
	var b0: Array = rings[0]
	st.add_vertex(Vector3(0, float(b0[0]), float(b0[3])))
	var t0: Array = rings[n - 1]
	st.add_vertex(Vector3(0, float(t0[0]), float(t0[3])))
	for i in n - 1:
		for k in segments:
			var a := i * segments + k
			var b := i * segments + (k + 1) % segments
			var c := a + segments
			var d := b + segments
			st.add_index(a); st.add_index(c); st.add_index(b)
			st.add_index(b); st.add_index(c); st.add_index(d)
	for k in segments:
		st.add_index(bottom); st.add_index(k); st.add_index((k + 1) % segments)
		var top := (n - 1) * segments
		st.add_index(bottom + 1); st.add_index(top + (k + 1) % segments); st.add_index(top + k)
	st.generate_normals()
	return st.commit()


## A smooth ball (hands, feet, pouches, hair), squashed by the part's `scl`.
static func _ball(radius: float, segments: int) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = radius
	m.height = radius * 2.0
	m.radial_segments = segments
	m.rings = maxi(segments / 2, 3)
	return m


static func _cyl(top: float, bottom: float, height: float, segments: int) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = top
	m.bottom_radius = bottom
	m.height = height
	m.radial_segments = segments
	m.rings = 1
	return m


## Skin from three 0..1 draws: the same draws as always (saved looks keep their place in the
## range), but a grounded range: no orange, no glow, from deep brown to fair.
static func skin_tone(a: float, b: float, c: float) -> Color:
	return Palette.skin(a, b, c)


## Natural hair for a seed, from its own hash (no rng draw): black, browns, auburn, ash blond, grey.
static func hair_colour(appearance_seed: int) -> Color:
	return Palette.HAIR[posmod(hash(appearance_seed), Palette.HAIR.size())]


static func _p(limb: String, mesh: Mesh, color: Color, pos: Vector3, rot: Vector3 = Vector3.ZERO, scl: Vector3 = Vector3.ONE) -> Dictionary:
	return {"limb": limb, "mesh": mesh, "color": color, "pos": pos, "rot": rot, "scl": scl}


## Every part is painted (colour and a little baked shading in its vertex colours) and merged,
## so every avatar in the world, however many there are, draws with the same single material
## as the trees and stones around it (art bible section 2).
## The parts of one group (same parent) as one painted mesh, each placed by its pos, rot and scl
## the way a child node with that transform would be.
static func merged(group: Array) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for p in group:
		var basis := Basis.from_euler(p.get("rot", Vector3.ZERO)) * Basis.from_scale(p.get("scl", Vector3.ONE))
		st.append_from(Emberlight.paint(p.mesh, p.color, PART_AO), 0, Transform3D(basis, p.pos))
	return st.commit()


## The material every avatar part uses: the world's shared Emberlight "solid".
static func material() -> ShaderMaterial:
	return Emberlight.material("solid")
