class_name Toon
## The survivors and the Zombai as goofy cartoon folk (owner's pick, 2026-11-26: "we can make
## them funny", direction C of the three shown in game). Art bible section 3, "Characters".
##
## A big round head with googly eyes, a long droopy nose and bushy brows; a pear-shaped body;
## thin noodle arms with big hands; short legs in big boots. Smooth, toy-like shapes in flat
## dyed colours, with no paint grain: the shared "folk" Emberlight material turns the grain
## and brush off, so a face reads as a face, not noise.
##
## Every part is a simple primitive (ball, capsule, cylinder) riding one bone rigidly, merged
## into ONE skinned mesh per figure (one draw call). It builds in a few milliseconds, so there is
## no sculpting thread or disk cache: a look is drawn the moment it is seen.
##
## The skeleton has the traveller's bone names and order (AvatarSkeleton), so every
## AvatarClips pose plays on it unchanged, with its own cartoon proportions. The leg chain
## (hip height, thigh, shin) is AvatarSkeleton's scaled by LEG_SCALE, so the clips' leg IK
## still plants the feet: an animator draws the gait at speed / LEG_SCALE (short legs take
## quick little steps) and scales the pose's root offset by LEG_SCALE (`AvatarAnimator`).
##
## `geometry(st)` is pure (no renderer), for tests and headless runs; `mesh`, `skeleton` and
## `build` make the nodes.

const LEG_SCALE := 0.74 ## the toon's legs against AvatarSkeleton's 0.92 m to the hip
const HIP_X := 0.085 ## the hip joints either side of centre
const SPINE := 0.1
const CHEST := 0.2
const NECK := 0.17
const HEAD := 0.05
const SHOULDER := Vector2(0.19, 0.13) ## from the chest bone: out, up
const UPPER_ARM := 0.26
const FOREARM := 0.25
const ARM_SPLAY := 0.12 ## radians the arms hang out from the body at rest
const HEAD_UP := 0.15 ## the head's centre above the head bone
const MAX_TRIS := 5000 ## art bible section 3, "Cost"
const DETAIL := 0.85 ## a survivor's segment counts against the parts' own (about 4,000 triangles)
const ZOMBAI_DETAIL := 0.6 ## a walker's: up to 24 of them at night, so about 2,500 triangles each
const SHADE_UP := 0.14 ## darker toward the feet, like the world's baked shade
const TAG_HEIGHT := 1.95 ## the name tag over a toon's head
const BUILDS := [0.86, 1.0, 1.12, 1.25] ## Appearance "body": girth of the body and limbs
const ZOMBAI_VARIANTS := 4
const WHITE := Palette.EYE_WHITE
const MOUTH := Palette.MOUTH


## The bones as [name, parent, offset at rest], the order AvatarSkeleton.BONES has.
static func bones() -> Array:
	var su := sin(ARM_SPLAY)
	var cu := cos(ARM_SPLAY)
	var k := LEG_SCALE
	var out: Array = []
	for b in AvatarSkeleton.BONES:
		var n: String = b[0]
		var off: Vector3 = b[2]
		var x := 1.0 if n.begins_with("Left") else -1.0
		match n:
			"Hips": off = Vector3(0, AvatarSkeleton.HIP_HEIGHT * k + 0.05 * k, 0)
			"Spine": off = Vector3(0, SPINE, 0)
			"Chest": off = Vector3(0, CHEST, 0)
			"Neck": off = Vector3(0, NECK, 0)
			"Head": off = Vector3(0, HEAD, 0)
			"LeftUpperArm", "RightUpperArm": off = Vector3(SHOULDER.x * x, SHOULDER.y, 0)
			"LeftLowerArm", "RightLowerArm": off = Vector3(su * UPPER_ARM * x, -cu * UPPER_ARM, 0)
			"LeftHand", "RightHand": off = Vector3(su * FOREARM * x, -cu * FOREARM, 0)
			"LeftUpperLeg", "RightUpperLeg": off = Vector3(HIP_X * x, -0.05 * k, 0)
			"LeftLowerLeg", "RightLowerLeg": off = Vector3(0, -AvatarSkeleton.THIGH * k, 0)
			"LeftFoot", "RightFoot": off = Vector3(0, -AvatarSkeleton.SHIN * k, 0)
		out.append([n, b[1], off])
	return out


## Every joint's position at rest in the figure's space: bone name -> Vector3.
static func world_rest() -> Dictionary:
	var w := {}
	for b in bones():
		w[b[0]] = b[2] if b[1] == "" else (w[b[1]] as Vector3) + (b[2] as Vector3)
	return w


## A posable Skeleton3D ("Skeleton") at the toon's proportions, every bone at rest.
static func skeleton() -> Skeleton3D:
	var sk := Skeleton3D.new()
	sk.name = "Skeleton"
	for b in bones():
		var i := sk.get_bone_count()
		sk.add_bone(b[0])
		if b[1] != "":
			sk.set_bone_parent(i, sk.find_bone(b[1]))
		sk.set_bone_rest(i, Transform3D(Basis(), b[2]))
	sk.reset_bone_poses()
	return sk


static func skin() -> Skin:
	var s := Skin.new()
	var w := world_rest()
	for b in bones():
		s.add_named_bind(b[0], Transform3D(Basis(), -(w[b[0]] as Vector3)))
	return s


## The shared material: Emberlight "solid" lighting with no paint grain or brush.
static func material() -> ShaderMaterial:
	var m := Emberlight.material("solid", "folk")
	if not m.has_meta("folk"):
		m.set_meta("folk", true)
		m.set_shader_parameter("texel_grain", 0.0)
		m.set_shader_parameter("brush", 0.0)
	return m


## Everything the parts need from a look (Appearance; {} = never chosen: the seed stands in).
static func style(look: Dictionary, appearance_seed: int) -> Dictionary:
	var lk := Appearance.normalize(look) if Appearance.is_chosen(look) else Appearance.from_seed(appearance_seed)
	return {
		"bulk": BUILDS[int(lk.body)], "face": int(lk.face), "hair": int(lk.hair), "beard": int(lk.beard),
		"headwear": int(lk.headwear),
		"tunic": AvatarBuilder.worn_dye(Palette.CLOTH[int(lk.tunic)], appearance_seed),
		"skin": Palette.skin_tone(int(lk.skin)), "hair_col": Palette.HAIR[int(lk.hair_colour)],
		"trousers": Palette.TROUSER_DYES[int(lk.trousers)],
		"hood_col": Palette.WOOL.darkened(0.18),
		# Where the pupils look: a little apart, a little different per traveller (goofy, never cross-eyed).
		"gaze": 0.004 + 0.008 * fposmod(float(appearance_seed) * 0.6180339, 1.0),
		"zombai": false,
	}


## A Zombai walker's style, `variant` 0..ZOMBAI_VARIANTS-1: the same folk, dead. Ash-grey
## flesh, the clothes they died in drained of colour, blank eyes (art bible: the Zombai grey
## and ash-cold, the living warm).
static func zombai_style(variant: int) -> Dictionary:
	var st := style({}, 90210 + variant * 7919)
	st.zombai = true
	st.skin = ZombaiBody.flesh(variant)
	st.tunic = ZombaiBody.drained(st.tunic)
	st.trousers = ZombaiBody.drained(st.trousers)
	st.hair_col = ZombaiBody.drained(st.hair_col)
	st.hood_col = ZombaiBody.drained(st.hood_col)
	st.headwear = 0 if variant != 2 else 2
	st.hair = [0, 3, 1, 5][variant % 4]
	st.beard = [0, 1, 0, 2][variant % 4]
	st.bulk = [1.0, 0.86, 1.12, 1.0][variant % 4]
	return st


# ------------------------------------------------------------------ parts
# A part: [bone, arrays (PrimitiveMesh.get_mesh_arrays), colour, Transform3D at rest].

static var _prims := {}
static var _detail := 1.0 ## segment count scale for the parts being built (DETAIL, ZOMBAI_DETAIL)


static func _n(segments: int, least: int) -> int:
	return maxi(least, roundi(segments * _detail))


static func _prim(key: String, m: PrimitiveMesh) -> Array:
	if not _prims.has(key):
		_prims[key] = m.get_mesh_arrays()
	return _prims[key]


static func _ball_arrays(seg: int, rings: int) -> Array:
	var m := SphereMesh.new()
	m.radius = 1.0
	m.height = 2.0
	m.radial_segments = seg
	m.rings = rings
	return _prim("ball%d/%d" % [seg, rings], m)


## A basis whose Y runs along `up`.
static func _along(up: Vector3) -> Basis:
	var y := up.normalized()
	var ref := Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.95 else Vector3.RIGHT
	var x := ref.cross(y).normalized()
	return Basis(x, y, x.cross(y).normalized())


static func _ball(out: Array, bone: String, pos: Vector3, r: Vector3, c: Color, seg := 12, rings := 6, rot := Vector3.ZERO) -> void:
	out.append([bone, _ball_arrays(_n(seg, 6), _n(rings, 3)), c, Transform3D(Basis.from_euler(rot) * Basis.from_scale(r), pos)])


## A capsule from a to b of radius r.
static func _cap(out: Array, bone: String, a: Vector3, b: Vector3, r: float, c: Color, seg := 8) -> void:
	var len := a.distance_to(b)
	var m := CapsuleMesh.new()
	m.radius = r
	m.height = len + 2.0 * r
	m.radial_segments = _n(seg, 5)
	m.rings = 1 if _detail < 0.8 else 2
	out.append([bone, _prim("cap%d/%d/%.3f/%.3f" % [m.radial_segments, m.rings, r, len], m), c, Transform3D(_along(a - b), (a + b) * 0.5)])


static func _cyl(out: Array, bone: String, pos: Vector3, rt: float, rb: float, h: float, c: Color, seg := 12, rot := Vector3.ZERO, scl := Vector3.ONE) -> void:
	var m := CylinderMesh.new()
	m.top_radius = rt
	m.bottom_radius = rb
	m.height = h
	m.radial_segments = _n(seg, 6)
	m.rings = 0
	out.append([bone, _prim("cyl%d/%.3f/%.3f/%.3f" % [m.radial_segments, rt, rb, h], m), c, Transform3D(Basis.from_euler(rot) * Basis.from_scale(scl), pos)])


## Every part of a figure in `st` (style / zombai_style).
static func parts(st: Dictionary) -> Array:
	_detail = ZOMBAI_DETAIL if st.zombai else DETAIL
	var out: Array = []
	var W := world_rest()
	var B: float = st.bulk
	var skin: Color = st.skin
	var tunic: Color = st.tunic
	var hair: Color = st.hair_col
	var z: bool = st.zombai
	var hip: Vector3 = W.Hips
	var hood := int(st.headwear) == 1
	# --- body: a pear, a belt, the seat of the trousers ---
	_ball(out, "Spine", hip + Vector3(0, 0.12, 0.01), Vector3(0.2 * B, 0.22, 0.17 * B), tunic, 14, 7)
	_ball(out, "Chest", W.Chest + Vector3(0, 0.06, 0), Vector3(0.17 * B, 0.16, 0.13 * B), tunic, 14, 7)
	_cyl(out, "Hips", hip + Vector3(0, 0.02, 0), 0.198 * B, 0.19 * B, 0.05, Palette.LEATHER_DARK, 14, Vector3.ZERO, Vector3(1, 1, 0.86))
	_ball(out, "Hips", hip + Vector3(0, 0.02, 0.165 * B), Vector3(0.035, 0.03, 0.015), Palette.IRON, 8, 4) # buckle
	_ball(out, "Hips", hip + Vector3(0, -0.04, 0), Vector3(0.17 * B, 0.09, 0.14 * B), st.trousers, 12, 6)
	if not z:
		_ball(out, "Hips", hip + Vector3(0.12 * B, -0.03, 0.12 * B), Vector3(0.05, 0.055, 0.03), Palette.LEATHER, 8, 4) # pouch
	if not hood and not z:
		for x in [-1.0, 1.0]: # braces over the belly
			_cap(out, "Chest", W.Chest + Vector3(0.085 * x * B, 0.17, 0.085 * B), hip + Vector3(0.11 * x * B, 0.05, 0.165 * B), 0.016, Palette.LEATHER_DARK, 6)
	if not z and not hood:
		# A little pack and a bedroll on the back: what the camera sees all game.
		_ball(out, "Chest", W.Chest + Vector3(0, 0.02, -0.15 * B - 0.05), Vector3(0.13, 0.15, 0.07), Palette.LEATHER, 10, 5)
		_cap(out, "Chest", W.Chest + Vector3(-0.13, 0.18, -0.15 * B - 0.05), W.Chest + Vector3(0.13, 0.18, -0.15 * B - 0.05), 0.05, Palette.BEDROLL, 8)
	if hood:
		_cyl(out, "Chest", W.Chest + Vector3(0, -0.06, -0.08 * B), 0.15 * B, 0.22 * B, 0.5, (st.hood_col as Color).darkened(0.08), 14, Vector3(0.1, 0, 0), Vector3(1, 1, 0.5)) # cloak
	if z:
		_ball(out, "Spine", hip + Vector3(-0.07, 0.15, 0.17 * B), Vector3(0.05, 0.06, 0.012), Palette.SOOT.lerp(Palette.SMOULDER, 0.35), 8, 4) # the wound it died of
	# --- neck and head ---
	_cap(out, "Neck", W.Neck, W.Head + Vector3(0, 0.03, 0), 0.05, skin, 8)
	var hc: Vector3 = W.Head + Vector3(0, HEAD_UP, 0.01)
	var face: int = st.face
	var hr: Vector3 = [Vector3(0.14, 0.18, 0.15), Vector3(0.155, 0.165, 0.15), Vector3(0.16, 0.16, 0.155), Vector3(0.15, 0.17, 0.15)][face]
	_ball(out, "Head", hc, hr, skin, 16, 8)
	var jowl: Vector3 = [Vector3(0.11, 0.08, 0.11), Vector3(0.14, 0.085, 0.12), Vector3(0.14, 0.1, 0.13), Vector3(0.13, 0.09, 0.12)][face]
	_ball(out, "Head", hc + Vector3(0, -0.08, 0.03), jowl, skin, 14, 7)
	# Googly eyes: big whites, dark pupils looking a little apart. The Zombai's are blank.
	var gaze: float = st.gaze
	for x in [-1.0, 1.0]:
		var er := 0.042 if not (z and x < 0.0) else 0.032
		var ec: Vector3 = hc + Vector3(0.055 * x, 0.04, hr.z - 0.025)
		_ball(out, "Head", ec, Vector3(er, er * 1.15, er * 0.8), WHITE if not z else WHITE.lerp(Palette.FIRE_ASH, 0.4), 10, 5)
		if z:
			_ball(out, "Head", ec + Vector3(0.0, -0.01, er * 0.74), Vector3(0.007, 0.007, 0.005), Palette.SOOT, 6, 3)
		else:
			_ball(out, "Head", ec + Vector3(gaze * x, -0.004, er * 0.72), Vector3(0.016, 0.018, 0.01), Palette.EYE, 8, 4)
			var heavy := 1.4 if face == 3 else 1.0
			_cap(out, "Head", ec + Vector3(-0.03 * x, 0.058 - 0.006 * (heavy - 1.0), 0.0), ec + Vector3(0.035 * x, 0.064 - 0.012 * heavy, -0.005), 0.02 * heavy, hair.darkened(0.15), 6)
		_ball(out, "Head", hc + Vector3((hr.x - 0.005) * x, 0.0, -0.01), Vector3(0.025, 0.045, 0.03), skin, 8, 4) # ears
	# A long droopy nose, and a smile (the Zombai's mouth hangs open).
	_cap(out, "Head", hc + Vector3(0, 0.0, hr.z), hc + Vector3(0, -0.06, hr.z + 0.05), 0.03, skin.darkened(0.04), 8)
	_ball(out, "Head", hc + Vector3(0, -0.068, hr.z + 0.055), Vector3(0.038, 0.032, 0.034), skin.darkened(0.06), 10, 5)
	if z:
		_ball(out, "Head", hc + Vector3(0.02, -0.12, hr.z - 0.03), Vector3(0.05, 0.03, 0.02), MOUTH.darkened(0.3), 8, 4)
	elif int(st.beard) < 2:
		_cap(out, "Head", hc + Vector3(-0.04, -0.105, hr.z - 0.025), hc + Vector3(0.04, -0.11, hr.z - 0.025), 0.008, MOUTH, 6)
	# --- beard (None, Stubble, Short, Full, Moustache) ---
	match int(st.beard):
		1:
			_ball(out, "Head", hc + Vector3(0, -0.083, 0.032), jowl + Vector3(0.004, 0.004, 0.004), skin.lerp(hair, 0.4), 14, 7)
		2:
			_ball(out, "Head", hc + Vector3(0, -0.11, 0.06), Vector3(0.11, 0.08, 0.1), hair, 12, 6)
		3:
			_ball(out, "Head", hc + Vector3(0, -0.13, 0.06), Vector3(0.13, 0.11, 0.11), hair, 12, 6)
	if int(st.beard) in [2, 3, 4]:
		_cap(out, "Head", hc + Vector3(-0.07, -0.085, hr.z), hc + Vector3(0.07, -0.085, hr.z), 0.022, hair, 8) # moustache
	# --- hair (Cropped, Shaved, Tied back, Shoulder length, Braid, Bald) ---
	var hs: int = st.hair
	if hs != 5 and not hood:
		var mop: Vector3 = hr + Vector3(0.006, -0.04, 0.0) if hs != 1 else hr + Vector3(0.003, -0.06, -0.003)
		_ball(out, "Head", hc + Vector3(0, 0.08 if hs != 1 else 0.06, -0.02), mop, hair if hs != 1 else skin.lerp(hair, 0.6), 14, 7, Vector3(-0.4, 0, 0))
		match hs:
			2: _ball(out, "Head", hc + Vector3(0, 0.05, -hr.z - 0.02), Vector3(0.06, 0.06, 0.06), hair, 8, 4) # the knot
			3:
				_ball(out, "Head", hc + Vector3(0, -0.05, -0.06), Vector3(hr.x + 0.01, 0.13, 0.11), hair, 12, 6)
			4:
				for x in [-1.0, 1.0]: # two braids
					_cap(out, "Head", hc + Vector3((hr.x - 0.03) * x, 0.0, -0.06), hc + Vector3((hr.x + 0.02) * x, -0.2, -0.04), 0.03, hair, 8)
	# --- head gear: a felt cap, or a hood with a long tail ---
	if int(st.headwear) == 2:
		_ball(out, "Head", hc + Vector3(0, 0.11, -0.01), Vector3(hr.x + 0.012, 0.08, hr.z + 0.012), tunic.darkened(0.3), 14, 7)
		_cyl(out, "Head", hc + Vector3(0, 0.09, 0.0), hr.x + 0.03, hr.x + 0.03, 0.015, tunic.darkened(0.36), 14, Vector3(-0.15, 0, 0)) # brim
	if hood:
		var hcol: Color = st.hood_col
		_ball(out, "Head", hc + Vector3(0, 0.03, -0.05), hr + Vector3(0.025, 0.03, 0.02), hcol, 14, 7)
		_cap(out, "Head", hc + Vector3(0, 0.15, -0.12), hc + Vector3(0, 0.05, -0.28), 0.06, hcol, 8)
	# --- noodle arms, big hands ---
	for s in ["Left", "Right"]:
		var x := 1.0 if s == "Left" else -1.0
		var sh: Vector3 = W[s + "UpperArm"]
		var el: Vector3 = W[s + "LowerArm"]
		var wr: Vector3 = W[s + "Hand"]
		var sleeve := tunic.darkened(0.05)
		_ball(out, s + "UpperArm", sh, Vector3(0.06, 0.06, 0.06) * sqrt(B), sleeve, 10, 5)
		_cap(out, s + "UpperArm", sh, el, 0.042 * sqrt(B), sleeve, 8)
		_cap(out, s + "LowerArm", el, wr, 0.036 * sqrt(B), skin if z else sleeve, 8)
		_cyl(out, s + "LowerArm", wr + (el - wr).normalized() * 0.04, 0.05, 0.05, 0.05, Palette.LEATHER, 10, Vector3(0, 0, ARM_SPLAY * x)) # cuff
		var dn := (wr - el).normalized()
		var hand := wr + dn * 0.06
		_ball(out, s + "Hand", hand, Vector3(0.05, 0.065, 0.062), skin, 10, 5)
		for f in 3:
			var o := Vector3(-0.025 + f * 0.025, 0, 0) * x
			_cap(out, s + "Hand", hand + dn * 0.045 + Vector3(0, 0, 0.02) + o, hand + dn * 0.07 + Vector3(0, 0, 0.065) + o, 0.019, skin, 6)
		_cap(out, s + "Hand", hand + Vector3(-0.02 * x, 0.01, 0.045), hand + Vector3(-0.035 * x, -0.04, 0.07), 0.018, skin, 6) # thumb
	# --- short legs, big boots ---
	for s in ["Left", "Right"]:
		var hj: Vector3 = W[s + "UpperLeg"]
		var kn: Vector3 = W[s + "LowerLeg"]
		var an: Vector3 = W[s + "Foot"]
		_cap(out, s + "UpperLeg", hj, kn, 0.06 * sqrt(B), st.trousers, 8)
		_cap(out, s + "LowerLeg", kn, an + Vector3(0, 0.12, 0), 0.05 * sqrt(B), st.trousers, 8)
		_cyl(out, s + "LowerLeg", an + Vector3(0, 0.1, 0), 0.07, 0.065, 0.13, Palette.LEATHER_DARK, 12)
		_ball(out, s + "Foot", an + Vector3(0, -0.005, 0.07), Vector3(0.085, 0.05, 0.15), Palette.LEATHER_DARK, 12, 6)
	return out


## The figure for `st` as plain arrays: {verts, normals, colors (linear), bones, weights}, one
## colour per part with a little shade toward the feet. Pure: no renderer, safe headless.
static func geometry(st: Dictionary) -> Dictionary:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var bone_ids := PackedInt32Array()
	var weights := PackedFloat32Array()
	for p in parts(st):
		var bi := AvatarSkeleton.index_of(p[0])
		var a: Array = p[1]
		var pv: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var pn: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
		var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX]
		var xf: Transform3D = p[3]
		var nb := xf.basis.inverse().transposed()
		var lin := (p[2] as Color).srgb_to_linear()
		var tv := PackedVector3Array()
		tv.resize(pv.size())
		var tn := PackedVector3Array()
		tn.resize(pv.size())
		for i in pv.size():
			tv[i] = xf * pv[i]
			tn[i] = (nb * pn[i]).normalized()
		for t in range(0, idx.size(), 3):
			var v0 := tv[idx[t]]
			var v1 := tv[idx[t + 1]]
			var v2 := tv[idx[t + 2]]
			if (v1 - v0).cross(v2 - v0).length_squared() < 1e-14:
				continue # a pole's sliver
			for j in 3:
				var v := tv[idx[t + j]]
				verts.append(v)
				normals.append(tn[idx[t + j]])
				var f := 1.0 - SHADE_UP * clampf(1.0 - v.y / 1.6, 0.0, 1.0)
				colors.append(Color(lin.r * f, lin.g * f, lin.b * f, 1.0))
				bone_ids.append_array([bi, 0, 0, 0])
				weights.append_array([1.0, 0.0, 0.0, 0.0])
	return {"verts": verts, "normals": normals, "colors": colors, "bones": bone_ids, "weights": weights}


static func mesh_from(geo: Dictionary) -> ArrayMesh:
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = geo.verts
	arr[Mesh.ARRAY_NORMAL] = geo.normals
	arr[Mesh.ARRAY_COLOR] = geo.colors
	arr[Mesh.ARRAY_BONES] = geo.bones
	arr[Mesh.ARRAY_WEIGHTS] = geo.weights
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


## A posable toon (Skeleton3D "Skeleton" with its one skinned MeshInstance3D "Mesh") wearing
## `mesh`, scaled to `height` about the feet.
static func rig(mesh: ArrayMesh, height: float = 1.0) -> Skeleton3D:
	var sk := skeleton()
	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	mi.mesh = mesh
	mi.skin = skin()
	mi.material_override = material()
	sk.add_child(mi)
	mi.skeleton = NodePath("..")
	sk.scale = Vector3.ONE * height
	return sk


## A survivor for `look` (Appearance) as a posable skeleton, like AvatarBuilder.skinned.
static func skinned(appearance_seed: int, look: Dictionary = {}) -> Skeleton3D:
	return rig(mesh_from(geometry(style(look, appearance_seed))), AvatarBuilder.height_scale(look))


## A survivor with a name tag, like AvatarBuilder.build: the "Skeleton" and the Label3D as
## direct children of the returned root.
static func build(display_name: String, appearance_seed: int, is_self: bool, look: Dictionary = {}) -> Node3D:
	var root := Node3D.new()
	root.add_child(skinned(appearance_seed, look))
	var tag := Label3D.new()
	tag.text = display_name
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.position = Vector3(0, TAG_HEIGHT, 0)
	tag.font_size = 40
	tag.pixel_size = 0.006
	tag.outline_size = 8
	tag.modulate = Palette.NAME_TAG_SELF if is_self else Palette.NAME_TAG
	root.add_child(tag)
	return root


## Walker body `variant` (ZombaiFigures builds each once and shares it).
static func zombai_mesh(variant: int) -> ArrayMesh:
	return mesh_from(geometry(zombai_style(variant)))
