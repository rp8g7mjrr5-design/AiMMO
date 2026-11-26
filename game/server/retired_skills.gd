class_name RetiredSkills
## The leveling system is gone (owner direction, 2026-11-26: "get rid of the leveling system
## and just work on the basics"). Nothing in the game reads or earns XP any more, and nothing
## should again (docs/vision.md "Never" list, docs/design_bible.md "No levels").
##
## What stays is the players' old XP itself. Characters saved while skills existed carry
## skill id -> total XP (Postgres table character_skills, migration 0003, and the `skills`
## field of a host's JSON save). Hard rule 1 says never delete or corrupt player data, so the
## stores still load it, keep it on the character untouched and write it back unchanged.
## This file only cleans what was stored; it gives the numbers no meaning.


## Turns whatever was stored (Postgres rows, JSON, garbage) into id -> XP (int >= 0). Every
## id is kept, known or not: never silently lose stored data.
static func normalize(src: Variant) -> Dictionary:
	var out := {}
	if typeof(src) != TYPE_DICTIONARY:
		return out
	for k in src:
		var id := str(k)
		if id == "":
			continue
		var v: Variant = src[k]
		var n := 0
		match typeof(v):
			TYPE_INT:
				n = v
			TYPE_FLOAT:
				n = int(v) if is_finite(v) else 0
			TYPE_STRING:
				n = (v as String).to_int()
		out[id] = maxi(0, n)
	return out
