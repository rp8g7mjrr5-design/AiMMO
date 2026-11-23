class_name Lamps
## Lanterns around the Spawn Meadow, and the faint night glow of the ember ash.
##
## The settlers keep a ring of lanterns lit around the meadow where everyone arrives, so
## the first thing a new player sees at night is a warm, gathered-together place. The ember
## ash leaves give off a faint warmth of their own after dark (the bible: they are warm to
## the touch; something under the valley is breathing), and the ember-sap seeps, which can
## only be gathered at night, brighten so players can find them.
##
## Split like NodeProps: `positions()`, `parts()`, `layout()` and `night_glow()` are pure
## data (safe headless, in unit tests and bots). `build()` makes the "Lamps" node with
## MultiMeshes and one OmniLight per lantern. `apply_glow(world, glow)` is called by
## DayNight on every repaint and sets lamp light, lantern glass, ash-leaf and sap emission
## from one number, so nothing is created or freed while playing.

const COUNT := 8 ## lanterns in the ring
const RING_RADIUS := 9.0 ## metres from spawn: inside the clear meadow, outside the bustle at the centre
const NODE_CLEARANCE := 2.5 ## never stand a lantern on a resource node
const POST_HEIGHT := 2.3
const LAYERS := ["LampWood", "LampIron", "LampGlass"]
const GLASS_LAYER := "LampGlass"

const WOOD := Color(0.36, 0.25, 0.17)
const IRON := Color(0.17, 0.16, 0.16)
const FLAME := Color(1.0, 0.56, 0.24) ## lantern light: warmer than the moon, softer than the sun
const EMBER := Color(1.0, 0.42, 0.14) ## the ash leaves' own warmth

## How bright each night-lit thing gets at full night (glow = 1). By day glow is 0.
const LIGHT_ENERGY := 1.6
const LIGHT_RANGE := 11.0
const GLASS_DAY := 0.15 ## unlit glass still catches a little light
const GLASS_NIGHT := 1.3
const ASH_GLOW := 0.10 ## faint: you notice it, it never looks like a light bulb
const NODE_ASH_GLOW := 0.14 ## gatherable ash a touch brighter, so it reads as special at night
const SAP_DAY := 0.9 ## matches NodeProps' daytime sap emission
const SAP_NIGHT := 1.6


## Where each lantern stands: an Array of {pos: Vector3 (on the ground), rot: float}.
## A ring around spawn, turned by the world seed so it isn't axis-aligned, and nudged
## outward if a resource node is in the way. Deterministic on every machine.
static func positions() -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = GameConfig.WORLD_SEED + 301
	var turn := rng.randf() * TAU
	var out: Array = []
	for i in COUNT:
		var a := turn + TAU * i / COUNT
		var r := RING_RADIUS + rng.randf_range(-0.6, 0.6)
		var p := Vector3.ZERO
		for _step in 8:
			p = GameConfig.SPAWN_POINT + Vector3(cos(a) * r, 0.0, sin(a) * r)
			if ResourceNodes.near(p, NODE_CLEARANCE).is_empty():
				break
			r += 1.0
		p.y = Terrain.height(p.x, p.z)
		# Face the lantern arm away from spawn so the light hangs over the path round the meadow.
		out.append({"pos": p, "rot": -a + PI * 0.5})
	return out


## Every part of one lantern in world space: Array of {layer, xform, color}.
## A wooden post on a stone foot, a short arm, and a hanging iron-capped lantern.
static func parts(lamp: Dictionary) -> Array:
	var out: Array = []
	var origin: Vector3 = lamp.pos
	var turn := Basis(Vector3.UP, lamp.rot)
	var put := func(layer: String, local_pos: Vector3, size: Vector3, color: Color, tilt: Basis = Basis.IDENTITY) -> void:
		out.append({"layer": layer, "xform": Transform3D(turn * tilt * Basis.from_scale(size), origin + turn * local_pos), "color": color})
	put.call("LampIron", Vector3(0, 0.08, 0), Vector3(0.5, 0.16, 0.5), Palette.ROCK.darkened(0.15)) # stone foot
	put.call("LampWood", Vector3(0, POST_HEIGHT * 0.5, 0), Vector3(0.14, POST_HEIGHT, 0.14), WOOD) # post
	put.call("LampWood", Vector3(0.28, POST_HEIGHT - 0.08, 0), Vector3(0.09, 0.62, 0.09), WOOD, Basis(Vector3.FORWARD, PI * 0.5)) # arm, a post lying along +x
	var hang := Vector3(0.52, POST_HEIGHT - 0.42, 0)
	put.call("LampIron", hang + Vector3(0, 0.22, 0), Vector3(0.34, 0.1, 0.34), IRON) # cap
	put.call("LampIron", hang - Vector3(0, 0.2, 0), Vector3(0.28, 0.06, 0.28), IRON) # base
	put.call("LampGlass", hang, Vector3(0.24, 0.34, 0.24), FLAME) # the glowing glass
	return out


## Where the lantern's light sits, in world space.
static func light_position(lamp: Dictionary) -> Vector3:
	return lamp.pos + Basis(Vector3.UP, lamp.rot) * Vector3(0.52, POST_HEIGHT - 0.42, 0)


## {layer: Array of [Transform3D, Color]} for every lantern.
static func layout(lamps: Array) -> Dictionary:
	var layers := {}
	for l in LAYERS:
		layers[l] = []
	for lamp in lamps:
		for p in parts(lamp):
			layers[p.layer].append([p.xform, p.color])
	return layers


## 0 by day, 1 at night. The settlers light the lanterns a little before sunset and put them
## out a little after sunrise, so the lamps are already on when the sky turns orange.
static func night_glow(frac: float) -> float:
	return smoothstep(0.14, -0.06, SkyClock.sun_height(frac))


## The values apply_glow() sets for a glow level, as plain numbers (tested headless).
static func glow_values(glow: float) -> Dictionary:
	var g := clampf(glow, 0.0, 1.0)
	return {
		"light_energy": LIGHT_ENERGY * g,
		"lights_on": g > 0.01,
		"glass": lerpf(GLASS_DAY, GLASS_NIGHT, g),
		"ash": ASH_GLOW * g,
		"node_ash": NODE_ASH_GLOW * g,
		"sap": lerpf(SAP_DAY, SAP_NIGHT, g),
	}


## The Lamps node WorldBuilder adds.
static func build(lamps: Array = []) -> Node3D:
	if lamps.is_empty():
		lamps = positions()
	var root := Node3D.new()
	root.name = "Lamps"
	var lay := layout(lamps)
	var meshes := _meshes()
	for l in LAYERS:
		root.add_child(_multimesh(l, meshes[l], lay[l], l == GLASS_LAYER))
	var lights := Node3D.new()
	lights.name = "Lights"
	root.add_child(lights)
	for i in lamps.size():
		var omni := OmniLight3D.new()
		omni.name = "Lamp%d" % i
		omni.position = light_position(lamps[i])
		omni.light_color = FLAME
		omni.light_energy = 0.0
		omni.omni_range = LIGHT_RANGE
		omni.omni_attenuation = 1.4
		omni.shadow_enabled = false # 8 shadowed omni lights is too much for a low-end laptop
		omni.visible = false
		lights.add_child(omni)
	return root


## Light everything that glows at night in `world` (WorldBuilder's root). Missing pieces are
## skipped, so this is safe on a partial world.
static func apply_glow(world: Node, glow: float) -> void:
	if world == null:
		return
	var v := glow_values(glow)
	var lights := world.get_node_or_null("Lamps/Lights")
	if lights:
		for omni in lights.get_children():
			(omni as OmniLight3D).light_energy = v.light_energy
			(omni as OmniLight3D).visible = v.lights_on
	_set_emission(world.get_node_or_null("Lamps/" + GLASS_LAYER), v.glass)
	_set_emission(world.get_node_or_null("AshCrowns"), v.ash)
	_set_emission(world.get_node_or_null("ResourceNodes/NodeAshCrowns"), v.node_ash)
	_set_emission(world.get_node_or_null("ResourceNodes/" + NodeProps.GLOW_LAYER), v.sap)
	Workbench.apply_glow(world.get_node_or_null("Workbench"), glow)


static func _set_emission(n: Node, energy: float) -> void:
	var gi := n as GeometryInstance3D
	if gi == null:
		return
	if gi.material_override is ShaderMaterial: # Emberlight: the heartbeat swells it in the shader
		(gi.material_override as ShaderMaterial).set_shader_parameter("emission_energy", energy)
		return
	var mat := gi.material_override as StandardMaterial3D
	if mat == null or not mat.emission_enabled:
		return
	mat.emission_energy_multiplier = energy


## The shared Emberlight foliage material for ember ash leaves: their warmth is off by day
## and apply_glow turns it up at night, beating with the valley's heartbeat.
static func ember_leaf_material() -> ShaderMaterial:
	var m := Emberlight.material("foliage", "ash_leaf")
	m.set_shader_parameter("emission_color", EMBER)
	return m


## Give a leaf material its ember warmth (off until apply_glow turns it up at night).
static func add_ember_emission(mat: StandardMaterial3D) -> void:
	mat.emission_enabled = true
	mat.emission = EMBER
	mat.emission_energy_multiplier = 0.0


static func _meshes() -> Dictionary:
	var post := CylinderMesh.new()
	post.top_radius = 0.5
	post.bottom_radius = 0.5
	post.height = 1.0
	post.radial_segments = 6
	post.rings = 1
	var iron := CylinderMesh.new() # caps and the stone foot: a squat hexagon
	iron.top_radius = 0.38
	iron.bottom_radius = 0.5
	iron.height = 1.0
	iron.radial_segments = 6
	iron.rings = 1
	var glass := CylinderMesh.new()
	glass.top_radius = 0.42
	glass.bottom_radius = 0.5
	glass.height = 1.0
	glass.radial_segments = 6
	glass.rings = 1
	return {"LampWood": post, "LampIron": iron, "LampGlass": glass}


static func _multimesh(node_name: String, mesh: Mesh, instances: Array, glow: bool) -> MultiMeshInstance3D:
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
	mat.roughness = 0.9
	if glow:
		mat.roughness = 0.3
		mat.emission_enabled = true
		mat.emission = FLAME
		mat.emission_energy_multiplier = GLASS_DAY
	var mmi := MultiMeshInstance3D.new()
	mmi.name = node_name
	mmi.multimesh = mm
	mmi.material_override = mat
	if glow:
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mmi
