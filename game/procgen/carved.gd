class_name Carved
## The survivors and the Zombai, clean carved (owner's pick, 2026-11-26: direction B of the three
## shown in game, "clean carved real proportions", after trying the goofy cartoon). Art bible
## section 3, "Characters".
##
## Real adult proportions on the traveller's own skeleton (AvatarSkeleton: 1.78 m, hips at
## 0.92 m), built from a few dozen low-poly solids (tapered prisms, faceted balls, blocks) with
## FLAT shading, so every facet catches the light like a carved and painted wooden figure. One
## flat dye per part, the usual darker-toward-the-feet shade, and NO paint grain: the shared
## "carved" Emberlight material turns the grain and brush off, so a face reads as a face, not
## pixel noise (the owner's screenshot of the sculpted body, 2026-11-26).
##
## Every part rides one bone rigidly; they merge into ONE skinned mesh per figure (one draw
## call), about 1,500 triangles. A figure builds in a few milliseconds, so there is no thread
## or cache: a look is drawn the moment it is seen. Every AvatarClips pose plays on it as is.
##
## `geometry(st)` is pure (no renderer), for tests and headless runs; `rig`, `skinned` and
## `build` make the nodes.

const MAX_TRIS := 3000
const SHADE_UP := 0.14 ## darker toward the feet, like the world's baked shade
const TAG_HEIGHT := 2.2 ## the name tag over a traveller's head
const BUILDS := [0.88, 1.0, 1.12, 1.24] ## Appearance "body": girth of the body and limbs
const ZOMBAI_VARIANTS := 4
const HEAD_UP := 0.13 ## the head's centre above the head bone
const ARM_IN := 0.035 ## the arm is carved this much closer in than the shoulder joint
## Face (Appearance "face": Narrow, Square, Round, Strong brow): [skull half widths, jaw width].
const FACES := [[Vector3(0.092, 0.122, 0.106), 0.105], [Vector3(0.1, 0.118, 0.106), 0.13],
	[Vector3(0.104, 0.116, 0.11), 0.12], [Vector3(0.1, 0.12, 0.108), 0.125]]


## The shared material: Emberlight "solid" lighting with no paint grain or brush.
static func material() -> ShaderMaterial:
	var m := Emberlight.material("solid", "carved")
	if not m.has_meta("carved"):
		m.set_meta("carved", true)
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
		"zombai": false,
	}


## A Zombai walker's style, `variant` 0..ZOMBAI_VARIANTS-1: a traveller, dead. Ash-grey flesh,
## the clothes they died in drained of colour, no pack (art bible: the Zombai grey and
## ash-cold, the living warm).
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
	st.bulk = [1.0, 0.88, 1.12, 1.0][variant % 4]
	return st


# ------------------------------------------------------------------ parts
# A part: [bone, arrays (PrimitiveMesh.get_mesh_arrays), colour, Transform3D at rest].

static var _prims := {}


static func _prim(key: String, m: PrimitiveMesh) -> Array:
	if not _prims.has(key):
		_prims[key] = m.get_mesh_arrays()
	return _prims[key]


## A basis whose Y runs along `up`.
static func _along(up: Vector3) -> Basis:
	var y := up.normalized()
	var ref := Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.95 else Vector3.RIGHT
	var x := ref.cross(y).normalized()
	return Basis(x, y, x.cross(y).normalized())


## A faceted ball of half widths `r`.
static func _ball(out: Array, bone: String, pos: Vector3, r: Vector3, c: Color, seg := 7, rings := 5, rot := Vector3.ZERO) -> void:
	var m := SphereMesh.new()
	m.radius = 1.0
	m.height = 2.0
	m.radial_segments = seg
	m.rings = rings
	out.append([bone, _prim("ball%d/%d" % [seg, rings], m), c, Transform3D(Basis.from_euler(rot) * Basis.from_scale(r), pos)])


static func _box(out: Array, bone: String, pos: Vector3, size: Vector3, c: Color, rot := Vector3.ZERO) -> void:
	var m := BoxMesh.new()
	out.append([bone, _prim("box", m), c, Transform3D(Basis.from_euler(rot) * Basis.from_scale(size), pos)])


## A prism of `sides` sides (a cone when rt is 0), squashed front to back by `depth`.
static func _cyl(out: Array, bone: String, pos: Vector3, rt: float, rb: float, h: float, c: Color, sides := 7, rot := Vector3.ZERO, depth := 1.0) -> void:
	var m := CylinderMesh.new()
	m.top_radius = rt
	m.bottom_radius = rb
	m.height = h
	m.radial_segments = sides
	m.rings = 0
	out.append([bone, _prim("cyl%d/%.3f/%.3f/%.3f" % [sides, rt, rb, h], m), c, Transform3D(Basis.from_euler(rot) * Basis.from_scale(Vector3(1, 1, depth)), pos)])


## A tapered limb segment from a (radius r1) to b (radius r2).
static func _seg(out: Array, bone: String, a: Vector3, b: Vector3, r1: float, r2: float, c: Color, sides := 6) -> void:
	var h := a.distance_to(b)
	var m := CylinderMesh.new()
	m.top_radius = r1
	m.bottom_radius = r2
	m.height = h
	m.radial_segments = sides
	m.rings = 0
	out.append([bone, _prim("cyl%d/%.3f/%.3f/%.3f" % [sides, r1, r2, h], m), c, Transform3D(_along(a - b), (a + b) * 0.5)])


## Every part of a figure in `st` (style / zombai_style).
static func parts(st: Dictionary) -> Array:
	var out: Array = []
	var W := {}
	for b in AvatarSkeleton.bones():
		W[b.name] = b.world
	var B: float = st.bulk
	var skin: Color = st.skin
	var tunic: Color = st.tunic
	var hair: Color = st.hair_col
	var trousers: Color = st.trousers
	var z: bool = st.zombai
	var hood := int(st.headwear) == 1
	var hip: Vector3 = W.Hips
	var sleeve := tunic.darkened(0.06)
	var leather := Palette.LEATHER
	var dark := Palette.LEATHER_DARK
	# --- torso: a broad chest over a narrower waist, flatter front to back ---
	_cyl(out, "Hips", hip + Vector3(0, -0.02, 0), 0.15 * B, 0.16 * B, 0.16, trousers, 7, Vector3.ZERO, 0.72) # pelvis
	_cyl(out, "Spine", hip + Vector3(0, 0.15, 0), 0.168 * B, 0.152 * B, 0.22, tunic, 7, Vector3.ZERO, 0.7)
	_cyl(out, "Chest", W.Chest + Vector3(0, 0.07, 0), 0.195 * B, 0.168 * B, 0.24, tunic, 7, Vector3.ZERO, 0.68)
	_cyl(out, "Chest", W.Neck + Vector3(0, -0.025, 0), 0.065, 0.185 * B, 0.07, sleeve, 7, Vector3.ZERO, 0.68) # the shoulders' slope
	if not hood and not z:
		_cyl(out, "Chest", W.Chest + Vector3(0, 0.02, 0.004), 0.19 * B, 0.175 * B, 0.3, leather.darkened(0.05), 7, Vector3.ZERO, 0.72) # jerkin
		_box(out, "Chest", W.Chest + Vector3(0, 0.03, 0.128 * B), Vector3(0.028, 0.26, 0.01), tunic) # its lacing gap
	_cyl(out, "Hips", hip + Vector3(0, 0.03, 0), 0.162 * B, 0.162 * B, 0.045, dark.darkened(0.1), 7, Vector3.ZERO, 0.74) # belt
	_box(out, "Hips", hip + Vector3(0, 0.03, 0.12 * B), Vector3(0.04, 0.035, 0.012), Palette.IRON) # buckle
	if not z:
		_box(out, "Hips", hip + Vector3(0.095 * B, -0.02, 0.105 * B), Vector3(0.07, 0.08, 0.04), leather) # pouch
		_box(out, "Hips", hip + Vector3(-0.15 * B, -0.07, -0.02), Vector3(0.025, 0.16, 0.04), dark, Vector3(0, 0, 0.15)) # knife at the hip
	_cyl(out, "Hips", hip + Vector3(0, -0.07, 0), 0.158 * B, 0.18 * B, 0.15, tunic.darkened(0.12), 7, Vector3.ZERO, 0.78) # the tunic's skirt
	if hood:
		_cyl(out, "Chest", W.Chest + Vector3(0, -0.14, -0.07 * B), 0.2 * B, 0.25 * B, 0.66, (st.hood_col as Color).darkened(0.06), 6, Vector3(0.06, 0, 0), 0.42) # cloak
	elif not z:
		# A pack and a bedroll: what the camera sees from behind all game.
		_box(out, "Chest", W.Chest + Vector3(0, 0.02, -0.13 * B - 0.06), Vector3(0.26, 0.3, 0.12), leather, Vector3(0.05, 0, 0))
		_cyl(out, "Chest", W.Chest + Vector3(0, 0.2, -0.13 * B - 0.07), 0.065, 0.065, 0.34, Palette.BEDROLL, 7, Vector3(0, 0, PI * 0.5))
		for x in [-1.0, 1.0]: # straps over the shoulders
			_box(out, "Chest", W.Chest + Vector3(0.085 * x, 0.12, 0.118 * B), Vector3(0.03, 0.26, 0.012), dark)
	if z:
		_box(out, "Chest", W.Chest + Vector3(-0.07, 0.03, 0.118 * B), Vector3(0.08, 0.1, 0.02), Palette.SOOT.lerp(Palette.SMOULDER, 0.3), Vector3(0, 0, 0.3)) # the wound
	# --- neck and head: angular ---
	_cyl(out, "Neck", W.Neck + Vector3(0, 0.06, 0), 0.052 * sqrt(B), 0.06 * sqrt(B), 0.14, skin, 6)
	var hc: Vector3 = W.Head + Vector3(0, HEAD_UP, 0)
	var face: int = st.face
	var hr: Vector3 = FACES[face][0]
	var jaw: float = FACES[face][1]
	_ball(out, "Head", hc, hr, skin, 7, 5)
	_box(out, "Head", hc + Vector3(0, -0.062, 0.036), Vector3(jaw, 0.07, 0.092), skin, Vector3(0.25, 0, 0)) # jaw
	_cyl(out, "Head", hc + Vector3(0, -0.012, hr.z - 0.006), 0.0, 0.024, 0.06, skin.darkened(0.05), 4, Vector3(0.35, 0, 0), 0.85) # nose
	var ridge := 0.03 if face == 3 else 0.02
	_box(out, "Head", hc + Vector3(0, 0.03, hr.z - 0.022), Vector3(hr.x * 1.25, ridge, 0.03), skin) # brow ridge
	var eye := Palette.EYE if not z else Palette.FIRE_ASH.lightened(0.2)
	for x in [-1.0, 1.0]:
		_box(out, "Head", hc + Vector3(0.036 * x, 0.012, hr.z - 0.012), Vector3(0.02, 0.013, 0.01), eye)
		if not z:
			_box(out, "Head", hc + Vector3(0.037 * x, 0.044 + ridge * 0.3, hr.z - 0.006), Vector3(0.036, 0.011 + ridge * 0.2, 0.01), hair.darkened(0.15), Vector3(0, 0, -0.12 * x)) # eyebrow
		_box(out, "Head", hc + Vector3((hr.x - 0.003) * x, -0.005, -0.005), Vector3(0.018, 0.042, 0.03), skin) # ear
	if z:
		_box(out, "Head", hc + Vector3(0.005, -0.06, hr.z - 0.012), Vector3(0.042, 0.028, 0.012), Palette.MOUTH.darkened(0.35)) # slack mouth
	else:
		_box(out, "Head", hc + Vector3(0, -0.058, hr.z - 0.012), Vector3(0.04, 0.008, 0.01), Palette.MOUTH)
	# --- beard (None, Stubble, Short beard, Full beard, Moustache) ---
	match int(st.beard):
		1:
			_box(out, "Head", hc + Vector3(0, -0.064, 0.037), Vector3(jaw + 0.006, 0.072, 0.094), skin.lerp(hair, 0.4), Vector3(0.25, 0, 0))
		2:
			_ball(out, "Head", hc + Vector3(0, -0.08, 0.05), Vector3(jaw * 0.6, 0.06, 0.065), hair, 6, 4)
		3:
			_ball(out, "Head", hc + Vector3(0, -0.095, 0.05), Vector3(jaw * 0.62, 0.085, 0.072), hair, 6, 4)
	if int(st.beard) in [2, 3, 4]:
		_box(out, "Head", hc + Vector3(0, -0.04, hr.z - 0.006), Vector3(0.065, 0.018, 0.02), hair) # moustache
	# --- hair (Cropped, Shaved, Tied back, Shoulder length, Braid, Bald) ---
	var hs: int = st.hair
	if hs != 5:
		var thin := 0.006 if hs == 1 else 0.0
		_ball(out, "Head", hc + Vector3(0, 0.035, -0.012), hr + Vector3(0.006 - thin, -0.025 - thin, 0.006 - thin), hair if hs != 1 else skin.lerp(hair, 0.6), 7, 5, Vector3(-0.3, 0, 0))
		match hs:
			2: # tied back: a knot and a short tail
				_ball(out, "Head", hc + Vector3(0, 0.0, -hr.z - 0.012), Vector3(0.032, 0.03, 0.03), hair, 5, 3)
				_seg(out, "Head", hc + Vector3(0, -0.02, -hr.z - 0.02), hc + Vector3(0, -0.12, -hr.z - 0.03), 0.02, 0.012, hair, 5)
			3: # shoulder length
				_box(out, "Head", hc + Vector3(0, -0.06, -0.055), Vector3(hr.x * 1.9, 0.17, 0.08), hair, Vector3(-0.1, 0, 0))
			4: # a braid down the back
				_seg(out, "Head", hc + Vector3(0, -0.04, -hr.z + 0.005), hc + Vector3(0, -0.3, -hr.z - 0.03), 0.028, 0.016, hair, 5)
	# --- head gear: a felt cap, or a hood set back so the face stays clear ---
	if int(st.headwear) == 2:
		_cyl(out, "Head", hc + Vector3(0, 0.08, -0.01), hr.x * 0.95, hr.x + 0.012, 0.07, tunic.darkened(0.3), 8, Vector3(-0.12, 0, 0))
		_cyl(out, "Head", hc + Vector3(0, 0.05, 0.0), hr.x + 0.028, hr.x + 0.028, 0.012, tunic.darkened(0.36), 8, Vector3(-0.12, 0, 0)) # brim
	if hood:
		var hcol: Color = st.hood_col
		_ball(out, "Head", hc + Vector3(0, 0.022, -0.045), hr + Vector3(0.022, 0.018, 0.016), hcol, 7, 5)
		_cyl(out, "Neck", W.Neck + Vector3(0, 0.03, -0.01), 0.1, 0.175 * B, 0.1, hcol, 7, Vector3.ZERO, 0.8) # cowl on the shoulders
	# --- arms, hands with fingers ---
	for s in ["Left", "Right"]:
		var x := 1.0 if s == "Left" else -1.0
		var sh: Vector3 = W[s + "UpperArm"] + Vector3(-ARM_IN * x, -0.01, 0)
		var el: Vector3 = W[s + "LowerArm"] + Vector3(-ARM_IN * 0.5 * x, 0, 0)
		var wr: Vector3 = W[s + "Hand"]
		var g := sqrt(B)
		_ball(out, s + "UpperArm", sh + Vector3(0, -0.02, 0), Vector3(0.066, 0.072, 0.066) * g, sleeve, 6, 4) # deltoid
		_seg(out, s + "UpperArm", sh, el, 0.06 * g, 0.05 * g, sleeve)
		_seg(out, s + "LowerArm", el, wr, 0.05 * g, 0.038 * g, skin if z else leather.darkened(0.1)) # bracer
		var dn := (wr - el).normalized()
		_box(out, s + "Hand", wr + dn * 0.045 + Vector3(0, 0, 0.005), Vector3(0.032, 0.08, 0.072), skin, Vector3(0, 0, -0.09 * x)) # palm
		_box(out, s + "Hand", wr + dn * 0.11 + Vector3(0, 0, 0.014), Vector3(0.03, 0.06, 0.066), skin.darkened(0.04), Vector3(0.3, 0, -0.09 * x)) # fingers, curled
		_box(out, s + "Hand", wr + dn * 0.05 + Vector3(-0.012 * x, 0, 0.046), Vector3(0.022, 0.052, 0.022), skin, Vector3(-0.3, 0, 0.2 * x)) # thumb
	# --- legs, boots ---
	for s in ["Left", "Right"]:
		var hj: Vector3 = W[s + "UpperLeg"]
		var kn: Vector3 = W[s + "LowerLeg"]
		var an: Vector3 = W[s + "Foot"]
		var g := sqrt(B)
		_seg(out, s + "UpperLeg", hj + Vector3(0, 0.04, 0), kn, 0.088 * g, 0.062 * g, trousers)
		_seg(out, s + "LowerLeg", kn, an + Vector3(0, 0.3, 0), 0.062 * g, 0.054 * g, trousers)
		_seg(out, s + "LowerLeg", an + Vector3(0, 0.32, 0), an, 0.066 * g, 0.056, dark) # boot shaft
		_cyl(out, s + "LowerLeg", an + Vector3(0, 0.3, 0), 0.075 * g, 0.072 * g, 0.045, leather, 6) # turned-down cuff
		_box(out, s + "Foot", an + Vector3(0, -0.028, 0.05), Vector3(0.095, 0.062, 0.24), dark) # foot
		_box(out, s + "Foot", an + Vector3(0, -0.05, 0.05), Vector3(0.102, 0.02, 0.25), dark.darkened(0.25)) # sole
	return out


## The figure for `st` as plain arrays: {verts, normals (flat, one per face), colors (linear),
## bones, weights}, one colour per part with a little shade toward the feet. Pure: no
## renderer, safe headless.
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
		for t in range(0, idx.size(), 3):
			var v0 := xf * pv[idx[t]]
			var v1 := xf * pv[idx[t + 1]]
			var v2 := xf * pv[idx[t + 2]]
			var fn := (v1 - v0).cross(v2 - v0)
			if fn.length_squared() < 1e-14:
				continue # a pole's sliver
			fn = fn.normalized()
			# Face the way the primitive's own normals point (winding differs between primitives).
			if fn.dot(nb * (pn[idx[t]] + pn[idx[t + 1]] + pn[idx[t + 2]])) < 0.0:
				fn = -fn
			for v in [v0, v1, v2]:
				verts.append(v)
				normals.append(fn)
				var f := 1.0 - SHADE_UP * clampf(1.0 - (v as Vector3).y / 1.8, 0.0, 1.0)
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


## A posable figure (AvatarSkeleton "Skeleton" with its one skinned MeshInstance3D "Mesh")
## wearing `mesh`, scaled to `height` about the feet.
static func rig(mesh: ArrayMesh, height: float = 1.0) -> Skeleton3D:
	var sk := AvatarSkeleton.build()
	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	mi.mesh = mesh
	mi.skin = AvatarSkeleton.skin()
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
