extends TestCase
## World stream: avatars have arms and short legs the client's walk cycle can swing.
## Uses AvatarBuilder.parts()/rig(), which never touch the renderer, so it runs headless.

const L := AvatarBuilder.LIMBS


func test_rig_has_four_limb_pivots() -> void:
	var r := AvatarBuilder.rig()
	for limb in L:
		var p := r.get_node_or_null(limb)
		check(p != null and p.get_parent() == r, "%s is a direct child of the root" % limb)
		check(p is Node3D and not (p is MeshInstance3D), "%s is a bare pivot" % limb)
	check(r.get_node("ArmL").position.x > 0.0 and r.get_node("ArmR").position.x < 0.0, "left is +x when facing +z")
	check(r.get_node("ArmL").position.y > r.get_node("LegL").position.y + 0.4, "shoulders above hips")
	r.free()


func test_every_limb_has_meshes_hanging_below_its_pivot() -> void:
	var count := {}
	for p in AvatarBuilder.parts(42):
		if p.limb == "":
			continue
		check(p.limb in L, "known limb %s" % p.limb)
		count[p.limb] = count.get(p.limb, 0) + 1
		var top: float = p.pos.y + (p.mesh as Mesh).get_aabb().end.y
		check(top <= 0.1, "%s part stays below its pivot (top %.3f)" % [p.limb, top])
	for limb in L:
		check(count.get(limb, 0) >= 2, "%s has a limb and a hand or boot" % limb)


func test_feet_touch_the_ground() -> void:
	var lowest := INF
	for p in AvatarBuilder.parts(42):
		var base: Vector3 = Vector3.ZERO if p.limb == "" else AvatarBuilder.LIMB_PIVOTS[p.limb]
		lowest = minf(lowest, base.y + p.pos.y + (p.mesh as Mesh).get_aabb().position.y)
	check(absf(lowest) < 0.03, "lowest point %.3f is the ground" % lowest)


func test_limbs_do_not_change_existing_looks() -> void:
	# The appearance rng draws the same numbers as before limbs existed, so a saved
	# character keeps their skin tone and hat. Recompute the old draws by hand.
	for s in [1, 42, 1234, 20261127]:
		var rng := RandomNumberGenerator.new()
		rng.seed = s
		var skin := AvatarBuilder.skin_tone(rng.randf(), rng.randf(), rng.randf())
		var style := rng.randi() % 3
		var root_parts := AvatarBuilder.parts(s).filter(func(p): return p.limb == "")
		check_eq(root_parts[0].color, Palette.cloth_from_seed(s), "tunic for seed %d" % s)
		check_eq(root_parts[1].color, skin, "skin for seed %d" % s)
		# 14 body and gear parts, plus: a hood (style 0); hair and a cap (1); hair (2)
		check_eq(root_parts.size(), [15, 16, 15][style], "headwear and hair (and body and gear) for seed %d" % s)


func test_walk_cycle_swings_the_limbs() -> void:
	var r := AvatarBuilder.rig()
	var anim := WalkAnim.new()
	for i in 12:
		anim.step(Vector3(0, 0, GameConfig.WALK_SPEED * 0.1 * i), 0.1)
	anim.apply(r)
	var arm_l: float = r.get_node("ArmL").rotation.x
	check(absf(arm_l) > 0.05, "left arm swings")
	check_near(arm_l, -r.get_node("ArmR").rotation.x, 0.0001, "arms swing opposite")
	check_near(r.get_node("LegL").rotation.x, -arm_l * WalkAnim.LEG_SWING / WalkAnim.ARM_SWING, 0.0001, "left leg opposes left arm")
	r.free()


func test_lean_adult_proportions() -> void:
	# Art bible section 3, "Characters": about 7 heads tall, never chibi, never a barrel.
	var top := -INF
	var widest := 0.0
	for p in AvatarBuilder.parts(42):
		var base: Vector3 = Vector3.ZERO if p.limb == "" else AvatarBuilder.LIMB_PIVOTS[p.limb]
		var aabb: AABB = (p.mesh as Mesh).get_aabb()
		var scl: Vector3 = p.get("scl", Vector3.ONE)
		top = maxf(top, base.y + p.pos.y + aabb.end.y * scl.y)
		if p.limb == "" and p.pos.y > 0.8 and p.pos.y < 1.5 and absf(p.pos.z) < 0.05:
			widest = maxf(widest, aabb.size.x * scl.x)
	check(top > 1.7 and top < 1.9, "an adult's height (%.2f m)" % top)
	check_near(top / AvatarBuilder.HEAD_HEIGHT, 7.0, 0.5, "about 7 heads tall")
	check(widest < 0.52, "a lean body, not a barrel (%.2f m across the body)" % widest)
	check(AvatarBuilder.LIMB_PIVOTS.ArmL.x - AvatarBuilder.ARM_RADIUS > AvatarBuilder.PACK_WIDTH * 0.5, "the pack fits between the swinging arms")
	check(AvatarBuilder.LIMB_PIVOTS.ArmL.y - AvatarBuilder.ARM_LENGTH < AvatarBuilder.LIMB_PIVOTS.LegL.y - 0.1, "hands reach below the hips")


func test_each_limb_and_the_body_merge_into_one_mesh() -> void:
	# Five draw calls an avatar (art bible section 7): the body and each limb are one mesh.
	var groups := {}
	for p in AvatarBuilder.parts(42):
		groups[p.limb] = groups.get(p.limb, []) + [p]
	check_eq(groups.size(), 5, "the body and four limbs")
	for limb in groups:
		var want := 0
		for p in groups[limb]:
			want += ((p.mesh as Mesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
		var m := AvatarBuilder.merged(groups[limb])
		check_eq(m.get_surface_count(), 1, "%s is one surface" % limb)
		var arrays := m.surface_get_arrays(0)
		check_eq((arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size(), want, "%s keeps every part's vertices" % limb)
		check((arrays[Mesh.ARRAY_COLOR] as PackedColorArray).size() == want, "%s keeps its painted colours" % limb)


func test_bodies_are_smooth_lofts_not_boxes() -> void:
	# Art bible section 3, "Characters": rounded organic shapes, not boxes or bare cylinders.
	for p in AvatarBuilder.parts(42):
		check(not (p.mesh is BoxMesh) and not (p.mesh is CylinderMesh), "no boxes or cylinders on a traveller")
	# A loft is closed and its normals point outwards (the right winding, so back-face culling
	# shows the outside): every vertex normal on the side rings faces away from the axis.
	var m := AvatarBuilder.loft([[0.0, 0.1, 0.1, 0.0], [0.5, 0.12, 0.08, 0.0], [1.0, 0.1, 0.1, 0.0]], 8)
	var arrays := m.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var outward := 0
	for i in 24:
		if Vector2(verts[i].x, verts[i].z).dot(Vector2(normals[i].x, normals[i].z)) > 0.0:
			outward += 1
	check_eq(outward, 24, "every side vertex's normal points outwards")
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var a := verts[idx[0]]
	var b := verts[idx[1]]
	var c := verts[idx[2]]
	var face := (b - a).cross(c - a)
	check(face.dot(Vector3(a.x, 0, a.z)) < 0.0, "triangles wind clockwise seen from outside (Godot's front face)")
