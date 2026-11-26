class_name TerrainMesh
## Builds the flat-shaded, vertex-coloured terrain from the shared Terrain height field.

const CELL := 4.0 ## metres per grid cell
const CHUNK_CELLS := 16 ## cells per chunk side (64 m chunks)


const AO_REACH := 2 ## grid cells (8 m) to each side that decide whether a vertex sits in a hollow
const AO_DARK := 0.06 ## darkening per metre a vertex sits below its surroundings
const AO_MAX := 0.32 ## deepest baked shadow in a hollow
const AO_LIGHT_MAX := 0.06 ## ridges and knolls catch a little more light


## Builds one chunk whose minimum corner is at world (x0, z0). Flat-shaded (one ground colour
## per triangle) with ambient occlusion baked into each vertex, so hollows and valley floors
## sit darker and ridges lighter, and every face carries a gentle gradient (Emberlight).
static func build_chunk(x0: float, z0: float, cells: int = CHUNK_CELLS, cell: float = CELL) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, chunk_arrays(x0, z0, cells, cell))
	return mesh


## build_chunk's surface as plain arrays (Mesh.ARRAY_*), no RenderingServer involved, so a
## background thread can work them out (TerrainStream) and the main thread only wraps them.
static func chunk_arrays(x0: float, z0: float, cells: int = CHUNK_CELLS, cell: float = CELL) -> Array:
	var m := AO_REACH
	var side := cells + 1 + 2 * m
	var hg := PackedFloat32Array()
	hg.resize(side * side)
	for gz in side:
		for gx in side:
			hg[gz * side + gx] = Terrain.height(x0 + (gx - m) * cell, z0 + (gz - m) * cell)
	var ao := PackedFloat32Array()
	ao.resize((cells + 1) * (cells + 1))
	for iz in cells + 1:
		for ix in cells + 1:
			var c := (iz + m) * side + ix + m
			var around := (hg[c - m] + hg[c + m] + hg[c - m * side] + hg[c + m * side]) * 0.25
			ao[iz * (cells + 1) + ix] = ao_factor(around - hg[c])
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var vp := func(ix: int, iz: int) -> Array:
		return [Vector3(x0 + ix * cell, hg[(iz + m) * side + ix + m], z0 + iz * cell), ao[iz * (cells + 1) + ix]]
	for iz in cells:
		for ix in cells:
			var a: Array = vp.call(ix, iz)
			var b: Array = vp.call(ix + 1, iz)
			var c: Array = vp.call(ix, iz + 1)
			var d: Array = vp.call(ix + 1, iz + 1)
			# Alternate the diagonal so the faceting doesn't look like a grid.
			if (ix + iz) % 2 == 0:
				_tri(st, a, b, c)
				_tri(st, b, d, c)
			else:
				_tri(st, a, d, c)
				_tri(st, a, b, d)
	st.generate_normals()
	return st.commit_to_arrays()


## Baked light at a vertex that sits `depth` metres below the average of its surroundings
## (negative on a ridge): 1.0 is untouched, lower is darker.
static func ao_factor(depth: float) -> float:
	if depth >= 0.0:
		return 1.0 - minf(depth * AO_DARK, AO_MAX)
	return 1.0 + minf(-depth * AO_DARK * 0.5, AO_LIGHT_MAX)


static func _p(x: float, z: float) -> Vector3:
	return Vector3(x, Terrain.height(x, z), z)


static func _tri(st: SurfaceTool, a: Array, b: Array, c: Array) -> void:
	var pa: Vector3 = a[0]
	var pb: Vector3 = b[0]
	var pc: Vector3 = c[0]
	var n := (pb - pa).cross(pc - pa).normalized()
	var slope := 1.0 - absf(n.y)
	var center := (pa + pb + pc) / 3.0
	var j := (fposmod(sin(center.x * 12.9898 + center.z * 78.233) * 43758.5453, 1.0) - 0.5) * 0.08
	var base := Palette.ground_at(center.x, center.z, center.y, slope, j).srgb_to_linear() # palette is sRGB; vertex colours are linear
	for v in [a, b, c]:
		var k: float = v[1]
		st.set_color(Color(base.r * k, base.g * k, base.b * k, 1.0))
		st.add_vertex(v[0])


## The terrain's material: the shared Emberlight "solid" (rim kept low, so flat ground seen
## at a grazing angle doesn't light up like a silhouette).
static func material() -> ShaderMaterial:
	var m := Emberlight.material("solid", "terrain")
	m.set_shader_parameter("rim_strength", 0.05)
	Emberlight.paint_material(m, "ground") # detail and grain off (Emberlight.PAINT): clean carved planes like the characters
	return m
