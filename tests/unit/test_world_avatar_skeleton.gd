extends TestCase
## The traveller's skeleton: humanoid bone names, the art bible's proportions, and one skinned
## mesh with every vertex bound to the bone its segment rides.


func test_bones_are_humanoid_and_ordered() -> void:
	var seen := {}
	for b in AvatarSkeleton.bones():
		check(not seen.has(b.name), "bone %s appears once" % b.name)
		if b.parent != -1:
			check(seen.has(AvatarSkeleton.BONES[b.parent][0]), "%s comes after its parent" % b.name)
		seen[b.name] = true
	for want in ["Hips", "Spine", "Chest", "Neck", "Head", "LeftUpperArm", "LeftLowerArm", "LeftHand",
			"RightUpperArm", "RightLowerArm", "RightHand", "LeftUpperLeg", "LeftLowerLeg", "LeftFoot",
			"RightUpperLeg", "RightLowerLeg", "RightFoot"]:
		check(seen.has(want), "has %s" % want)
	check_eq(AvatarSkeleton.bones()[0].name, "Root", "Root first")


func test_proportions_match_the_traveller() -> void:
	# Art bible section 3: shoulders at 1.42 m, hip joints at 0.92 m, limbs 0.31/0.27/0.46/0.40.
	check_near(AvatarSkeleton.world_rest("LeftUpperArm").y, 1.42, 0.001, "shoulder height")
	check_near(AvatarSkeleton.world_rest("LeftUpperArm").x, 0.235, 0.001, "shoulder width")
	check_near(AvatarSkeleton.world_rest("LeftUpperLeg").y, AvatarSkeleton.HIP_HEIGHT, 0.001, "hip joint height")
	check_near(AvatarSkeleton.world_rest("LeftFoot").y, AvatarSkeleton.ANKLE_HEIGHT, 0.001, "ankle height")
	check_near(AvatarSkeleton.world_rest("LeftLowerArm").distance_to(AvatarSkeleton.world_rest("LeftUpperArm")), AvatarSkeleton.UPPER_ARM, 0.001, "upper arm")
	check_near(AvatarSkeleton.world_rest("LeftHand").distance_to(AvatarSkeleton.world_rest("LeftLowerArm")), AvatarSkeleton.FOREARM, 0.001, "forearm")
	check_near(AvatarSkeleton.world_rest("LeftLowerLeg").distance_to(AvatarSkeleton.world_rest("LeftUpperLeg")), AvatarSkeleton.THIGH, 0.001, "thigh")
	check_near(AvatarSkeleton.world_rest("LeftFoot").distance_to(AvatarSkeleton.world_rest("LeftLowerLeg")), AvatarSkeleton.SHIN, 0.001, "shin")
	check(AvatarSkeleton.world_rest("Head").y > 1.5 and AvatarSkeleton.world_rest("Head").y < 1.6, "head joint under the skull")
	# Left is +X, mirrored on the right.
	check_near(AvatarSkeleton.world_rest("RightHand").x, -AvatarSkeleton.world_rest("LeftHand").x, 0.0001, "mirrored")


func test_skeleton_node_matches_the_table() -> void:
	var sk := AvatarSkeleton.build()
	check_eq(sk.get_bone_count(), AvatarSkeleton.BONES.size(), "bone count")
	for b in AvatarSkeleton.bones():
		var i := sk.find_bone(b.name)
		check(i != -1, "skeleton has %s" % b.name)
		check(sk.get_bone_global_rest(i).origin.distance_to(b.world) < 0.0001, "%s rest position" % b.name)
	sk.free()


func test_skinned_mesh_binds_each_segment_to_its_bone() -> void:
	var groups := AvatarSkeleton.mannequin_groups()
	var mesh := AvatarSkeleton.skinned_mesh(groups)
	check_eq(mesh.get_surface_count(), 1, "one surface, one draw call")
	var a := mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var bones: PackedInt32Array = a[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = a[Mesh.ARRAY_WEIGHTS]
	var colors: PackedColorArray = a[Mesh.ARRAY_COLOR]
	check_eq(bones.size(), verts.size() * 4, "4 bone slots a vertex")
	check_eq(weights.size(), verts.size() * 4, "4 weights a vertex")
	check_eq(colors.size(), verts.size(), "painted")
	var expected := 0
	for bone in groups:
		for p in groups[bone]:
			expected += (p.mesh as Mesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size()
	check_eq(verts.size(), expected, "every vertex of every part")
	var ok := true
	for i in verts.size():
		if weights[i * 4] != 1.0 or bones[i * 4] < 0 or bones[i * 4] >= AvatarSkeleton.BONES.size():
			ok = false
	check(ok, "every vertex rigidly bound to a real bone")
	# The head's vertices ride the Head bone.
	var head := AvatarSkeleton.index_of("Head")
	var top := 0
	for i in verts.size():
		if verts[i].y > 1.7:
			top += 1
			check_eq(bones[i * 4], head, "the crown rides the head")
			if bones[i * 4] != head:
				break
	check(top > 0, "something above 1.7 m")


func test_skin_binds_every_bone() -> void:
	var s := AvatarSkeleton.skin()
	check_eq(s.get_bind_count(), AvatarSkeleton.BONES.size(), "a bind per bone")
	for i in s.get_bind_count():
		var w := AvatarSkeleton.world_rest(s.get_bind_name(i))
		check((s.get_bind_pose(i) * w).length() < 0.0001, "bind %s is its inverse rest" % s.get_bind_name(i))


func test_traveller_is_skinned_smoothly() -> void:
	for appearance_seed in [1, 7, 42, 12345]:
		var parts := AvatarBuilder.parts(appearance_seed)
		var mesh := AvatarSkeleton.skin_parts(parts, AvatarBuilder.LIMB_PIVOTS)
		check_eq(mesh.get_surface_count(), 1, "one draw call")
		var a := mesh.surface_get_arrays(0)
		var verts: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var bones: PackedInt32Array = a[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = a[Mesh.ARRAY_WEIGHTS]
		var bad := 0
		var blended := 0
		for i in verts.size():
			var sum := weights[i * 4] + weights[i * 4 + 1] + weights[i * 4 + 2] + weights[i * 4 + 3]
			if absf(sum - 1.0) > 0.001:
				bad += 1
			if weights[i * 4 + 1] > 0.0:
				blended += 1
		check_eq(bad, 0, "weights sum to 1 (seed %d)" % appearance_seed)
		check(blended > 50, "joints blend across bones (seed %d: %d vertices)" % [appearance_seed, blended])
		# Feet ride the feet, the crown rides the head, a hand rides its hand.
		for i in verts.size():
			var v := verts[i]
			var b := AvatarSkeleton.BONES[bones[i * 4]][0] as String
			if v.y < 0.02:
				check(b.ends_with("Foot"), "sole vertex on a foot, got %s" % b)
				if not b.ends_with("Foot"):
					break
			if v.y > 1.72:
				check_eq(b, "Head", "crown on the head")
				if b != "Head":
					break


func test_traveller_fits_the_triangle_budget() -> void:
	# Art bible section 3: at most 3,000 triangles a character (and now 1 draw call, not 5).
	# (A MeshInstance3D logs engine errors headless, so the node itself is checked by the client
	# smoke run; this checks the mesh it carries.)
	for appearance_seed in [1, 42]:
		var mesh := AvatarSkeleton.skin_parts(AvatarBuilder.parts(appearance_seed), AvatarBuilder.LIMB_PIVOTS)
		var tris := mesh.surface_get_array_index_len(0) / 3
		check(tris <= 3000, "inside the 3,000-triangle budget (%d)" % tris)


func test_vertex_bones_blend_at_the_elbow_and_knee() -> void:
	var elbow := AvatarSkeleton.vertex_bones("ArmL", Vector3(0, -AvatarSkeleton.UPPER_ARM, 0), Vector3.ZERO)
	check_eq(elbow.size(), 2, "two bones at the elbow")
	check_near(float(elbow[0][1]), 0.5, 0.01, "half and half")
	var shin := AvatarSkeleton.vertex_bones("LegR", Vector3(0, -0.65, 0), Vector3.ZERO)
	check_eq(shin, [["RightLowerLeg", 1.0]], "mid-shin is all shin")
	var belly := AvatarSkeleton.vertex_bones("", Vector3.ZERO, Vector3(0, 1.0, 0))
	check_eq(belly, [["Hips", 1.0]], "the belt line rides the hips")
