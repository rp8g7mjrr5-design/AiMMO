class_name Skills
## The long road (owner direction 5, roadmap Milestone 1): four skills that level by doing.
## Every number for skills lives in this one file: the skills, the XP curve, how much XP
## each gather and craft pays, the "better together" bonus and the unlock table. Pure
## functions over a small Dictionary (skill id -> total XP), so the rules are unit tested
## without a running server. The server keeps that Dictionary in the character
## (CharacterData.skills, stored in character_skills) and changes it only through gain().
##
## A character with no XP in a skill is level 1 in it, so characters saved before skills
## existed load at level 1 everywhere with nothing lost.

## Skill ids are PERMANENT: they are stored in character_skills.skill.
const SKILLS := {
	"felling": {"label": "Felling", "verb": "gathers"},
	"quarrying": {"label": "Quarrying", "verb": "gathers"},
	"tapping": {"label": "Tapping", "verb": "gathers"},
	"toolcraft": {"label": "Toolcraft", "verb": "crafts"},
}
const ORDER := ["felling", "quarrying", "tapping", "toolcraft"]
const CAP := 100

## Which skill a gather from each node kind trains (ResourceNodes.KINDS).
const KIND_SKILL := {"ash": "felling", "pine": "felling", "stone": "quarrying", "ember_sap": "tapping"}

## XP for one completed gather, by node kind. Stone takes a little longer than wood and
## pays a little more; a seep gives once, only at night, so it pays the most.
const GATHER_XP := {"ash": 10, "pine": 10, "stone": 12, "ember_sap": 30}
## XP for one completed craft: Toolcraft pays per ingredient used, so bigger things teach
## more (a stone axe, 5 items, is 40 XP; a campfire, 8 items, is 64).
const CRAFT_XP_PER_ITEM := 8

## Better together: a gather or craft with another player within TOGETHER_RANGE metres
## pays TOGETHER_BONUS more (rounded up), so working a grove side by side is the fast way.
const TOGETHER_RANGE := 15.0
const TOGETHER_BONUS := 0.25

## Every level makes that skill's gathers SPEED_PER_LEVEL quicker (level 100: 30% quicker).
const SPEED_PER_LEVEL := 0.003

## The XP curve: XP needed to go from level L to L + 1 is
##   round_to_5(CURVE_A * L^CURVE_P + CURVE_C * L^3).
## Our own shape, tuned for the timings in GatherChannel (about 2 s a gather bare-handed,
## 1 s with a tool, ~10 XP each): level 2 at 150 XP (about 15 gathers, a minute), level 5
## at ~1,700 XP (about 10 minutes), level 10 at ~8,400 XP (inside a first evening), level
## 50 at ~480,000 XP (weeks), level 100 at ~4.8 million (months). The gentle L^1.1 part
## keeps the early levels coming quickly; the cubic part makes the high levels a long road.
## tests/unit/test_gameplay_skills.gd pins these targets; retune here, nowhere else.
const CURVE_A := 150.0
const CURVE_P := 1.1
const CURVE_C := 0.15

## Named unlocks, by skill and level. `yield`: extra items per gather from then on (adds
## up). `soon`: named now so a player can see it coming, built in a later milestone part
## (tier-2 nodes, Toolcraft recipes). Every level also gives SPEED_PER_LEVEL.
const UNLOCKS := {
	"felling": {
		5: {"name": "Old ember ash", "text": "work the old ember ashes past the meadow", "soon": true},
		10: {"name": "Clean cuts", "text": "+1 wood from every gather", "yield": 1},
		25: {"name": "Heartwood", "text": "+1 more wood from every gather", "yield": 1},
	},
	"quarrying": {
		5: {"name": "Rich seam", "text": "work the rich stone seams past the meadow", "soon": true},
		10: {"name": "True strike", "text": "+1 stone from every gather", "yield": 1},
		25: {"name": "Splitter", "text": "+1 more stone from every gather", "yield": 1},
	},
	"tapping": {
		5: {"name": "Patient hands", "text": "+1 ember sap from every seep", "yield": 1},
		15: {"name": "Deep draw", "text": "+1 more ember sap from every seep", "yield": 1},
	},
	"toolcraft": {
		3: {"name": "Bench sense", "text": "the first Toolcraft recipes at the workbench", "soon": true},
		5: {"name": "Ember-hardened tools", "text": "a better axe and pickaxe that gather faster", "soon": true},
	},
}

static var _total_for: PackedInt64Array = PackedInt64Array()


static func is_skill(id: String) -> bool:
	return SKILLS.has(id)


static func label(id: String) -> String:
	return str(SKILLS.get(id, {}).get("label", id.capitalize()))


## XP needed to go from `level` to `level + 1` (0 at the cap).
static func xp_step(level: int) -> int:
	if level < 1 or level >= CAP:
		return 0
	var raw := CURVE_A * pow(float(level), CURVE_P) + CURVE_C * pow(float(level), 3.0)
	return int(round(raw / 5.0)) * 5


## Total XP at which `level` is reached (level 1 is 0 XP).
static func xp_for_level(level: int) -> int:
	if _total_for.is_empty():
		_total_for.resize(CAP + 1)
		_total_for[0] = 0
		_total_for[1] = 0
		for l in range(2, CAP + 1):
			_total_for[l] = _total_for[l - 1] + xp_step(l - 1)
	return int(_total_for[clampi(level, 1, CAP)])


## The level a total of `xp` gives, 1..CAP.
static func level_for(xp: int) -> int:
	var lo := 1
	var hi := CAP
	while lo < hi: # highest level whose threshold is <= xp
		var mid := (lo + hi + 1) / 2
		if xp_for_level(mid) <= xp:
			lo = mid
		else:
			hi = mid - 1
	return lo


## XP still needed for the next level (0 at the cap).
static func xp_to_next(xp: int) -> int:
	var l := level_for(xp)
	return 0 if l >= CAP else xp_for_level(l + 1) - xp


## 0..1 through the current level (1.0 at the cap), for a progress bar.
static func progress(xp: int) -> float:
	var l := level_for(xp)
	if l >= CAP:
		return 1.0
	var base := xp_for_level(l)
	return clampf(float(xp - base) / float(xp_for_level(l + 1) - base), 0.0, 1.0)


static func xp_of(skills: Dictionary, skill: String) -> int:
	return int(skills.get(skill, 0))


static func level_of(skills: Dictionary, skill: String) -> int:
	return level_for(xp_of(skills, skill))


## The skill a gather of node `kind` trains, or "" for none.
static func skill_for_kind(kind: String) -> String:
	return str(KIND_SKILL.get(kind, ""))


## XP for one gather of `kind`, with the together bonus when `together` is true.
static func gather_xp(kind: String, together: bool = false) -> int:
	return with_bonus(int(GATHER_XP.get(kind, 0)), together)


## XP for crafting `recipe` once (Toolcraft), with the together bonus when `together`.
static func craft_xp(recipe: String, together: bool = false) -> int:
	var r: Dictionary = Crafting.RECIPES.get(recipe, {})
	var items := 0
	for item in r.get("needs", {}):
		items += int(r.needs[item])
	return with_bonus(items * CRAFT_XP_PER_ITEM, together)


static func with_bonus(xp: int, together: bool) -> int:
	return int(ceil(xp * (1.0 + TOGETHER_BONUS))) if together and xp > 0 else xp


## Adds `amount` XP to `skill` in `skills`. Returns {skill, gained, xp (the new total),
## level_before, level (now), unlocks (Array of the unlocks reached, in level order)}.
## An unknown skill or a non-positive amount changes nothing (gained 0).
static func gain(skills: Dictionary, skill: String, amount: int) -> Dictionary:
	var before := xp_of(skills, skill)
	var lb := level_for(before)
	if not is_skill(skill) or amount <= 0:
		return {"skill": skill, "gained": 0, "xp": before, "level_before": lb, "level": lb, "unlocks": []}
	var after := before + amount
	skills[skill] = after
	var la := level_for(after)
	var reached: Array = []
	for l in range(lb + 1, la + 1):
		var u = unlock_at(skill, l)
		if u != null:
			reached.append(u)
	return {"skill": skill, "gained": amount, "xp": after, "level_before": lb, "level": la, "unlocks": reached}


## The unlock at exactly `level` of `skill` ({level, name, text, ...}), or null.
static func unlock_at(skill: String, level: int) -> Variant:
	var table: Dictionary = UNLOCKS.get(skill, {})
	if not table.has(level):
		return null
	var u: Dictionary = table[level].duplicate()
	u.level = level
	return u


## The next named unlock above `level`, or null when there is none left.
static func next_unlock(skill: String, level: int) -> Variant:
	var levels: Array = UNLOCKS.get(skill, {}).keys()
	levels.sort()
	for l in levels:
		if int(l) > level:
			return unlock_at(skill, int(l))
	return null


## Extra items per gather that `skill` at `level` gives (the `yield` unlocks reached).
static func yield_bonus(skill: String, level: int) -> int:
	var extra := 0
	var table: Dictionary = UNLOCKS.get(skill, {})
	for l in table:
		if int(l) <= level:
			extra += int(table[l].get("yield", 0))
	return extra


## How much quicker gathers get at `level`: multiply the gather time by this.
static func speed_factor(level: int) -> float:
	return 1.0 - SPEED_PER_LEVEL * float(clampi(level, 1, CAP) - 1)


## Turns whatever was stored (Postgres rows, JSON, garbage) into skill id -> XP (int >= 0).
## Unknown skill ids are kept (as Inventory keeps retired items): never silently lose XP.
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


## "Felling is now level 2! Your gathers are a little quicker. Next: Felling 5, Old ember ash."
## The system line for a level-up (`r` from gain()).
static func level_up_text(r: Dictionary) -> String:
	var skill := str(r.skill)
	var name := label(skill)
	var line := "%s is now level %d!" % [name, int(r.level)]
	var unlocks: Array = r.get("unlocks", [])
	if not unlocks.is_empty():
		var parts := PackedStringArray()
		for u in unlocks:
			parts.append("%s (%s%s)" % [u.name, u.text, ", coming soon" if u.get("soon", false) else ""])
		line += " Unlocked: %s." % ", ".join(parts)
	elif skill != "toolcraft":
		line += " Your %s are a little quicker." % str(SKILLS[skill].verb)
	var nxt = next_unlock(skill, int(r.level))
	if nxt != null:
		line += " Next: %s %d, %s." % [name, int(nxt.level), nxt.name]
	return line


## "Felling 3 (40/505 XP), Quarrying 1 (0/150 XP), ..." for the hidden /skills dev command.
static func describe(skills: Dictionary) -> String:
	var parts := PackedStringArray()
	for id in ORDER:
		var xp := xp_of(skills, id)
		var l := level_for(xp)
		if l >= CAP:
			parts.append("%s %d (max)" % [label(id), l])
		else:
			parts.append("%s %d (%d/%d XP)" % [label(id), l, xp - xp_for_level(l), xp_for_level(l + 1) - xp_for_level(l)])
	return "Skills: %s." % ", ".join(parts)
