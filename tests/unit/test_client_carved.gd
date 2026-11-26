extends TestCase
## Client stream: the clean carved survivors and Zombai (Carved; art bible section 3).

const LOOK := {"body": 2, "height": 3, "skin": 4, "face": 1, "hair": 2, "hair_colour": 1,
	"beard": 3, "headwear": 0, "tunic": 2, "trousers": 1}


func _span(verts: PackedVector3Array) -> Array:
	var lo := Vector3.ONE * INF
	var hi := -Vector3.ONE * INF
	for v in verts:
		lo = lo.min(v)
		hi = hi.max(v)
	return [lo, hi]


func test_every_option_builds_within_budget() -> void:
	var seen := {}
	for key in ["body", "face", "hair", "beard", "headwear"]:
		for i in Appearance.count(key):
			var lk := LOOK.duplicate()
			lk[key] = i
			var g := Carved.geometry(Carved.style(lk, 7))
			var tris: int = (g.verts as PackedVector3Array).size() / 3
			check(tris <= Carved.MAX_TRIS and tris >= 600, "%s %d: %d triangles" % [key, i, tris])
			seen[tris * 1000 + int(_span(g.verts)[1].y * 100)] = true
	check(seen.size() >= 8, "options change the shape (%d distinct)" % seen.size())
	for v in Carved.ZOMBAI_VARIANTS:
		var tris: int = (Carved.geometry(Carved.zombai_style(v)).verts as PackedVector3Array).size() / 3
		check(tris <= Carved.MAX_TRIS, "a walker stays cheap, 24 of them at night (%d)" % tris)


func test_real_proportions() -> void:
	var g := Carved.geometry(Carved.style(LOOK, 77))
	var s := _span(g.verts)
	check(s[1].y > 1.72 and s[1].y < 1.86, "about 1.78 m before height scaling (%.2f)" % s[1].y)
	check(s[0].y > -0.03 and s[0].y < 0.02, "stands on its soles (%.3f)" % s[0].y)
	check(s[1].x - s[0].x < 0.8, "arms by its sides (%.2f m across)" % (s[1].x - s[0].x))


func test_skinned_to_the_avatar_skeleton() -> void:
	var g := Carved.geometry(Carved.style(LOOK, 77))
	var bones: PackedInt32Array = g.bones
	var weights: PackedFloat32Array = g.weights
	var verts: PackedVector3Array = g.verts
	var n := AvatarSkeleton.names().size()
	var bad := 0
	for i in range(0, weights.size(), 4):
		if absf(weights[i] - 1.0) > 0.0001 or bones[i] < 0 or bones[i] >= n:
			bad += 1
	check_eq(bad, 0, "every vertex rides one real bone")
	var top := 0
	var low := 0
	for i in verts.size():
		if verts[i].y > verts[top].y:
			top = i
		if verts[i].y < verts[low].y:
			low = i
	check_eq(bones[top * 4], AvatarSkeleton.index_of("Head"), "the crown rides the head")
	check(bones[low * 4] in [AvatarSkeleton.index_of("LeftFoot"), AvatarSkeleton.index_of("RightFoot")], "the soles ride the feet")


func test_flat_carved_facets() -> void:
	var g := Carved.geometry(Carved.style(LOOK, 77))
	var verts: PackedVector3Array = g.verts
	var normals: PackedVector3Array = g.normals
	var bad := 0
	for t in range(0, verts.size(), 3):
		var fn := (verts[t + 1] - verts[t]).cross(verts[t + 2] - verts[t]).normalized()
		for j in 3:
			if absf(absf(normals[t + j].dot(fn)) - 1.0) > 0.001:
				bad += 1
	check_eq(bad, 0, "every corner takes its face's normal: flat facets")
	# Normals point out: the frontmost facet of the chest, and of the crown, face out.
	var front := -1
	var top := -1
	for t in range(0, verts.size(), 3):
		var c := (verts[t] + verts[t + 1] + verts[t + 2]) / 3.0
		if c.y > 1.2 and c.y < 1.35 and absf(c.x) < 0.05 and (front < 0 or c.z > verts[front].z):
			front = t
		if top < 0 or c.y > verts[top].y:
			top = t
	check(normals[front].z > 0.3, "the chest's front faces forward")
	check(normals[top].y > 0.3, "the crown faces up")


func test_paint_follows_the_look() -> void:
	var st := Carved.style(LOOK, 77)
	var g := Carved.geometry(st)
	var cols: PackedColorArray = g.colors
	var verts: PackedVector3Array = g.verts
	check_eq(cols.size(), verts.size(), "a colour per vertex")
	var want := (st.skin as Color).srgb_to_linear()
	var skin_seen := false
	for i in cols.size():
		var f := 1.0 - Carved.SHADE_UP * clampf(1.0 - verts[i].y / 1.8, 0.0, 1.0)
		if verts[i].y > 1.6 and absf(cols[i].r - want.r * f) < 0.002 and absf(cols[i].g - want.g * f) < 0.002:
			skin_seen = true
	check(skin_seen, "the face is the chosen skin")
	check_eq(Carved.style({}, 5).headwear, Appearance.from_seed(5).headwear, "an unchosen look stands in from the seed")


func test_zombai_are_the_dead() -> void:
	for v in Carved.ZOMBAI_VARIANTS:
		var st := Carved.zombai_style(v)
		check(st.zombai, "a walker")
		var c: Color = st.skin
		check(c.g <= c.b + 0.02, "ash-grey flesh, never green (%s)" % c)
		var living := Carved.style({}, 90210 + v * 7919)
		check((st.tunic as Color).s < (living.tunic as Color).s + 0.001, "clothes drained of colour")
	var live_tris: int = (Carved.geometry(Carved.style({}, 90210)).verts as PackedVector3Array).size()
	var dead_tris: int = (Carved.geometry(Carved.zombai_style(0)).verts as PackedVector3Array).size()
	check(dead_tris < live_tris, "they carry nothing: no pack")


func test_no_paint_grain() -> void:
	var m := Carved.material()
	check_eq(float(m.get_shader_parameter("texel_grain")), 0.0, "no texel grain on a face")
	check_eq(float(m.get_shader_parameter("brush")), 0.0, "no brush noise")
	check(Emberlight.is_emberlight(m), "still lit like the world")
