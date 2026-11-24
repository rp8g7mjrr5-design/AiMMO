class_name Ruins
## The ruins of a generated kingdom as gameplay sees them (Phase 1 part 3, vision "The map"):
## every site WorldGen places, with its grade's name and a label players can read, and the
## questions later systems ask (which ruin am I in, which is nearest). Ruin loot, the Gloam
## that guard them and signet keys build on this list.
##
## Pure and deterministic, read by server and client: the list comes from WorldGen's config
## alone. A site's `id` is WorldGen's (stable for a config). Ashgrove (gen_version 0) has none.

## Grade names, quiet to deadly (vision, "Ruins ... graded by how much it can kill you").
const GRADE_NAMES := {1: "Quiet", 2: "Uneasy", 3: "Grim", 4: "Deadly"}

## What players read for each kind. Kinds WorldGen doesn't know yet get a plain fallback.
const LABELS := {
	"burned_farmstead": "Burned Farmstead",
	"roadside_shrine": "Roadside Shrine",
	"woodcutters_hut": "Woodcutter's Hut",
	"abandoned_village": "Abandoned Village",
	"watchtower": "Watchtower",
	"old_mine": "The Old Mine",
	"walled_abbey": "Walled Abbey",
	"fallen_castle": "The Fallen Castle",
	"toll_bridge": "Toll Bridge",
	"drowned_village": "The Drowned Village",
}


## Every ruin site: [{id, kind, grade, grade_name, label, pos: Vector3, radius}], in WorldGen's
## order (the castle first, then by grade). Empty on Ashgrove.
static func all() -> Array:
	var out: Array = []
	for s in WorldGen.ruin_sites():
		var g := int(s.grade)
		out.append({
			"id": int(s.id), "kind": str(s.kind), "grade": g, "grade_name": grade_name(g),
			"label": label(str(s.kind)), "pos": s.pos, "radius": float(s.radius),
		})
	return out


static func count() -> int:
	return WorldGen.ruin_sites().size()


static func grade_name(grade: int) -> String:
	return str(GRADE_NAMES.get(grade, "Unknown"))


static func label(kind: String) -> String:
	return str(LABELS.get(kind, kind.capitalize()))


## The ruin whose pad `pos` stands on (horizontal distance within its radius), or {} if none.
static func at(pos: Vector3) -> Dictionary:
	for r in all():
		if Vector2(pos.x - r.pos.x, pos.z - r.pos.z).length() <= r.radius:
			return r
	return {}


## The nearest ruin to `pos`, optionally only of `grade`, or {} if there is none.
static func nearest(pos: Vector3, grade: int = 0) -> Dictionary:
	var best := {}
	var best_d := INF
	for r in all():
		if grade > 0 and r.grade != grade:
			continue
		var d := Vector2(pos.x - r.pos.x, pos.z - r.pos.z).length()
		if d < best_d:
			best_d = d
			best = r
	return best


## "Burned Farmstead (Quiet)".
static func title(r: Dictionary) -> String:
	if r.is_empty():
		return ""
	return "%s (%s)" % [r.label, r.grade_name]


## One line for the server log: "11 ruins (grade 1: 5, grade 2: 3, grade 3: 2, grade 4: 1)".
static func describe() -> String:
	var by_grade := {}
	for r in all():
		by_grade[r.grade] = by_grade.get(r.grade, 0) + 1
	var bits := PackedStringArray()
	for g in [1, 2, 3, 4]:
		bits.append("grade %d: %d" % [g, by_grade.get(g, 0)])
	return "%d ruins (%s)" % [count(), ", ".join(bits)]
