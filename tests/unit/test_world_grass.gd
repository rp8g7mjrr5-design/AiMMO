extends TestCase
## World stream: grass tufts near the camera (Grass). Same world, same tufts; grass only grows
## where the ground is turf; the Graphics setting thins it; one material, one draw call; the
## meadow thins out with distance instead of ending in an edge, and never pops in.


func _tufts(buf: PackedFloat32Array) -> Array:
	var out: Array = []
	for i in buf.size() / Grass.FLOATS:
		var o := i * Grass.FLOATS
		out.append({"pos": Vector3(buf[o + 3], buf[o + 7], buf[o + 11]), "col": Color(buf[o + 12], buf[o + 13], buf[o + 14], buf[o + 15]), "rank": buf[o + 16]})
	return out


func test_cells_are_deterministic() -> void:
	check_eq(Grass.cell(2, -3), Grass.cell(2, -3), "same cell, same tufts")
	check(Grass.cell(2, -3) != Grass.cell(3, -3), "neighbouring cells differ")
	check_eq(Grass.cell(2, -3).size() % Grass.FLOATS, 0, "whole tufts in the buffer")


func test_meadow_grows_grass_and_stays_in_its_cell() -> void:
	var total := 0
	for cx in range(-2, 2):
		for cz in range(-2, 2):
			for t in _tufts(Grass.cell(cx, cz)):
				total += 1
				var p: Vector3 = t.pos
				check(p.x >= cx * Grass.CELL and p.x <= (cx + 1) * Grass.CELL and p.z >= cz * Grass.CELL and p.z <= (cz + 1) * Grass.CELL, "tuft inside its cell")
				check(absf(p.y - Terrain.height(p.x, p.z)) < 0.25, "tuft on the ground")
				check(p.y > Terrain.water_level() + Grass.WATER_CLEAR - 0.3, "no grass in the water")
				var c: Color = t.col
				check(c.g >= c.b, "blades are green or straw, never blue: %s" % c)
	check(total > 1000, "the Spawn Meadow is grassy (%d tufts in 16 cells)" % total)
	check(total <= int(Grass.DENSITY * Grass.CELL * Grass.CELL) * 16, "never more than the density allows")


func test_no_grass_in_water_or_on_cliffs() -> void:
	check_eq(Grass.growth(0.0, 0.0, Terrain.water_level() - 1.0, 0.0), 0.0, "under water")
	check_eq(Grass.growth(0.0, 0.0, Terrain.water_level() + 3.0, 0.8), 0.0, "on a cliff")
	check(Grass.growth(0.0, 0.0, Terrain.water_level() + 3.0, 0.0) > 0.5, "on flat meadow")


func test_graphics_thins_grass() -> void:
	var full := Grass.cell(0, 0, 1.0).size()
	var half := Grass.cell(0, 0, 0.5).size()
	check(half < full * 0.7, "half density, fewer tufts (%d vs %d)" % [half, full])
	check_eq(Grass.cell(0, 0, 0.0).size(), 0, "off is off")


func test_range_is_bounded_and_nearest_first() -> void:
	var cells := Grass.cells_near(Vector3(3.0, 0.0, -2.0))
	# 52 m with a cell's reach: about 170 cells, most of them far and nearly empty.
	check(cells.size() <= 200, "a bounded set of cells (%d)" % cells.size())
	check_eq(cells[0], Vector2i(0, -1), "the centre's own cell comes first")


func test_meadow_thins_out_with_distance_no_edge() -> void:
	check_eq(Grass.visible_fraction(0.0), 1.0, "every tuft stands near you")
	check_eq(Grass.visible_fraction(Grass.FULL), 1.0, "out to FULL")
	check_eq(Grass.visible_fraction(Grass.RANGE), 0.0, "none at RANGE")
	var last := 1.0
	var biggest_step := 0.0
	var d := Grass.FULL
	while d <= Grass.RANGE:
		var f := Grass.visible_fraction(d)
		check(f <= last + 1e-6, "never thicker further out (%.1f m)" % d)
		biggest_step = maxf(biggest_step, last - f)
		last = f
		d += 1.0
	check(biggest_step < 0.06, "no metre drops more than 6%% of the meadow (an edge): %.3f" % biggest_step)
	check(Grass.RANGE - Grass.FULL >= 30.0, "the thinning runs over at least 30 m")


func test_ranks_and_caps_are_subsets() -> void:
	var full := _tufts(Grass.cell(1, 1))
	var ranks: Array = full.map(func(t): return t.rank)
	check(ranks.all(func(r): return r >= 0.0 and r < 1.0), "ranks in 0..1")
	var lo := 0
	for r in ranks:
		if r < 0.5:
			lo += 1
	check(lo > ranks.size() * 0.35 and lo < ranks.size() * 0.65, "ranks spread evenly (%d of %d under 0.5)" % [lo, ranks.size()])
	for cap in Grass.TIERS:
		var some := _tufts(Grass.cell(1, 1, 1.0, cap))
		var want: Array = full.filter(func(t): return t.rank < cap)
		check_eq(some.size(), want.size(), "cap %.2f keeps exactly the tufts ranked under it" % cap)
		for i in some.size():
			check_eq(some[i].pos, want[i].pos, "same tufts, same order, at cap %.2f" % cap)
	check_eq(Grass.cell(1, 1, 1.0, 0.0).size(), 0, "cap 0: an empty cell")


func test_a_far_cell_is_rebuilt_before_its_missing_tufts_could_show() -> void:
	# A cell built for distance d holds every tuft that could stand anywhere TIER_MARGIN nearer.
	var d := 0.0
	while d < Grass.RANGE + 10.0:
		var cap := Grass.tier_cap(d)
		check(cap >= Grass.visible_fraction(d - Grass.TIER_MARGIN), "cap covers what could show at %.0f m" % d)
		check(cap == 0.0 or cap in Grass.TIERS, "caps come from TIERS")
		d += 0.5
	check_eq(Grass.tier_cap(Grass.RANGE + Grass.TIER_MARGIN + 1.0), 0.0, "past the range: empty")
	check_eq(Grass.cell_distance(Vector2i(0, 0), Vector3(3.0, 0.0, 3.0)), 0.0, "inside the cell: 0")
	check(is_equal_approx(Grass.cell_distance(Vector2i(2, 0), Vector3(3.0, 0.0, 3.0)), 13.0), "13 m to the next-but-one cell")


func test_tuft_budget_on_open_meadow() -> void:
	# Everything in range on the Spawn Meadow, at the tiers the field would build: the frame
	# budget (art bible section 7): about 11k tufts (44k triangles) on the thickest meadow,
	# against about 5k for the old hard-edged 24 m disc.
	var center := Vector3(0.0, 0.0, 0.0)
	var total := 0
	for c in Grass.cells_near(center):
		total += Grass.cell(c.x, c.y, 1.0, Grass.tier_cap(Grass.cell_distance(c, center))).size() / Grass.FLOATS
	check(total < 13000, "tufts in range on the meadow: %d" % total)
	check(total > 3000, "and still a meadow: %d" % total)


func test_blade_mips_keep_their_coverage() -> void:
	# Averaged mips thin the blades below the alpha cut, so far tufts vanished; ours stay solid.
	var im := Grass.blade_image()
	check(im.has_mipmaps(), "the blade sheet has mipmaps")
	var lvl := Image.create_from_data(16, 8, false, Image.FORMAT_RGBA8,
		im.get_data().slice(im.get_mipmap_offset(2), im.get_mipmap_offset(3)))
	var opaque := 0
	for y in 8:
		for x in 16:
			if lvl.get_pixel(x, y).a > 0.4:
				opaque += 1
	check(opaque > 16 * 8 * 0.3, "a quarter-size mip still shows blades (%d of 128 texels)" % opaque)


func test_one_material_no_shadows_one_draw() -> void:
	var g := Grass.build()
	var mmis := g.find_children("*", "MultiMeshInstance3D", true, false)
	check_eq(mmis.size(), 1, "one MultiMesh: one draw call")
	var mmi: MultiMeshInstance3D = mmis[0]
	check_eq(mmi.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "grass casts no shadow")
	check_eq(mmi.material_override, Grass.material(), "one shared material")
	check_eq(Grass.mesh().get_faces().size() / 3, 4, "a tuft is four triangles")
	g.free()


func test_shader_source() -> void:
	var src := Grass.source(false)
	check(not src.contains("$"), "every token filled in")
	check(not src.begins_with("#define COMPAT_SRGB"), "Forward+: no Compatibility encode")
	check(Grass.source(true).begins_with("#define COMPAT_SRGB"), "Compatibility gets the encode")
	check(src.contains("global uniform float ember_night"), "drains at night with the world")
