class_name Workbench
## The Spawn Meadow workbench: a sturdy low-poly table where settlers craft their first tools.
##
## It always stands at `Crafting.workbench_pos()` (gameplay's rule for where /craft works), so
## the picture and the rule can never drift apart. The bench faces spawn, so a new player sees
## its long side and the tools on it the moment they arrive.
##
## Looks: a thick top of three pale ash-wood planks resting on four squat stone legs, two
## cross rails, a stone-headed hammer and a few stone chips on the top, a chopping block with
## an axe-split log at one end, and two cut logs stacked at the back. It reads as "a place to
## make things" from the edge of the meadow and holds up close to the action camera (3.5 m).
##
## A small iron lantern stands on the back corner of the top. By day it is just a lantern; at
## night its glass glows and a short-range warm light pools over the bench, so a player who
## comes back to the meadow after dark can walk straight to it (`apply_glow`, called by
## `Lamps.apply_glow` from the one shared clock).
##
## `set_highlight(bench, on)` gives the whole bench the same soft ember-gold rim glow that a
## resource node in reach gets (NodeFx's rim shader), so "[E] Use Workbench" has something to
## point at. Calling it every frame with the same value is a no-op.
##
## Split like Lamps: `spot()`, `parts()`, `layout()`, `light_position()` and `glow_values()`
## are pure data (safe headless, in unit tests and bots); `build()` makes the "Workbench" node
## from MultiMesh layers, the lantern's light and a hidden highlight shell.

const TOP_HEIGHT := 0.92 ## metres from the ground to the top of the planks (a good standing height)
const TOP_LENGTH := 1.8
const TOP_DEPTH := 0.84
const FOOTPRINT := 2.0 ## metres from the bench's centre that its parts (block, logs) reach
const CLEARANCE := 2.5 ## nothing else (lanterns, nodes, trees, flowers) stands this close
const LAYERS := ["BenchWood", "BenchStone", "BenchLogs", "BenchGlass"]
const GLASS_LAYER := "BenchGlass"

## The bench lantern: stands on the top's back-left corner, clear of the hammer and chips.
const LANTERN_SPOT := Vector2(-0.68, -0.25) ## local x, z on the top
const LANTERN_GLASS := Vector3(0.15, 0.2, 0.15)
const LIGHT_ENERGY := 1.1 ## at full night; softer than a meadow lantern, it only has to light the bench
const LIGHT_RANGE := 6.0
## The bench lantern's glass is the meadow lanterns' glass (one shared material,
## `Lamps.glass_material()`), so it lights to exactly the same brightness: one family.
const GLASS_DAY := Lamps.GLASS_DAY
const GLASS_NIGHT := Lamps.GLASS_NIGHT
const HIGHLIGHT_FADE := 0.15 ## seconds, like NodeFx.FADE_IN
const HIGHLIGHT_STRENGTH := 0.8 ## a touch softer than a node's: the bench is big and close

const ASH_WOOD := Color(0.74, 0.58, 0.42) ## planed ash: pale and warm, lighter than bark
const ASH_WOOD_DARK := Color(0.58, 0.43, 0.30) ## rails, handle and end grain
const BENCH_STONE := Color(0.47, 0.45, 0.43) ## legs: a touch darker than meadow rocks so they read under the top
const CUT_FACE := Color(0.80, 0.63, 0.43) ## fresh cut ends of logs and the block's top
const BARK := Color(0.47, 0.34, 0.23) ## a shade lighter than tree trunks so logs read in the bench's shadow


## Where the bench stands: {pos: Vector3 on the ground, rot: yaw}. Local +Z faces spawn.
static func spot() -> Dictionary:
	var pos := Crafting.workbench_pos()
	var to_spawn := GameConfig.SPAWN_POINT - pos
	var rot := atan2(to_spawn.x, to_spawn.z) if Vector2(to_spawn.x, to_spawn.z).length() > 0.01 else 0.0
	return {"pos": pos, "rot": rot}


## Every part of the bench in world space: Array of {layer, xform, color, name}.
## Box layers use a unit cube; the log layer uses a unit cylinder standing on its axis.
static func parts(s: Dictionary = {}) -> Array:
	if s.is_empty():
		s = spot()
	var out: Array = []
	var origin: Vector3 = s.pos
	var turn := Basis(Vector3.UP, s.rot)
	# Each part sits on the terrain right under it, so a bench on a slight slope doesn't float.
	var ground := func(local: Vector3) -> float:
		var w := origin + turn * Vector3(local.x, 0.0, local.z)
		return Terrain.height(w.x, w.z) - origin.y
	var put := func(part_name: String, layer: String, local: Vector3, size: Vector3, color: Color, tilt: Basis = Basis.IDENTITY) -> void:
		out.append({"name": part_name, "layer": layer, "color": color,
			"xform": Transform3D(turn * tilt * Basis.from_scale(size), origin + turn * local)})

	# Legs: four squat stone blocks, a little wider at the foot (two stacked blocks each).
	var lx := TOP_LENGTH * 0.5 - 0.2
	var lz := TOP_DEPTH * 0.5 - 0.14
	var top_y := TOP_HEIGHT
	var leg_i := 0
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var g: float = ground.call(Vector3(sx * lx, 0, sz * lz))
			var shade := BENCH_STONE.darkened(0.04 * leg_i)
			var foot_h := 0.22
			put.call("leg_foot", "BenchStone", Vector3(sx * lx, g + foot_h * 0.5 - 0.04, sz * lz), Vector3(0.34, foot_h, 0.32), shade.darkened(0.08),
				Basis(Vector3.UP, 0.12 * sx * sz))
			var leg_h := top_y - 0.1 - (g + foot_h - 0.04)
			put.call("leg", "BenchStone", Vector3(sx * lx, g + foot_h - 0.04 + leg_h * 0.5, sz * lz), Vector3(0.24, leg_h, 0.24), shade,
				Basis(Vector3.UP, -0.08 * sx))
			leg_i += 1
	# Rails: one long rail at each side just under the top, and a low shelf rail at the back.
	for sz in [-1.0, 1.0]:
		put.call("rail", "BenchWood", Vector3(0, top_y - 0.17, sz * lz), Vector3(TOP_LENGTH - 0.3, 0.1, 0.08), ASH_WOOD_DARK)
	put.call("shelf_rail", "BenchWood", Vector3(0, 0.34, -lz), Vector3(TOP_LENGTH - 0.42, 0.08, 0.1), ASH_WOOD_DARK.darkened(0.05))
	# Top: three thick planks with small gaps and slightly different tints, so it reads as planks.
	var plank_d := (TOP_DEPTH - 0.04) / 3.0
	for i in 3:
		var z := -TOP_DEPTH * 0.5 + plank_d * (i + 0.5) + 0.02 * i - 0.02
		var tint := ASH_WOOD.darkened(0.06 * ((i * 2) % 3)) # 0, 0.12, 0.06: no two neighbours alike
		var nudge := 0.03 * (i - 1) # planks don't line up perfectly at the ends
		put.call("plank", "BenchWood", Vector3(nudge, top_y - 0.05, z), Vector3(TOP_LENGTH, 0.1, plank_d - 0.02), tint)
	# On the top: a stone-headed hammer lying across the planks and a few stone chips.
	var hammer_turn := Basis(Vector3.UP, 0.5)
	var hpos := Vector3(0.38, top_y + 0.035, 0.08)
	put.call("hammer_handle", "BenchWood", hpos, Vector3(0.05, 0.05, 0.42), ASH_WOOD_DARK, hammer_turn)
	put.call("hammer_head", "BenchStone", hpos + hammer_turn * Vector3(0, 0.025, -0.2), Vector3(0.2, 0.11, 0.1), Palette.ROCK.darkened(0.2), hammer_turn)
	var chips := [[Vector3(-0.45, 0, -0.12), 0.11, 0.4], [Vector3(-0.3, 0, -0.22), 0.08, 1.3], [Vector3(-0.58, 0, 0.1), 0.07, 2.2]]
	for c in chips:
		var csz: float = c[1]
		put.call("chip", "BenchStone", c[0] + Vector3(0, top_y + csz * 0.3, 0), Vector3(csz, csz * 0.6, csz * 0.8), Palette.ROCK.lightened(0.08), Basis(Vector3.UP, c[2]))
	# A chopping block at the right end, with a split log leaning on it.
	var bx := TOP_LENGTH * 0.5 + 0.55
	var bg: float = ground.call(Vector3(bx, 0, 0.1))
	put.call("block", "BenchLogs", Vector3(bx, bg + 0.24, 0.1), Vector3(0.62, 0.52, 0.62), BARK)
	put.call("block_top", "BenchLogs", Vector3(bx, bg + 0.505, 0.1), Vector3(0.56, 0.02, 0.56), CUT_FACE)
	put.call("split_log", "BenchLogs", Vector3(bx + 0.34, bg + 0.3, 0.42), Vector3(0.24, 0.62, 0.24), BARK.lightened(0.05),
		Basis(Vector3.FORWARD, -0.38))
	# A little woodpile behind the bench: two cut logs side by side and one resting on them,
	# lying along its length, with pale cut ends showing at both sides.
	var lie := Basis(Vector3.FORWARD, PI * 0.5)
	var back := -TOP_DEPTH * 0.5 - 0.45
	var g2: float = ground.call(Vector3(0, 0, back))
	var logs := [ # [x centre, z offset, height above ground, radius*2, length, tint]
		[-0.2, 0.18, 0.17, 0.34, 1.1, BARK],
		[0.05, -0.18, 0.16, 0.32, 1.0, BARK.darkened(0.06)],
		[-0.05, 0.0, 0.45, 0.28, 0.9, BARK.lightened(0.06)],
	]
	for l in logs:
		var c := Vector3(l[0], g2 + l[2], back + l[1])
		put.call("log", "BenchLogs", c, Vector3(l[3], l[4], l[3]), l[5], lie)
		for side in [-1.0, 1.0]: # cut faces just proud of each end
			put.call("log_end", "BenchLogs", c + Vector3(side * (l[4] * 0.5 + 0.008), 0, 0), Vector3(l[3] - 0.04, 0.02, l[3] - 0.04), CUT_FACE, lie)
	# The lantern on the back-left corner (appended last, so every older part keeps its index):
	# an iron foot, the glowing glass held by four thin corner rods, a cap and a carry handle.
	var lp := Vector3(LANTERN_SPOT.x, top_y, LANTERN_SPOT.y)
	var gl := LANTERN_GLASS
	put.call("lantern_foot", "BenchStone", lp + Vector3(0, 0.025, 0), Vector3(0.21, 0.05, 0.21), Lamps.IRON)
	put.call("lantern_glass", GLASS_LAYER, lp + Vector3(0, 0.05 + gl.y * 0.5, 0), gl, Lamps.FLAME)
	for cx in [-1.0, 1.0]:
		for cz in [-1.0, 1.0]:
			put.call("lantern_rod", "BenchStone", lp + Vector3(cx * gl.x * 0.5, 0.05 + gl.y * 0.5, cz * gl.z * 0.5), Vector3(0.025, gl.y, 0.025), Lamps.IRON)
	var cap_y := 0.05 + gl.y
	put.call("lantern_cap", "BenchStone", lp + Vector3(0, cap_y + 0.025, 0), Vector3(0.23, 0.05, 0.23), Lamps.IRON)
	put.call("lantern_top", "BenchStone", lp + Vector3(0, cap_y + 0.07, 0), Vector3(0.12, 0.04, 0.12), Lamps.IRON.lightened(0.05))
	for hx in [-1.0, 1.0]:
		put.call("lantern_handle", "BenchStone", lp + Vector3(hx * 0.07, cap_y + 0.12, 0), Vector3(0.02, 0.08, 0.02), Lamps.IRON)
	put.call("lantern_handle", "BenchStone", lp + Vector3(0, cap_y + 0.165, 0), Vector3(0.16, 0.02, 0.02), Lamps.IRON)
	return out


## Where the bench lantern's light sits, in world space (the middle of its glass).
static func light_position(s: Dictionary = {}) -> Vector3:
	if s.is_empty():
		s = spot()
	var local := Vector3(LANTERN_SPOT.x, TOP_HEIGHT + 0.05 + LANTERN_GLASS.y * 0.5, LANTERN_SPOT.y)
	return s.pos + Basis(Vector3.UP, s.rot) * local


## The values apply_glow() sets for a night-glow level (Lamps.night_glow), as plain numbers.
static func glow_values(glow: float) -> Dictionary:
	var g := clampf(glow, 0.0, 1.0)
	return {
		"light_energy": LIGHT_ENERGY * g,
		"light_on": g > 0.01,
		"glass": lerpf(GLASS_DAY, GLASS_NIGHT, g),
	}


## {layer: Array of [Transform3D, Color]}.
static func layout(s: Dictionary = {}) -> Dictionary:
	var layers := {}
	for l in LAYERS:
		layers[l] = []
	for p in parts(s):
		layers[p.layer].append([p.xform, p.color])
	return layers


## The Workbench node WorldBuilder adds.
static func build() -> Node3D:
	var root := Node3D.new()
	root.name = "Workbench"
	var lay := layout()
	var meshes := _meshes()
	for l in LAYERS:
		root.add_child(_multimesh(l, meshes[l], lay[l], l == GLASS_LAYER))
	var omni := OmniLight3D.new()
	omni.name = "Light"
	omni.position = light_position()
	omni.light_color = Lamps.FLAME
	omni.light_energy = 0.0
	omni.omni_range = LIGHT_RANGE
	omni.omni_attenuation = 1.2
	omni.shadow_enabled = false
	omni.visible = false
	root.add_child(omni)
	root.add_child(_highlight_shell(meshes))
	return root


## Light the bench lantern for a night-glow level (0 by day, 1 at night). Safe on null.
static func apply_glow(bench: Node, glow: float) -> void:
	if bench == null:
		return
	var v := glow_values(glow)
	var omni := bench.get_node_or_null("Light") as OmniLight3D
	if omni:
		omni.light_energy = v.light_energy
		omni.visible = v.light_on
	var gi := bench.get_node_or_null(GLASS_LAYER) as GeometryInstance3D
	if gi and gi.material_override is ShaderMaterial: # shared with the meadow lanterns
		(gi.material_override as ShaderMaterial).set_shader_parameter("emission_energy", v.glass)


## Turn the bench's warm rim glow on or off (the client calls this while "[E] Use Workbench"
## shows). Fades over HIGHLIGHT_FADE when the bench is in the tree, else switches at once.
## Calling it again with the same value does nothing. Returns false if `bench` has no shell.
static func set_highlight(bench: Node, on: bool) -> bool:
	if bench == null:
		return false
	var shell := bench.get_node_or_null("Highlight") as Node3D
	if shell == null:
		return false
	if bool(bench.get_meta("lit", false)) == on:
		return true
	bench.set_meta("lit", on)
	var mat := shell.get_meta("material") as ShaderMaterial
	var target := HIGHLIGHT_STRENGTH if on else 0.0
	if bench.has_meta("fade"):
		var old := bench.get_meta("fade") as Tween
		if old and old.is_valid():
			old.kill()
		bench.remove_meta("fade")
	if on:
		shell.visible = true
	if not bench.is_inside_tree():
		mat.set_shader_parameter("strength", target)
		shell.visible = on
		return true
	var tw := bench.create_tween()
	tw.tween_method(func(v: float) -> void: mat.set_shader_parameter("strength", v),
		float(mat.get_shader_parameter("strength")), target, HIGHLIGHT_FADE)
	if not on:
		tw.tween_callback(func() -> void: shell.visible = false)
	bench.set_meta("fade", tw)
	return true


## True while the bench is highlighted.
static func highlighted(bench: Node) -> bool:
	return bench != null and bool(bench.get_meta("lit", false))


## Every highlight-shell transform: each part grown about its own centre, like a node's shell.
## {"box": Array of Transform3D, "log": Array of Transform3D}.
static func shell_layout(s: Dictionary = {}) -> Dictionary:
	var out := {"box": [], "log": []}
	for p in parts(s):
		out["log" if p.layer == "BenchLogs" else "box"].append(NodeFx.shell_xform(p.xform))
	return out


static func _highlight_shell(meshes: Dictionary) -> Node3D:
	var shell := Node3D.new()
	shell.name = "Highlight"
	shell.visible = false
	var mat := ShaderMaterial.new()
	mat.shader = NodeFx.rim_shader()
	mat.set_shader_parameter("rim_color", NodeFx.HIGHLIGHT)
	mat.set_shader_parameter("strength", 0.0)
	shell.set_meta("material", mat)
	var sl := shell_layout()
	for key in ["box", "log"]:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = meshes["BenchLogs" if key == "log" else "BenchWood"]
		mm.instance_count = sl[key].size()
		for i in sl[key].size():
			mm.set_instance_transform(i, sl[key][i])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Shell" + key.capitalize()
		mmi.multimesh = mm
		mmi.material_override = mat
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		shell.add_child(mmi)
	return shell


static func _meshes() -> Dictionary:
	var box := BoxMesh.new() # unit cube; each part is scaled to size
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.5
	cyl.bottom_radius = 0.5
	cyl.height = 1.0
	cyl.radial_segments = 7
	cyl.rings = 1
	# Baked like the rest of the world (art bible section 2): each part darkens toward its foot.
	var wood := Emberlight.bake(box, 0.25)
	return {"BenchWood": wood, "BenchStone": Emberlight.bake(box, 0.35, 1.4), "BenchLogs": Emberlight.bake(cyl, 0.3),
		"BenchGlass": Emberlight.bake(box, 0.0)}


static func _multimesh(node_name: String, mesh: Mesh, instances: Array, glow: bool = false) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = instances.size()
	for i in instances.size():
		mm.set_instance_transform(i, instances[i][0])
		mm.set_instance_color(i, (instances[i][1] as Color).srgb_to_linear())
	var mmi := MultiMeshInstance3D.new()
	mmi.name = node_name
	mmi.multimesh = mm
	mmi.material_override = Lamps.glass_material() if glow else Emberlight.material("solid")
	if glow: # the lantern glass: lit from the shared clock by apply_glow
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mmi
