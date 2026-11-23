class_name ItemIcons
## Procedural inventory icons, drawn in code (no image files; hard rule 3).
##
## Every item in `Inventory.ITEMS` has a little picture: logs with a cut end for wood, a grey
## chunk with a quartz seam for stone, a glowing drop for ember sap, the two stone tools, a
## lit torch and a campfire, and the two tier-2 materials: ember heartwood (an old grey log
## whose cut end glows like a coal) and veinstone (a deep mauve chunk split by glowing
## veins with gold flecks), drawn like the old ember ash and the rich seam, and the two
## ember tools (the stone tools' shapes with coal-dark heads and an ember-hot edge). They match what the world draws (the outcrop's pale seam, the
## seep's ember glow, the ash's warm leaves), so a "+2 ash wood" toast looks like the tree
## you just hit.
##
## How it works: each icon is a short list of flat shapes in a 0..1 square (`shapes(item)`,
## pure data). `image()` rasterises them with signed distance fields: one anti-aliased edge
## per shape, a soft top-left light across each shape, a dark outline round the whole
## silhouette, a faint drop shadow, and an optional warm halo for things that glow. It is
## plain maths on an `Image`, so it runs headless (tests, bots) as well as in the client.
##
## Client use: `ItemIcons.texture("ash_wood")` gives a cached 64 px `ImageTexture`. Unknown
## ids (an item retired from `Inventory.ITEMS` but still in someone's saved pack) get a
## plain cloth bundle, never null.

const DEFAULT_SIZE := 64
const OUTLINE := 0.028 ## silhouette outline width, in icon units (about 1.8 px at 64)
const OUTLINE_COLOR := Color(0.13, 0.09, 0.07)
const SHADOW_OFFSET := Vector2(0.025, 0.035)
const SHADOW_ALPHA := 0.28
const LIGHT := Vector2(-0.6, -0.8) ## light from the top left (y grows downward)
const SHADE := 0.2 ## how much a shape brightens toward the light and darkens away from it
const MARGIN := 0.04 ## nothing is drawn this close to the edge, so nothing is clipped
const FALLBACK := "_bundle"

# Colours, matched to the world's props and palette.
const ASH_BARK := Color(0.62, 0.56, 0.48)
const ASH_CUT := Color(0.93, 0.82, 0.62)
const PINE_BARK := Color(0.47, 0.27, 0.18)
const PINE_CUT := Color(0.86, 0.66, 0.42)
const RING := Color(0.66, 0.47, 0.29)
const STONE := Color(0.56, 0.54, 0.52)
const STONE_DARK := Color(0.43, 0.41, 0.40)
const QUARTZ := Color(0.92, 0.90, 0.84)
const SAP := Color(1.0, 0.55, 0.16)
const SAP_CORE := Color(1.0, 0.82, 0.38)
const HANDLE := Color(0.60, 0.44, 0.28)
const LASHING := Color(0.36, 0.26, 0.16)
const FLAME := Color(1.0, 0.50, 0.12)
const FLAME_CORE := Color(1.0, 0.88, 0.45)
const CLOTH := Color(0.70, 0.60, 0.44)
const WARM_GLOW := Color(1.0, 0.55, 0.15)
static var COAL := Palette.SOOT.lightened(0.12) ## ember tool heads: coal-dark, but lighter than the outline so the shape reads

static var _cache := {}


## True if `item` has its own icon (false means it would get the fallback bundle).
static func has_icon(item: String) -> bool:
	return _recipe(item) != []


## The icon's shapes, back to front. Each is a Dictionary with `t` ("circle", "capsule",
## "box", "poly"), its geometry in 0..1 units, `col` (Color), and optional `shade` (light
## amount, default SHADE), `outline` (false keeps it out of the silhouette outline, for
## small details drawn on top) and `glow` (radius of a warm halo behind it).
static func shapes(item: String) -> Array:
	var r := _recipe(item)
	return r if r != [] else _recipe(FALLBACK)


## A fresh `size` x `size` RGBA image of the icon, transparent round the outside.
static func image(item: String, size: int = DEFAULT_SIZE) -> Image:
	return rasterise(shapes(item), size)


## Draws any shape list (the same format as `shapes()`) into a fresh `size` x `size` RGBA
## image with ItemIcons' outline, light, shadow and halo. `SkillIcons` draws through this
## too, so every icon in the game shares one hand.
static func rasterise(raw: Array, size: int = DEFAULT_SIZE) -> Image:
	size = clampi(size, 8, 512)
	var ss := _prepare(raw)
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var px := 1.0 / size
	for y in size:
		for x in size:
			var p := Vector2((x + 0.5) * px, (y + 0.5) * px)
			img.set_pixel(x, y, _shade_pixel(p, px, ss))
	return img


## Cached ImageTexture of the icon. Safe to call every frame.
static func texture(item: String, size: int = DEFAULT_SIZE) -> ImageTexture:
	var key := "%s@%d" % [item if has_icon(item) else FALLBACK, size]
	if not _cache.has(key):
		_cache[key] = ImageTexture.create_from_image(image(item, size))
	return _cache[key]


## The main colour of the icon (for tinting a toast or slot border to match).
static func tint(item: String) -> Color:
	match item:
		"ash_wood":
			return ASH_CUT
		"pine_wood":
			return PINE_CUT
		"stone":
			return QUARTZ
		"ember_sap", "torch", "campfire":
			return SAP
		"ember_heartwood":
			return Palette.OLD_ASH_LEAF
		"veinstone":
			return Palette.RICH_FLECK
		"stone_axe", "stone_pickaxe":
			return STONE.lightened(0.2)
		"ember_axe", "ember_pickaxe":
			return Palette.EMBER
	return CLOTH


# --- drawing -------------------------------------------------------------------------

static func _shade_pixel(p: Vector2, px: float, ss: Array) -> Color:
	var out := Color(0, 0, 0, 0)
	# Warm halo behind glowing shapes.
	for s in ss:
		if s.glow > 0.0:
			var gd: float = s.centre.distance_to(p) / s.glow
			if gd < 1.0:
				out = _over(out, Color(WARM_GLOW, 0.55 * pow(1.0 - gd, 2.0)))
	# Drop shadow and outline from the union of every outlined shape.
	# A shape's bounding circle gives a cheap lower bound on its distance; only shapes
	# whose bound is near the pixel need the exact distance.
	var near := OUTLINE + px * 3.0
	var shadow_d := INF
	var union_d := INF
	for s in ss:
		if s.outline:
			shadow_d = minf(shadow_d, _sdf_near(p - SHADOW_OFFSET, s, near))
			union_d = minf(union_d, _sdf_near(p, s, near))
	out = _over(out, Color(0, 0, 0, SHADOW_ALPHA * _cover(shadow_d - OUTLINE, px * 2.5)))
	out = _over(out, Color(OUTLINE_COLOR, _cover(union_d - OUTLINE, px)))
	# The shapes themselves, back to front, lit from the top left.
	for s in ss:
		var d := _sdf_near(p, s, near)
		var a := _cover(d, px)
		if a <= 0.0:
			continue
		var c: Color = s.col
		var t := clampf((p - s.centre).dot(LIGHT.normalized()) / maxf(s.radius, 0.01), -1.0, 1.0)
		if t > 0.0:
			c = c.lightened(s.shade * t)
		else:
			c = c.darkened(s.shade * -t)
		out = _over(out, Color(c, c.a * a))
	return out


## Coverage of a pixel whose centre is `d` from an edge (negative = inside).
static func _cover(d: float, px: float) -> float:
	return clampf(0.5 - d / px, 0.0, 1.0)


## Porter-Duff "over" with straight alpha.
static func _over(dst: Color, src: Color) -> Color:
	var a := src.a + dst.a * (1.0 - src.a)
	if a <= 0.00001:
		return Color(0, 0, 0, 0)
	var r := (src.r * src.a + dst.r * dst.a * (1.0 - src.a)) / a
	var g := (src.g * src.a + dst.g * dst.a * (1.0 - src.a)) / a
	var b := (src.b * src.a + dst.b * dst.a * (1.0 - src.a)) / a
	return Color(r, g, b, a)


## Adds defaults plus a centre and radius (for the light gradient) to every shape.
static func _prepare(raw: Array) -> Array:
	var out := []
	for s0 in raw:
		var s: Dictionary = s0.duplicate()
		s["shade"] = s.get("shade", SHADE)
		s["outline"] = s.get("outline", true)
		s["glow"] = s.get("glow", 0.0)
		match s.t:
			"circle":
				s["centre"] = s.c
				s["radius"] = s.r
			"capsule":
				s["centre"] = (s.a + s.b) * 0.5
				s["radius"] = s.a.distance_to(s.b) * 0.5 + s.r
			"box":
				s["centre"] = s.c
				s["radius"] = s.h.length()
				s["rot"] = s.get("rot", 0.0)
				s["round"] = s.get("round", 0.0)
			"poly":
				var c := Vector2.ZERO
				for q in s.pts:
					c += q
				c /= s.pts.size()
				var r := 0.0
				for q in s.pts:
					r = maxf(r, c.distance_to(q))
				s["centre"] = c
				s["radius"] = r
		out.append(s)
	return out


## The exact distance when the shape is within `near` of `p`, else a lower bound from its
## bounding circle (which is all the caller needs to know it is out of reach).
static func _sdf_near(p: Vector2, s: Dictionary, near: float) -> float:
	var lb: float = p.distance_to(s.centre) - s.radius
	return lb if lb > near else _sdf(p, s)


## Signed distance from `p` to the shape (negative inside).
static func _sdf(p: Vector2, s: Dictionary) -> float:
	match s.t:
		"circle":
			return p.distance_to(s.c) - s.r
		"capsule":
			var ab: Vector2 = s.b - s.a
			var h := clampf((p - s.a).dot(ab) / ab.length_squared(), 0.0, 1.0)
			return p.distance_to(s.a + ab * h) - s.r
		"box":
			var q: Vector2 = (p - (s.c as Vector2)).rotated(-float(s.rot))
			var rr: float = s.round
			var d: Vector2 = q.abs() - ((s.h as Vector2) - Vector2(rr, rr))
			return Vector2(maxf(d.x, 0.0), maxf(d.y, 0.0)).length() + minf(maxf(d.x, d.y), 0.0) - rr
		"poly":
			return _sdf_poly(p, s.pts)
	return INF


## Exact signed distance to a simple polygon (Inigo Quilez's method).
static func _sdf_poly(p: Vector2, v: PackedVector2Array) -> float:
	var n := v.size()
	var d := (p - v[0]).length_squared()
	var sgn := 1.0
	var j := n - 1
	for i in n:
		var e := v[j] - v[i]
		var w := p - v[i]
		var b := w - e * clampf(w.dot(e) / e.length_squared(), 0.0, 1.0)
		d = minf(d, b.length_squared())
		var c1 := p.y >= v[i].y
		var c2 := p.y < v[j].y
		var c3 := e.x * w.y > e.y * w.x
		if (c1 and c2 and c3) or (not c1 and not c2 and not c3):
			sgn = -sgn
		j = i
	return sgn * sqrt(d)


# --- the icons -----------------------------------------------------------------------

static func _circle(c: Vector2, r: float, col: Color, extra := {}) -> Dictionary:
	var s := {"t": "circle", "c": c, "r": r, "col": col}
	s.merge(extra)
	return s


static func _capsule(a: Vector2, b: Vector2, r: float, col: Color, extra := {}) -> Dictionary:
	var s := {"t": "capsule", "a": a, "b": b, "r": r, "col": col}
	s.merge(extra)
	return s


static func _box(c: Vector2, h: Vector2, rot: float, col: Color, extra := {}) -> Dictionary:
	var s := {"t": "box", "c": c, "h": h, "rot": rot, "col": col}
	s.merge(extra)
	return s


static func _poly(pts: Array, col: Color, extra := {}) -> Dictionary:
	var s := {"t": "poly", "pts": PackedVector2Array(pts), "col": col}
	s.merge(extra)
	return s


## A log lying from `a` (far end) to `b` (the cut end facing us), with growth rings.
static func _log(a: Vector2, b: Vector2, r: float, bark: Color, cut: Color) -> Array:
	return [
		_capsule(a, b, r, bark),
		_capsule(a.lerp(b, 0.2), a.lerp(b, 0.75), r * 0.12, bark.darkened(0.25), {"outline": false, "shade": 0.0}),
		_circle(b, r * 0.86, cut, {"shade": 0.1}),
		_circle(b, r * 0.55, RING, {"outline": false, "shade": 0.0}),
		_circle(b, r * 0.42, cut, {"outline": false, "shade": 0.0}),
		_circle(b, r * 0.14, RING, {"outline": false, "shade": 0.0}),
	]


## A flame pointing up, base centred on `base`, `h` tall.
static func _flame(base: Vector2, h: float, glow: float) -> Array:
	var w := h * 0.36
	return [
		_poly([base + Vector2(-w, -h * 0.25), base + Vector2(-w * 0.15, -h), base + Vector2(w * 0.55, -h * 0.55), base + Vector2(w, -h * 0.2)], FLAME, {"glow": glow}),
		_circle(base + Vector2(0, -h * 0.2), w, FLAME),
		_poly([base + Vector2(-w * 0.5, -h * 0.2), base + Vector2(0, -h * 0.72), base + Vector2(w * 0.5, -h * 0.2)], FLAME_CORE, {"outline": false, "shade": 0.05}),
		_circle(base + Vector2(0, -h * 0.16), w * 0.5, FLAME_CORE, {"outline": false, "shade": 0.05}),
	]


static func _recipe(item: String) -> Array:
	match item:
		"ash_wood":
			var a := _log(Vector2(0.76, 0.32), Vector2(0.28, 0.58), 0.13, ASH_BARK, ASH_CUT)
			a.append_array(_log(Vector2(0.76, 0.55), Vector2(0.40, 0.76), 0.12, ASH_BARK.darkened(0.06), ASH_CUT))
			# A warm ash leaf on top, like the ember-leaved trees it came from.
			a.append(_box(Vector2(0.66, 0.20), Vector2(0.11, 0.05), -0.6, Palette.ASH_LEAF, {"round": 0.045}))
			a.append(_capsule(Vector2(0.58, 0.25), Vector2(0.75, 0.15), 0.008, Palette.ASH_LEAF.darkened(0.35), {"outline": false, "shade": 0.0}))
			return a
		"pine_wood":
			var a := _log(Vector2(0.76, 0.32), Vector2(0.28, 0.58), 0.13, PINE_BARK, PINE_CUT)
			a.append_array(_log(Vector2(0.76, 0.55), Vector2(0.40, 0.76), 0.12, PINE_BARK.darkened(0.06), PINE_CUT))
			# A sprig of needles.
			var root := Vector2(0.56, 0.28)
			var tip := Vector2(0.80, 0.17)
			a.append(_capsule(root, tip, 0.014, PINE_BARK.darkened(0.2)))
			for i in 5:
				var t := 0.15 + i * 0.18
				var on := root.lerp(tip, t)
				a.append(_capsule(on, on + Vector2(-0.02, -0.075), 0.016, Palette.PINE))
				a.append(_capsule(on, on + Vector2(0.07, 0.05), 0.016, Palette.PINE))
			return a
		"stone":
			return [
				_poly([Vector2(0.14, 0.62), Vector2(0.24, 0.32), Vector2(0.50, 0.18), Vector2(0.76, 0.26), Vector2(0.88, 0.56), Vector2(0.74, 0.82), Vector2(0.36, 0.86)], STONE, {"shade": 0.28}),
				_poly([Vector2(0.50, 0.18), Vector2(0.76, 0.26), Vector2(0.88, 0.56), Vector2(0.62, 0.48)], STONE_DARK.lightened(0.15), {"outline": false, "shade": 0.1}),
				# The outcrop's pale quartz seam, studs and all.
				_capsule(Vector2(0.22, 0.70), Vector2(0.80, 0.40), 0.03, QUARTZ, {"outline": false, "shade": 0.1}),
				_circle(Vector2(0.36, 0.63), 0.035, QUARTZ.lightened(0.3), {"outline": false, "shade": 0.0}),
				_circle(Vector2(0.62, 0.49), 0.03, QUARTZ.lightened(0.3), {"outline": false, "shade": 0.0}),
			]
		"ember_heartwood":
			# One fat old log, greyer than ash wood, its heart still a live coal: the old ember
			# ash's grey bark and gold crown, so the pick reads "rarer" at a glance.
			var a := [
				_capsule(Vector2(0.74, 0.34), Vector2(0.34, 0.62), 0.17, Palette.OLD_ASH_BARK, {"shade": 0.26}),
				_capsule(Vector2(0.70, 0.30), Vector2(0.46, 0.47), 0.016, Palette.OLD_ASH_BARK.darkened(0.35), {"outline": false, "shade": 0.0}),
				_capsule(Vector2(0.78, 0.42), Vector2(0.56, 0.58), 0.015, Palette.OLD_ASH_BARK.darkened(0.35), {"outline": false, "shade": 0.0}),
				# A glowing crack along the bark, like the old ash's vein cracks.
				_poly([Vector2(0.74, 0.24), Vector2(0.62, 0.34), Vector2(0.66, 0.36), Vector2(0.52, 0.46), Vector2(0.60, 0.40), Vector2(0.58, 0.38)], Palette.EMBER, {"outline": false, "shade": 0.0}),
				_circle(Vector2(0.34, 0.62), 0.15, ASH_CUT.darkened(0.12), {"shade": 0.1}),
				_circle(Vector2(0.34, 0.62), 0.11, RING.darkened(0.1), {"outline": false, "shade": 0.0}),
				# The heart: a live coal in the middle of the rings, with a warm halo.
				_circle(Vector2(0.34, 0.62), 0.08, Palette.EMBER, {"outline": false, "shade": 0.1, "glow": 0.34}),
				_circle(Vector2(0.34, 0.62), 0.05, Palette.EMBER_CORE, {"outline": false, "shade": 0.0}),
			]
			# Two small gold leaves from the old crown.
			a.append(_box(Vector2(0.70, 0.17), Vector2(0.10, 0.045), -0.5, Palette.OLD_ASH_LEAF, {"round": 0.04}))
			a.append(_box(Vector2(0.82, 0.24), Vector2(0.07, 0.035), 0.5, Palette.OLD_ASH_LEAF.darkened(0.1), {"round": 0.03}))
			return a
		"veinstone":
			# A deep mauve chunk like the rich seam, split by a glowing ember vein and dotted
			# with gold flecks: plain stone, but obviously worth more.
			return [
				_poly([Vector2(0.12, 0.58), Vector2(0.22, 0.30), Vector2(0.44, 0.14), Vector2(0.72, 0.18), Vector2(0.90, 0.44), Vector2(0.80, 0.78), Vector2(0.50, 0.88), Vector2(0.22, 0.80)], Palette.RICH_STONE, {"shade": 0.3}),
				_poly([Vector2(0.44, 0.14), Vector2(0.72, 0.18), Vector2(0.90, 0.44), Vector2(0.60, 0.42)], Palette.RICH_STONE.darkened(0.18), {"outline": false, "shade": 0.1}),
				# The vein: a zig-zag crack of ember light across the face.
				_capsule(Vector2(0.18, 0.66), Vector2(0.38, 0.52), 0.032, Palette.EMBER, {"outline": false, "shade": 0.0, "glow": 0.22}),
				_capsule(Vector2(0.38, 0.52), Vector2(0.52, 0.62), 0.032, Palette.EMBER, {"outline": false, "shade": 0.0}),
				_capsule(Vector2(0.52, 0.62), Vector2(0.80, 0.38), 0.032, Palette.EMBER, {"outline": false, "shade": 0.0, "glow": 0.22}),
				_capsule(Vector2(0.20, 0.65), Vector2(0.78, 0.39), 0.012, Palette.EMBER_CORE, {"outline": false, "shade": 0.0}),
				# Gold flecks.
				_circle(Vector2(0.34, 0.36), 0.03, Palette.RICH_FLECK, {"outline": false, "shade": 0.0}),
				_circle(Vector2(0.62, 0.30), 0.024, Palette.RICH_FLECK, {"outline": false, "shade": 0.0}),
				_circle(Vector2(0.44, 0.76), 0.028, Palette.RICH_FLECK, {"outline": false, "shade": 0.0}),
				_circle(Vector2(0.70, 0.66), 0.022, Palette.RICH_FLECK, {"outline": false, "shade": 0.0}),
			]
		"ember_sap":
			return [
				_circle(Vector2(0.50, 0.62), 0.24, SAP, {"glow": 0.46, "shade": 0.3}),
				_poly([Vector2(0.27, 0.55), Vector2(0.50, 0.12), Vector2(0.73, 0.55)], SAP, {"shade": 0.3}),
				_circle(Vector2(0.52, 0.64), 0.13, SAP_CORE, {"outline": false, "shade": 0.1}),
				_circle(Vector2(0.41, 0.52), 0.05, Color(1, 1, 0.92, 0.85), {"outline": false, "shade": 0.0}),
			]
		"stone_axe":
			return [
				_capsule(Vector2(0.24, 0.84), Vector2(0.66, 0.22), 0.045, HANDLE),
				_poly([Vector2(0.50, 0.24), Vector2(0.70, 0.12), Vector2(0.86, 0.24), Vector2(0.88, 0.48), Vector2(0.74, 0.44), Vector2(0.58, 0.40)], STONE, {"shade": 0.28}),
				_capsule(Vector2(0.86, 0.25), Vector2(0.88, 0.47), 0.012, QUARTZ, {"outline": false, "shade": 0.0}),
				_box(Vector2(0.62, 0.29), Vector2(0.06, 0.025), 0.98, LASHING, {"outline": false}),
				_box(Vector2(0.58, 0.35), Vector2(0.06, 0.025), 0.98, LASHING, {"outline": false}),
			]
		"stone_pickaxe":
			return [
				_capsule(Vector2(0.26, 0.86), Vector2(0.60, 0.26), 0.045, HANDLE),
				_poly([Vector2(0.22, 0.30), Vector2(0.44, 0.17), Vector2(0.62, 0.16), Vector2(0.64, 0.26), Vector2(0.44, 0.27)], STONE, {"shade": 0.28}),
				_poly([Vector2(0.58, 0.16), Vector2(0.76, 0.22), Vector2(0.90, 0.40), Vector2(0.76, 0.34), Vector2(0.60, 0.28)], STONE, {"shade": 0.28}),
				_box(Vector2(0.59, 0.24), Vector2(0.055, 0.05), 0.5, LASHING, {"outline": false, "round": 0.01}),
			]
		"ember_axe":
			# The stone axe's shape, but the head is a dark coal-veined wedge, broader and
			# bearded, whose cutting edge glows ember orange: the tool you earned at Toolcraft 5.
			return [
				_capsule(Vector2(0.24, 0.84), Vector2(0.64, 0.24), 0.045, HANDLE.darkened(0.1)),
				_poly([Vector2(0.48, 0.22), Vector2(0.68, 0.10), Vector2(0.86, 0.16), Vector2(0.90, 0.40), Vector2(0.84, 0.58), Vector2(0.72, 0.46), Vector2(0.56, 0.40)], COAL, {"shade": 0.3}),
				# Coal veins across the head.
				_capsule(Vector2(0.60, 0.22), Vector2(0.74, 0.30), 0.011, Palette.SMOULDER, {"outline": false, "shade": 0.0}),
				_capsule(Vector2(0.66, 0.38), Vector2(0.78, 0.33), 0.010, Palette.SMOULDER, {"outline": false, "shade": 0.0}),
				# The glowing edge: a smoulder rim, an ember band and a hot core line.
				_poly([Vector2(0.84, 0.14), Vector2(0.90, 0.17), Vector2(0.94, 0.40), Vector2(0.88, 0.60), Vector2(0.84, 0.56), Vector2(0.87, 0.40)], Palette.SMOULDER, {"outline": false, "shade": 0.0}),
				_capsule(Vector2(0.88, 0.20), Vector2(0.90, 0.40), 0.022, Palette.EMBER, {"outline": false, "shade": 0.0, "glow": 0.18}),
				_capsule(Vector2(0.90, 0.40), Vector2(0.86, 0.54), 0.020, Palette.EMBER, {"outline": false, "shade": 0.0}),
				_capsule(Vector2(0.89, 0.22), Vector2(0.89, 0.46), 0.008, Palette.EMBER_CORE, {"outline": false, "shade": 0.0}),
				_box(Vector2(0.60, 0.30), Vector2(0.06, 0.025), 0.98, LASHING, {"outline": false}),
				_box(Vector2(0.56, 0.36), Vector2(0.06, 0.025), 0.98, LASHING, {"outline": false}),
			]
		"ember_pickaxe":
			# The stone pick's two prongs in dark coal, each tip burning ember hot.
			return [
				_capsule(Vector2(0.26, 0.86), Vector2(0.60, 0.26), 0.045, HANDLE.darkened(0.1)),
				_poly([Vector2(0.14, 0.34), Vector2(0.40, 0.16), Vector2(0.62, 0.14), Vector2(0.64, 0.27), Vector2(0.42, 0.28)], COAL, {"shade": 0.3}),
				_poly([Vector2(0.56, 0.14), Vector2(0.78, 0.20), Vector2(0.92, 0.46), Vector2(0.76, 0.35), Vector2(0.58, 0.28)], COAL, {"shade": 0.3}),
				_capsule(Vector2(0.30, 0.25), Vector2(0.48, 0.21), 0.010, Palette.SMOULDER, {"outline": false, "shade": 0.0}),
				_capsule(Vector2(0.68, 0.22), Vector2(0.80, 0.32), 0.010, Palette.SMOULDER, {"outline": false, "shade": 0.0}),
				# Hot tips.
				_poly([Vector2(0.15, 0.335), Vector2(0.30, 0.23), Vector2(0.33, 0.30)], Palette.EMBER, {"outline": false, "shade": 0.0, "glow": 0.2}),
				_poly([Vector2(0.91, 0.455), Vector2(0.78, 0.25), Vector2(0.74, 0.34)], Palette.EMBER, {"outline": false, "shade": 0.0, "glow": 0.2}),
				_capsule(Vector2(0.19, 0.31), Vector2(0.27, 0.27), 0.014, Palette.EMBER_CORE, {"outline": false, "shade": 0.0}),
				_capsule(Vector2(0.86, 0.39), Vector2(0.80, 0.31), 0.014, Palette.EMBER_CORE, {"outline": false, "shade": 0.0}),
				_box(Vector2(0.59, 0.24), Vector2(0.055, 0.05), 0.5, LASHING, {"outline": false, "round": 0.01}),
			]
		"torch":
			var a := [
				_capsule(Vector2(0.38, 0.85), Vector2(0.56, 0.48), 0.045, HANDLE),
				_box(Vector2(0.57, 0.47), Vector2(0.07, 0.06), 0.42, LASHING, {"round": 0.02}),
			]
			a.append_array(_flame(Vector2(0.59, 0.43), 0.32, 0.32))
			return a
		"campfire":
			var a := []
			for i in 7:
				var ang := PI * (0.05 + 0.9 * i / 6.0)
				a.append(_circle(Vector2(0.50 + cos(ang) * 0.31, 0.74 + sin(ang) * 0.08), 0.065, STONE.darkened(0.08 * (i % 2)), {"shade": 0.3}))
			a.append(_capsule(Vector2(0.26, 0.76), Vector2(0.69, 0.53), 0.05, PINE_BARK))
			a.append(_capsule(Vector2(0.74, 0.76), Vector2(0.31, 0.53), 0.05, ASH_BARK))
			a.append_array(_flame(Vector2(0.50, 0.63), 0.44, 0.40))
			return a
		FALLBACK:
			return [
				_circle(Vector2(0.50, 0.60), 0.27, CLOTH),
				_poly([Vector2(0.36, 0.38), Vector2(0.30, 0.16), Vector2(0.50, 0.28), Vector2(0.70, 0.16), Vector2(0.64, 0.38)], CLOTH.darkened(0.05)),
				_box(Vector2(0.50, 0.37), Vector2(0.12, 0.03), 0.0, LASHING, {"round": 0.01}),
			]
	return []
