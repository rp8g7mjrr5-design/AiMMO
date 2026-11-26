extends TestCase
## World stream: grass tufts near the camera (Grass). Same world, same tufts; grass only grows
## where the ground is turf; the Graphics setting thins it; one material, one draw call.


func _tufts(buf: PackedFloat32Array) -> Array:
	var out: Array = []
	for i in buf.size() / Grass.FLOATS:
		var o := i * Grass.FLOATS
		out.append({"pos": Vector3(buf[o + 3], buf[o + 7], buf[o + 11]), "col": Color(buf[o + 12], buf[o + 13], buf[o + 14], buf[o + 15])})
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


func test_range_is_small_and_nearest_first() -> void:
	var cells := Grass.cells_near(Vector3(3.0, 0.0, -2.0))
	check(cells.size() <= 60, "a bounded set of cells (%d)" % cells.size())
	check_eq(cells[0], Vector2i(0, -1), "the centre's own cell comes first")


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
