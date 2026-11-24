class_name AvatarSkeleton
## The traveller's skeleton: one Skeleton3D every avatar shares the shape of, which the client's
## AvatarAnimator poses and the character's body-segment meshes are skinned to.
##
## Bone names follow Godot's humanoid profile (SkeletonProfileHumanoid), so a pose or clip
## written against one rig reads the same on any other. Proportions are the lean adult of art
## bible section 3: about 1.78 m tall, shoulders at 1.42 m, hip joints at 0.92 m, upper arm
## 0.31 m, forearm 0.27 m, thigh 0.46 m, shin 0.40 m, ankle 0.06 m above the sole.
##
## Conventions (the same as the avatar's meshes): the rig faces local +Z, left is +X, feet at
## y = 0. Every rest rotation is the identity, so a bone's pose rotation is its whole turn and
## clips can be written as plain Euler angles:
## - rotation.x on a bone that hangs down (arms, legs) swings it BACK when positive, forward
##   when negative (-PI/2 points an arm straight ahead);
## - rotation.x on a bone that points up (spine, chest, neck, head) tilts it FORWARD when positive;
## - rotation.z on the left arm raises it out to the side when positive (mirrored on the right:
##   see AvatarClips.side()).
## "Root" sits on the ground under the hips. Moving it moves the whole body (a jump's crouch,
## a fall to the ground); its yaw turns the body (facing the node you gather).
##
## Skinning: `skinned_mesh(groups)` merges every body segment into ONE mesh, each vertex bound
## rigidly (weight 1) to the bone its segment rides, with `skin()` holding the bind poses. One
## draw call per avatar (PR 171's per-limb merge needed five), and nothing about the colours
## or the shared Emberlight material changes. `bones()`, `world_rest()` and the static helpers
## are pure, for tests and bots.

## [name, parent ("" for the root), offset from the parent at rest]
const BONES := [
	["Root", "", Vector3(0, 0, 0)],
	["Hips", "Root", Vector3(0, 0.97, 0)],
	["Spine", "Hips", Vector3(0, 0.1, 0)],
	["Chest", "Spine", Vector3(0, 0.2, 0)],
	["Neck", "Chest", Vector3(0, 0.2, 0)],
	["Head", "Neck", Vector3(0, 0.08, 0)],
	["LeftUpperArm", "Chest", Vector3(0.235, 0.15, 0)],
	["LeftLowerArm", "LeftUpperArm", Vector3(0, -0.31, 0)],
	["LeftHand", "LeftLowerArm", Vector3(0, -0.27, 0)],
	["RightUpperArm", "Chest", Vector3(-0.235, 0.15, 0)],
	["RightLowerArm", "RightUpperArm", Vector3(0, -0.31, 0)],
	["RightHand", "RightLowerArm", Vector3(0, -0.27, 0)],
	["LeftUpperLeg", "Hips", Vector3(0.095, -0.05, 0)],
	["LeftLowerLeg", "LeftUpperLeg", Vector3(0, -0.46, 0)],
	["LeftFoot", "LeftLowerLeg", Vector3(0, -0.4, 0)],
	["RightUpperLeg", "Hips", Vector3(-0.095, -0.05, 0)],
	["RightLowerLeg", "RightUpperLeg", Vector3(0, -0.46, 0)],
	["RightFoot", "RightLowerLeg", Vector3(0, -0.4, 0)],
]

const HIP_HEIGHT := 0.92 ## the hip joints above the soles at rest
const THIGH := 0.46
const SHIN := 0.4
const ANKLE_HEIGHT := 0.06 ## the ankle joint above the sole
const UPPER_ARM := 0.31
const FOREARM := 0.27
const HIP_HALF_WIDTH := 0.095

## Bones whose motion an upper-body action (a swing, a chop) owns; the legs keep walking.
const UPPER := ["Spine", "Chest", "Neck", "Head", "LeftUpperArm", "LeftLowerArm", "LeftHand",
	"RightUpperArm", "RightLowerArm", "RightHand"]
const LEGS := ["LeftUpperLeg", "LeftLowerLeg", "LeftFoot", "RightUpperLeg", "RightLowerLeg", "RightFoot"]


static func names() -> Array:
	var out: Array = []
	for b in BONES:
		out.append(b[0])
	return out


static func index_of(bone: String) -> int:
	for i in BONES.size():
		if BONES[i][0] == bone:
			return i
	return -1


## Every bone as {name, parent (index, -1 for the root), offset, world}: `world` is the joint's
## position in the avatar's space at rest. Parents always come before their children.
static func bones() -> Array:
	var out: Array = []
	for b in BONES:
		var parent := index_of(b[1]) if b[1] != "" else -1
		var world: Vector3 = b[2] if parent == -1 else out[parent].world + b[2]
		out.append({"name": b[0], "parent": parent, "offset": b[2], "world": world})
	return out


## Where a bone's joint sits in the avatar's space at rest.
static func world_rest(bone: String) -> Vector3:
	var i := index_of(bone)
	return Vector3.ZERO if i == -1 else bones()[i].world


## A fresh Skeleton3D named "Skeleton" with every bone at rest.
static func build() -> Skeleton3D:
	var sk := Skeleton3D.new()
	sk.name = "Skeleton"
	for b in bones():
		var i := sk.get_bone_count()
		sk.add_bone(b.name)
		if b.parent != -1:
			sk.set_bone_parent(i, b.parent)
		sk.set_bone_rest(i, Transform3D(Basis(), b.offset))
	sk.reset_bone_poses()
	return sk


## The bind poses for `skinned_mesh`: each bone's inverse rest transform in the avatar's space.
static func skin() -> Skin:
	var s := Skin.new()
	for b in bones():
		s.add_named_bind(b.name, Transform3D(Basis(), -b.world))
	return s


## One skinned mesh from body segments. `groups` maps a bone name to the parts that ride it,
## each {mesh, color, pos, rot?, scl?} with `pos` in the avatar's space at rest (where the part
## sits when the rig stands still). Every vertex is painted for the shared Emberlight material
## (colour and a little baked shade, like every other prop) and bound to its bone with weight 1.
static func skinned_mesh(groups: Dictionary, ao: float = 0.14) -> ArrayMesh:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var bone_ids := PackedInt32Array()
	var weights := PackedFloat32Array()
	var indices := PackedInt32Array()
	for bone in groups:
		var bi := index_of(bone)
		assert(bi != -1, "unknown bone %s" % bone)
		for p in groups[bone]:
			var basis := Basis.from_euler(p.get("rot", Vector3.ZERO)) * Basis.from_scale(p.get("scl", Vector3.ONE))
			var xf := Transform3D(basis, p.pos)
			var painted := Emberlight.paint(p.mesh, p.color, ao)
			var a := painted.surface_get_arrays(0)
			var base := verts.size()
			var pv: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
			var pn: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
			var pc: PackedColorArray = a[Mesh.ARRAY_COLOR]
			var nb := basis.inverse().transposed()
			for i in pv.size():
				verts.append(xf * pv[i])
				normals.append((nb * pn[i]).normalized())
				colors.append(pc[i])
				bone_ids.append_array([bi, 0, 0, 0])
				weights.append_array([1.0, 0.0, 0.0, 0.0])
			var pi = a[Mesh.ARRAY_INDEX]
			if pi == null or (pi as PackedInt32Array).is_empty():
				for i in pv.size():
					indices.append(base + i)
			else:
				for i in (pi as PackedInt32Array):
					indices.append(base + i)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_BONES] = bone_ids
	arrays[Mesh.ARRAY_WEIGHTS] = weights
	arrays[Mesh.ARRAY_INDEX] = indices
	var out := ArrayMesh.new()
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return out


## A Skeleton3D with one skinned MeshInstance3D ("Mesh") under it, on the shared Emberlight
## "solid" material. The client hands the skeleton to AvatarAnimator.apply every frame.
static func rigged(groups: Dictionary) -> Skeleton3D:
	var sk := build()
	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	mi.mesh = skinned_mesh(groups)
	mi.skin = skin()
	mi.material_override = Emberlight.material("solid")
	sk.add_child(mi)
	mi.skeleton = NodePath("..")
	return sk


## A plain mannequin for previews and tests until the traveller's real segments (PR 171) are
## skinned: a capsule per long bone, a box chest and pelvis, a ball head, boxes for feet.
## Toned like undyed wool so poses read in a frame strip; never shown in the game.
static func mannequin_groups() -> Dictionary:
	var cloth := Palette.GRAZER_COAT.lerp(Palette.ROCK, 0.5) # undyed wool
	var skin_c := Palette.HAZE.darkened(0.15)
	var dark := Palette.TRUNK.darkened(0.3)
	var g := {}
	var hips := world_rest("Hips")
	var chest := world_rest("Chest")
	g["Hips"] = [_part(_box(Vector3(0.3, 0.2, 0.18)), dark, hips + Vector3(0, -0.02, 0))]
	g["Spine"] = [_part(_box(Vector3(0.28, 0.2, 0.17)), cloth.darkened(0.1), world_rest("Spine") + Vector3(0, 0.1, 0))]
	g["Chest"] = [_part(_box(Vector3(0.38, 0.24, 0.2)), cloth, chest + Vector3(0, 0.1, 0))]
	g["Neck"] = [_part(_capsule(0.045, 0.12), skin_c, world_rest("Neck") + Vector3(0, 0.04, 0))]
	g["Head"] = [_part(_sphere(0.11, 0.25), skin_c, world_rest("Head") + Vector3(0, 0.11, 0.005)),
		_part(_box(Vector3(0.03, 0.04, 0.05)), skin_c.darkened(0.1), world_rest("Head") + Vector3(0, 0.1, 0.11))] # a nose, so facing reads
	for s in ["Left", "Right"]:
		var ua := world_rest(s + "UpperArm")
		var la := world_rest(s + "LowerArm")
		var hd := world_rest(s + "Hand")
		g[s + "UpperArm"] = [_part(_capsule(0.055, UPPER_ARM + 0.06), cloth, ua + Vector3(0, -UPPER_ARM * 0.5, 0))]
		g[s + "LowerArm"] = [_part(_capsule(0.048, FOREARM + 0.04), cloth.darkened(0.15), la + Vector3(0, -FOREARM * 0.5, 0))]
		g[s + "Hand"] = [_part(_box(Vector3(0.07, 0.11, 0.05)), skin_c, hd + Vector3(0, -0.05, 0))]
		var th := world_rest(s + "UpperLeg")
		var sh := world_rest(s + "LowerLeg")
		var ft := world_rest(s + "Foot")
		g[s + "UpperLeg"] = [_part(_capsule(0.075, THIGH + 0.06), dark.lightened(0.15), th + Vector3(0, -THIGH * 0.5, 0))]
		g[s + "LowerLeg"] = [_part(_capsule(0.06, SHIN + 0.04), dark.lightened(0.1), sh + Vector3(0, -SHIN * 0.5, 0))]
		g[s + "Foot"] = [_part(_box(Vector3(0.1, 0.07, 0.24)), dark, ft + Vector3(0, -0.025, 0.05))]
	return g


static func _part(mesh: Mesh, color: Color, pos: Vector3) -> Dictionary:
	return {"mesh": mesh, "color": color, "pos": pos}


static func _box(size: Vector3) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = size
	return m


static func _capsule(radius: float, height: float) -> CapsuleMesh:
	var m := CapsuleMesh.new()
	m.radius = radius
	m.height = maxf(height, radius * 2.0)
	m.radial_segments = 8
	m.rings = 2
	return m


static func _sphere(radius: float, height: float) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = radius
	m.height = height
	m.radial_segments = 10
	m.rings = 5
	return m
