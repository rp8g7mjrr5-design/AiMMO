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
	["LeftLowerArm", "LeftUpperArm", Vector3(0.0279, -0.3087, 0)], # the arm hangs ARM_SPLAY out from the body
	["LeftHand", "LeftLowerArm", Vector3(0.0243, -0.2689, 0)],
	["RightUpperArm", "Chest", Vector3(-0.235, 0.15, 0)],
	["RightLowerArm", "RightUpperArm", Vector3(-0.0279, -0.3087, 0)],
	["RightHand", "RightLowerArm", Vector3(-0.0243, -0.2689, 0)],
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
const ARM_SPLAY := 0.09 ## radians the arms hang out from the body at rest (AvatarBuilder.ARM_SPLAY)

## Skinning the traveller's parts (AvatarBuilder.parts): every vertex is weighted along its
## chain by where it sits at rest, blending across a joint over 2 * BLEND m so an elbow or a
## knee bends as one smooth sleeve, not two boxes. Torso heights are in the avatar's space,
## limb distances run down the limb from its pivot.
const BLEND := 0.035
const TORSO_CHAIN := [["Hips", 1.07], ["Spine", 1.27], ["Chest", 1.48], ["Neck", 1.56], ["Head", INF]]
const HEAD_FROM := 1.57 ## a part centred above this (head, face, hood, hair, cap) rides the head whole
const BACK_FROM := -0.15 ## a part centred further back than this (pack, bedroll) rides the chest whole

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
	return _commit(verts, normals, colors, bone_ids, weights, indices)


## The bones and weights for one vertex of a traveller part: [[bone, weight], ...] (one or
## two entries summing to 1). `limb` is the part's AvatarBuilder limb ("" for the body,
## "ArmL", "LegR", ...), `local` the vertex in that limb's pivot space, `world` in the
## avatar's. Pure.
static func vertex_bones(limb: String, local: Vector3, world: Vector3) -> Array:
	if limb == "":
		return _chain_weights(TORSO_CHAIN, world.y)
	var s := "Left" if limb.ends_with("L") else "Right"
	var down := -local.y # metres down the limb from its pivot
	if limb.begins_with("Arm"):
		return _chain_weights([[s + "UpperArm", UPPER_ARM], [s + "LowerArm", UPPER_ARM + FOREARM], [s + "Hand", INF]], -down, true)
	return _chain_weights([[s + "UpperLeg", THIGH], [s + "LowerLeg", THIGH + SHIN], [s + "Foot", INF]], -down, true)


## Weights along a chain of [bone, ends_at] by `v`: going UP the chain (torso, by height) or,
## with `descending`, down it (limbs, where v is minus the distance from the pivot).
static func _chain_weights(chain: Array, v: float, descending: bool = false) -> Array:
	var x := -v if descending else v
	for i in chain.size():
		var end: float = chain[i][1]
		if x < end - BLEND or i == chain.size() - 1:
			return [[chain[i][0], 1.0]]
		if x < end + BLEND:
			var k := smoothstep(end - BLEND, end + BLEND, x)
			return [[chain[i][0], 1.0 - k], [chain[i + 1][0], k]]
	return [[chain[chain.size() - 1][0], 1.0]]


## One skinned mesh for the traveller from AvatarBuilder.parts(): each part placed where
## AvatarBuilder puts it (its limb's pivot + pos, rotated and scaled), every vertex painted
## and weighted by `vertex_bones`, except that head gear and the pack ride one bone whole.
static func skin_parts(parts: Array, pivots: Dictionary, ao: float = 0.14) -> ArrayMesh:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var bone_ids := PackedInt32Array()
	var weights := PackedFloat32Array()
	var indices := PackedInt32Array()
	for p in parts:
		var limb: String = p.limb
		var pivot: Vector3 = Vector3.ZERO if limb == "" else pivots[limb]
		var basis := Basis.from_euler(p.get("rot", Vector3.ZERO)) * Basis.from_scale(p.get("scl", Vector3.ONE))
		var local_xf := Transform3D(basis, p.pos)
		var painted := Emberlight.paint(p.mesh, p.color, ao)
		var a := painted.surface_get_arrays(0)
		var pv: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var pn: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
		var pc: PackedColorArray = a[Mesh.ARRAY_COLOR]
		var nb := basis.inverse().transposed()
		var whole := ""
		if limb == "":
			var centre: Vector3 = local_xf * painted.get_aabb().get_center()
			if centre.y > HEAD_FROM:
				whole = "Head"
			elif centre.z < BACK_FROM:
				whole = "Chest"
		var base := verts.size()
		for i in pv.size():
			var local := local_xf * pv[i]
			var world := pivot + local
			verts.append(world)
			normals.append((nb * pn[i]).normalized())
			colors.append(pc[i])
			var bw: Array = [[whole, 1.0]] if whole != "" else vertex_bones(limb, local, world)
			for j in 4:
				if j < bw.size():
					bone_ids.append(index_of(bw[j][0]))
					weights.append(float(bw[j][1]))
				else:
					bone_ids.append(0)
					weights.append(0.0)
		var pi = a[Mesh.ARRAY_INDEX]
		if pi == null or (pi as PackedInt32Array).is_empty():
			for i in pv.size():
				indices.append(base + i)
		else:
			for i in (pi as PackedInt32Array):
				indices.append(base + i)
	return _commit(verts, normals, colors, bone_ids, weights, indices)


static func _commit(verts: PackedVector3Array, normals: PackedVector3Array, colors: PackedColorArray,
		bone_ids: PackedInt32Array, weights: PackedFloat32Array, indices: PackedInt32Array) -> ArrayMesh:
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


## A Skeleton3D with `mesh` (skinned to it) as its one MeshInstance3D child "Mesh", on the
## shared Emberlight "solid" material.
static func rig_mesh(mesh: ArrayMesh) -> Skeleton3D:
	var sk := build()
	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	mi.mesh = mesh
	mi.skin = skin()
	mi.material_override = Emberlight.material("solid")
	sk.add_child(mi)
	mi.skeleton = NodePath("..")
	return sk


## A Skeleton3D with one skinned MeshInstance3D ("Mesh") under it, on the shared Emberlight
## "solid" material. The client hands the skeleton to AvatarAnimator.apply every frame.
static func rigged(groups: Dictionary) -> Skeleton3D:
	return rig_mesh(skinned_mesh(groups))


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
