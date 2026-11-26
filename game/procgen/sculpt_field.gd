class_name SculptField
extends RefCounted
## A body sculpted from soft shapes (art bible section 3, "One sculpted body"): round cones and
## ellipsoids blended with smooth unions into one signed distance field, turned into a mesh by
## surface nets, smoothed (Taubin) and cut to a low triangle budget by meshoptimizer.
##
## Ported from the test camp's scratch `Sculpt`, made fast enough to run on a worker thread in
## a couple of seconds: shapes live in packed arrays, and the box is split into buckets that
## each list only the shapes that can touch them, so a sample point looks at a handful of
## shapes instead of all of them.
##
## Forearms and hands (arm shapes centred below LOWARM_Y) are their own blend group, joined to
## the rest by a hard min, so a hand hanging by the belt never melts into the hip.
##
## Pure: no nodes, no renderer. Safe headless and off the main thread.

const CELL := 0.017 ## metres between samples
const LO := Vector3(-0.46, -0.03, -0.34)
const HI := Vector3(0.46, 1.84, 0.28)
const BUCKET := 4 ## samples per bucket side
const LOWARM_Y := 1.1

const RC := 0 ## round cone a -> b, radii r1 -> r2
const EL := 1 ## ellipsoid centre a, radii r

var kind := PackedInt32Array()
var pa := PackedVector3Array()
var pb := PackedVector3Array()
var rad := PackedVector3Array() ## EL: radii; RC: (r1, r2, 0)
var blend := PackedFloat32Array()
var prio := PackedFloat32Array() ## owner(): a shape this much "nearer" wins its border
var ymin := PackedFloat32Array() ## a flat hem: the shape ends below this height (-INF: none)
var clip_n := PackedVector3Array() ## a cut plane: the shape keeps only dot(p, n) <= clip_d (zero n: none)
var clip_d := PackedFloat32Array()
var lowarm := PackedByteArray()
var col: Array[String] = []
var limb: Array[String] = []

var _dims := Vector3i.ZERO
var _bdims := Vector3i.ZERO
var _buckets: Array = [] ## bucket index -> PackedInt32Array of shape indices


func rc(a: Vector3, b: Vector3, r1: float, r2: float, c: String, l: String, k := 0.035) -> int:
	return _add(RC, a, b, Vector3(r1, r2, 0.0), c, l, k)


func el(c: Vector3, r: Vector3, colour: String, l: String, k := 0.035) -> int:
	return _add(EL, c, c, r, colour, l, k)


## Sets the last shape's paint priority (owner()) and returns its index.
func set_prio(i: int, p: float) -> void:
	prio[i] = p


func set_ymin(i: int, y: float) -> void:
	ymin[i] = y


## Cuts shape `i` flat: it keeps only the side where dot(p, n) <= d (a cloak that hangs behind).
func set_clip(i: int, n: Vector3, d: float) -> void:
	clip_n[i] = n.normalized()
	clip_d[i] = d


func size() -> int:
	return kind.size()


func _add(k: int, a: Vector3, b: Vector3, r: Vector3, c: String, l: String, bl: float) -> int:
	kind.append(k)
	pa.append(a)
	pb.append(b)
	rad.append(r)
	blend.append(bl)
	prio.append(0.0)
	ymin.append(-INF)
	clip_n.append(Vector3.ZERO)
	clip_d.append(0.0)
	var mid_y := a.y if k == EL else (a.y + b.y) * 0.5
	lowarm.append(1 if l.begins_with("Arm") and mid_y < LOWARM_Y else 0)
	col.append(c)
	limb.append(l)
	return kind.size() - 1


static func sd_rc(p: Vector3, a: Vector3, b: Vector3, r1: float, r2: float) -> float:
	var ba := b - a
	var l2 := ba.dot(ba)
	var rr := r1 - r2
	var a2 := l2 - rr * rr
	var il2 := 1.0 / l2
	var q := p - a
	var y := q.dot(ba)
	var z := y - l2
	var xv := q * l2 - ba * y
	var x2 := xv.dot(xv)
	var y2 := y * y * l2
	var z2 := z * z * l2
	var kk := signf(rr) * rr * rr * x2
	if signf(z) * a2 * z2 > kk:
		return sqrt(x2 + z2) * il2 - r2
	if signf(y) * a2 * y2 < kk:
		return sqrt(x2 + y2) * il2 - r1
	return (sqrt(x2 * a2 * il2) + y * rr) * il2 - r1


static func sd_el(p: Vector3, c: Vector3, r: Vector3) -> float:
	var q := p - c
	var k0 := Vector3(q.x / r.x, q.y / r.y, q.z / r.z).length()
	var k1 := Vector3(q.x / (r.x * r.x), q.y / (r.y * r.y), q.z / (r.z * r.z)).length()
	return k0 * (k0 - 1.0) / maxf(k1, 1e-6)


static func smin(a: float, b: float, k: float) -> float:
	var h := clampf(0.5 + 0.5 * (b - a) / k, 0.0, 1.0)
	return lerpf(b, a, h) - k * h * (1.0 - h)


func d_shape(i: int, p: Vector3) -> float:
	var d: float
	if kind[i] == RC:
		var r := rad[i]
		d = sd_rc(p, pa[i], pb[i], r.x, r.y)
	else:
		d = sd_el(p, pa[i], rad[i])
	var ym := ymin[i]
	if ym > -1e9:
		d = maxf(d, ym - p.y)
	var cn := clip_n[i]
	if cn != Vector3.ZERO:
		d = maxf(d, p.dot(cn) - clip_d[i])
	return d


## Builds the buckets: which shapes can change the field near each part of the box.
func prepare() -> void:
	_dims = Vector3i(((HI - LO) / CELL).ceil()) + Vector3i.ONE
	_bdims = Vector3i(ceili(float(_dims.x) / BUCKET), ceili(float(_dims.y) / BUCKET), ceili(float(_dims.z) / BUCKET))
	_buckets.resize(_bdims.x * _bdims.y * _bdims.z)
	var lists: Array = []
	lists.resize(_buckets.size())
	for i in lists.size():
		lists[i] = PackedInt32Array()
	var bsize := CELL * BUCKET
	for i in size():
		var r := rad[i]
		var lo: Vector3
		var hi: Vector3
		if kind[i] == RC:
			var m := maxf(r.x, r.y)
			lo = pa[i].min(pb[i]) - Vector3.ONE * m
			hi = pa[i].max(pb[i]) + Vector3.ONE * m
		else:
			lo = pa[i] - r
			hi = pa[i] + r
		var pad := blend[i] + CELL * 2.0 + 0.01
		lo -= Vector3.ONE * pad
		hi += Vector3.ONE * pad
		var b0 := Vector3i(((lo - LO) / bsize).floor()).clamp(Vector3i.ZERO, _bdims - Vector3i.ONE)
		var b1 := Vector3i(((hi - LO) / bsize).floor()).clamp(Vector3i.ZERO, _bdims - Vector3i.ONE)
		for z in range(b0.z, b1.z + 1):
			for y in range(b0.y, b1.y + 1):
				for x in range(b0.x, b1.x + 1):
					var bi := x + _bdims.x * (y + _bdims.y * z)
					var lst: PackedInt32Array = lists[bi]
					lst.append(i)
					lists[bi] = lst # packed arrays are values: store the grown copy back
	_buckets = lists


func _bucket_at(p: Vector3) -> PackedInt32Array:
	var b := Vector3i(((p - LO) / (CELL * BUCKET)).floor()).clamp(Vector3i.ZERO, _bdims - Vector3i.ONE)
	return _buckets[b.x + _bdims.x * (b.y + _bdims.y * b.z)]


## The field at `p` from the shapes in `ids` (the body group and the forearm group, joined).
func field_with(p: Vector3, ids: PackedInt32Array) -> float:
	var d := 1.0
	var arm := 1.0
	for i in ids:
		var ds := d_shape(i, p)
		if lowarm[i] == 1:
			arm = smin(arm, ds, blend[i])
		else:
			d = smin(d, ds, blend[i])
	return minf(d, arm)


func field(p: Vector3) -> float:
	return field_with(p, _bucket_at(p))


## The shape a surface point belongs to (for paint and bones): the nearest, less its priority.
## A point nearer a forearm or hand than anything else belongs to the arm, even against the belt.
func owner(p: Vector3) -> int:
	var ids := _bucket_at(p)
	if ids.is_empty():
		ids = PackedInt32Array(range(size()))
	var d_low := INF
	var d_rest := INF
	var ds := PackedFloat32Array()
	ds.resize(ids.size())
	for j in ids.size():
		var i := ids[j]
		ds[j] = d_shape(i, p)
		if lowarm[i] == 1:
			d_low = minf(d_low, ds[j])
		else:
			d_rest = minf(d_rest, ds[j])
	var arm_only := d_low <= d_rest
	var best := INF
	var who := -1
	for j in ids.size():
		var i := ids[j]
		if arm_only and lowarm[i] == 0:
			continue
		var d := ds[j] - prio[i]
		if d < best:
			best = d
			who = i
	return who


## Surface nets: one vertex per cell the surface crosses, a quad across every crossed edge.
## {verts: PackedVector3Array, tris: PackedInt32Array}.
func polygonize() -> Dictionary:
	if _buckets.is_empty():
		prepare()
	var n := _dims
	var nxy := n.x * n.y
	var vals := PackedFloat32Array()
	vals.resize(n.x * n.y * n.z)
	vals.fill(1.0)
	for bz in _bdims.z:
		for by in _bdims.y:
			for bx in _bdims.x:
				var ids: PackedInt32Array = _buckets[bx + _bdims.x * (by + _bdims.y * bz)]
				if ids.is_empty():
					continue
				for z in range(bz * BUCKET, mini((bz + 1) * BUCKET, n.z)):
					for y in range(by * BUCKET, mini((by + 1) * BUCKET, n.y)):
						for x in range(bx * BUCKET, mini((bx + 1) * BUCKET, n.x)):
							vals[x + n.x * y + nxy * z] = field_with(LO + Vector3(x, y, z) * CELL, ids)
	var idx := {}
	var verts := PackedVector3Array()
	var corners := [Vector3i(0, 0, 0), Vector3i(1, 0, 0), Vector3i(0, 1, 0), Vector3i(1, 1, 0),
		Vector3i(0, 0, 1), Vector3i(1, 0, 1), Vector3i(0, 1, 1), Vector3i(1, 1, 1)]
	var coff := PackedInt32Array()
	for c in corners:
		coff.append(c.x + n.x * c.y + nxy * c.z)
	var edges := [[0, 1], [2, 3], [4, 5], [6, 7], [0, 2], [1, 3], [4, 6], [5, 7], [0, 4], [1, 5], [2, 6], [3, 7]]
	var v := PackedFloat32Array()
	v.resize(8)
	for z in n.z - 1:
		for y in n.y - 1:
			var row := n.x * y + nxy * z
			for x in n.x - 1:
				var base := row + x
				var neg := 0
				for c in 8:
					var f := vals[base + coff[c]]
					v[c] = f
					if f < 0.0:
						neg += 1
				if neg == 0 or neg == 8:
					continue
				var acc := Vector3.ZERO
				var cnt := 0
				for e in edges:
					var fa := v[e[0]]
					var fb := v[e[1]]
					if (fa < 0.0) != (fb < 0.0):
						acc += Vector3(corners[e[0]]).lerp(Vector3(corners[e[1]]), fa / (fa - fb))
						cnt += 1
				var p := LO + (Vector3(x, y, z) + acc / cnt) * CELL
				# One gradient step onto the surface.
				var ids := _bucket_at(p)
				var h := 0.002
				var g := Vector3(field_with(p + Vector3(h, 0, 0), ids) - field_with(p - Vector3(h, 0, 0), ids),
					field_with(p + Vector3(0, h, 0), ids) - field_with(p - Vector3(0, h, 0), ids),
					field_with(p + Vector3(0, 0, h), ids) - field_with(p - Vector3(0, 0, h), ids)) / (2.0 * h)
				if g.length() > 0.1:
					p -= g.normalized() * field_with(p, ids)
				idx[Vector3i(x, y, z)] = verts.size()
				verts.append(p)
	var tris := PackedInt32Array()
	for key in idx:
		var c0: Vector3i = key
		var f0 := vals[c0.x + n.x * c0.y + nxy * c0.z]
		for axis in 3:
			var dv := Vector3i(1 if axis == 0 else 0, 1 if axis == 1 else 0, 1 if axis == 2 else 0)
			var q := c0 + dv
			if q.x >= n.x or q.y >= n.y or q.z >= n.z:
				continue
			var f1 := vals[q.x + n.x * q.y + nxy * q.z]
			if (f0 < 0.0) == (f1 < 0.0):
				continue
			var u := Vector3i(0, 1, 0) if axis == 0 else (Vector3i(0, 0, 1) if axis == 1 else Vector3i(1, 0, 0))
			var w := Vector3i(0, 0, 1) if axis == 0 else (Vector3i(1, 0, 0) if axis == 1 else Vector3i(0, 1, 0))
			var cs := [c0, c0 - u, c0 - u - w, c0 - w]
			var ids := PackedInt32Array()
			for c in cs:
				if not idx.has(c):
					break
				ids.append(idx[c])
			if ids.size() < 4:
				continue
			if f0 < 0.0:
				tris.append_array([ids[0], ids[1], ids[2], ids[0], ids[2], ids[3]])
			else:
				tris.append_array([ids[0], ids[2], ids[1], ids[0], ids[3], ids[2]])
	return {"verts": verts, "tris": tris}


## Taubin smoothing (a shrink step, then an inflate step, `passes` times): the lumps and
## stair-steps of the distance field even out without the body shrinking.
static func taubin(verts: PackedVector3Array, tris: PackedInt32Array, passes: int) -> PackedVector3Array:
	var nv := verts.size()
	var sets: Array = []
	sets.resize(nv)
	for i in nv:
		sets[i] = {}
	for i in range(0, tris.size(), 3):
		for j in 3:
			var a := tris[i + j]
			var b := tris[i + (j + 1) % 3]
			sets[a][b] = true
			sets[b][a] = true
	var start := PackedInt32Array()
	var adj := PackedInt32Array()
	for i in nv:
		start.append(adj.size())
		adj.append_array(PackedInt32Array((sets[i] as Dictionary).keys()))
	start.append(adj.size())
	var v := verts.duplicate()
	for p in passes:
		for k in [0.5, -0.53]:
			var out := v.duplicate()
			for i in nv:
				var s0 := start[i]
				var s1 := start[i + 1]
				if s1 == s0:
					continue
				var avg := Vector3.ZERO
				for j in range(s0, s1):
					avg += v[adj[j]]
				out[i] = v[i] + (avg / (s1 - s0) - v[i]) * k
			v = out
	return v


## Polygonize, smooth, and cut to about `target` triangles. Array of [a, b, c] triangles.
func decimated(target: int, smooth_passes: int = 6) -> Array:
	var g := polygonize()
	var verts: PackedVector3Array = taubin(g.verts, g.tris, smooth_passes)
	var tris: PackedInt32Array = g.tris
	var normals := PackedVector3Array()
	normals.resize(verts.size())
	for i in range(0, tris.size(), 3):
		var nrm := (verts[tris[i + 2]] - verts[tris[i]]).cross(verts[tris[i + 1]] - verts[tris[i]])
		for j in 3:
			normals[tris[i + j]] += nrm
	for i in normals.size():
		normals[i] = normals[i].normalized()
	var im := ImporterMesh.new()
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = normals
	arr[Mesh.ARRAY_INDEX] = tris
	im.add_surface(Mesh.PRIMITIVE_TRIANGLES, arr)
	im.generate_lods(25.0, 60.0, [])
	var use := tris
	var best := tris.size() / 3
	var lod_verts := verts
	var final_verts: PackedVector3Array = im.get_surface_arrays(0)[Mesh.ARRAY_VERTEX]
	for l in im.get_surface_lod_count(0):
		var li := im.get_surface_lod_indices(0, l)
		var nt := li.size() / 3
		if absi(nt - target) < absi(best - target):
			best = nt
			use = li
			lod_verts = final_verts
	var out: Array = []
	for i in range(0, use.size(), 3):
		out.append([lod_verts[use[i]], lod_verts[use[i + 1]], lod_verts[use[i + 2]]])
	return out
