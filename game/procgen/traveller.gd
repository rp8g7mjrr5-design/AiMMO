class_name Traveller
## The sculpted traveller (art bible section 3, "Characters": the model direction). One
## continuous body sculpted from soft shapes (SculptField), smoothed, cut to the triangle
## budget, painted in flat regions with straight hems, and skinned to the 18-bone
## AvatarSkeleton, so every clip AvatarAnimator plays (idle, walk, run, swings, the fight)
## poses it unchanged.
##
## The work is split so the slow part runs once and off the main thread:
## - `shape_key(look)` names the geometry a look needs (build, face, hair, beard, head, layer).
##   Colours are not in it: a dye or skin change reuses the same geometry.
## - `geometry(style)` sculpts it: seconds of GDScript, pure, safe on a worker thread and
##   headless. The result is plain packed arrays, cached by the client (TravellerBodies).
## - `paint(geo, style)` colours it from the look: fast, and gives the ArrayMesh.
##
## A look is an Appearance (`{}` = never chosen: `Appearance.from_seed` stands in, so a seed
## still picks the hood, skin, hair colour and dye it always did).

const VERSION := 1 ## bump when the sculpt or paint rules change (the client's disk cache is keyed by it)
const TARGET_TRIS := 2900 ## before the hem slices; the finished body stays under MAX_TRIS
const MAX_TRIS := 5000 ## art bible section 3, "Cost"
const SMOOTH_PASSES := 6
const CREASE := 0.55 ## cos of the angle past which two faces keep a hard edge (about 57 degrees)
const SH := 0.235 ## shoulder joint x (AvatarSkeleton)
const ARM_IN := 0.025 ## arms are sculpted this much closer in than the joints: natural shoulders
const SHADE_UP := 0.14 ## darker toward the feet, like the world's baked shade
const SEAM := 0.19 ## |x| of the shoulder seam on an Average build (scales with bulk)
const LACING := 0.028 ## half width of the jerkin's lacing gap
const ARMPIT := 1.22 ## above this, the shoulder seam (not the nearest shape) splits sleeve from body
const HOOD_OPENING := 1.53 ## below this the hood's cowl covers the throat; above it, the face shows
const CLOAK_HEM := 0.8 ## the scout's cloak ends at the upper thigh, cut straight, clear of the striding legs
const POUCH_X := 0.1 ## the belt pouch: centre x on an Average build, half width, bottom edge
const POUCH_W := 0.045
const POUCH_BOTTOM := 0.875

## Body build (Appearance "body": Lean, Average, Sturdy, Broad) as the sculpt's one girth number.
const BULKS := [0.95, 1.03, 1.11, 1.2]

## Paint regions, by index (stored per triangle). Order is the cache format: add at the end.
const KEYS := ["tunic", "tunic_dark", "sleeve", "belt", "buckle", "leather", "skin", "brow", "eye",
	"beard", "lip", "hair", "trousers", "bracer", "boot", "boot_cuff", "hood", "cloak", "coat",
	"apron", "jerkin", "cap", "stubble"]


## Everything the sculpt and the paint need from a look: geometry choices and colours.
static func style(look: Dictionary, appearance_seed: int) -> Dictionary:
	var lk := Appearance.normalize(look) if Appearance.is_chosen(look) else Appearance.from_seed(appearance_seed)
	var tunic := AvatarBuilder.worn_dye(Palette.CLOTH[int(lk.tunic)], appearance_seed)
	var hair: Color = Palette.HAIR[int(lk.hair_colour)]
	var skin := Palette.skin_tone(int(lk.skin))
	var hood := int(lk.headwear) == 1
	return {
		"body": int(lk.body), "bulk": BULKS[int(lk.body)], "face": int(lk.face), "hair": int(lk.hair),
		"beard": int(lk.beard), "headwear": int(lk.headwear),
		# The trade layer: a hooded traveller is a scout (hood and cloak, no jerkin); everyone
		# else wears the leather jerkin. More layers come with their own choice in the window.
		"hood": hood, "cloak": hood, "jerkin": not hood, "coat": false, "apron": false, "rolled": false,
		"tunic": tunic, "skin": skin, "hair_col": hair,
		"trousers": Palette.TROUSER_DYES[int(lk.trousers)],
		"hood_col": Palette.WOOL.darkened(0.18), # undyed wool, so the hood and cloak read apart from the shirt
	}


## The geometry a style needs, as a cache key. Same key, same mesh before paint.
static func shape_key(st: Dictionary) -> String:
	return "v%d-b%d-f%d-h%d-d%d-w%d-%s" % [VERSION, st.body, st.face, st.hair, st.beard, st.headwear,
		"scout" if st.cloak else "jerkin"]


## The colour of every paint region for a style.
static func colours(st: Dictionary) -> Dictionary:
	var tunic: Color = st.tunic
	var skin: Color = st.skin
	var hair: Color = st.hair_col
	return {"tunic": tunic, "tunic_dark": tunic.darkened(0.12), "sleeve": tunic.darkened(0.06),
		"belt": Palette.LEATHER_DARK.darkened(0.15), "buckle": Palette.IRON, "leather": Palette.LEATHER,
		"skin": skin, "brow": hair.darkened(0.12), "eye": Palette.EYE, "beard": hair.darkened(0.08),
		"lip": skin.darkened(0.1), "hair": hair, "trousers": st.trousers, "bracer": Palette.LEATHER.darkened(0.1),
		"boot": Palette.LEATHER_DARK, "boot_cuff": Palette.LEATHER, "hood": st.hood_col,
		"cloak": (st.hood_col as Color).darkened(0.08), "coat": Palette.COAT, "apron": Palette.LEATHER.darkened(0.2),
		"jerkin": Palette.LEATHER.darkened(0.05), "cap": tunic.darkened(0.3), "stubble": skin.lerp(hair, 0.45)}


## The anatomy and clothing of one traveller as soft shapes.
static func sculpt(s: SculptField, st: Dictionary) -> void:
	var B: float = st.bulk
	var face: int = st.face
	# --- torso: a sturdy working build, no waist pinch ---
	s.el(Vector3(0, 0.95, -0.005), Vector3(0.172 * B, 0.12, 0.12 * B), "tunic", "")
	s.el(Vector3(0, 1.10, 0.0), Vector3(0.172 * B, 0.15, 0.122 * B), "tunic", "")
	s.el(Vector3(0, 1.27, -0.005), Vector3(0.178 * B, 0.17, 0.13 * B), "tunic", "", 0.05)
	s.el(Vector3(0, 1.335, 0.055), Vector3(0.155, 0.07, 0.06) * B, "tunic", "", 0.05) # one broad chest slab
	for x in [-1.0, 1.0]:
		s.rc(Vector3(0.04 * x, 1.50, -0.025), Vector3(0.15 * x, 1.415, -0.02), 0.05 * B, 0.034 * B, "tunic", "", 0.05) # trapezius
		s.el(Vector3(0.07 * x, 0.9, -0.065), Vector3(0.08, 0.085, 0.065) * B, "trousers", "", 0.04) # seat
	s.rc(Vector3(0, 1.42, -0.06), Vector3(0, 1.08, -0.06), 0.115 * B, 0.095 * B, "tunic", "", 0.06) # back muscles
	s.rc(Vector3(0, 1.0, 0.0), Vector3(0, 0.93, -0.004), 0.174 * B, 0.176 * B, "tunic_dark", "", 0.03) # shirt hem
	if st.jerkin:
		s.set_prio(s.el(Vector3(0, 1.2, 0.0), Vector3(0.198 * B, 0.235, 0.142 * B), "jerkin", "", 0.02), 0.018)
		s.set_prio(s.rc(Vector3(0.0, 1.06, 0.15 * B), Vector3(0.0, 1.38, 0.13 * B), 0.012, 0.016, "tunic", "", 0.004), 0.03) # lacing gap
	# belt (proud of the jerkin) with a pouch and a knife at the back hip
	s.set_prio(s.el(Vector3(0, 1.0, 0.004), Vector3(0.178 * B + 0.006, 0.032, 0.132 * B + 0.006), "belt", "", 0.006), 0.03)
	s.el(Vector3(0.1 * B, 0.93, 0.125 * B), Vector3(0.045, 0.055, 0.03), "leather", "", 0.01) # pouch
	s.rc(Vector3(-0.1 * B, 0.98, -0.125 * B), Vector3(-0.11 * B, 0.84, -0.14 * B), 0.02, 0.012, "belt", "", 0.006) # knife sheath
	# --- neck and head ---
	var jaw_w: float = [0.93, 1.1, 1.06, 1.0][face]
	var cheek: float = [0.92, 1.04, 1.12, 1.0][face]
	s.rc(Vector3(0, 1.43, -0.005), Vector3(0, 1.57, 0.01), 0.058 * sqrt(B), 0.05 * sqrt(B), "skin", "Head", 0.03)
	s.el(Vector3(0, 1.685, -0.012), Vector3(0.089 * (1.04 if face == 2 else 1.0), 0.104, 0.104), "skin", "Head", 0.02) # cranium
	s.rc(Vector3(0, 1.665, 0.02), Vector3(0, 1.59 - (0.006 if face == 1 else 0.0), 0.05), 0.08 * jaw_w, 0.05 * jaw_w, "skin", "Head", 0.035) # jaw to chin
	s.el(Vector3(0, 1.635, 0.035), Vector3(0.074 * cheek, 0.05, 0.062), "skin", "Head", 0.03) # cheeks and jaw fill
	var brow := 1.35 if face == 3 else 1.0
	for x in [-1.0, 1.0]:
		s.el(Vector3(0.045 * x * cheek, 1.655, 0.07), Vector3(0.032, 0.024, 0.028), "skin", "Head", 0.025) # cheekbone
		s.rc(Vector3(0.012 * x, 1.705, 0.088), Vector3(0.055 * x, 1.703, 0.075), 0.014 * brow, 0.011 * brow, "brow", "Head", 0.012) # brow ridge
		s.el(Vector3(0.084 * x, 1.665, -0.005), Vector3(0.012, 0.03, 0.02), "skin", "Head", 0.01) # ear
	s.rc(Vector3(0, 1.69, 0.092), Vector3(0, 1.645, 0.117), 0.011, 0.017, "skin", "Head", 0.012) # nose
	for x in [-1.0, 1.0]:
		s.set_prio(s.el(Vector3(0.034 * x, 1.676, 0.091), Vector3(0.01, 0.0055, 0.005), "eye", "Head", 0.002), 0.003)
	s.set_prio(s.rc(Vector3(-0.022, 1.616, 0.082), Vector3(0.022, 1.616, 0.082), 0.005, 0.005, "skin", "Head", 0.004), 0.004)
	# --- hair (Appearance "hair": Cropped, Shaved, Tied back, Shoulder length, Braid, Bald) ---
	var hs: int = st.hair
	if hs != 5:
		var cap := 0.006 if hs == 1 else 0.0 # shaved: a close shadow over the skull
		s.set_prio(s.el(Vector3(0, 1.72, -0.03), Vector3(0.096 - cap, 0.088 - cap, 0.106 - cap), "hair", "Head", 0.012), 0.003)
		if hs != 1: # volume swept back over the crown, thicker at the back and over the ears
			s.el(Vector3(0, 1.745, -0.055), Vector3(0.09, 0.06, 0.09), "hair", "Head", 0.03)
			for x in [-1.0, 1.0]:
				s.el(Vector3(0.078 * x, 1.69, -0.04), Vector3(0.026, 0.05, 0.06), "hair", "Head", 0.02)
			s.el(Vector3(0, 1.66, -0.085), Vector3(0.075, 0.07, 0.035), "hair", "Head", 0.03)
		match hs:
			2: # tied back: a knot at the nape and a short tail
				s.el(Vector3(0, 1.665, -0.125), Vector3(0.034, 0.03, 0.03), "hair", "Head", 0.02)
				s.rc(Vector3(0, 1.65, -0.14), Vector3(0, 1.585, -0.15), 0.022, 0.012, "hair", "Head", 0.01)
			3: # shoulder length: hair falling behind the ears to the shoulders
				s.rc(Vector3(0, 1.66, -0.09), Vector3(0, 1.49, -0.11), 0.09, 0.07, "hair", "Head", 0.04)
				for x in [-1.0, 1.0]:
					s.rc(Vector3(0.075 * x, 1.66, -0.04), Vector3(0.085 * x, 1.52, -0.07), 0.03, 0.026, "hair", "Head", 0.03)
			4: # a braid down the back
				s.rc(Vector3(0, 1.66, -0.12), Vector3(0, 1.36, -0.155), 0.026, 0.016, "hair", "Head", 0.012)
	# --- beard (None, Stubble, Short beard, Full beard, Moustache): real mass on the jaw ---
	match int(st.beard):
		2:
			s.set_prio(s.el(Vector3(0, 1.61, 0.055), Vector3(0.074, 0.05, 0.062), "beard", "Head", 0.02), 0.004)
		3:
			s.set_prio(s.el(Vector3(0, 1.605, 0.05), Vector3(0.078, 0.062, 0.068), "beard", "Head", 0.02), 0.004)
			s.set_prio(s.el(Vector3(0, 1.56, 0.07), Vector3(0.05, 0.05, 0.045), "beard", "Head", 0.03), 0.004)
	if int(st.beard) in [2, 3, 4]:
		s.set_prio(s.rc(Vector3(-0.03, 1.628, 0.098), Vector3(0.03, 1.628, 0.098), 0.009, 0.009, "beard", "Head", 0.006), 0.006) # moustache
	# --- head gear and the trade layer ---
	if int(st.headwear) == 2: # felt cap, proud of the hair
		s.set_prio(s.el(Vector3(0, 1.75, -0.02), Vector3(0.104, 0.06, 0.114), "cap", "Head", 0.01), 0.02)
		s.set_ymin(s.size() - 1, 1.725)
	if st.hood:
		s.set_prio(s.el(Vector3(0, 1.7, -0.07), Vector3(0.116, 0.13, 0.125), "hood", "Head", 0.02), 0.02)
		s.set_prio(s.rc(Vector3(0, 1.535, -0.065), Vector3(0, 1.46, -0.025), 0.085, 0.16 * B, "hood", "Head", 0.03), 0.02) # cowl, below the chin
	if st.cloak:
		# A wool cloak hanging from the shoulders behind, flaring a little, cut flat at the hem
		# (mid-thigh, clear of the striding legs) and flat at the front so it never wraps the arms.
		var c := s.rc(Vector3(0, 1.4, -0.07 * B), Vector3(0, CLOAK_HEM, -0.1 * B), 0.15 * B, 0.2 * B, "cloak", "", 0.03)
		s.set_prio(c, 0.02)
		s.set_ymin(c, CLOAK_HEM)
		s.set_clip(c, Vector3(0, 0, 1), -0.085 * B)
	if st.coat:
		var i := s.rc(Vector3(0, 1.02, 0.0), Vector3(0, 0.5, -0.01), 0.176 * B, 0.205 * B, "coat", "", 0.03)
		s.set_prio(i, 0.01)
		s.set_ymin(i, 0.6)
	if st.apron:
		s.set_ymin(s.el(Vector3(0, 0.95, 0.1 * B), Vector3(0.16 * B, 0.4, 0.05), "apron", "", 0.03), 0.64)
	# --- arms, a little closer in than the joints ---
	var elb := AvatarSkeleton.world_rest("LeftLowerArm")
	var wri := AvatarSkeleton.world_rest("LeftHand")
	for x in [-1.0, 1.0]:
		var l := "ArmL" if x > 0 else "ArmR"
		var sh := Vector3((SH - ARM_IN) * x, 1.415, 0)
		var el := Vector3((absf(elb.x) - ARM_IN) * x, elb.y, 0)
		var wr := Vector3((absf(wri.x) - ARM_IN) * x, wri.y, 0)
		s.el(sh + Vector3(-0.025 * x, -0.035, 0), Vector3(0.056, 0.072, 0.062) * B, "sleeve", l, 0.05) # deltoid
		s.rc(sh + Vector3(0, -0.02, 0), el, 0.058 * B, 0.05 * B, "sleeve", l, 0.035)
		s.el(sh.lerp(el, 0.5) + Vector3(0, 0, 0.018), Vector3(0.052, 0.085, 0.052) * B, "sleeve", l, 0.03) # biceps
		s.rc(el, wr, 0.054 * B, 0.038, "bracer", l, 0.02)
		s.el(el.lerp(wr, 0.3) + Vector3(0, 0, 0.005), Vector3(0.057, 0.08, 0.052) * B, "bracer", l, 0.025) # forearm
		var down := (wr - el).normalized()
		s.rc(wr + down * 0.01, wr + down * 0.12 + Vector3(0, 0, 0.012), 0.034, 0.026, "skin", l, 0.015) # hand
		s.el(wr + down * 0.065, Vector3(0.03, 0.062, 0.052), "skin", l, 0.015)
		s.rc(wr + down * 0.03 + Vector3(-0.005 * x, 0, 0.03), wr + down * 0.08 + Vector3(-0.01 * x, 0, 0.05), 0.013, 0.011, "skin", l, 0.01) # thumb
	# --- legs ---
	for x in [-1.0, 1.0]:
		var l := "LegL" if x > 0 else "LegR"
		var hip := Vector3(0.095 * x, 0.92, 0)
		var knee := Vector3(0.095 * x, 0.46, 0.0)
		var ankle := Vector3(0.095 * x, 0.06, 0)
		s.rc(hip + Vector3(0.01 * x, 0.02, 0), knee, 0.102 * B, 0.066 * B, "trousers", l, 0.04)
		s.el(Vector3(0.1 * x, 0.7, 0.03), Vector3(0.072, 0.15, 0.07) * B, "trousers", l, 0.04) # quads
		s.el(knee + Vector3(0, 0.0, 0.035), Vector3(0.04, 0.045, 0.03), "trousers", l, 0.02) # knee
		s.rc(knee, ankle + Vector3(0, 0.1, 0), 0.062 * B, 0.045, "trousers", l, 0.02)
		s.el(Vector3(0.095 * x, 0.32, -0.03), Vector3(0.06, 0.11, 0.058) * B, "boot", l, 0.03) # calf
		s.rc(ankle + Vector3(0, 0.0, -0.035), ankle + Vector3(0.006 * x, -0.025, 0.15), 0.05, 0.038, "boot", l, 0.025) # foot
		s.set_prio(s.rc(ankle + Vector3(0, -0.01, 0), Vector3(0.095 * x, 0.33, -0.01), 0.058, 0.066 * B, "boot", l, 0.02), 0.01) # boot shaft
		s.set_prio(s.el(Vector3(0.095 * x, 0.34, -0.01), Vector3(0.078, 0.028, 0.074) * B, "boot_cuff", l, 0.008), 0.015) # cuff


## Where paint borders are cut into the mesh before it is coloured, so hems stay straight
## lines (art bible: "Hems and colour borders are straight lines"). Each: [axis, value,
## region lo, region hi] (a triangle is cut only if its centre is inside the region).
static func cuts(st: Dictionary) -> Array:
	var out: Array = []
	var any := Vector3(-9, -9, -9)
	var all := Vector3(9, 9, 9)
	for y in [0.335, 0.36]: # boot cuff
		out.append([1, y, any, Vector3(9, 0.6, 9)])
	for y in [0.84, 1.09]: # hand and bracer
		out.append([1, y, Vector3(-9, 0.7, -9), Vector3(9, 1.2, 9)])
	out.append([1, ARMPIT, Vector3(-0.35, 1.1, -9), Vector3(0.35, 1.3, 9)])
	out.append([1, POUCH_BOTTOM, Vector3(0.0, 0.8, 0.0), Vector3(0.3, 0.95, 9)])
	for y in [0.93, 0.966, 1.034]: # shirt hem and belt
		out.append([1, y, Vector3(-0.3, 0.85, -9), Vector3(0.3, 1.1, 9)])
	for y in [1.4, 1.44]: # jerkin top, neckline
		out.append([1, y, Vector3(-0.3, 1.3, -9), Vector3(0.3, 1.55, 9)])
	if st.hood:
		out.append([1, HOOD_OPENING, Vector3(-9, 1.45, 0.0), Vector3(9, 1.7, 9)])
	for y in [1.5, 1.645, 1.668, 1.684, 1.69, 1.7, 1.755]: # beard line, eyes, brows, hairline
		out.append([1, y, Vector3(-0.15, 1.45, 0.0), Vector3(0.15, 1.85, 9)])
	for x in [0.014, 0.024, 0.044, 0.054]: # eyes and brows across
		for sx in [-1.0, 1.0]:
			out.append([0, x * sx, Vector3(-0.1, 1.655, 0.04), Vector3(0.1, 1.715, 9)])
	for sx in [-1.0, 1.0]:
		out.append([0, 0.022 * sx, Vector3(-0.08, 0.95, 0.0), Vector3(0.08, 1.05, 9)]) # buckle
		out.append([0, SEAM * float(st.bulk) * sx, Vector3(-9, ARMPIT - 0.02, -9), Vector3(9, 1.47, 9)]) # sleeve seam
		out.append([0, (POUCH_X * float(st.bulk) + POUCH_W * sx), Vector3(0.0, 0.85, 0.0), Vector3(0.3, 1.0, 9)]) # pouch sides
		if st.jerkin:
			out.append([0, LACING * sx, Vector3(-0.08, 0.96, 0.0), Vector3(0.08, 1.41, 9)]) # the lacing gap
		if st.apron:
			out.append([0, 0.15 * sx, Vector3(-9, 0.6, 0.0), Vector3(9, 1.45, 9)])
	if st.cloak:
		out.append([1, CLOAK_HEM + 0.004, Vector3(-9, CLOAK_HEM - 0.05, -9), Vector3(9, CLOAK_HEM + 0.06, 0.0)])
	if st.coat:
		out.append([1, 0.86, Vector3(-9, 0.75, -9), Vector3(9, 0.95, 9)])
	return out


## Which paint region a surface triangle gets: the shape it came from, tidied into clean
## clothing bands by where it is.
static func paint_rule(st: Dictionary, k: String, l: String, p: Vector3, n: Vector3) -> String:
	var seam: float = SEAM * float(st.bulk)
	var faceish := k in ["skin", "brow", "eye", "lip", "hair", "beard"]
	if l == "Head" and faceish and n.z > 0.4 and p.z > 0.04:
		var ax := absf(p.x)
		if p.y > 1.668 and p.y < 1.684 and ax > 0.024 and ax < 0.044:
			return "eye"
		if p.y > 1.69 and p.y < 1.7 and ax > 0.014 and ax < 0.054 and k != "hair" and k != "cap":
			return "brow"
	if l == "Head" and k == "skin" and p.y < 1.44 and not (p.z > 0.03 and absf(p.x) < 0.05):
		return "tunic" # the neckline: a clean collar, with the shirt's open V at the front
	if l == "Head" and k == "brow":
		return "skin" # the brow ridge is skin; only the painted band is eyebrow
	if l == "Head" and k == "hair" and p.z > 0.04 and p.y < 1.755 and p.y > 1.6:
		return "skin" # a clean hairline
	if l == "Head" and k in ["skin", "lip"] and p.y < 1.645 and p.y > 1.5 and p.z > -0.03:
		if int(st.beard) == 1:
			return "stubble"
		if int(st.beard) in [2, 3] and p.y < 1.625:
			return "beard"
	if st.hood and p.y > 1.44 and not (faceish and p.y > HOOD_OPENING and p.z > 0.02):
		return "hood"
	if k == "hood":
		return "tunic"
	if st.coat and k != "leather":
		if l.begins_with("Arm") and p.y > 0.86:
			return "coat"
		if l == "" and p.y > 0.6 and p.y < 1.44:
			if absf(p.y - 1.0) < 0.034:
				return "buckle" if (n.z > 0.5 and absf(p.x) < 0.022) else "belt"
			return "coat"
	if k in ["cloak", "coat", "cap"]:
		return k
	# Shoulders: above the armpit, sleeve or body is decided by one straight seam at |x| = seam,
	# not by which blended shape is nearest (that border zigzags across the deltoid).
	if p.y > ARMPIT and p.y < 1.44 and (l == "" or l.begins_with("Arm")) and k != "hood" and k != "cloak":
		if absf(p.x) > seam:
			return "sleeve" if not st.coat else "coat"
		if l.begins_with("Arm"):
			l = ""
			k = "tunic"
	if l.begins_with("Arm"):
		if p.y < 0.84:
			return "skin"
		if p.y < 1.09:
			return "skin" if st.rolled else "bracer"
		return "sleeve"
	if l == "" and absf(p.x) > seam and p.y > 1.034 and p.y < 1.44:
		return "sleeve"
	if l == "" and p.y < 0.966 and k in ["tunic", "tunic_dark"]:
		return "tunic_dark" if p.y > 0.93 else "trousers"
	if l == "" and _in_pouch(st, p) and n.z > -0.2:
		return "leather"
	if l == "" and k == "leather":
		return "tunic_dark" if p.y > 0.93 else "trousers"
	if l == "" and k != "leather":
		if absf(p.y - 1.0) < 0.034:
			return "buckle" if (n.z > 0.5 and absf(p.x) < 0.022) else "belt"
		if st.apron and p.z > 0.05 and p.y > 0.62 and p.y < 1.4 and absf(p.x) < 0.15 and k != "belt":
			return "apron"
		if st.jerkin and p.y > 0.966 and p.y < 1.4 and not (n.z > 0.5 and p.z > 0.0 and absf(p.x) < LACING):
			return "jerkin"
		if k == "jerkin":
			return "tunic"
	if l.begins_with("Leg"):
		if p.y < 0.36:
			return "boot" if p.y < 0.335 else "boot_cuff"
		if k in ["boot", "boot_cuff"]:
			return "trousers"
	return k


## The belt pouch (painted by its own outline, not by nearest shape, so its edge is clean).
static func _in_pouch(st: Dictionary, p: Vector3) -> bool:
	var B: float = st.bulk
	return absf(p.x - POUCH_X * B) < POUCH_W and p.y > POUCH_BOTTOM and p.y < 0.966 and p.z > 0.08 * B


## Bones and weights for a surface point owned by limb `l`: [[bone, weight], ...].
static func bones_for(l: String, p: Vector3) -> Array:
	if l == "Head":
		return [["Head", 1.0]] if p.y > 1.56 else AvatarSkeleton.vertex_bones("", p, p)
	if l == "":
		return AvatarSkeleton.vertex_bones("", p, p)
	var pivot: Vector3 = AvatarBuilder.LIMB_PIVOTS[l]
	return AvatarSkeleton.vertex_bones(l, p - pivot, p)


## Sculpts a style's body: {key, verts, normals, regions (one byte per triangle, KEYS index),
## bones, weights}. Slow (seconds); pure and thread-safe.
static func geometry(st: Dictionary) -> Dictionary:
	var s := SculptField.new()
	sculpt(s, st)
	s.prepare()
	var tl: Array = []
	# Drop the thin bridges surface nets can leave where a hand hangs against the hip.
	for t in s.decimated(TARGET_TRIS, SMOOTH_PASSES):
		var low := 0
		var trunk := 0
		for v in t:
			var o := s.owner(v)
			if o < 0:
				continue
			if s.lowarm[o] == 1:
				low += 1
			elif not s.limb[o].begins_with("Arm") and s.limb[o] != "Head":
				trunk += 1
		if low > 0 and trunk > 0:
			continue
		tl.append(t)
	for c in cuts(st):
		tl = _slice(tl, c[0], c[1], c[2], c[3])
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var regions := PackedByteArray()
	var bones := PackedInt32Array()
	var weights := PackedFloat32Array()
	var wcache := {}
	for t in tl:
		var a: Vector3 = t[0]
		var b: Vector3 = t[1]
		var c: Vector3 = t[2]
		var nrm := -(c - a).cross(b - a).normalized()
		var mid := (a + b + c) / 3.0
		var o := s.owner(mid)
		var k := "tunic" if o < 0 else s.col[o]
		var l := "" if o < 0 else s.limb[o]
		regions.append(maxi(KEYS.find(paint_rule(st, k, l, mid, nrm)), 0))
		for p in [a, c, b]:
			verts.append(p)
			normals.append(nrm)
			# Weights by the vertex's own position, so a corner shared by two triangles never tears.
			var vk := Vector3i((p * 4096.0).round())
			if not wcache.has(vk):
				var po := s.owner(p)
				wcache[vk] = bones_for("" if po < 0 else s.limb[po], p)
			var bw: Array = wcache[vk]
			for j in 4:
				if j < bw.size():
					bones.append(AvatarSkeleton.index_of(bw[j][0]))
					weights.append(float(bw[j][1]))
				else:
					bones.append(0)
					weights.append(0.0)
	return {"key": shape_key(st), "verts": verts, "normals": smooth_normals(verts, normals),
		"regions": regions, "bones": bones, "weights": weights}


## Colours a sculpted body for a style: the finished, skinned ArrayMesh (one surface).
static func paint(geo: Dictionary, st: Dictionary) -> ArrayMesh:
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = geo.verts
	arr[Mesh.ARRAY_NORMAL] = geo.normals
	arr[Mesh.ARRAY_COLOR] = vertex_colours(geo, st)
	arr[Mesh.ARRAY_BONES] = geo.bones
	arr[Mesh.ARRAY_WEIGHTS] = geo.weights
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


## Every vertex's linear colour for a style (pure; what `paint` puts in the mesh).
static func vertex_colours(geo: Dictionary, st: Dictionary) -> PackedColorArray:
	var cols := colours(st)
	var lin: Array[Color] = []
	for k in KEYS:
		lin.append((cols.get(k, Palette.LEATHER) as Color).srgb_to_linear())
	var verts: PackedVector3Array = geo.verts
	var regions: PackedByteArray = geo.regions
	var colors := PackedColorArray()
	colors.resize(verts.size())
	for t in regions.size():
		var c: Color = lin[regions[t]]
		for j in 3:
			var y := verts[t * 3 + j].y
			var f := 1.0 - SHADE_UP * clampf(1.0 - y / 1.8, 0.0, 1.0)
			colors[t * 3 + j] = Color(c.r * f, c.g * f, c.b * f, 1.0)
	return colors


## The finished body for a look in one call (slow: tests, tools and the client's worker).
static func mesh(look: Dictionary, appearance_seed: int) -> ArrayMesh:
	var st := style(look, appearance_seed)
	return paint(geometry(st), st)


## Splits every triangle (centre inside the region) that crosses the plane `axis` = `k`.
static func _slice(tl: Array, axis: int, k: float, lo: Vector3, hi: Vector3) -> Array:
	var out: Array = []
	for t in tl:
		var mid: Vector3 = (t[0] + t[1] + t[2]) / 3.0
		if mid.x < lo.x or mid.y < lo.y or mid.z < lo.z or mid.x > hi.x or mid.y > hi.y or mid.z > hi.z:
			out.append(t)
			continue
		var above: Array = []
		var below: Array = []
		for i in 3:
			if (t[i] as Vector3)[axis] >= k:
				above.append(i)
			else:
				below.append(i)
		if above.is_empty() or below.is_empty():
			out.append(t)
			continue
		var lone: int = above[0] if above.size() == 1 else below[0]
		var p0: Vector3 = t[lone]
		var p1: Vector3 = t[(lone + 1) % 3]
		var p2: Vector3 = t[(lone + 2) % 3]
		var q1 := p0.lerp(p1, (k - p0[axis]) / (p1[axis] - p0[axis]))
		var q2 := p0.lerp(p2, (k - p0[axis]) / (p2[axis] - p0[axis]))
		out.append([p0, q1, q2])
		out.append([q1, p1, p2])
		out.append([q1, p2, q2])
	return out


## Soft shading: each corner takes the area-weighted mean normal of the faces around its point
## that bend less than CREASE from its own, so cloth reads soft and hems and folds stay crisp.
static func smooth_normals(verts: PackedVector3Array, normals: PackedVector3Array) -> PackedVector3Array:
	var around := {}
	for i in range(0, verts.size(), 3):
		for j in 3:
			var vk := Vector3i((verts[i + j] * 4096.0).round())
			var lst: PackedInt32Array = around.get(vk, PackedInt32Array())
			lst.append(i)
			around[vk] = lst
	var area := PackedFloat32Array()
	area.resize(verts.size() / 3)
	for i in range(0, verts.size(), 3):
		area[i / 3] = (verts[i + 1] - verts[i]).cross(verts[i + 2] - verts[i]).length()
	var res := normals.duplicate()
	for i in range(0, verts.size(), 3):
		var fn := normals[i]
		for j in 3:
			var acc := Vector3.ZERO
			for f in (around[Vector3i((verts[i + j] * 4096.0).round())] as PackedInt32Array):
				var gn := normals[f]
				if gn.dot(fn) > CREASE:
					acc += gn * area[f / 3]
			res[i + j] = acc.normalized() if acc.length() > 1e-9 else fn
	return res
