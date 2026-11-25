class_name WorldBuilder
## Assembles the visible world: terrain chunks, water, trees, rocks, flora (birches, mossy boulders,
## wildflowers), resource nodes, the Spawn Meadow
## lanterns and workbench, sky, sun, and fog.
## Everything is generated here from code and the shared world seed.
## A DayNight child moves the sun, repaints the sky, and lights the lamps with the time of day.

const HAZE_TOP := 3.0 ## metres: height haze thickens below this (the meadow floor is ~0-1.5 m)
const HAZE_DENSITY := 0.02 ## extra fog density per metre below HAZE_TOP; gentle, it must not hide the meadow
const GRADE_SATURATION := 0.92 ## whole-frame saturation: grounded, never candy
const GRADE_CONTRAST := 1.10 ## a little more weight in the darks
const SUN_SCATTER := 0.22 ## how much the haze glows when you look towards the sun
const SSAO_RADIUS := 1.0 ## m: contact shadow reaches about a hand's breadth to a stride
const SSAO_INTENSITY := 1.6


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
	root.add_child(Grass.build()) # tufts near the camera only, one draw call
	root.add_child(NodeProps.build())
	root.add_child(Lamps.build())
	root.add_child(Workbench.build())
	root.add_child(CampfireProps.build()) # hidden and empty until the server says a fire burns
	root.add_child(Motes.build())
	var ranges := Chunks.RangeWatch.new() # Low pulls chunk draw distances in (Chunks.RANGE_SCALES)
	ranges.name = "RangeWatch"
	root.add_child(ranges)
	root.set_meta("range_scale", Chunks.quality_range_scale())
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
	env.ambient_light_energy = SkyClock.DAY_AMBIENT
	env.ambient_light_sky_contribution = SkyClock.DAY_SKY_SHARE # DayNight moves it with the sky
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	# The grade (art bible section 5): a touch less saturation and a touch more contrast over
	# everything, so the whole frame sits in one muted, grounded key. Runs in the tonemap pass
	# Godot draws anyway, so it costs nothing.
	env.adjustment_enabled = true
	env.adjustment_saturation = GRADE_SATURATION
	env.adjustment_contrast = GRADE_CONTRAST
	# Contact shadow (art bible "Model direction", the test camp): soft darkening where trunks,
	# rocks, walls and feet meet the ground and each other, so nothing looks pasted on. Medium
	# and High only, half resolution; Forward+ draws it, Compatibility ignores it.
	env.ssao_enabled = _quality_ao()
	env.ssao_radius = SSAO_RADIUS
	env.ssao_intensity = SSAO_INTENSITY
	env.ssao_light_affect = 0.15
	env.fog_enabled = true
	env.fog_light_color = Color(0.85, 0.78, 0.70)
	env.fog_density = 0.0045 # lighter air than before (the test camp), still about 93% solid at the 600 m draw distance
	env.fog_sky_affect = 0.3
	# Height haze (art bible section 5): the valley floors and lake hollows fill with warm HAZE
	# by day and blue NIGHT_HAZE after dark (DayNight sets the colour); the hills stand clear of it.
	env.fog_height = HAZE_TOP
	env.fog_height_density = HAZE_DENSITY
	# Looking into a low sun, the haze lights up gold: golden hour you can see in the air.
	env.fog_sun_scatter = SUN_SCATTER
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
	# Two cascades, not Godot's default four: every cascade draws each shadow-casting chunk
	# again, and at 60 to 120 m of shadow two are plenty for chunky low-poly shapes.
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	return sun


static func _terrain() -> Node3D:
	var node := Node3D.new()
	node.name = "Terrain"
	var mat := TerrainMesh.material()
	var span := TerrainMesh.CELL * TerrainMesh.CHUNK_CELLS
	var half := WorldGen.half_size()
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
	pm.size = Vector2(WorldGen.half_size() * 2.0, WorldGen.half_size() * 2.0)
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
	trunk_mesh.top_radius = 0.22 # grounded: a trunk that could hold its crown, not a lollipop stick
	trunk_mesh.bottom_radius = 0.36
	trunk_mesh.height = 2.4
	trunk_mesh.radial_segments = 6
	trunk_mesh.rings = 1
	var crown_mesh := SphereMesh.new() # ash crowns: broad, heavy canopy lobes (two per tree), never a ball on a stick
	crown_mesh.radius = 1.6
	crown_mesh.height = 3.0
	crown_mesh.radial_segments = 6 # two lobes per tree now, so each is a little cheaper (render budget)
	crown_mesh.rings = 2
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
		"AshCrowns": Emberlight.bake(crown_mesh, 0.5), # heavy shade under the canopy
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
		"Trunks":
			return Emberlight.painted("bark")
		"Rocks":
			return Emberlight.painted("stone")
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
				var leaf := Palette.ASH_LEAF.lerp(Palette.ASH_LEAF_DRY, rng.randf() * 0.6)
				# Two overlapping canopy lobes, the second smaller, lower and off to one side
				# (from the tree's own rotation, no rng draw), so the silhouette is lopsided and
				# heavy like a real crown instead of a lollipop (art bible, "Shape language").
				parts.append({"layer": "AshCrowns", "xform": Transform3D(basis, p + Vector3.UP * 3.4 * it.scale), "color": leaf})
				var side: Vector3 = Vector3(cos(it.rot), 0.0, sin(it.rot)) * 1.15 * float(it.scale)
				parts.append({"layer": "AshCrowns", "xform": Transform3D(basis.scaled(Vector3.ONE * 0.62), p + side + Vector3.UP * 2.9 * it.scale), "color": leaf.darkened(0.08)})
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


## The scatter forest's instances per layer: {layer: Array of [Transform3D, Color]}.
static func scatter_layout() -> Dictionary:
	var layers := {}
	for l in SCATTER_LAYERS:
		layers[l] = []
	for parts in scatter_parts(Props.scatter()):
		for p in parts:
			layers[p.layer].append([p.xform, p.color])
	return layers


## One chunked node per scatter layer (`Chunks`: the camera and the shadow passes cull by area,
## and far chunks fade into the haze).
static func _props() -> Array:
	var meshes := scatter_meshes()
	var layers := scatter_layout()
	var out: Array = []
	for l in SCATTER_LAYERS:
		out.append(Chunks.build(l, meshes[l], layers[l], scatter_material(l)))
	return out


## The client's `Quality.ambient_occlusion()`, loaded by path like `Flora.quality_density()`
## (the server export leaves `client/` out); off where the client code isn't there.
static func _quality_ao() -> bool:
	if not ResourceLoader.exists(Flora.QUALITY_SCRIPT):
		return false
	var q: Script = load(Flora.QUALITY_SCRIPT)
	return bool(q.call("ambient_occlusion"))
