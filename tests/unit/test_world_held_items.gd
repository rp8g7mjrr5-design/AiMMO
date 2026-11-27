extends TestCase
## World stream: the tools and weapons you hold (HeldItems), sized to the carved hand.


func _span(id: String) -> Array:
	var lo := Vector3.ONE * INF
	var hi := -Vector3.ONE * INF
	var g := HeldItems.geometry(id)
	for layer in ["solid", "glow"]:
		for v in g[layer].verts:
			lo = lo.min(v)
			hi = hi.max(v)
	return [lo, hi]


func test_every_tool_weapon_and_the_torch_has_a_shape() -> void:
	for id in Crafting.RECIPE_ORDER:
		var r: Dictionary = Crafting.RECIPES[id]
		if r.get("tool", false) or Weapons.exists(id) or id == "torch":
			check(HeldItems.has(id), "%s can be held" % id)
	for id in Weapons.ORDER:
		check(HeldItems.has(id), "weapon %s can be held" % id)
	for id in HeldItems.IDS:
		var tris := HeldItems.triangles(id)
		check(tris >= 40 and tris <= HeldItems.MAX_TRIS, "%s: %d triangles, cheap and not a stick" % [id, tris])
	check(HeldItems.parts("fists").is_empty() and HeldItems.mesh("fists") == null, "bare hands hold nothing")


func test_real_sizes_in_hand() -> void:
	# About 1.2x real size (art bible section 3), measured along the haft (item +Y).
	var lengths := {"wooden_axe": [0.55, 0.75], "stone_axe": [0.55, 0.75], "wooden_pickaxe": [0.65, 0.85],
		"stone_pickaxe": [0.65, 0.85], "wooden_club": [0.65, 0.85], "stone_maul": [0.7, 0.9],
		"wooden_spear": [1.8, 2.1], "stone_spear": [1.8, 2.1], "torch": [0.6, 0.9]}
	for id in lengths:
		var s := _span(id)
		var length: float = s[1].y - s[0].y
		check(length > lengths[id][0] and length < lengths[id][1], "%s is %.2f m long" % [id, length])
		check(s[0].y < -0.05, "%s: the hand holds the haft, not the end (butt at %.2f)" % [id, s[0].y])
	# Heads sit on the striking side (+Z), so a chop lands edge first.
	for id in ["wooden_axe", "stone_axe", "wooden_pickaxe", "stone_pickaxe", "stone_maul"]:
		var s := _span(id)
		check(s[1].z > -s[0].z, "%s: the edge or long prong faces the swing" % id)
	# Thin enough for the carved fist (the palm is 0.072 m across).
	var hand := HeldItems.geometry("wooden_axe").solid.verts as PackedVector3Array
	var widest := 0.0
	for v in hand:
		if v.y > -0.095 and v.y < -0.08: # the haft's ring just below the fist
			widest = maxf(widest, Vector2(v.x, v.z).length())
	check(widest > 0.015 and widest < 0.04, "the grip fits a hand (radius %.3f)" % widest)


func test_flat_carved_and_grounded_colours() -> void:
	for id in HeldItems.IDS:
		var g := HeldItems.geometry(id)
		var cols: PackedColorArray = g.solid.colors
		var normals: PackedVector3Array = g.solid.normals
		var bad := 0
		for i in range(0, normals.size(), 3):
			if not (normals[i].is_equal_approx(normals[i + 1]) and normals[i].is_equal_approx(normals[i + 2])):
				bad += 1
		check_eq(bad, 0, "%s: flat facets" % id)
		for c in cols:
			var s := c.linear_to_srgb()
			if s.s > 0.6 or c.a < 1.0:
				check(false, "%s: a solid part is muted and never glows (%s)" % [id, s])
				break
	# Only fire glows (design bible direction 11): the torch's flame and nothing else.
	for id in HeldItems.IDS:
		var glow: PackedVector3Array = HeldItems.geometry(id).glow.verts
		check((glow.size() > 0) == (id == "torch"), "%s: glows only if it is the torch" % id)


func test_mesh_materials() -> void:
	var m := HeldItems.mesh("stone_axe")
	check_eq(m.get_surface_count(), 1, "one draw call")
	check(m.surface_get_material(0) == Carved.material(), "the carved material, no grain")
	check(HeldItems.mesh("stone_axe") == m, "cached")
	var t := HeldItems.mesh("torch")
	check_eq(t.get_surface_count(), 2, "the torch adds its flame")
	check(t.surface_get_material(1) == Emberlight.material("glow"), "the flame glows")


func test_attach_to_the_right_hand() -> void:
	# The headless dummy renderer logs this for any MeshInstance3D it is handed.
	expect_error("Parameter \"m\" is null")
	var sk := Carved.skinned(77)
	var ba := HeldItems.attach(sk, "stone_spear")
	check(ba != null and ba.bone_name == "RightHand", "rides the right hand")
	check_eq(HeldItems.held(sk), "stone_spear")
	check(HeldItems.attach(sk, "stone_spear") == ba, "the same item keeps its node (safe every frame)")
	HeldItems.attach(sk, "wooden_club")
	check_eq(HeldItems.held(sk), "wooden_club")
	var count := 0
	for c in sk.get_children():
		if c is BoneAttachment3D and not c.is_queued_for_deletion():
			count += 1
	check_eq(count, 1, "one thing in hand at a time")
	check(HeldItems.attach(sk, "fists") == null and HeldItems.held(sk) == "", "fists empty the hand")
	# With the arm raised straight ahead (an overhead chop), the haft points up and the edge forward.
	var up: Vector3 = Basis(Vector3.RIGHT, -PI / 2.0) * HeldItems.GRIP.basis * Vector3.UP
	var edge: Vector3 = Basis(Vector3.RIGHT, -PI / 2.0) * HeldItems.GRIP.basis * Vector3.BACK
	check(up.dot(Vector3.UP) > 0.99, "haft up in a raised hand (%s)" % up)
	check(edge.dot(Vector3.BACK) > 0.99, "edge toward the swing, the figure's front (+Z) (%s)" % edge)
	sk.free()
