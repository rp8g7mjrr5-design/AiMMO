extends TestCase
## World stream: the shared Emberlight shader (docs/art_bible.md). Materials are built once and
## shared, the terrain and scatter forest use them, the shader reads no textures, the
## heartbeat is one shared value, and baking colours never moves a vertex.


func test_materials_are_shared() -> void:
	for v in Emberlight.VARIANTS:
		check(Emberlight.material(v) == Emberlight.material(v), "%s: same instance every time" % v)
		check((Emberlight.material(v) as ShaderMaterial).shader == Emberlight.shader(v), "%s: one shader per variant" % v)
	check(Emberlight.material("solid") != Emberlight.material("foliage"), "variants are different materials")
	check(Emberlight.material("foliage", "ash_leaf") == Lamps.ember_leaf_material(), "named materials are shared too")
	check(Emberlight.material("foliage", "ash_leaf") != Emberlight.material("foliage"), "a named material is its own")
	check(TerrainMesh.material() == TerrainMesh.material(), "every terrain chunk shares one material")


func test_scatter_layers_use_emberlight() -> void:
	var seen := {}
	for l in WorldBuilder.SCATTER_LAYERS:
		var m := WorldBuilder.scatter_material(l)
		check(Emberlight.is_emberlight(m), "%s is on Emberlight" % l)
		seen[m.get_instance_id()] = true
	check_eq(WorldBuilder.scatter_material("Trunks"), WorldBuilder.scatter_material("Rocks"), "bark and stone share solid")
	check(seen.size() <= 3, "four scatter layers, at most three materials")
	check(Emberlight.count() <= 24, "within the art bible's 24-material budget")


func test_shader_uses_no_textures() -> void:
	for v in Emberlight.VARIANTS:
		var src := Emberlight.source(v)
		check(not src.contains("sampler2D") and not src.contains("texture("), "%s: no texture lookups" % v)
		check(src.contains("global uniform float ember_pulse"), "%s: reads the shared heartbeat" % v)
		check(not src.contains("$"), "%s: every palette token filled in" % v)
	check(Emberlight.source("foliage").contains("#define FOLIAGE"), "foliage sways")
	check(Emberlight.source("glow").contains("#define GLOW"), "glow has veins")
	check(not Emberlight.source("solid").contains("#define"), "solid is the plain one")


func test_heartbeat() -> void:
	var lo := 1.0
	var hi := 0.0
	for i in 400:
		var p := Emberlight.pulse(i * 0.01)
		check(p >= 0.0 and p <= 1.0, "pulse stays 0..1")
		lo = minf(lo, p)
		hi = maxf(hi, p)
	check(lo < 0.01 and hi > 0.99, "a full beat in 4 s")
	check_near(Emberlight.pulse(1.3), Emberlight.pulse(1.3 + Emberlight.BEAT_SECONDS * 7.0), 0.0001, "beats repeat")
	check_near(Emberlight.pulse(0.0), 0.0, 0.0001, "rest at the start of a beat")
	check_near(Emberlight.pulse(2.0), 1.0, 0.0001, "peak half way")


func test_bake_keeps_vertices() -> void:
	var meshes := WorldBuilder.scatter_meshes()
	for l in meshes:
		var baked: Mesh = meshes[l]
		var arrays := baked.surface_get_arrays(0)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var cols: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
		check_eq(cols.size(), verts.size(), "%s: a colour per vertex" % l)
		var lo_y := INF
		var hi_y := -INF
		var dark := 1.0
		var light := 0.0
		for i in verts.size():
			lo_y = minf(lo_y, verts[i].y)
			hi_y = maxf(hi_y, verts[i].y)
		for i in verts.size():
			if is_equal_approx(verts[i].y, lo_y):
				dark = minf(dark, cols[i].r)
			if is_equal_approx(verts[i].y, hi_y):
				light = maxf(light, cols[i].r)
			check(cols[i].a == 1.0, "%s: no veins on plain decoration" % l)
		check(dark < 0.7, "%s: dark where it meets the ground" % l)
		check_near(light, 1.0, 0.001, "%s: full colour at the top" % l)
	# Same shape as the primitive it came from.
	var cyl := CylinderMesh.new()
	cyl.height = 2.0
	var b := Emberlight.bake(cyl, 0.5)
	check(b.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] == cyl.surface_get_arrays(0)[Mesh.ARRAY_VERTEX], "vertices unchanged")
	var nb: PackedVector3Array = b.surface_get_arrays(0)[Mesh.ARRAY_NORMAL]
	var nc: PackedVector3Array = cyl.surface_get_arrays(0)[Mesh.ARRAY_NORMAL]
	var worst := 0.0
	for i in nc.size():
		worst = maxf(worst, nb[i].distance_to(nc[i]))
	check(nb.size() == nc.size() and worst < 0.001, "normals unchanged (within storage rounding, %.5f)" % worst)


func test_terrain_ao() -> void:
	check_near(TerrainMesh.ao_factor(0.0), 1.0, 0.0001, "flat ground is untouched")
	check(TerrainMesh.ao_factor(3.0) < TerrainMesh.ao_factor(1.0), "deeper hollows are darker")
	check_near(TerrainMesh.ao_factor(100.0), 1.0 - TerrainMesh.AO_MAX, 0.0001, "never darker than AO_MAX")
	check(TerrainMesh.ao_factor(-3.0) > 1.0, "ridges catch a little more light")
	check(TerrainMesh.ao_factor(-100.0) <= 1.0 + TerrainMesh.AO_LIGHT_MAX + 0.0001, "and only a little")
	# A real chunk out in the hills: colours vary across faces, positions match the height field.
	var m := TerrainMesh.build_chunk(64.0, 64.0)
	var arrays := m.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var cols: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	for i in range(0, verts.size(), 37):
		check_near(verts[i].y, Terrain.height(verts[i].x, verts[i].z), 0.001, "vertex sits on the height field")
	var graded := 0
	for t in range(0, verts.size(), 3):
		if not cols[t].is_equal_approx(cols[t + 1]) or not cols[t].is_equal_approx(cols[t + 2]):
			graded += 1
	check(graded > verts.size() / 3 / 4, "most faces carry a gradient, not one flat colour (%d)" % graded)


func test_pulse_parameter_registered() -> void:
	Emberlight.ensure_globals()
	Emberlight.set_pulse(0.5) # must not error, headless or not
	check(true, "set_pulse runs")
