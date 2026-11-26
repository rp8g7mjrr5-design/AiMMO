extends TestCase
## World stream: the ruin kit and the burned farmstead (Basics 4, grade 1). The plan is shared
## data (RuinLayout) and gameplay's loot spots come from it; the meshes (RuinKit) are built
## from the same plan. Every test puts the world back to Ashgrove, because the config is global.

const SEEDS := [1126, 7]


func _farmsteads() -> Array:
	return Ruins.all().filter(func(r): return r.kind == "burned_farmstead")


func test_every_island_has_a_farmstead_with_four_loot_spots() -> void:
	for s in SEEDS:
		WorldGen.configure(s, 3000.0, WorldGen.ISLAND)
		var farms := _farmsteads()
		check(farms.size() >= 1, "seed %d has a burned farmstead" % s)
		for r in farms:
			var spots := RuinLayout.loot_spots(r)
			var kinds := spots.map(func(l): return l.kind)
			kinds.sort()
			check_eq(kinds, ["body", "chest", "crate", "sack"], "a crate, a chest, a sack and a body")
			for l in spots:
				check_eq(l.ruin_id, r.id, "spot knows its ruin")
				var flat := Vector2(l.pos.x - r.pos.x, l.pos.z - r.pos.z).length()
				check(flat < RuinLayout.FARM_YARD, "%s is inside the yard (%.1f m)" % [l.kind, flat])
				check(absf(l.pos.y - Terrain.height(l.pos.x, l.pos.z)) < 0.001, "%s sits on the ground" % l.kind)
			for i in spots.size():
				for j in range(i + 1, spots.size()):
					check(spots[i].pos.distance_to(spots[j].pos) > 1.5, "loot spots are apart")
		check(RuinLayout.all_loot_spots().size() >= 4 * farms.size(), "all_loot_spots covers every farmstead")
	WorldGen.reset()
	check_eq(RuinLayout.all_loot_spots(), [], "Ashgrove has no ruins and no loot spots")


func test_same_site_same_layout_new_seed_new_layout() -> void:
	var a := RuinLayout.farmstead(42)
	check_eq(RuinLayout.farmstead(42), a, "deterministic")
	var b := RuinLayout.farmstead(43)
	check(str(a) != str(b), "another seed lays it out differently")
	check_eq(RuinLayout.plan({"kind": "watchtower"}), {"pieces": [], "loot": []}, "kinds without a set piece are empty")


func test_pieces_stand_apart_and_inside_the_yard() -> void:
	for seed in range(1, 40):
		var p := RuinLayout.farmstead(seed)
		var by := {}
		for piece in p.pieces:
			by[piece.piece] = piece
		for k in ["house", "barn", "well", "cart", "fence", "rubble"]:
			check(by.has(k), "seed %d has a %s" % [seed, k])
		var house: Dictionary = by.house
		var house_reach: float = (house.size as Vector2).length() * 0.5
		var barn_reach: float = (by.barn.size as Vector2).length() * 0.5
		check((by.barn.pos as Vector2).distance_to(house.pos) > house_reach + barn_reach - 0.5, "barn clear of the house (seed %d)" % seed)
		check((by.well.pos as Vector2).distance_to(house.pos) > house_reach + 1.0, "well clear of the house (seed %d)" % seed)
		check((by.cart.pos as Vector2).distance_to(house.pos) > house_reach + 1.5, "cart clear of the house (seed %d)" % seed)
		check((by.well.pos as Vector2).distance_to(by.barn.pos) > barn_reach + 1.5, "well clear of the barn (seed %d)" % seed)
		for post in by.fence.posts:
			check((post.pos as Vector2).length() < RuinLayout.FARM_YARD, "fence inside the yard")


func test_kit_parts_are_grounded_muted_and_the_chimney_is_the_landmark() -> void:
	WorldGen.configure(1126, 3000.0, WorldGen.ISLAND)
	var r: Dictionary = _farmsteads()[0]
	var ps := RuinKit.parts(r)
	check(ps.size() > 80 and ps.size() < 400, "a full set piece inside a small budget (%d parts)" % ps.size())
	var tallest := 0.0
	for p in ps:
		check(p.layer in RuinKit.LAYERS, "%s is on a known layer" % p.name)
		var o: Vector3 = p.xform.origin
		var flat := Vector2(o.x - r.pos.x, o.z - r.pos.z).length()
		check(flat < r.radius, "%s stays on the pad (%.1f m)" % [p.name, flat])
		check(o.y > Terrain.height(o.x, o.z) - 0.2, "%s is not under the ground" % p.name)
		check(absf(p.xform.basis.determinant()) > 0.000001, "%s has a real size" % p.name)
		check(p.color.s < 0.45, "%s is a muted natural (%.2f)" % [p.name, p.color.s])
		check(p.color.v > 0.12, "%s is never black" % p.name)
		var top := o.y - Terrain.height(o.x, o.z) + absf(p.xform.basis.y.y) * 0.5
		if top > tallest:
			tallest = top
		if top > 4.5:
			check(p.far, "%s is tall, so it is drawn far (the landmark)" % p.name)
	check(tallest > 6.5 and tallest < 8.5, "the chimney stands about 7 m (%.1f)" % tallest)
	check(ps.filter(func(p): return p.name == "chimney").size() == 1, "one chimney")
	# The loot props sit on the loot spots.
	for l in RuinLayout.loot_spots(r):
		var near := ps.filter(func(p): return p.name == l.kind or p.name == "body_cloak" and l.kind == "body")
		check(near.size() == 1, "%s is drawn" % l.kind)
		var o: Vector3 = near[0].xform.origin
		check(Vector2(o.x - l.pos.x, o.z - l.pos.z).length() < 0.05, "%s drawn on its spot" % l.kind)
	WorldGen.reset()


func test_build_makes_a_node_per_farmstead_with_ranges() -> void:
	WorldGen.reset()
	var none := RuinKit.build()
	check_eq(none.get_child_count(), 0, "Ashgrove: no ruins")
	none.free()
	WorldGen.configure(1126, 3000.0, WorldGen.ISLAND)
	var root := RuinKit.build()
	check_eq(str(root.name), RuinKit.NODE_NAME)
	check_eq(root.get_child_count(), _farmsteads().size(), "one node per farmstead")
	var ruin := root.get_child(0)
	var far := 0
	for c in ruin.get_children():
		var mmi := c as MultiMeshInstance3D
		check(mmi != null and mmi.multimesh.instance_count > 0, "%s has instances" % c.name)
		check(mmi.material_override == Emberlight.material("solid"), "%s uses the shared material" % c.name)
		if str(c.name).ends_with("Far"):
			far += 1
			check_eq(mmi.visibility_range_end, RuinKit.FAR_RANGE, "far layer seen from afar")
		else:
			check_eq(mmi.visibility_range_end, RuinKit.NEAR_RANGE, "near layer fades in close")
	check(far >= 1, "the chimney's layer is drawn far")
	root.free()
	WorldGen.reset()
