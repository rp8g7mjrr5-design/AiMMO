class_name WorldBuilder
## Assembles the visible world: terrain chunks, water, trees, rocks, flora (birches, mossy boulders,
## wildflowers), resource nodes, the Spawn Meadow
## lanterns and workbench, sky, sun, and fog.
## Everything is generated here from code and the shared world seed.
## A DayNight child moves the sun, repaints the sky, and lights the lamps with the time of day.


static func build() -> Node3D:
	var root := Node3D.new()
	root.name = "World"
	var we := _environment()
	var sun := _sun()
	root.add_child(we)
	root.add_child(sun)
	DayNight.pin_from_env()
	var dn := DayNight.new()
	dn.name = "DayNight"
	dn.env = we.environment
	dn.sky_mat = we.environment.sky.sky_material as ShaderMaterial
	dn.sun = sun
	root.add_child(dn)
	root.add_child(_terrain())
	root.add_child(_water())
	for n in _props():
		root.add_child(n)
	root.add_child(Flora.build())
	root.add_child(NodeProps.build())
	root.add_child(Lamps.build())
	root.add_child(Workbench.build())
	dn.apply(DayNight.now_fraction()) # light the lamps and leaves now that they exist
	WorldSolids.all() # build the camera's decoration solids now (~0.15 s), not on the first camera frame
	return root


static func _environment() -> WorldEnvironment:
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = DayNight.sky_shader() # colours are set by DayNight; the ground colour matches the fog so the world edge fades out
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.5
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = Color(0.85, 0.78, 0.70)
	env.fog_density = 0.006
	env.fog_sky_affect = 0.3
	var we := WorldEnvironment.new()
	we.environment = env
	return we


static func _sun() -> DirectionalLight3D:
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-38, -35, 0) # DayNight takes over from the first frame
	sun.light_color = Color(1.0, 0.92, 0.80)
	sun.light_energy = 1.0
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 120.0
	return sun


static func _terrain() -> Node3D:
	var node := Node3D.new()
	node.name = "Terrain"
	var mat := TerrainMesh.material()
	var span := TerrainMesh.CELL * TerrainMesh.CHUNK_CELLS
	var half := GameConfig.WORLD_HALF_SIZE
	var z := -half
	while z < half:
		var x := -half
		while x < half:
			var mi := MeshInstance3D.new()
			mi.mesh = TerrainMesh.build_chunk(x, z)
			mi.material_override = mat
			node.add_child(mi)
			x += span
		z += span
	return node


static func _water() -> MeshInstance3D:
	var pm := PlaneMesh.new()
	pm.size = Vector2(GameConfig.WORLD_HALF_SIZE * 2.0, GameConfig.WORLD_HALF_SIZE * 2.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Palette.WATER
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 0.15
	mat.metallic = 0.1
	var mi := MeshInstance3D.new()
	mi.name = "Water"
	mi.mesh = pm
	mi.material_override = mat
	mi.position.y = Terrain.water_level()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


const SCATTER_LAYERS := ["Trunks", "AshCrowns", "PineTiers", "Rocks"]


## The decorative scatter's meshes, one per layer.
static func scatter_meshes() -> Dictionary:
	var trunk_mesh := CylinderMesh.new()
	trunk_mesh.top_radius = 0.18
	trunk_mesh.bottom_radius = 0.28
	trunk_mesh.height = 2.4
	trunk_mesh.radial_segments = 6
	trunk_mesh.rings = 1
	var crown_mesh := SphereMesh.new() # ash crowns: chunky low-poly balls
	crown_mesh.radius = 1.6
	crown_mesh.height = 2.6
	crown_mesh.radial_segments = 7
	crown_mesh.rings = 3
	var cone_mesh := CylinderMesh.new() # pine tiers
	cone_mesh.top_radius = 0.0
	cone_mesh.bottom_radius = 1.4
	cone_mesh.height = 2.4
	cone_mesh.radial_segments = 7
	cone_mesh.rings = 1
	var rock_mesh := SphereMesh.new()
	rock_mesh.radius = 0.8
	rock_mesh.height = 1.0
	rock_mesh.radial_segments = 5
	rock_mesh.rings = 2
	# Baked vertex colours (Emberlight): dark where the part meets the ground or the trunk,
	# lightening up its height. Same vertices as the primitive meshes, so the camera solids
	# and the forest's look-from-afar are unchanged.
	return {
		"Trunks": Emberlight.bake(trunk_mesh, 0.45, 1.6),
		"AshCrowns": Emberlight.bake(crown_mesh, 0.35),
		"PineTiers": Emberlight.bake(cone_mesh, 0.40),
		"Rocks": Emberlight.bake(rock_mesh, 0.40, 1.5),
	}


## Which shared Emberlight material each scatter layer uses.
static func scatter_material(layer: String) -> ShaderMaterial:
	match layer:
		"AshCrowns":
			return Lamps.ember_leaf_material() # foliage, plus the leaves' night glow
		"PineTiers":
			return Emberlight.material("foliage")
		_:
			return Emberlight.material("solid")


## Every part of every decorative scatter tree and rock, one Array of {layer, xform, color}
## per `Props.scatter()` item, in the same order. Pure and deterministic (colours come from
## their own seeded rng, drawn in item order, exactly as the forest has always been drawn).
static func scatter_parts(items: Array) -> Array:
	var out: Array = []
	var rng := RandomNumberGenerator.new()
	rng.seed = GameConfig.WORLD_SEED + 11
	for it in items:
		var parts: Array = []
		var basis := Basis(Vector3.UP, it.rot).scaled(Vector3.ONE * it.scale)
		var p: Vector3 = it.pos
		match it.kind:
			"ash":
				parts.append({"layer": "Trunks", "xform": Transform3D(basis, p + Vector3.UP * 1.2 * it.scale), "color": Palette.TRUNK})
				var leaf := Palette.ASH_LEAF.lerp(Color(0.95, 0.70, 0.35), rng.randf() * 0.5)
				parts.append({"layer": "AshCrowns", "xform": Transform3D(basis, p + Vector3.UP * 3.2 * it.scale), "color": leaf})
			"pine":
				parts.append({"layer": "Trunks", "xform": Transform3D(basis, p + Vector3.UP * 1.2 * it.scale), "color": Palette.TRUNK.darkened(0.2)})
				for tier in 3:
					var s := 1.0 - tier * 0.25
					parts.append({"layer": "PineTiers", "xform": Transform3D(basis.scaled(Vector3(s, 1.0, s)), p + Vector3.UP * (2.2 + tier * 1.1) * it.scale), "color": Palette.PINE.lightened(tier * 0.05)})
			_:
				var squash := Basis(Vector3.UP, it.rot).scaled(Vector3(it.scale * 1.3, it.scale * 0.8, it.scale))
				parts.append({"layer": "Rocks", "xform": Transform3D(squash, p + Vector3.UP * 0.2), "color": Palette.ROCK.darkened(rng.randf() * 0.15)})
		out.append(parts)
	return out


static func _props() -> Array:
	var meshes := scatter_meshes()
	var layers := {}
	for l in SCATTER_LAYERS:
		layers[l] = []
	for parts in scatter_parts(Props.scatter()):
		for p in parts:
			layers[p.layer].append([p.xform, p.color])
	var out: Array = []
	for l in SCATTER_LAYERS:
		out.append(_multimesh(l, meshes[l], layers[l]))
	return out


static func _multimesh(node_name: String, mesh: Mesh, instances: Array) -> MultiMeshInstance3D:
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
	mmi.material_override = scatter_material(node_name)
	return mmi
