extends TestCase
## World stream: Emberlight part 2b (docs/art_bible.md, sections 2 and 7). The last things in
## the valley that drew with their own StandardMaterial3D (meadow lanterns, the workbench,
## every avatar part and NodeFx's flying hit bits) now draw with the shared Emberlight family,
## and the whole built world stays inside the art bible's material budget.

const RenderStats := preload("res://tests/client_smoke/render_stats.gd")
const WORLD_MATERIAL_CEILING := 12 ## 11 on 2026-11-23 (part 2b); art bible target 24, smoke-test ceiling 20


func _meshes_under(n: Node, out: Array) -> Array:
	if n is GeometryInstance3D:
		out.append(n)
	for c in n.get_children():
		_meshes_under(c, out)
	return out


func test_lanterns_and_bench_are_on_emberlight() -> void:
	var lamps := Lamps.build()
	var bench := Workbench.build()
	for l in Lamps.LAYERS:
		var mmi := lamps.get_node(l) as MultiMeshInstance3D
		check(Emberlight.is_emberlight(mmi.material_override), "lantern layer %s is on Emberlight" % l)
	for l in Workbench.LAYERS:
		var mmi := bench.get_node(l) as MultiMeshInstance3D
		check(Emberlight.is_emberlight(mmi.material_override), "bench layer %s is on Emberlight" % l)
	check_eq((lamps.get_node("LampWood") as MultiMeshInstance3D).material_override, Emberlight.material("solid"),
		"lantern posts share the forest's solid")
	check_eq((bench.get_node("BenchWood") as MultiMeshInstance3D).material_override, Emberlight.material("solid"),
		"the bench shares the forest's solid")
	check_eq((bench.get_node(Workbench.GLASS_LAYER) as MultiMeshInstance3D).material_override,
		(lamps.get_node(Lamps.GLASS_LAYER) as MultiMeshInstance3D).material_override,
		"the bench lantern and the meadow lanterns share one glass")
	var mesh := (lamps.get_node("LampWood") as MultiMeshInstance3D).multimesh.mesh
	check(mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR] != null, "lantern meshes carry baked shading")
	lamps.free()
	bench.free()


func test_lantern_glass_still_lights_at_night() -> void:
	var world := Node3D.new()
	world.add_child(Lamps.build())
	world.add_child(Workbench.build())
	var glass := Lamps.glass_material()
	Lamps.apply_glow(world, 1.0)
	check_near(float(glass.get_shader_parameter("emission_energy")), Lamps.GLASS_NIGHT, 0.001, "glass at night")
	Lamps.apply_glow(world, 0.0)
	check_near(float(glass.get_shader_parameter("emission_energy")), Lamps.GLASS_DAY, 0.001, "glass by day")
	check_eq(glass.get_shader_parameter("emission_color"), Lamps.FLAME, "glass glows flame-coloured")
	check(float(glass.get_shader_parameter("pulse_depth")) < 0.25, "glass breathes more gently than the ash leaves")
	world.free()


func test_avatars_share_one_material_and_keep_their_colours() -> void:
	# (AvatarBuilder.build() makes MeshInstance3Ds, which log engine errors on the headless
	# dummy renderer, so this checks the pieces build() is made of: every part goes through
	# `_part()`, which paints the part's mesh and puts it on `material()`.)
	check_eq(AvatarBuilder.material(), Emberlight.material("solid"), "every avatar part: the world's own solid")
	check(Emberlight.is_emberlight(AvatarBuilder.material()), "avatar parts on Emberlight")
	var src := (load("res://procgen/avatar_builder.gd") as GDScript).source_code
	check(not src.contains("StandardMaterial3D.new()"), "AvatarBuilder makes no private materials")
	# The tunic keeps its seed colour, now in the vertex colours (top vertex: no baked shade).
	var spec: Array = AvatarBuilder.parts(11)
	var body := Emberlight.paint(spec[0].mesh, spec[0].color, AvatarBuilder.PART_AO)
	var arrays := body.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var cols: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	var top := 0
	for i in verts.size():
		if verts[i].y > verts[top].y:
			top = i
	var want := (spec[0].color as Color).srgb_to_linear()
	check_near(cols[top].r, want.r, 0.01, "tunic red")
	check_near(cols[top].g, want.g, 0.01, "tunic green")
	check_near(cols[top].b, want.b, 0.01, "tunic blue")
	check_eq(verts, (spec[0].mesh as Mesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX], "painting keeps the shape")
	for p in AvatarBuilder.parts(12345): # every part, every shape, paints cleanly
		var m := Emberlight.paint(p.mesh, p.color, AvatarBuilder.PART_AO)
		check(m.get_surface_count() == 1 and m.surface_get_arrays(0)[Mesh.ARRAY_COLOR].size() > 0, "a painted avatar part")


func test_hit_bits_fly_on_the_vein_material() -> void:
	var root := NodeProps.build()
	var fx := root.get_node("Fx") as NodeFx
	var bits := fx.get_node("HitBits") as MultiMeshInstance3D
	check_eq(bits.material_override, Emberlight.material("glow"), "hit bits share the veins' glow material")
	check_eq(NodeFx.bit_color({"color": Palette.ROCK, "glow": 0.0}).a, 1.0, "a plain chip doesn't glow")
	var warm := NodeFx.bit_color({"color": Palette.ASH_LEAF, "glow": 0.25}).a
	var spark := NodeFx.bit_color({"color": Palette.RICH_FLECK, "glow": 0.4}).a
	var drop := NodeFx.bit_color({"color": Palette.EMBER, "glow": 1.6}).a
	check(1.0 > warm and warm > spark and spark > drop and drop >= 0.0, "more glow, more vein (%.2f %.2f %.2f)" % [warm, spark, drop])
	# The vein light at rest is about 2 x vein^2: the same brightness the old private shader gave.
	check_near(2.0 * pow(1.0 - drop, 2.0), 1.6, 0.01, "a sap droplet glows as bright as before")
	root.free()


func test_whole_world_fits_the_material_budget() -> void:
	# The headless dummy renderer logs this for every MeshInstance3D it is handed (terrain,
	# water); the real renderer doesn't. Everything else here is checked as usual.
	expect_error("Parameter \"m\" is null")
	var world := WorldBuilder.build()
	var count := RenderStats.count_materials_in([world])
	# Avatars add none: they draw on the world's own solid (test above), however many come.
	if not Emberlight.is_emberlight(AvatarBuilder.material()):
		count += 1
	check(count <= WORLD_MATERIAL_CEILING, "the built world uses %d materials (ceiling %d, art bible 24)" % [count, WORLD_MATERIAL_CEILING])
	var plain := []
	for n in _meshes_under(world, []):
		if (n as GeometryInstance3D).material_override is StandardMaterial3D and n.name != "Water":
			plain.append(String(n.name))
	check(plain.is_empty(), "nothing but the lake draws with a plain StandardMaterial3D: %s" % [plain])
	print("[world] materials in the built world: %d" % count)
	world.free()
