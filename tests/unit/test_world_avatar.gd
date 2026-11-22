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
		var skin := Color.from_hsv(0.07 + rng.randf() * 0.04, 0.35 + rng.randf() * 0.25, 0.55 + rng.randf() * 0.4)
		var style := rng.randi() % 3
		var root_parts := AvatarBuilder.parts(s).filter(func(p): return p.limb == "")
		check_eq(root_parts[0].color, Palette.from_seed(s), "tunic for seed %d" % s)
		check_eq(root_parts[1].color, skin, "skin for seed %d" % s)
		check_eq(root_parts.size(), 4 if style == 2 else 5, "headwear for seed %d" % s)


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
