class_name SkillIcons
## Procedural skill badges, drawn in code (no image files; hard rule 3).
##
## One badge per skill in `Skills.ORDER`, for the skills window, the level-up toast and
## anything else that names a skill. Each is a coloured disc with a darker rim and an emblem
## on top, so the four read apart by colour alone at 24 px and by shape up close:
##   felling    green disc, a stone axe bitten into a stump with an ash leaf
##   quarrying  slate-blue disc, a pickaxe over a stone with its quartz seam and chips
##   tapping    deep ember-red disc, a glowing drop falling from a spout into a bowl
##   toolcraft  warm wood disc, a hammer laid across the workbench's plank
## Item icons are free shapes on transparent ground; skill badges are always round, so a
## player can tell "a thing I carry" from "a road I'm on" at a glance.
##
## Drawn by `ItemIcons.rasterise` (same outline, light and shadow as the item icons).
## Client use: `SkillIcons.texture("felling")` gives a cached 64 px `ImageTexture`, and
## `SkillIcons.tint("felling")` the badge colour for a toast border or XP bar. Unknown skill
## ids get a plain badge with a star, never null.

const DEFAULT_SIZE := 64
const CENTRE := Vector2(0.5, 0.5)
const RADIUS := 0.42 ## badge disc radius, in icon units (inside ItemIcons.MARGIN plus outline)
const RIM := 0.05 ## width of the darker rim inside the disc
const FALLBACK := "_badge"

const FELLING := Color(0.36, 0.56, 0.32)
const QUARRYING := Color(0.42, 0.50, 0.62)
const TAPPING := Color(0.62, 0.24, 0.17)
const TOOLCRAFT := Color(0.66, 0.48, 0.30)
const PLAIN := Color(0.58, 0.56, 0.52)

static var _cache := {}


## True if `skill` has its own badge (false means it would get the plain one).
static func has_icon(skill: String) -> bool:
	return _emblem(skill) != []


## The badge colour for a skill (for tinting a toast, an XP bar or a window header).
static func tint(skill: String) -> Color:
	match skill:
		"felling":
			return FELLING
		"quarrying":
			return QUARRYING
		"tapping":
			return TAPPING
		"toolcraft":
			return TOOLCRAFT
	return PLAIN


## The badge's shapes, back to front, in `ItemIcons.shapes()` format.
static func shapes(skill: String) -> Array:
	var key := skill if has_icon(skill) else FALLBACK
	var col := tint(key)
	var out := [
		ItemIcons._circle(CENTRE, RADIUS, col.darkened(0.3), {"shade": 0.15}),
		ItemIcons._circle(CENTRE, RADIUS - RIM, col, {"outline": false, "shade": 0.25}),
	]
	out.append_array(_emblem(key))
	return out


## A fresh `size` x `size` RGBA image of the badge, transparent round the outside.
static func image(skill: String, size: int = DEFAULT_SIZE) -> Image:
	return ItemIcons.rasterise(shapes(skill), size)


## Cached ImageTexture of the badge. Safe to call every frame.
static func texture(skill: String, size: int = DEFAULT_SIZE) -> ImageTexture:
	var key := "%s@%d" % [skill if has_icon(skill) else FALLBACK, size]
	if not _cache.has(key):
		_cache[key] = ImageTexture.create_from_image(image(skill, size))
	return _cache[key]


# --- emblems (drawn on the disc; outline off so the badge keeps one clean silhouette) ----

static func _e(extra := {}) -> Dictionary:
	var d := {"outline": false}
	d.merge(extra)
	return d


static func _emblem(skill: String) -> Array:
	var ink := Color(0.16, 0.11, 0.09, 0.55) # a soft dark backing so emblems pop off the disc
	match skill:
		"felling":
			var stump := ItemIcons.ASH_BARK
			return [
				# Stump with its cut top and rings.
				ItemIcons._box(Vector2(0.44, 0.66), Vector2(0.16, 0.10), 0.0, stump, _e({"shade": 0.25})),
				ItemIcons._box(Vector2(0.44, 0.565), Vector2(0.16, 0.035), 0.0, ItemIcons.ASH_CUT, _e({"round": 0.03, "shade": 0.05})),
				ItemIcons._capsule(Vector2(0.34, 0.565), Vector2(0.54, 0.565), 0.008, ItemIcons.RING, _e({"shade": 0.0})),
				# A stone axe bitten into the top.
				ItemIcons._capsule(Vector2(0.72, 0.30), Vector2(0.50, 0.53), 0.032, ItemIcons.HANDLE, _e()),
				ItemIcons._poly([Vector2(0.40, 0.53), Vector2(0.47, 0.36), Vector2(0.62, 0.41), Vector2(0.60, 0.57)], ItemIcons.STONE.lightened(0.1), _e({"shade": 0.3})),
				ItemIcons._capsule(Vector2(0.41, 0.52), Vector2(0.47, 0.37), 0.012, ItemIcons.QUARTZ, _e({"shade": 0.0})),
				# An ash leaf drifting down.
				ItemIcons._box(Vector2(0.30, 0.34), Vector2(0.075, 0.035), 0.5, Palette.ASH_LEAF, _e({"round": 0.03})),
			]
		"quarrying":
			return [
				ItemIcons._circle(Vector2(0.50, 0.68), 0.15, ink, _e({"shade": 0.0})),
				ItemIcons._poly([Vector2(0.30, 0.72), Vector2(0.36, 0.56), Vector2(0.52, 0.50), Vector2(0.68, 0.56), Vector2(0.72, 0.72), Vector2(0.50, 0.78)], ItemIcons.STONE, _e({"shade": 0.3})),
				ItemIcons._capsule(Vector2(0.38, 0.70), Vector2(0.64, 0.58), 0.018, ItemIcons.QUARTZ, _e({"shade": 0.0})),
				# Pickaxe swung over it.
				ItemIcons._capsule(Vector2(0.36, 0.48), Vector2(0.62, 0.22), 0.03, ItemIcons.HANDLE, _e()),
				ItemIcons._poly([Vector2(0.40, 0.18), Vector2(0.56, 0.18), Vector2(0.74, 0.30), Vector2(0.58, 0.27), Vector2(0.44, 0.26)], ItemIcons.STONE.lightened(0.1), _e({"shade": 0.3})),
				# Flying chips.
				ItemIcons._circle(Vector2(0.26, 0.50), 0.022, ItemIcons.QUARTZ, _e({"shade": 0.0})),
				ItemIcons._circle(Vector2(0.76, 0.46), 0.018, ItemIcons.QUARTZ, _e({"shade": 0.0})),
			]
		"tapping":
			return [
				# Spout from the top left.
				ItemIcons._capsule(Vector2(0.22, 0.28), Vector2(0.46, 0.30), 0.035, ItemIcons.ASH_BARK, _e()),
				# The falling ember drop, with a halo (it is the only badge that glows).
				ItemIcons._circle(Vector2(0.50, 0.50), 0.085, Palette.EMBER, _e({"glow": 0.24, "shade": 0.25})),
				ItemIcons._poly([Vector2(0.42, 0.48), Vector2(0.50, 0.33), Vector2(0.58, 0.48)], Palette.EMBER, _e({"shade": 0.25})),
				ItemIcons._circle(Vector2(0.51, 0.51), 0.045, Palette.EMBER_CORE, _e({"shade": 0.05})),
				# The bowl catching it, already glowing.
				ItemIcons._poly([Vector2(0.28, 0.64), Vector2(0.72, 0.64), Vector2(0.62, 0.78), Vector2(0.38, 0.78)], ItemIcons.HANDLE, _e({"shade": 0.25})),
				ItemIcons._box(Vector2(0.50, 0.655), Vector2(0.19, 0.022), 0.0, Palette.EMBER_CORE, _e({"round": 0.02, "shade": 0.0})),
			]
		"toolcraft":
			return [
				# The workbench plank and two legs.
				ItemIcons._box(Vector2(0.50, 0.62), Vector2(0.27, 0.045), 0.0, ItemIcons.ASH_CUT, _e({"round": 0.015})),
				ItemIcons._box(Vector2(0.32, 0.73), Vector2(0.04, 0.07), 0.0, ItemIcons.STONE_DARK, _e()),
				ItemIcons._box(Vector2(0.68, 0.73), Vector2(0.04, 0.07), 0.0, ItemIcons.STONE_DARK, _e()),
				# A hammer laid across it, head up.
				ItemIcons._capsule(Vector2(0.62, 0.54), Vector2(0.38, 0.28), 0.03, ItemIcons.HANDLE, _e()),
				ItemIcons._box(Vector2(0.37, 0.27), Vector2(0.11, 0.055), -0.84, ItemIcons.STONE, _e({"round": 0.015, "shade": 0.3})),
				ItemIcons._box(Vector2(0.385, 0.285), Vector2(0.04, 0.06), -0.84, ItemIcons.LASHING, _e()),
				# A spark off the strike.
				ItemIcons._circle(Vector2(0.62, 0.30), 0.022, Palette.EMBER_CORE, _e({"shade": 0.0})),
			]
		FALLBACK:
			var pts := []
			for i in 10:
				var ang := -PI * 0.5 + i * PI / 5.0
				var r := 0.2 if i % 2 == 0 else 0.09
				pts.append(CENTRE + Vector2(cos(ang), sin(ang)) * r)
			return [ItemIcons._poly(pts, Color(0.92, 0.88, 0.78), _e({"shade": 0.2}))]
	return []
