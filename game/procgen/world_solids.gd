class_name WorldSolids
## Camera clearance shapes for everything decorative in the world: the scatter forest's ash,
## pine and rocks (`Props.scatter`), the lake-shore birches and mossy boulders (`Flora`), the
## Spawn Meadow lanterns (`Lamps`) and the workbench (`Workbench`). Resource nodes have their
## own hand-made columns (`NodeProps.solid_columns`); these are worked out from the very parts
## and meshes the world draws, so the camera and the meshes can never drift apart.
##
## Each solid is a Dictionary that `NodeProps.inside_solid` (and so the client's
## `ActionCamera.inside_prop` / `clear_arm`) understands as-is:
##   {kind: "deco", source: "ash"|"pine"|"rock"|"birch"|"boulder"|"lantern"|"workbench",
##    pos: Vector3 (base), reach: float (furthest column edge from pos, in x/z),
##    columns: Array of [radius, y_from, y_to, offset_x, offset_z]}
## Heights are metres above `pos.y`; offsets are world x/z metres from `pos`. A point is inside
## when it is inside any one column, so the union of columns holds every vertex of every part
## (a unit test checks every vertex). Wildflowers have none: 40 cm stems are not worth a camera
## bump, and the camera already keeps clear of the ground.
##
## Usage (client): `WorldSolids.near(pos, radius)` next to `ResourceNodes.near(pos, radius)`.

const KIND := "deco"
const CELL := 16.0 ## grid cell for near(): about the camera's reach, so a query reads a few cells

static var _all: Array = []
static var _built_for: Dictionary = {} ## the WorldGen config `_all` was built for
static var _grid: Dictionary = {}
static var _max_reach := 0.0
static var _verts: Dictionary = {} # mesh instance id -> PackedVector3Array (unique vertices)
static var _profiles: Dictionary = {} # mesh instance id -> [r_xz, y_min, y_max]


## Every decorative solid, built once (deterministic: the same world on every machine).
static func all() -> Array:
	if _all.is_empty() or _built_for != WorldGen.config():
		_build()
	return _all


## Solids whose columns come within `radius` of `pos` in x/z (height is ignored, like
## `ResourceNodes.near`).
static func near(pos: Vector3, radius: float) -> Array:
	if _all.is_empty() or _built_for != WorldGen.config():
		_build()
	var out: Array = []
	var reach := radius + _max_reach
	var c0 := _cell(pos.x - reach, pos.z - reach)
	var c1 := _cell(pos.x + reach, pos.z + reach)
	for cx in range(c0.x, c1.x + 1):
		for cz in range(c0.y, c1.y + 1):
			for s in _grid.get(Vector2i(cx, cz), []):
				var d := Vector2(s.pos.x - pos.x, s.pos.z - pos.z).length()
				if d <= radius + s.reach:
					out.append(s)
	return out


## True if `p` is inside `solid` (one of all()), or within `margin` of it.
static func inside(p: Vector3, solid: Dictionary, margin: float = 0.0) -> bool:
	var base: Vector3 = solid.pos
	var bx := p.x - base.x
	var bz := p.z - base.z
	var far: float = solid.reach + margin
	if bx * bx + bz * bz > far * far:
		return false
	var h := p.y - base.y
	for c in solid.columns:
		if h < c[1] - margin or h > c[2] + margin:
			continue
		var dx: float = bx - c[3]
		var dz: float = bz - c[4]
		var r: float = c[0] + margin
		if dx * dx + dz * dz <= r * r:
			return true
	return false


## One solid from a list of parts ({layer, xform}) drawn with `meshes` ({layer: Mesh}), based
## at `base`: one column per part, around that part's own centre, holding all its vertices.
static func solid_of(source: String, base: Vector3, parts: Array, meshes: Dictionary) -> Dictionary:
	var columns: Array = []
	var reach := 0.0
	for p in parts:
		var col := _column(p.xform, meshes[p.layer], base)
		columns.append(col)
		reach = maxf(reach, Vector2(col[3], col[4]).length() + col[0])
	return {"kind": KIND, "source": source, "pos": base, "reach": reach, "columns": columns}


static func _column(xf: Transform3D, mesh: Mesh, base: Vector3) -> Array:
	var c := xf.origin
	var b := xf.basis
	var r := 0.0
	var y0 := INF
	var y1 := -INF
	var hx := Vector2(b.x.x, b.x.z)
	var hz := Vector2(b.z.x, b.z.z)
	var upright := is_zero_approx(b.x.y) and is_zero_approx(b.z.y) and is_zero_approx(b.y.x) and is_zero_approx(b.y.z)
	# Round in plan (the same horizontal scale both ways, axes square): a squashed rock is not,
	# its stretched axes skew under the turn, so it takes the vertex path below.
	var round_plan := is_equal_approx(hx.length(), hz.length()) and absf(hx.dot(hz)) < 0.0001 * hx.length_squared() + 1e-9
	if upright and round_plan:
		# Upright and round in plan (turned about Y, scaled evenly across): the mesh's own
		# profile, scaled. Exact for the widest vertex.
		var prof := _profile(mesh)
		r = prof[0] * hx.length()
		var sy := b.y.y
		y0 = c.y + minf(prof[1] * sy, prof[2] * sy)
		y1 = c.y + maxf(prof[1] * sy, prof[2] * sy)
	else:
		# Tilted or squashed (a leaning birch, a lantern arm, a rock): every vertex.
		for v in _unique_verts(mesh):
			var w := xf * v
			r = maxf(r, Vector2(w.x - c.x, w.z - c.z).length())
			y0 = minf(y0, w.y)
			y1 = maxf(y1, w.y)
	return [r, y0 - base.y, y1 - base.y, c.x - base.x, c.z - base.z]


static func _profile(mesh: Mesh) -> Array:
	var key := mesh.get_instance_id()
	if not _profiles.has(key):
		var r := 0.0
		var y0 := INF
		var y1 := -INF
		for v in _unique_verts(mesh):
			r = maxf(r, Vector2(v.x, v.z).length())
			y0 = minf(y0, v.y)
			y1 = maxf(y1, v.y)
		_profiles[key] = [r, y0, y1]
	return _profiles[key]


static func _unique_verts(mesh: Mesh) -> PackedVector3Array:
	var key := mesh.get_instance_id()
	if not _verts.has(key):
		var seen := {}
		var out := PackedVector3Array()
		for s in mesh.get_surface_count():
			for v in mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]:
				var k := Vector3i(roundi(v.x * 10000.0), roundi(v.y * 10000.0), roundi(v.z * 10000.0))
				if not seen.has(k):
					seen[k] = true
					out.append(v)
		_verts[key] = out
	return _verts[key]


static func _cell(x: float, z: float) -> Vector2i:
	return Vector2i(floori(x / CELL), floori(z / CELL))


static func _add(s: Dictionary) -> void:
	_all.append(s)
	_max_reach = maxf(_max_reach, s.reach)
	var k := _cell(s.pos.x, s.pos.z)
	if not _grid.has(k):
		_grid[k] = []
	_grid[k].append(s)


static func _build() -> void:
	_built_for = WorldGen.config()
	_all = []
	_grid = {}
	_max_reach = 0.0
	var scatter_meshes := WorldBuilder.scatter_meshes()
	var items := Props.scatter()
	var per_item := WorldBuilder.scatter_parts(items)
	for i in items.size():
		_add(solid_of(items[i].kind, items[i].pos, per_item[i], scatter_meshes))
	var flora_meshes := Flora._meshes()
	for spot in Flora.spots():
		if spot.kind == "flowers":
			continue
		_add(solid_of(spot.kind, spot.pos, Flora.parts(spot), flora_meshes))
	var lamp_meshes := Lamps._meshes()
	for lamp in Lamps.positions():
		_add(solid_of("lantern", lamp.pos, Lamps.parts(lamp), lamp_meshes))
	var bench := Workbench.spot()
	_add(solid_of("workbench", bench.pos, Workbench.parts(bench), Workbench._meshes()))
