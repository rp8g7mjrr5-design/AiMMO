extends TestCase
## Client stream: the goofy cartoon folk (Toon; art bible section 3): survivors and Zombai.

const LOOK := {"body": 2, "height": 3, "skin": 4, "face": 1, "hair": 2, "hair_colour": 1,
	"beard": 3, "headwear": 0, "tunic": 2, "trousers": 1}


func _span(verts: PackedVector3Array) -> Array:
	var lo := Vector3.ONE * INF
	var hi := -Vector3.ONE * INF
	for v in verts:
		lo = lo.min(v)
		hi = hi.max(v)
	return [lo, hi]


func test_every_look_within_budget() -> void:
	for body in 4:
		for hw in 3:
			var lk := LOOK.duplicate()
			lk.body = body
			lk.headwear = hw
			lk.hair = (body + hw) % 6
			lk.beard = (body * 2 + hw) % 5
			var tris: int = (Toon.geometry(Toon.style(lk, 7)).verts as PackedVector3Array).size() / 3
			check(tris <= Toon.MAX_TRIS and tris >= 1500, "build %d head %d: %d triangles" % [body, hw, tris])
	for v in Toon.ZOMBAI_VARIANTS:
		var tris: int = (Toon.geometry(Toon.zombai_style(v)).verts as PackedVector3Array).size() / 3
		check(tris <= 3000, "a walker stays cheap, 24 of them at night (%d)" % tris)


func test_cartoon_proportions() -> void:
	var g := Toon.geometry(Toon.style(LOOK, 77))
	var s := _span(g.verts)
	check(s[1].y > 1.5 and s[1].y < 1.7, "a short cartoon body, about 1.6 m (%.2f)" % s[1].y)
	check(s[0].y > -0.03 and s[0].y < 0.02, "stands on its boots (%.3f)" % s[0].y)
	check(s[1].x - s[0].x < 0.8, "arms by its sides (%.2f m across)" % (s[1].x - s[0].x))
	var w := Toon.world_rest()
	var head_r := 0.15
	check((w.Head as Vector3).y + Toon.HEAD_UP - head_r > 1.2, "a big head on short legs")
	check((w.LeftUpperLeg as Vector3).y < 0.72, "short legs: hips at %.2f m" % (w.LeftUpperLeg as Vector3).y)


func test_skeleton_plays_every_clip() -> void:
	var names: Array = []
	for b in Toon.bones():
		names.append(b[0])
	check_eq(names, AvatarSkeleton.names(), "the traveller's bones, in its order")
	var w := Toon.world_rest()
	var k := Toon.LEG_SCALE
	check(absf((w.LeftUpperLeg as Vector3).y - AvatarSkeleton.HIP_HEIGHT * k) < 0.001, "hip height is the clips' scaled")
	check(absf((w.LeftUpperLeg as Vector3).y - (w.LeftLowerLeg as Vector3).y - AvatarSkeleton.THIGH * k) < 0.001, "thigh scaled")
	check(absf((w.LeftLowerLeg as Vector3).y - (w.LeftFoot as Vector3).y - AvatarSkeleton.SHIN * k) < 0.001, "shin scaled")
	var sk := Toon.skeleton()
	AvatarAnimator.apply_pose(sk, {"root_pos": Vector3(0, -0.5, 0.2)}, k)
	var got := sk.get_bone_pose_position(0)
	check(got.distance_to(Vector3(0, -0.5, 0.2) * k) < 0.0001, "a crouch or fall drops the same share of the hips")
	sk.free()


func test_skinned_to_real_bones() -> void:
	var g := Toon.geometry(Toon.style(LOOK, 77))
	var bones: PackedInt32Array = g.bones
	var weights: PackedFloat32Array = g.weights
	var verts: PackedVector3Array = g.verts
	var n := AvatarSkeleton.names().size()
	var bad := 0
	for i in range(0, weights.size(), 4):
		if absf(weights[i] - 1.0) > 0.0001 or bones[i] < 0 or bones[i] >= n:
			bad += 1
	check_eq(bad, 0, "every vertex rides one real bone")
	var head := AvatarSkeleton.index_of("Head")
	var feet := [AvatarSkeleton.index_of("LeftFoot"), AvatarSkeleton.index_of("RightFoot")]
	var top := 0
	var low := 0
	for i in verts.size():
		if verts[i].y > verts[top].y:
			top = i
		if verts[i].y < verts[low].y:
			low = i
	check_eq(bones[top * 4], head, "the crown rides the head")
	check(bones[low * 4] in feet, "the soles ride the feet")


func test_paint_follows_the_look() -> void:
	var st := Toon.style(LOOK, 77)
	var g := Toon.geometry(st)
	var cols: PackedColorArray = g.colors
	check_eq(cols.size(), (g.verts as PackedVector3Array).size(), "a colour per vertex")
	var want := (st.skin as Color).srgb_to_linear()
	var white := Toon.WHITE.srgb_to_linear()
	var skin_seen := false
	var eyes_seen := false
	for i in cols.size():
		var y: float = (g.verts as PackedVector3Array)[i].y
		var f := 1.0 - Toon.SHADE_UP * clampf(1.0 - y / 1.6, 0.0, 1.0)
		if y > 1.3 and absf(cols[i].r - want.r * f) < 0.002 and absf(cols[i].g - want.g * f) < 0.002:
			skin_seen = true
		if y > 1.3 and absf(cols[i].r - white.r * f) < 0.002 and absf(cols[i].b - white.b * f) < 0.002:
			eyes_seen = true
	check(skin_seen, "the face is the chosen skin")
	check(eyes_seen, "googly eyes")
	check_eq(Toon.style({}, 5).headwear, Appearance.from_seed(5).headwear, "an unchosen look stands in from the seed")


func test_zombai_are_the_dead() -> void:
	for v in Toon.ZOMBAI_VARIANTS:
		var st := Toon.zombai_style(v)
		check(st.zombai, "a walker")
		var c: Color = st.skin
		check(c.g <= c.b + 0.02, "ash-grey flesh, never green (%s)" % c)
		var living := Toon.style({}, 90210 + v * 7919)
		check((st.tunic as Color).s < (living.tunic as Color).s + 0.001, "clothes drained of colour")


func test_no_paint_grain() -> void:
	var m := Toon.material()
	check_eq(float(m.get_shader_parameter("texel_grain")), 0.0, "no texel grain on a face")
	check_eq(float(m.get_shader_parameter("brush")), 0.0, "no brush noise")
	check(Emberlight.is_emberlight(m), "still lit like the world")


func test_short_legs_step_quicker() -> void:
	var long := AvatarAnimator.new()
	var short := AvatarAnimator.new()
	short.leg_scale = Toon.LEG_SCALE
	for i in 60:
		var p := Vector3(0.0, 0.0, i * 0.05)
		long.step(1.0 / 60.0, {"pos": p})
		short.step(1.0 / 60.0, {"pos": p})
	check(short.footsteps > long.footsteps or short.phase > long.phase, "short legs take more steps over the same ground")
