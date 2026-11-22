class_name TerrainMesh
## Builds the flat-shaded, vertex-coloured terrain from the shared Terrain height field.

const CELL := 4.0 ## metres per grid cell
const CHUNK_CELLS := 16 ## cells per chunk side (64 m chunks)


## Builds one chunk whose minimum corner is at world (x0, z0).
static func build_chunk(x0: float, z0: float, cells: int = CHUNK_CELLS, cell: float = CELL) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for iz in cells:
		for ix in cells:
			var ax := x0 + ix * cell
			var az := z0 + iz * cell
			var a := _p(ax, az)
			var b := _p(ax + cell, az)
			var c := _p(ax, az + cell)
			var d := _p(ax + cell, az + cell)
			# Alternate the diagonal so the faceting doesn't look like a grid.
			if (ix + iz) % 2 == 0:
				_tri(st, a, b, c)
				_tri(st, b, d, c)
			else:
				_tri(st, a, d, c)
				_tri(st, a, b, d)
	st.generate_normals()
	return st.commit()


static func _p(x: float, z: float) -> Vector3:
	return Vector3(x, Terrain.height(x, z), z)


static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	var n := (b - a).cross(c - a).normalized()
	var slope := 1.0 - absf(n.y)
	var center := (a + b + c) / 3.0
	var j := (fposmod(sin(center.x * 12.9898 + center.z * 78.233) * 43758.5453, 1.0) - 0.5) * 0.08
	st.set_color(Palette.ground(center.y, slope, j).srgb_to_linear()) # palette is sRGB; vertex colours are linear
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)


static func material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 1.0
	m.metallic_specular = 0.0
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	return m
