class_name Chunks
## Chunked instancing (art bible section 7, "Draw less"). One MultiMesh spanning the whole
## 512 m world can never be culled: the camera draws all of it, and every shadow cascade draws
## all of it again. `Chunks.build` splits one layer's instances into square chunks by area
## (each its own MultiMeshInstance3D under one Node3D named after the layer), so the camera
## and the shadow passes skip chunks they can't see, and a per-layer `visibility_range_end`
## lets distant chunks fade into the haze.
##
## Never moves a prop: every instance keeps its exact transform and colour, only which
## MultiMesh holds it changes (unit test compares). Pure layout (`split`) is separate from
## node building so tests can check it headless.

const SIZE := 128.0 ## metres per chunk side for trees (see CHUNK_SIZES for the small layers)

## Per-layer draw distance in metres (art bible: flowers 90 m, props about 160 m, trees about
## 300 m; past that the haze is nearly solid). 0 = no limit. Layers not listed have no limit.
const RANGES := {
	# scatter forest
	"Trunks": 300.0, "AshCrowns": 300.0, "PineTiers": 300.0, "Rocks": 160.0,
	# flora
	"BirchBark": 300.0, "BirchCrowns": 300.0, "BirchMarks": 160.0,
	"MossRocks": 160.0, "Moss": 160.0, "FlowerStems": 90.0, "FlowerBlooms": 90.0,
}

## Chunk side per layer when it differs from SIZE. Visibility range is measured to a chunk, not
## to each prop, so the cut is padded by half the chunk's diagonal (`cut_of`): nothing closer than
## its layer's range ever disappears. Short ranges get small chunks so that padding stays small;
## trees get big ones because every chunk is a draw call in the main pass and in each shadow
## cascade (2026-11-23 spawn shot: 64 m everywhere cut primitives to 525k but cost 326 draw
## calls, over the 300 budget; 128 m trees with smaller chunks for the small layers fit both).
const CHUNK_SIZES := {
	"Rocks": 64.0, "BirchMarks": 64.0, "MossRocks": 64.0, "Moss": 64.0,
	"FlowerStems": 32.0, "FlowerBlooms": 32.0,
}

## Small layers that don't cast shadows: their shadow is a few pixels nobody notices, and every
## shadow cascade would draw them again.
const NO_SHADOW := ["FlowerStems", "FlowerBlooms", "BirchMarks", "Moss"]


static func size_of(layer: String) -> float:
	return CHUNK_SIZES.get(layer, SIZE)


static func range_of(layer: String) -> float:
	return RANGES.get(layer, 0.0)


## The visibility_range_end a layer's chunks get: its range plus half a chunk diagonal, so a prop
## at the edge of a chunk is still drawn out to the layer's range. 0 = no limit.
static func cut_of(layer: String) -> float:
	var r := range_of(layer)
	return 0.0 if r <= 0.0 else r + size_of(layer) * 0.7072


## The centre of chunk `k` on the ground plane (y 0): each chunk's node sits there and holds its
## instances relative to it, so "distance to the chunk" means the same thing to every renderer.
static func centre(k: Vector2i, size: float = SIZE) -> Vector3:
	return Vector3((k.x + 0.5) * size, 0.0, (k.y + 0.5) * size)


## The chunk a world position falls in.
static func key(p: Vector3, size: float = SIZE) -> Vector2i:
	return Vector2i(floori(p.x / size), floori(p.z / size))


## Splits `instances` ([Transform3D, Color] pairs) by the chunk of each transform's origin.
## Returns {Vector2i: Array of [Transform3D, Color]}, keeping the input order inside each chunk.
static func split(instances: Array, size: float = SIZE) -> Dictionary:
	var out := {}
	for inst in instances:
		var k := key((inst[0] as Transform3D).origin, size)
		if not out.has(k):
			out[k] = []
		(out[k] as Array).append(inst)
	return out


## One layer as a Node3D named `layer` holding a MultiMeshInstance3D per chunk ("c<x>_<z>"),
## every chunk sharing `mesh` and `material`. Chunk order is sorted so builds are identical.
static func build(layer: String, mesh: Mesh, instances: Array, material: Material) -> Node3D:
	var root := Node3D.new()
	root.name = layer
	var by_chunk := split(instances, size_of(layer))
	var keys := by_chunk.keys()
	keys.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y < b.y or (a.y == b.y and a.x < b.x))
	var vis := cut_of(layer)
	for k in keys:
		var at := centre(k, size_of(layer))
		var mmi := _multimesh(mesh, by_chunk[k], material, at)
		mmi.name = "c%d_%d" % [k.x, k.y]
		mmi.position = at
		if vis > 0.0:
			mmi.visibility_range_end = vis
		if NO_SHADOW.has(layer):
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mmi)
	return root


## Every [Transform3D, Color] instance under a layer built by `build`, in world space (colours
## as stored, i.e. linear), chunk by chunk. Needs a renderer that keeps MultiMesh data (the
## headless dummy one doesn't).
static func instances_of(layer_node: Node) -> Array:
	var out: Array = []
	for c in layer_node.get_children():
		var mm := (c as MultiMeshInstance3D).multimesh
		for i in mm.instance_count:
			out.append([(c as Node3D).transform * mm.get_instance_transform(i), mm.get_instance_color(i)])
	return out


## The first drawn piece of a layer node (or the node itself if it's a GeometryInstance3D),
## for code that tweaks the layer's shared material (Lamps.apply_glow).
static func first_geometry(n: Node) -> GeometryInstance3D:
	if n is GeometryInstance3D:
		return n as GeometryInstance3D
	if n == null:
		return null
	for c in n.get_children():
		if c is GeometryInstance3D:
			return c as GeometryInstance3D
	return null


static func _multimesh(mesh: Mesh, instances: Array, material: Material, at: Vector3) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = instances.size()
	for i in instances.size():
		var t: Transform3D = instances[i][0]
		mm.set_instance_transform(i, Transform3D(t.basis, t.origin - at)) # the node sits at `at`
		mm.set_instance_color(i, (instances[i][1] as Color).srgb_to_linear())
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = material
	return mmi
