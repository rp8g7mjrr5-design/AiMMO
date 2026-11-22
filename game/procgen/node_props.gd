class_name NodeProps
## The props players gather from: an ember ash, a pine, a stone outcrop and an ember-sap
## seep at every position in ResourceNodes.all(), each with a "depleted" look (a stump,
## rubble, a dried-out seep) for when gathering empties it.
##
## Resource nodes are drawn bigger and brighter than the decorative trees and rocks from
## Props.scatter, so players can tell at a glance what can be gathered.
##
## Split like AvatarBuilder: `parts()` and `layout()` are pure data (no renderer, safe in
## headless tests and bots); `build()` turns the layout into a few MultiMeshes, and
## `set_depleted()` swaps one node between its live and depleted look by showing and hiding
## its MultiMesh instances, so no meshes are created or freed while playing.

const LAYERS := ["NodeTrunks", "NodeAshCrowns", "NodePineTiers", "NodeStones", "NodeSapPools", "NodeStumps"]
const GLOW_LAYER := "NodeSapPools" ## drawn with a warm emissive material

## Colours. Live nodes are lifted above the decoration palette so they stand out.
const ASH_NODE_LEAF := Color(0.93, 0.50, 0.24)
const PINE_NODE := Color(0.18, 0.52, 0.33)
const STONE_NODE := Color(0.62, 0.60, 0.57)
const STONE_VEIN := Color(0.80, 0.76, 0.66) ## a pale quartz seam: "this rock is worth hitting"
const SAP_GLOW := Color(1.0, 0.55, 0.18)
const SAP_RIM := Color(0.30, 0.24, 0.20)
const SAP_DRY := Color(0.22, 0.19, 0.17)
const STUMP_CUT := Color(0.74, 0.60, 0.42) ## the pale cut face on top of a stump

## A collapsed basis hides a MultiMesh instance without resizing the MultiMesh.
const HIDDEN := Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO)


## Every part of one node's prop, in world space, as an Array of
## {layer: String, xform: Transform3D, color: Color}. Pure and deterministic: the same node
## always gives the same parts (small variations are seeded from the node id).
static func parts(node: Dictionary, depleted: bool = false) -> Array:
	var out: Array = []
	var s: float = node.scale
	var origin: Vector3 = node.pos
	var turn := Basis(Vector3.UP, node.rot)
	var rng := RandomNumberGenerator.new()
	rng.seed = GameConfig.WORLD_SEED + 211 + int(node.id) * 7919
	var put := func(layer: String, local_pos: Vector3, size: Vector3, color: Color, spin: float = 0.0) -> void:
		var b := (turn * Basis(Vector3.UP, spin)).scaled(size * s)
		out.append({"layer": layer, "xform": Transform3D(b, origin + turn * (local_pos * s)), "color": color})
	match node.kind:
		"ash":
			if depleted:
				_stump(put, Palette.TRUNK)
			else:
				put.call("NodeTrunks", Vector3(0, 1.4, 0), Vector3.ONE, Palette.TRUNK)
				put.call("NodeAshCrowns", Vector3(0, 3.5, 0), Vector3.ONE, ASH_NODE_LEAF)
				put.call("NodeAshCrowns", Vector3(0.35, 4.6, -0.2), Vector3.ONE * 0.62, ASH_NODE_LEAF.lightened(0.10 + rng.randf() * 0.08))
		"pine":
			if depleted:
				_stump(put, Palette.TRUNK.darkened(0.2))
			else:
				put.call("NodeTrunks", Vector3(0, 1.4, 0), Vector3.ONE, Palette.TRUNK.darkened(0.2))
				for tier in 4:
					var w := 1.0 - tier * 0.2
					put.call("NodePineTiers", Vector3(0, 2.4 + tier * 1.05, 0), Vector3(w, 1.0, w), PINE_NODE.lightened(tier * 0.05))
		"stone":
			if depleted:
				for i in 3: # low scattered rubble where the outcrop was
					var a := TAU * i / 3.0 + rng.randf() * 0.6
					put.call("NodeStones", Vector3(cos(a) * 0.9, 0.08, sin(a) * 0.9), Vector3(0.85, 0.32, 0.7), STONE_NODE.darkened(0.25), a)
			else:
				put.call("NodeStones", Vector3(0, 0.6, 0), Vector3(2.2, 1.8, 1.8), STONE_NODE)
				put.call("NodeStones", Vector3(1.2, 0.3, 0.5), Vector3(1.2, 1.0, 1.0), STONE_NODE.darkened(0.08), 0.9)
				put.call("NodeStones", Vector3(-1.0, 0.25, 0.7), Vector3(0.95, 0.8, 0.9), STONE_NODE.darkened(0.04 + rng.randf() * 0.06), 2.1)
				put.call("NodeStones", Vector3(0.2, 1.35, -0.3), Vector3(1.0, 0.35, 0.6), STONE_VEIN, 0.4)
		"ember_sap":
			# A ring of dark stones around a shallow pool. Live, the pool glows ember orange and
			# a few glowing shards poke up so the seep reads from a distance (and at night).
			for i in 5:
				var a := TAU * i / 5.0 + rng.randf() * 0.4
				put.call("NodeStones", Vector3(cos(a) * 0.95, 0.15, sin(a) * 0.95), Vector3(0.6, 0.5, 0.55), SAP_RIM, a)
			if depleted:
				put.call("NodeStumps", Vector3(0, 0.05, 0), Vector3(2.0, 0.1, 2.0), SAP_DRY)
			else:
				put.call("NodeSapPools", Vector3(0, 0.2, 0), Vector3(1.4, 0.3, 1.4), SAP_GLOW)
				for i in 3:
					var a := TAU * i / 3.0 + rng.randf() * 0.8
					var tall := 0.8 + rng.randf() * 0.5
					put.call("NodeSapPools", Vector3(cos(a) * 0.3, tall * 0.5, sin(a) * 0.3), Vector3(0.18, tall, 0.18), SAP_GLOW.lightened(0.15), a)
	return out


static func _stump(put: Callable, bark: Color) -> void:
	put.call("NodeStumps", Vector3(0, 0.25, 0), Vector3.ONE, bark)
	put.call("NodeStumps", Vector3(0, 0.51, 0), Vector3(0.85, 0.04, 0.85), STUMP_CUT)


## Both looks of every node, ready for MultiMeshes:
## {layers: {layer: Array of [Transform3D, Color]}, slots: {id: {live: [[layer, index]...],
## depleted: [[layer, index]...]}}}. Every node starts live, so its depleted parts begin
## hidden (their transforms are kept in `layers`; build() hides them).
static func layout(nodes: Array) -> Dictionary:
	var layers := {}
	for l in LAYERS:
		layers[l] = []
	var slots := {}
	for n in nodes:
		var slot := {"live": [], "depleted": []}
		for look in ["live", "depleted"]:
			for p in parts(n, look == "depleted"):
				slot[look].append([p.layer, layers[p.layer].size()])
				layers[p.layer].append([p.xform, p.color])
		slots[n.id] = slot
	return {"layers": layers, "slots": slots}


## The node that draws every resource node. Call set_depleted() on it to change a look.
static func build(nodes: Array = []) -> Node3D:
	if nodes.is_empty():
		nodes = ResourceNodes.all()
	var lay := layout(nodes)
	var root := Node3D.new()
	root.name = "ResourceNodes"
	root.set_meta("layout", lay)
	var meshes := _meshes()
	for l in LAYERS:
		var mmi := _multimesh(l, meshes[l], lay.layers[l], l == GLOW_LAYER)
		root.add_child(mmi)
	for id in lay.slots:
		_show(root, lay.slots[id].depleted, false)
	return root


## Switch node `id` between its live and depleted look. Returns false for an unknown id.
static func set_depleted(root: Node3D, id: int, depleted: bool) -> bool:
	var lay: Dictionary = root.get_meta("layout", {})
	if not lay.get("slots", {}).has(id):
		return false
	var slot: Dictionary = lay.slots[id]
	_show(root, slot.live, not depleted)
	_show(root, slot.depleted, depleted)
	return true


static func _show(root: Node3D, entries: Array, visible: bool) -> void:
	var lay: Dictionary = root.get_meta("layout")
	for e in entries:
		var mm := (root.get_node(e[0]) as MultiMeshInstance3D).multimesh
		var xf: Transform3D = lay.layers[e[0]][e[1]][0]
		mm.set_instance_transform(e[1], xf if visible else Transform3D(HIDDEN, xf.origin))


static func _meshes() -> Dictionary:
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.24
	trunk.bottom_radius = 0.36
	trunk.height = 2.8
	trunk.radial_segments = 6
	trunk.rings = 1
	var crown := SphereMesh.new()
	crown.radius = 1.9
	crown.height = 3.0
	crown.radial_segments = 7
	crown.rings = 3
	var tier := CylinderMesh.new()
	tier.top_radius = 0.0
	tier.bottom_radius = 1.6
	tier.height = 2.5
	tier.radial_segments = 7
	tier.rings = 1
	var stone := SphereMesh.new()
	stone.radius = 0.5
	stone.height = 1.0
	stone.radial_segments = 5
	stone.rings = 2
	var pool := SphereMesh.new()
	pool.radius = 0.5
	pool.height = 1.0
	pool.radial_segments = 8
	pool.rings = 2
	var stump := CylinderMesh.new()
	stump.top_radius = 0.34
	stump.bottom_radius = 0.42
	stump.height = 0.5
	stump.radial_segments = 6
	stump.rings = 1
	return {"NodeTrunks": trunk, "NodeAshCrowns": crown, "NodePineTiers": tier, "NodeStones": stone, "NodeSapPools": pool, "NodeStumps": stump}


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
		mat.roughness = 0.35
		mat.emission_enabled = true
		mat.emission = SAP_GLOW
		mat.emission_energy_multiplier = 0.9
	elif node_name == "NodeAshCrowns":
		Lamps.add_ember_emission(mat) # lit at night by Lamps.apply_glow
	var mmi := MultiMeshInstance3D.new()
	mmi.name = node_name
	mmi.multimesh = mm
	mmi.material_override = mat
	if glow:
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mmi
