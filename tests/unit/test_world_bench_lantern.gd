extends TestCase
## World stream: the workbench's lantern and highlight. The lantern sits on the bench top,
## clear of the tools, and glows from the shared clock (lit at night, dim by day); the
## highlight shell wraps every part of the bench and switches cleanly on and off.


func _lantern_parts() -> Array:
	return Workbench.parts().filter(func(p): return str(p.name).begins_with("lantern"))


func test_lantern_stands_on_the_bench_top() -> void:
	var s := Workbench.spot()
	var lantern := _lantern_parts()
	check(lantern.size() >= 8, "lantern has a foot, glass, rods, cap and handle")
	var glass := lantern.filter(func(p): return p.layer == Workbench.GLASS_LAYER)
	check_eq(glass.size(), 1, "one glowing glass")
	var inv := Transform3D(Basis(Vector3.UP, s.rot), s.pos).affine_inverse()
	var foot: Dictionary = lantern.filter(func(p): return p.name == "lantern_foot")[0]
	var foot_bottom: float = (inv * foot.xform.origin).y - foot.xform.basis.get_scale().y * 0.5
	check_near(foot_bottom, Workbench.TOP_HEIGHT, 0.005, "lantern foot rests on the planks")
	for p in lantern:
		var l: Vector3 = inv * p.xform.origin
		check(absf(l.x) < Workbench.TOP_LENGTH * 0.5 - 0.1 and absf(l.z) < Workbench.TOP_DEPTH * 0.5 - 0.03,
			"%s is over the bench top, not hanging off it" % p.name)
		check(l.y > Workbench.TOP_HEIGHT and l.y < Workbench.TOP_HEIGHT + 0.45, "%s is a small lantern, not a post" % p.name)
	# Clear of the hammer and the chips, so nothing pokes through the glass.
	for p in Workbench.parts():
		if p.name in ["hammer_head", "hammer_handle", "chip"]:
			var l: Vector3 = inv * p.xform.origin
			check(Vector2(l.x - Workbench.LANTERN_SPOT.x, l.z - Workbench.LANTERN_SPOT.y).length() > 0.2,
				"%s is clear of the lantern" % p.name)


func test_lantern_parts_come_last() -> void:
	# Older parts keep their index (the bench looks the same as before apart from the lantern).
	var ps := Workbench.parts()
	var first := -1
	for i in ps.size():
		if str(ps[i].name).begins_with("lantern"):
			if first == -1:
				first = i
		else:
			check(first == -1, "no older part comes after the lantern (%s at %d)" % [ps[i].name, i])
	check_eq(ps[0].name, "leg_foot", "the bench still starts with its first leg")


func test_light_sits_in_the_glass() -> void:
	var glass: Dictionary = _lantern_parts().filter(func(p): return p.layer == Workbench.GLASS_LAYER)[0]
	check(Workbench.light_position().distance_to(glass.xform.origin) < 0.01, "light is at the glass's centre")


func test_glow_follows_the_clock() -> void:
	var day := Workbench.glow_values(Lamps.night_glow(0.5))
	var night := Workbench.glow_values(Lamps.night_glow(0.0))
	check(not day.light_on and day.light_energy == 0.0, "lantern light is out at noon")
	check(night.light_on and night.light_energy > 0.5, "lantern light is on at midnight")
	check(night.glass > day.glass * 4.0, "glass glows much brighter at night")
	check_near(Workbench.glow_values(-1.0).glass, Workbench.GLASS_DAY, 0.001, "glow is clamped low")
	check_near(Workbench.glow_values(3.0).light_energy, Workbench.LIGHT_ENERGY, 0.001, "glow is clamped high")


func test_built_bench_lights_up_from_lamps() -> void:
	var world := Node3D.new()
	var bench := Workbench.build()
	world.add_child(bench)
	var omni := bench.get_node("Light") as OmniLight3D
	var glass := bench.get_node(Workbench.GLASS_LAYER) as MultiMeshInstance3D
	check(omni != null and glass != null, "bench has its lantern light and glass")
	check(not omni.visible, "light starts off")
	Lamps.apply_glow(world, 1.0)
	check(omni.visible and omni.light_energy > 0.5, "Lamps.apply_glow lights the bench lantern at night")
	check_near((glass.material_override as StandardMaterial3D).emission_energy_multiplier, Workbench.GLASS_NIGHT, 0.001, "glass at night brightness")
	Lamps.apply_glow(world, 0.0)
	check(not omni.visible, "and puts it out by day")
	Workbench.apply_glow(null, 1.0) # safe on a partial world
	world.free()


func test_highlight_wraps_the_bench() -> void:
	var sl := Workbench.shell_layout()
	check_eq(sl.box.size() + sl.log.size(), Workbench.parts().size(), "one shell piece per part")
	var ps := Workbench.parts()
	for i in ps.size():
		var xf: Transform3D = ps[i].xform
		var shell: Transform3D = NodeFx.shell_xform(xf)
		check(shell.basis.get_scale().length() > xf.basis.get_scale().length(), "shell %d is a little bigger than its part" % i)
	var bench := Workbench.build()
	var shell_node := bench.get_node("Highlight") as Node3D
	check(not shell_node.visible and not Workbench.highlighted(bench), "highlight starts off")
	check_eq((shell_node.get_node("ShellBox") as MultiMeshInstance3D).multimesh.instance_count, sl.box.size(), "box shell has every box part")
	check(Workbench.set_highlight(bench, true), "highlight turns on")
	var mat := shell_node.get_meta("material") as ShaderMaterial
	check(shell_node.visible and Workbench.highlighted(bench), "shell shows")
	check_near(float(mat.get_shader_parameter("strength")), Workbench.HIGHLIGHT_STRENGTH, 0.001, "full strength out of the tree")
	check(Workbench.set_highlight(bench, true), "calling again is a harmless no-op")
	Workbench.set_highlight(bench, false)
	check(not shell_node.visible and not Workbench.highlighted(bench), "highlight turns off")
	check(not Workbench.set_highlight(null, true), "null bench is refused")
	bench.free()

