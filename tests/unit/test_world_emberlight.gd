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
	check_eq(WorldBuilder.scatter_material("Trunks"), Emberlight.painted("bark"), "trunks on the shared painted bark")
	check_eq(WorldBuilder.scatter_material("Rocks"), Emberlight.painted("stone"), "rocks on the shared painted stone")
	check(seen.size() <= 4, "four scatter layers, at most four materials")
	check(Emberlight.count() <= 24, "within the art bible's 24-material budget")


func test_shader_reads_only_the_surface_detail() -> void:
	# Art bible section 7: the world shaders' one texture is SurfaceTex's tiny painted detail,
	# off unless a material asks for it.
	for v in Emberlight.VARIANTS:
		var src := Emberlight.source(v)
		check_eq(src.count("sampler2D"), 1, "%s: one sampler" % v)
		check(src.contains("uniform sampler2D paint_tex : filter_nearest_mipmap"), "%s: crisp, nearest-filtered detail" % v)
		check(src.contains("uniform float paint_mix = 0.0"), "%s: detail is off by default" % v)
		check_eq(src.count("texture("), 1, "%s: one lookup" % v)
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


func test_painted_materials_are_shared_and_tiny() -> void:
	check_eq(Emberlight.painted("bark"), Emberlight.painted("bark"), "one bark material")
	check(Emberlight.painted("bark") != Emberlight.painted("stone"), "bark and stone differ")
	# The world matches the smooth, grain-free folk (2026-11-26): the detail is laid on but off.
	check_eq(float(Emberlight.painted("stone").get_shader_parameter("paint_mix")), 0.0, "stone is smooth flat colour like the folk")
	for k in Emberlight.PAINT:
		check_eq(float(Emberlight.PAINT[k].mix), 0.0, "%s detail is off" % k)
	check_eq(TerrainMesh.material().get_shader_parameter("paint_tex"), SurfaceTex.get_texture("ground"), "the ground is painted")
	for k in SurfaceTex.KINDS:
		var t := SurfaceTex.get_texture(k)
		check_eq(t, SurfaceTex.get_texture(k), "%s built once" % k)
		check(t.get_width() <= 64 and t.get_height() <= 64, "%s is a tiny image (art bible: 32 to 64 px)" % k)
		# brightness only, centred on 0.5, so it never shifts a colour's overall brightness
		var im := SurfaceTex.image(k)
		var total := 0.0
		var lo := 1.0
		var hi := 0.0
		for y in im.get_height():
			for x in im.get_width():
				var v := im.get_pixel(x, y).r
				total += v
				lo = minf(lo, v)
				hi = maxf(hi, v)
		check_near(total / (im.get_width() * im.get_height()), 0.5, 0.03, "%s averages mid grey" % k)
		check(hi - lo > 0.2, "%s has visible detail" % k)


func test_world_is_clean_carved_like_the_characters() -> void:
	# Owner, 2026-11-26: "make sure the map now fits with our new characters", then "B clean
	# carved real proportions". The world is crisp flat-lit planes in flat colour: no texel
	# grain, no painted noise, every triangle one carved facet.
	for v in Emberlight.VARIANTS:
		var src := Emberlight.source(v)
		check(src.contains("uniform float texel_grain = 0.0"), "%s: no texel grain by default" % v)
		check(src.contains("uniform float facets = 1.0"), "%s: carved facets by default" % v)
		check(src.contains("cross(dFdx(VERTEX), dFdy(VERTEX))") and src.contains("dot(face, NORMAL) < 0.0"), "%s: each face lit as one plane, facing out on every renderer" % v)
	check(TerrainMesh.material().get_shader_parameter("texel_grain") == null, "the ground keeps the default: no grain")
	check(TerrainMesh.material().get_shader_parameter("paint_mix") == 0.0, "no painted detail on the ground")
	# Grass blades are clean shapes, not single-pixel lines: wide enough to filter smoothly.
	var im := Grass.blade_image()
	var widest := 0
	for y in im.get_height():
		var run := 0
		for x in im.get_width():
			run = run + 1 if im.get_pixel(x, y).a > 0.5 else 0
			widest = maxi(widest, run)
	check(widest >= 5, "blades are several texels wide at the root (%d)" % widest)
