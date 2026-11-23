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
## Split like Lamps: `spot()`, `parts()` and `layout()` are pure data (safe headless, in unit
## tests and bots); `build()` makes the "Workbench" node from three MultiMesh layers.

const TOP_HEIGHT := 0.92 ## metres from the ground to the top of the planks (a good standing height)
const TOP_LENGTH := 1.8
const TOP_DEPTH := 0.84
const FOOTPRINT := 2.0 ## metres from the bench's centre that its parts (block, logs) reach
const CLEARANCE := 2.5 ## nothing else (lanterns, nodes, trees, flowers) stands this close
const LAYERS := ["BenchWood", "BenchStone", "BenchLogs"]

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
	return out


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
		root.add_child(_multimesh(l, meshes[l], lay[l]))
	return root


static func _meshes() -> Dictionary:
	var box := BoxMesh.new() # unit cube; each part is scaled to size
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.5
	cyl.bottom_radius = 0.5
	cyl.height = 1.0
	cyl.radial_segments = 7
	cyl.rings = 1
	return {"BenchWood": box, "BenchStone": box, "BenchLogs": cyl}


static func _multimesh(node_name: String, mesh: Mesh, instances: Array) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = instances.size()
	for i in instances.size():
		mm.set_instance_transform(i, instances[i][0])
		mm.set_instance_color(i, (instances[i][1] as Color).srgb_to_linear())
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.85
	var mmi := MultiMeshInstance3D.new()
	mmi.name = node_name
	mmi.multimesh = mm
	mmi.material_override = mat
	return mmi
