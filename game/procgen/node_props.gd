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

const LAYERS := ["NodeTrunks", "NodeAshCrowns", "NodePineTiers", "NodeStones", "NodeSapPools", "NodeStumps", "NodeDetail"]
const GLOW_LAYER := "NodeSapPools" ## drawn with a warm emissive material
## Small boxes that only matter up close, behind the action camera's shoulder: root flares
## and bark ridges on trees and stumps, quartz studs along the outcrop's seam. Shadowless.
const DETAIL_LAYER := "NodeDetail"

## Colours. Live nodes are lifted above the decoration palette so they stand out.
const ASH_NODE_LEAF := Color(0.93, 0.50, 0.24)
const PINE_NODE := Color(0.18, 0.52, 0.33)
const STONE_NODE := Color(0.62, 0.60, 0.57)
const STONE_VEIN := Color(0.80, 0.76, 0.66) ## a pale quartz seam: "this rock is worth hitting"
const SAP_GLOW := Color(1.0, 0.55, 0.18)
const SAP_RIM := Color(0.30, 0.24, 0.20)
const SAP_DRY := Color(0.22, 0.19, 0.17)
const STUMP_CUT := Color(0.74, 0.60, 0.42) ## the pale cut face on top of a stump
const SEAM_STUD := Color(0.84, 0.80, 0.70) ## quartz studs along the outcrop's seam

## The solid shape of each kind of prop, as vertical columns [radius, bottom, top] in metres
## at scale 1, relative to the node's ground position (multiply by the node's scale; see
## solid_columns()). Every part of both looks (live and depleted) fits inside them, which a
## unit test checks vertex by vertex, so a camera kept outside them never sees inside a mesh.
const SOLID_COLUMNS := {
	"ash": [[0.8, 0.0, 0.4], [0.42, 0.0, 2.0], [1.45, 2.0, 2.5], [1.92, 2.5, 5.0], [1.6, 5.0, 5.55]],
	"pine": [[0.8, 0.0, 0.4], [0.42, 0.0, 1.15], [1.62, 1.15, 2.2], [1.3, 2.2, 3.25], [0.98, 3.25, 4.3], [0.66, 4.3, 6.8]],
	"stone": [[1.95, 0.0, 0.85], [1.15, 0.85, 1.56]],
	"ember_sap": [[1.3, 0.0, 0.45], [0.42, 0.45, 1.32]],
}

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
	# Close-up detail. Added after every older part (and with its own rng) so the older parts,
	# their order and their colours are exactly as before.
	var put_detail := func(local_basis: Basis, local_pos: Vector3, size: Vector3, color: Color) -> void:
		var b := turn * local_basis * Basis.from_scale(size * s)
		out.append({"layer": DETAIL_LAYER, "xform": Transform3D(b, origin + turn * (local_pos * s)), "color": color})
	var drng := RandomNumberGenerator.new()
	drng.seed = GameConfig.WORLD_SEED + 227 + int(node.id) * 7919
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
	match node.kind:
		"ash", "pine":
			var bark: Color = Palette.TRUNK if node.kind == "ash" else Palette.TRUNK.darkened(0.2)
			_roots(put_detail, drng, bark)
			if not depleted:
				_bark_ridges(put_detail, drng, bark, node.kind == "ash")
		"stone":
			if not depleted:
				_seam_studs(put_detail, drng, node.rot)
	return out


## Three root flares where the trunk meets the ground, so a tree (or its stump) grows out of
## the slope instead of standing on it like a post.
static func _roots(put_detail: Callable, rng: RandomNumberGenerator, bark: Color) -> void:
	var start := rng.randf() * TAU
	for i in 3:
		var a := start + TAU * i / 3.0 + rng.randf_range(-0.35, 0.35)
		var out_dir := Vector3(cos(a), 0.0, sin(a))
		var b := Basis(Vector3.UP, atan2(out_dir.x, out_dir.z)) * Basis(Vector3.RIGHT, deg_to_rad(24.0))
		var length := rng.randf_range(0.5, 0.62)
		put_detail.call(b, out_dir * 0.42 + Vector3(0, 0.1, 0), Vector3(0.2, 0.2, length), bark.darkened(0.08))


## Bark ridges on the trunk: dark fissures on the pale-barked ash, lighter reddish plates on
## the pine. They break up the flat six-sided trunk the camera sees from 3 m.
static func _bark_ridges(put_detail: Callable, rng: RandomNumberGenerator, bark: Color, ash: bool) -> void:
	var color := bark.darkened(0.3) if ash else bark.lightened(0.12).lerp(Color(0.55, 0.30, 0.20), 0.25)
	var start := rng.randf() * TAU
	for i in 4:
		var a := start + TAU * i / 4.0 + rng.randf_range(-0.3, 0.3)
		var y := 0.65 + (i % 2) * 0.85 + rng.randf_range(-0.15, 0.15)
		var r := 0.36 - 0.12 * y / 2.8 # the trunk's radius at this height
		var b := Basis(Vector3.UP, a + PI * 0.5)
		put_detail.call(b, Vector3(cos(a), 0.0, -sin(a)) * (r - 0.005) + Vector3(0, y, 0), Vector3(0.06, rng.randf_range(0.7, 1.0), 0.1), color)


## Pale quartz studs set along a rising seam across the outcrop's big stone, the close-up
## version of "this rock is worth hitting". The big stone is an ellipsoid with world-axis
## half sizes (1.1, 0.9, 0.9) round local (0, 0.6, 0) (see parts()), so each stud sits on
## its surface with its flat face along the surface normal.
static func _seam_studs(put_detail: Callable, rng: RandomNumberGenerator, rot: float) -> void:
	var half := Vector3(1.1, 0.9, 0.9)
	var unturn := Basis(Vector3.UP, -rot) # the stone is drawn in world axes; studs go in node axes
	var face := rng.randf() * TAU
	for k in 6:
		var phi := face + lerpf(-0.75, 0.75, k / 5.0)
		var theta := lerpf(0.05, 0.55, k / 5.0) + rng.randf_range(-0.05, 0.05)
		var d := Vector3(sin(phi) * cos(theta), sin(theta), cos(phi) * cos(theta))
		var surf := Vector3(half.x * d.x, half.y * d.y, half.z * d.z)
		var normal := Vector3(d.x / half.x, d.y / half.y, d.z / half.z).normalized()
		var tangent := Vector3.UP.cross(normal).normalized()
		var b := unturn * Basis(tangent, normal, tangent.cross(normal))
		var size := Vector3(rng.randf_range(0.26, 0.32), 0.045, rng.randf_range(0.07, 0.09)) # long along the seam
		put_detail.call(b, unturn * (surf - normal * 0.012) + Vector3(0, 0.6, 0), size, SEAM_STUD.darkened(rng.randf() * 0.08))


## The solid columns of `kind` at `scale`: [[radius, bottom, top], ...] relative to the
## node's ground position. Covers the live and the depleted look.
static func solid_columns(kind: String, scale: float = 1.0) -> Array:
	var out: Array = []
	for c in SOLID_COLUMNS.get(kind, []):
		out.append([c[0] * scale, c[1] * scale, c[2] * scale])
	return out


## True if `p` is inside node's prop, or within `margin` of it (by its solid columns). For
## the action camera: keep it outside every nearby node with a margin and it never sees
## inside a trunk, crown, pine tier or stone.
static func inside_solid(p: Vector3, node: Dictionary, margin: float = 0.0) -> bool:
	var base: Vector3 = node.pos
	var dx := p.x - base.x
	var dz := p.z - base.z
	var h := p.y - base.y
	for c in solid_columns(str(node.kind), float(node.get("scale", 1.0))):
		var r: float = c[0] + margin
		if h >= c[1] - margin and h <= c[2] + margin and dx * dx + dz * dz <= r * r:
			return true
	return false


static func _stump(put: Callable, bark: Color) -> void:
	put.call("NodeStumps", Vector3(0, 0.25, 0), Vector3.ONE, bark)
	put.call("NodeStumps", Vector3(0, 0.51, 0), Vector3(0.85, 0.04, 0.85), STUMP_CUT)


## Both looks of every node, ready for MultiMeshes:
## {layers: {layer: Array of [Transform3D, Color]}, slots: {id: {live: [[layer, index]...],
## depleted: [[layer, index]...], kind, pos, scale}}}. Every node starts live, so its depleted parts begin
## hidden (their transforms are kept in `layers`; build() hides them).
static func layout(nodes: Array) -> Dictionary:
	var layers := {}
	for l in LAYERS:
		layers[l] = []
	var slots := {}
	for n in nodes:
		var slot := {"live": [], "depleted": [], "kind": n.kind, "pos": n.pos, "scale": n.scale}
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
	root.set_meta("depleted", {})
	var fx := NodeFx.new()
	root.add_child(fx)
	fx.setup(root, meshes)
	return root


## Switch node `id` between its live and depleted look. Returns false for an unknown id.
static func set_depleted(root: Node3D, id: int, depleted: bool) -> bool:
	var lay: Dictionary = root.get_meta("layout", {})
	if not lay.get("slots", {}).has(id):
		return false
	var slot: Dictionary = lay.slots[id]
	_show(root, slot.live, not depleted)
	_show(root, slot.depleted, depleted)
	var dead: Dictionary = root.get_meta("depleted", {})
	if depleted:
		dead[id] = true
	else:
		dead.erase(id)
	root.set_meta("depleted", dead)
	var fx := root.get_node_or_null("Fx") as NodeFx
	if fx:
		fx.refresh(id)
	return true


## Softly light node `id` (the one in reach / under the reticle) with a warm rim glow, or
## turn it off. One node is lit at a time: lighting another moves the glow. Cheap to call
## every frame (the same node again is a no-op). Returns false for an unknown id.
static func set_highlight(root: Node3D, id: int, on: bool) -> bool:
	var fx := root.get_node_or_null("Fx") as NodeFx
	return fx != null and fx.set_highlight(id, on)


## The id lit by set_highlight, or -1.
static func highlighted(root: Node3D) -> int:
	var fx := root.get_node_or_null("Fx") as NodeFx
	return fx.highlighted() if fx else -1


## One gather's reaction on node `id`: an ash or pine shudders and sheds a few leaves or
## needles, an outcrop jolts and throws stone chips, a seep's pool swells and splashes
## glowing droplets. Call it once per gather result (for anyone's gather nearby). Returns
## false for an unknown id.
static func play_hit(root: Node3D, id: int) -> bool:
	var fx := root.get_node_or_null("Fx") as NodeFx
	return fx != null and fx.play_hit(id)


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
	var detail := BoxMesh.new()
	return {"NodeTrunks": trunk, "NodeAshCrowns": crown, "NodePineTiers": tier, "NodeStones": stone, "NodeSapPools": pool, "NodeStumps": stump, DETAIL_LAYER: detail}


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
		# Wet, glossy sap: a low roughness and a clearcoat give it a moving highlight up close.
		mat.roughness = 0.14
		mat.metallic_specular = 0.8
		mat.clearcoat_enabled = true
		mat.clearcoat = 1.0
		mat.clearcoat_roughness = 0.05
		mat.emission_enabled = true
		mat.emission = SAP_GLOW
		mat.emission_energy_multiplier = 0.9
	elif node_name == "NodeAshCrowns":
		Lamps.add_ember_emission(mat) # lit at night by Lamps.apply_glow
	var mmi := MultiMeshInstance3D.new()
	mmi.name = node_name
	mmi.multimesh = mm
	mmi.material_override = mat
	if glow or node_name == DETAIL_LAYER:
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mmi
