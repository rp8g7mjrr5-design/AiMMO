class_name Loot
## What you find when you search a ruin's crates, chests, sacks and bodies (RuinLayout's loot
## spots), and what a washed-up crate holds besides its wood. Step 2 of the owner's survival
## plan (2026-11-27: "study project zomboid and put that system into our game ... make sure
## every item has a purpose"): a ruin is worth the walk, and the riskier the ruin the better
## the haul (vision, "Ruins ... graded by how much it can kill you").
##
## Our take (design bible, "Take the best, then beat it"): searching is short and physical,
## never a menu you dig through. Walk up, hold the key for SEARCH_SECONDS while the bar fills,
## and what you found pops up as haul toasts. A searched spot stays empty for REFILL seconds
## (one in-game day), so a ruin you cleared is worth coming back to tomorrow.
##
## Loot only ever holds items another system already uses (owner, 2026-11-27: every item has a
## purpose): food for hunger, bandages and torches, fibre for crafting, and at higher grades
## the tools and weapons that save you a trip to the bench. A new item joins a table only with
## the system that needs it.
##
## Pure and deterministic for a given RandomNumberGenerator, so the tables are unit tested.

## How long a search takes, in seconds (a scrub gather is 1.6).
const SEARCH_SECONDS := 1.8
## How close you stand to a loot spot to search it (flat metres).
const REACH := 2.5
## Walking further than this from where the search started stops it.
const MOVE_TOLERANCE := 0.5
## Seconds a searched spot stays empty: one in-game day (WorldClock's 40-minute day). Not
## saved: a restart refills every spot, which only ever helps players.
const REFILL := 2400.0
## How far a search carries for the Gloam (Gloam.NOISE_RADIUS is a gather's): rummaging is
## quieter than chopping, but not silent.
const NOISE := 15.0

## Loot by ruin grade (Ruins.GRADE_NAMES: 1 Quiet .. 4 Deadly). Each entry is
## [item, min, max, weight]. An item id of "" is "nothing in this draw".
const TABLES := {
	1: [
		["plant_fibre", 2, 4, 30],
		["berries", 2, 4, 22],
		["bandage", 1, 1, 14],
		["torch", 1, 1, 12],
		["hide", 1, 1, 8],
		["cooked_meat", 1, 1, 8],
		["wooden_club", 1, 1, 3],
		["wooden_spear", 1, 1, 3],
	],
	2: [
		["plant_fibre", 3, 5, 20],
		["berries", 3, 5, 16],
		["bandage", 1, 2, 18],
		["torch", 1, 2, 14],
		["hide", 1, 2, 10],
		["cooked_meat", 1, 2, 10],
		["stone_axe", 1, 1, 4],
		["stone_pickaxe", 1, 1, 4],
		["wooden_spear", 1, 1, 4],
	],
	3: [
		["bandage", 2, 3, 22],
		["torch", 1, 2, 14],
		["cooked_meat", 1, 2, 14],
		["hide", 2, 3, 12],
		["stone_axe", 1, 1, 8],
		["stone_pickaxe", 1, 1, 8],
		["stone_spear", 1, 1, 7],
		["stone_maul", 1, 1, 7],
	],
	4: [
		["bandage", 2, 4, 24],
		["cooked_meat", 2, 3, 16],
		["torch", 2, 3, 12],
		["stone_spear", 1, 1, 12],
		["stone_maul", 1, 1, 12],
		["stone_axe", 1, 1, 8],
		["stone_pickaxe", 1, 1, 8],
	],
}
## A washed-up crate (ResourceNodes "wreck_crate") gives its pine wood and one draw from here.
const BEACH_CRATE := [
	["", 0, 0, 30],
	["plant_fibre", 2, 3, 26],
	["berries", 2, 3, 14],
	["torch", 1, 1, 14],
	["bandage", 1, 1, 10],
	["hide", 1, 1, 6],
]
## How many draws each kind of spot gets: [min, max].
const DRAWS := {"sack": [1, 2], "crate": [2, 2], "chest": [2, 3], "body": [1, 2]}
## Each kind leans toward what you'd expect in it (weight multipliers): a traveller's body
## carried bandages and a torch, a sack holds food and fibre, a chest the good stuff.
const BIAS := {
	"body": {"bandage": 2.0, "torch": 2.0},
	"sack": {"berries": 2.0, "plant_fibre": 1.5, "cooked_meat": 1.5},
	"chest": {"wooden_club": 3.0, "wooden_spear": 3.0, "stone_axe": 2.0, "stone_pickaxe": 2.0, "stone_spear": 2.0, "stone_maul": 2.0},
	"crate": {},
}
## What players read for each kind ("the chest").
## Items read as "some" when there is one ("some cooked meat", not "a cooked meat").
const MASS := ["plant_fibre", "berries", "cooked_meat", "raw_meat", "hide", "stone"]
const NAMES := {"crate": "crate", "chest": "chest", "sack": "sack", "body": "body"}

const TEXTS := {
	"begin": "Searching the %s...",
	"found": "You search the %s and find %s.",
	"nothing": "You search the %s. Someone got here first: there's nothing left.",
	"empty": "You've searched this %s already. Come back tomorrow.",
	"none": "There's nothing to search here.",
	"busy": "You're busy.",
	"moved": "",
	"dead": "",
}


static func kind_name(kind: String) -> String:
	return str(NAMES.get(kind, "pile"))


## The table for a ruin grade (clamped to 1..4).
static func table_for(grade: int) -> Array:
	return TABLES[clampi(grade, 1, 4)]


## A spot's key in the searched-state Dictionary: "<ruin_id>:<index>".
static func key(spot: Dictionary) -> String:
	return "%d:%d" % [int(spot.get("ruin_id", -1)), int(spot.get("index", -1))]


## One weighted draw from `table`, with `bias` multipliers: [item, qty] (item "" = nothing).
static func draw(table: Array, rng: RandomNumberGenerator, bias: Dictionary = {}) -> Array:
	var total := 0.0
	for e in table:
		total += float(e[3]) * float(bias.get(str(e[0]), 1.0))
	if total <= 0.0:
		return ["", 0]
	var pick := rng.randf() * total
	for e in table:
		pick -= float(e[3]) * float(bias.get(str(e[0]), 1.0))
		if pick < 0.0:
			if str(e[0]) == "":
				return ["", 0]
			return [str(e[0]), rng.randi_range(int(e[1]), int(e[2]))]
	var last: Array = table[table.size() - 1]
	return [str(last[0]), int(last[1])]


## What one search of a `kind` spot in a grade-`grade` ruin finds: {item: qty}, merged.
static func roll(grade: int, kind: String, rng: RandomNumberGenerator) -> Dictionary:
	var out := {}
	var d: Array = DRAWS.get(kind, [1, 1])
	var n := rng.randi_range(int(d[0]), int(d[1]))
	var bias: Dictionary = BIAS.get(kind, {})
	for i in n:
		var got := draw(table_for(grade), rng, bias)
		if str(got[0]) != "":
			out[got[0]] = int(out.get(got[0], 0)) + int(got[1])
	return out


## The extra a washed-up crate gives besides its wood: {item: qty}, often empty.
static func roll_beach(rng: RandomNumberGenerator) -> Dictionary:
	var got := draw(BEACH_CRATE, rng)
	return {} if str(got[0]) == "" else {got[0]: int(got[1])}


## --- Which spots are searched (server state, not saved) ---

static func new_state() -> Dictionary:
	return {}


## Whether the spot `k` was searched less than REFILL seconds ago.
static func is_empty(state: Dictionary, k: String, now: float) -> bool:
	return state.has(k) and now - float(state[k]) < REFILL


static func mark_searched(state: Dictionary, k: String, now: float) -> void:
	state[k] = now


## Seconds until spot `k` is full again (0 when it already is).
static func refill_in(state: Dictionary, k: String, now: float) -> float:
	if not state.has(k):
		return 0.0
	return maxf(REFILL - (now - float(state[k])), 0.0)


## --- Finding a spot ---

## The nearest of `spots` (RuinLayout.loot_spots entries) within REACH of `pos`, or {}.
static func nearest(spots: Array, pos: Vector3, reach: float = REACH) -> Dictionary:
	var best := {}
	var best_d := reach
	for sp in spots:
		var p: Vector3 = sp.pos
		var d := Vector2(p.x - pos.x, p.z - pos.z).length()
		if d <= best_d:
			best_d = d
			best = sp
	return best


## The grade of the ruin a spot belongs to (1 when the ruin is unknown).
static func grade_of(spot: Dictionary, ruins: Array) -> int:
	for r in ruins:
		if int(r.id) == int(spot.get("ruin_id", -1)):
			return int(r.grade)
	return 1


## --- Lines ---

## "2 berries and a bandage" for a find of {berries: 2, bandage: 1}, in Inventory.ITEM_ORDER.
static func list_text(found: Dictionary) -> String:
	var bits: Array = []
	for item in Inventory.ITEM_ORDER:
		if int(found.get(item, 0)) > 0:
			var n := int(found[item])
			if n > 1:
				bits.append("%d %s" % [n, Inventory.label(item)])
			else:
				bits.append(("some %s" if item in MASS else "a %s") % Inventory.label(item))
	if bits.is_empty():
		return ""
	if bits.size() == 1:
		return str(bits[0])
	return "%s and %s" % [", ".join(bits.slice(0, bits.size() - 1)), bits[bits.size() - 1]]


static func found_text(kind: String, found: Dictionary) -> String:
	var list := list_text(found)
	if list == "":
		return str(TEXTS.nothing) % kind_name(kind)
	return str(TEXTS.found) % [kind_name(kind), list]


static func text(reason: String, kind: String = "") -> String:
	var t := str(TEXTS.get(reason, ""))
	return t % kind_name(kind) if t.contains("%s") else t


## The prompt the client shows at a spot: "[E] Search the chest".
static func prompt(kind: String, key_label: String = "E") -> String:
	return "[%s] Search the %s" % [key_label, kind_name(kind)]
