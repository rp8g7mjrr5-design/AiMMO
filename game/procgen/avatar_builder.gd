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

	# Torso: a tapered chest, wider than deep, from the waist (1.02) to the shoulders (1.46).
	# Index 0 is the tunic and index 1 the head, as they have always been.
	out.append(_p("", _cyl(0.205, 0.155, CHEST_TOP - WAIST_Y, 8), tunic, Vector3(0, (CHEST_TOP + WAIST_Y) * 0.5, 0), Vector3.ZERO, Vector3(1.0, 1.0, CHEST_DEPTH)))
	var head := SphereMesh.new()
	head.radius = HEAD_RADIUS
	head.height = HEAD_HEIGHT
	head.radial_segments = 8
	head.rings = 5
	out.append(_p("", head, skin, Vector3(0, HEAD_Y, 0.005), Vector3.ZERO, Vector3(0.92, 1.0, 1.0)))

	# Neck, jaw-line and a nose: enough for a face to read as a face at 3 m, no more.
	out.append(_p("", _cyl(0.048, 0.055, 0.12, 6), skin.darkened(0.06), Vector3(0, CHEST_TOP + 0.04, 0)))
	var nose := BoxMesh.new()
	nose.size = Vector3(0.022, 0.045, 0.03)
	out.append(_p("", nose, skin.darkened(0.04), Vector3(0, HEAD_Y - 0.01, HEAD_RADIUS * 0.95), Vector3(-0.25, 0, 0)))
	var eye := BoxMesh.new()
	eye.size = Vector3(0.028, 0.014, 0.02)
	var socket := skin.darkened(0.55)
	out.append(_p("", eye, socket, Vector3(-0.038, HEAD_Y + 0.018, HEAD_RADIUS * 0.86)))
	out.append(_p("", eye, socket, Vector3(0.038, HEAD_Y + 0.018, HEAD_RADIUS * 0.86)))

	# Head: a hood pulled up, or hair (and a felt cap on top of it).
	if style == 0:
		var hood := SphereMesh.new()
		hood.radius = HEAD_RADIUS + 0.028
		hood.height = HEAD_HEIGHT + 0.06
		hood.radial_segments = 8
		hood.rings = 5
		out.append(_p("", hood, wool.darkened(0.12), Vector3(0, HEAD_Y + 0.025, -0.06), Vector3(-0.15, 0, 0), Vector3(1.0, 1.0, 1.0))) # set back, so the face shows in its opening
	else:
		var cut := SphereMesh.new()
		cut.radius = HEAD_RADIUS + 0.012
		cut.height = HEAD_HEIGHT * 0.86
		cut.radial_segments = 8
		cut.rings = 4
		out.append(_p("", cut, hair, Vector3(0, HEAD_Y + 0.03, -0.02), Vector3.ZERO, Vector3(0.95, 1.0, 1.0)))
		if style == 1:
			out.append(_p("", _cyl(HEAD_RADIUS * 0.8, HEAD_RADIUS + 0.018, 0.07, 8), tunic.darkened(0.3), Vector3(0, HEAD_Y + HEAD_HEIGHT * 0.36, -0.01), Vector3(-0.12, 0, 0)))

	# Hips and the tunic's skirt to mid-thigh, belted at the waist.
	out.append(_p("", _cyl(0.16, 0.175, 0.26, 8), tunic.darkened(0.08), Vector3(0, WAIST_Y - 0.12, 0), Vector3.ZERO, Vector3(1.0, 1.0, 0.8)))
	out.append(_p("", _cyl(0.163, 0.163, 0.055, 8), dark_leather, Vector3(0, WAIST_Y, 0), Vector3.ZERO, Vector3(1.0, 1.0, CHEST_DEPTH + 0.04)))
	# Gear on the belt: a pouch on the left hip, a knife on the right.
	var pouch := BoxMesh.new()
	pouch.size = Vector3(0.09, 0.1, 0.06)
	out.append(_p("", pouch, leather, Vector3(0.13, WAIST_Y - 0.07, 0.08), Vector3(0, 0.5, 0)))
	var sheath := BoxMesh.new()
	sheath.size = Vector3(0.035, 0.2, 0.05)
	out.append(_p("", sheath, dark_leather, Vector3(-0.155, WAIST_Y - 0.11, 0.02), Vector3(0, 0, 0.18)))

	# A strap across the chest to the pack, and a wool mantle over the shoulders: the layers
	# that make a traveller read as someone who sleeps outdoors.
	var strap := BoxMesh.new()
	strap.size = Vector3(0.05, 0.5, 0.02)
	out.append(_p("", strap, dark_leather, Vector3(0.0, 1.25, 0.135), Vector3(0, 0, 0.62)))
	out.append(_p("", _cyl(0.1, 0.25, 0.17, 8), wool, Vector3(0, CHEST_TOP - 0.035, -0.005), Vector3.ZERO, Vector3(1.0, 1.0, 0.72)))

	# Back: a framed pack and the bedroll strapped on top of it, inside the arms' swing.
	var pack := BoxMesh.new()
	pack.size = Vector3(PACK_WIDTH, 0.38, 0.14)
	out.append(_p("", pack, leather, Vector3(0, 1.17, -PACK_BACK)))
	var roll := CylinderMesh.new()
	roll.top_radius = 0.06
	roll.bottom_radius = 0.06
	roll.height = PACK_WIDTH + 0.02
	roll.radial_segments = 7
	roll.rings = 1
	out.append(_p("", roll, Palette.BEDROLL, Vector3(0, 1.4, -PACK_BACK - 0.01), Vector3(0, 0, PI * 0.5)))

	# Arms: a sleeve, a leather bracer over the forearm, a hand. Hanging to mid-thigh.
	for a in ["ArmL", "ArmR"]:
		out.append(_p(a, _cyl(0.058, 0.048, UPPER_ARM, 6), tunic.darkened(0.1), Vector3(0, -UPPER_ARM * 0.5 + 0.02, 0)))
		out.append(_p(a, _cyl(0.05, 0.042, FOREARM, 6), leather.darkened(0.1), Vector3(0, -UPPER_ARM - FOREARM * 0.5 + 0.02, 0.01)))
		var hand := SphereMesh.new()
		hand.radius = 0.045
		hand.height = 0.11
		hand.radial_segments = 6
		hand.rings = 3
		out.append(_p(a, hand, skin, Vector3(0, -ARM_LENGTH + 0.04, 0.01)))
	# Legs: trousers, a tall boot with a turned-down cuff, and a foot that points forward.
	for l in ["LegL", "LegR"]:
		out.append(_p(l, _cyl(0.085, 0.064, THIGH, 6), trousers, Vector3(0, -THIGH * 0.5 + 0.02, 0)))
		out.append(_p(l, _cyl(0.062, 0.054, SHIN, 6), trousers.darkened(0.08), Vector3(0, -THIGH - SHIN * 0.5 + 0.02, 0)))
		out.append(_p(l, _cyl(0.07, 0.064, 0.24, 6), dark_leather, Vector3(0, -LEG_LENGTH + 0.16, 0)))
		var foot := BoxMesh.new()
		foot.size = Vector3(0.1, 0.075, 0.25)
		out.append(_p(l, foot, dark_leather.darkened(0.15), Vector3(0, -LEG_LENGTH + 0.0375, 0.045)))
	return out


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
