class_name AvatarBuilder
## Builds a little low-poly wanderer from an appearance seed: tunic colour, hood or hat,
## arms and short legs, and a name tag. Faces local +Z, feet at y = 0.
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
const LIMB_PIVOTS := {
	"ArmL": Vector3(0.4, 1.04, 0), "ArmR": Vector3(-0.4, 1.04, 0), # shoulders
	"LegL": Vector3(0.14, 0.4, 0), "LegR": Vector3(-0.14, 0.4, 0), # hips
}
const ARM_LENGTH := 0.5
const LEG_LENGTH := 0.4
const LEATHER := Color(0.45, 0.31, 0.19)
const BEDROLL := Color(0.70, 0.63, 0.50)
const PART_AO := 0.18 ## baked shade at the bottom of each part, so limbs and the tunic read as round
const PACK_BACK := 0.38 ## how far behind the body's centre the pack sits (the body is 0.32 round)


static func build(display_name: String, appearance_seed: int, is_self: bool) -> Node3D:
	var root := rig()
	for p in parts(appearance_seed):
		var parent: Node3D = root if p.limb == "" else root.get_node(p.limb)
		var mi := _part(p.mesh, p.color, p.pos)
		mi.rotation = p.get("rot", Vector3.ZERO)
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


## Every mesh of the avatar as {limb, mesh, color, pos, rot}: `limb` is "" for parts on the root,
## else the pivot it hangs from, and `pos` is relative to that parent. Deterministic.
static func parts(appearance_seed: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = appearance_seed
	var tunic := Palette.from_seed(appearance_seed)
	var skin := Color.from_hsv(0.07 + rng.randf() * 0.04, 0.35 + rng.randf() * 0.25, 0.55 + rng.randf() * 0.4)
	var out: Array = []

	# The tunic sits on the legs: from just above the knees (y 0.3) to the neck (1.26).
	out.append(_p("", _capsule(0.32, 0.96, 8, 2), tunic, Vector3(0, 0.78, 0)))

	var head := SphereMesh.new()
	head.radius = 0.24
	head.height = 0.48
	head.radial_segments = 8
	head.rings = 4
	out.append(_p("", head, skin, Vector3(0, 1.42, 0)))

	var eye := BoxMesh.new()
	eye.size = Vector3(0.06, 0.08, 0.04)
	out.append(_p("", eye, Color(0.1, 0.1, 0.12), Vector3(-0.09, 1.46, 0.21)))
	out.append(_p("", eye, Color(0.1, 0.1, 0.12), Vector3(0.09, 1.46, 0.21)))

	var style := rng.randi() % 3
	if style == 0: # pointed hat
		var hat := CylinderMesh.new()
		hat.top_radius = 0.0
		hat.bottom_radius = 0.32
		hat.height = 0.5
		hat.radial_segments = 8
		out.append(_p("", hat, tunic.darkened(0.35), Vector3(0, 1.82, 0)))
	elif style == 1: # flat cap
		var cap := CylinderMesh.new()
		cap.top_radius = 0.22
		cap.bottom_radius = 0.27
		cap.height = 0.12
		cap.radial_segments = 8
		out.append(_p("", cap, tunic.lightened(0.3), Vector3(0, 1.64, 0)))
	# style 2: bare-headed

	# Limbs take no rng draws, so every existing appearance seed keeps its hat and skin.
	var sleeve := tunic.darkened(0.12)
	var trousers := tunic.darkened(0.5).lerp(Color(0.32, 0.27, 0.22), 0.5)
	var boots := Color(0.2, 0.15, 0.12)
	var arm := _capsule(0.085, ARM_LENGTH, 6, 1)
	var hand := SphereMesh.new()
	hand.radius = 0.075
	hand.height = 0.15
	hand.radial_segments = 6
	hand.rings = 3
	var leg := _capsule(0.1, LEG_LENGTH, 6, 1)
	var boot := BoxMesh.new()
	boot.size = Vector3(0.17, 0.09, 0.24)
	for a in ["ArmL", "ArmR"]:
		out.append(_p(a, arm, sleeve, Vector3(0, -ARM_LENGTH * 0.5 + 0.06, 0)))
		out.append(_p(a, hand, skin, Vector3(0, -ARM_LENGTH + 0.04, 0)))
	for l in ["LegL", "LegR"]:
		out.append(_p(l, leg, trousers, Vector3(0, -LEG_LENGTH * 0.5 + 0.02, 0)))
		out.append(_p(l, boot, boots, Vector3(0, -LEG_LENGTH + 0.045, 0.03)))

	# What the action camera sees most: the back. A belt, a small travel pack and a rolled
	# blanket on top of it, so the wanderer reads as a traveller from over the shoulder.
	# Root parts, added last and with no rng draws, so older looks and part indices keep.
	var belt := CylinderMesh.new()
	belt.top_radius = 0.335
	belt.bottom_radius = 0.335
	belt.height = 0.07
	belt.radial_segments = 8
	belt.rings = 1
	out.append(_p("", belt, LEATHER.darkened(0.3), Vector3(0, 0.68, 0)))
	var pack := BoxMesh.new()
	pack.size = Vector3(0.34, 0.36, 0.16)
	out.append(_p("", pack, LEATHER, Vector3(0, 0.94, -PACK_BACK)))
	var roll := CylinderMesh.new()
	roll.top_radius = 0.075
	roll.bottom_radius = 0.075
	roll.height = 0.42
	roll.radial_segments = 7
	roll.rings = 1
	out.append(_p("", roll, BEDROLL, Vector3(0, 1.17, -PACK_BACK + 0.01), Vector3(0, 0, PI * 0.5)))
	return out


static func _p(limb: String, mesh: Mesh, color: Color, pos: Vector3, rot: Vector3 = Vector3.ZERO) -> Dictionary:
	return {"limb": limb, "mesh": mesh, "color": color, "pos": pos, "rot": rot}


static func _capsule(radius: float, height: float, segments: int, rings: int) -> CapsuleMesh:
	var m := CapsuleMesh.new()
	m.radius = radius
	m.height = height
	m.radial_segments = segments
	m.rings = rings
	return m


## One part on the world's shared Emberlight material (art bible section 2): the colour and a
## little baked shading live in the mesh's vertex colours, so every avatar in the world, however
## many there are, draws with the same single material as the trees and stones around it.
static func _part(mesh: Mesh, color: Color, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = Emberlight.paint(mesh, color, PART_AO)
	mi.material_override = material()
	mi.position = pos
	return mi


## The material every avatar part uses: the world's shared Emberlight "solid".
static func material() -> ShaderMaterial:
	return Emberlight.material("solid")
