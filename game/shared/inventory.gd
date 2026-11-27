class_name Inventory
## A character's pack: what they carry, as a Dictionary of item id -> quantity, e.g.
## {"ash_wood": 4, "stone": 2}. Pure functions, used by the server (which owns every
## change), the stores (which save it), and later the client (which shows it).
##
## Rules:
## - Only the server changes an inventory. Clients see it; they never send one.
## - Items stack by id. One item id holds at most MAX_STACK.
## - A quantity of 0 means "none". Removed items stay in the Dictionary at 0 until the next
##   load, so the next save writes the 0 instead of leaving a stale row behind.
## - normalize() never drops an item id it doesn't know, so an item retired from ITEMS can
##   never silently vanish from someone's saved pack (save compatibility rule).

## per item id. Was 99; raised to 999 (2026-11-23) because both wood stacks filled in
## one long session and a full pack quietly ended it (test_gameplay_first_session_pace).
const MAX_STACK := 999

## Every item that exists. Ids are PERMANENT: they are stored in inventory_items.item.
## The raw materials match ResourceNodes.KINDS[*].item (plant fibre from the scrub) and the
## creatures' drops (Wildlife.KINDS); the rest are made with Crafting.RECIPES (whose ids are
## the same as the item they make); cooked meat is cooked at a campfire (Needs.COOKS) and berries come with scrub fibre; a
## waterskin (crafted) fills at fresh water into a full waterskin (Needs.FILLS).
##
## Grounded zombie survival (owner direction, 2026-11-26, design bible direction 11): no magic.
## Tools go wood, then stone (an axe and a pickaxe of each); the first weapons are a wooden
## club and spear, then a stone maul and spear; a bandage is the first medicine.
const ITEMS := {
	"ash_wood": {"label": "ash wood"},
	"pine_wood": {"label": "pine wood"},
	"stone": {"label": "stone"},
	"plant_fibre": {"label": "plant fibre"},
	"hide": {"label": "hide"},
	"raw_meat": {"label": "raw meat"},
	"wooden_axe": {"label": "wooden axe"},
	"wooden_pickaxe": {"label": "wooden pickaxe"},
	"stone_axe": {"label": "stone axe"},
	"stone_pickaxe": {"label": "stone pickaxe"},
	"wooden_club": {"label": "wooden club"},
	"wooden_spear": {"label": "wooden spear"},
	"stone_maul": {"label": "stone maul"},
	"stone_spear": {"label": "stone spear"},
	"bandage": {"label": "bandage"},
	"torch": {"label": "torch"},
	"campfire": {"label": "campfire"},
	"cooked_meat": {"label": "cooked meat"},
	"berries": {"label": "berries"},
	"waterskin": {"label": "waterskin"},
	"full_waterskin": {"label": "full waterskin"},
}
const ITEM_ORDER := ["ash_wood", "pine_wood", "stone", "plant_fibre", "hide", "raw_meat",
	"wooden_axe", "wooden_pickaxe", "stone_axe", "stone_pickaxe",
	"wooden_club", "wooden_spear", "stone_maul", "stone_spear",
	"bandage", "torch", "campfire", "cooked_meat", "berries", "waterskin", "full_waterskin"]
## Items that are drawn (world's ItemIcons has them) but not moved into ITEMS yet. Empty
## today: the first hunt's hide and raw meat waited here until the grounded-tools pass
## (2026-11-26) moved them into ITEMS. Kept as the waiting room for the next one.
const NEW_ITEMS := {}
## Items that are real (crafted, saved, named) before world has drawn their icon. A client
## shows them with the fallback bundle until then. Ids are PERMANENT like ITEMS'. Empty today.
const UNDRAWN := {}
## Items that no longer exist: the ember (magic) items, retired by owner direction on
## 2026-11-26 ("we don't need magic"). A saved pack that still holds one is converted once,
## when it loads (convert_retired, from CharacterData.normalize), into its grounded
## equivalent, so nobody loses what they earned: `into` gets `per` for each one held (a tool
## only if you don't already carry one). The retired id is left at 0, which the next save
## writes. These ids must never be reused for something else.
const RETIRED := {
	"ember_axe": {"into": "stone_axe", "per": 1},
	"ember_pickaxe": {"into": "stone_pickaxe", "per": 1},
	"ember_lantern": {"into": "torch", "per": 3},
	"ember_heartwood": {"into": "ash_wood", "per": 2},
	"veinstone": {"into": "stone", "per": 2},
	"ember_sap": {"into": "plant_fibre", "per": 1},
}
## Items you only ever carry one of (they never wear out): Crafting refuses a second, and
## convert_retired never gives a second.
const ONE_ONLY := ["wooden_axe", "wooden_pickaxe", "stone_axe", "stone_pickaxe",
	"wooden_club", "wooden_spear", "stone_maul", "stone_spear"]


static func is_item(item: String) -> bool:
	return ITEMS.has(item) or NEW_ITEMS.has(item) or UNDRAWN.has(item)


static func label(item: String) -> String:
	if ITEMS.has(item):
		return str(ITEMS[item].label)
	if NEW_ITEMS.has(item):
		return str(NEW_ITEMS[item].label)
	if UNDRAWN.has(item):
		return str(UNDRAWN[item].label)
	return item.replace("_", " ")


## Turns anything stored or received into a clean inventory: String keys, int quantities
## of 0 or more. Not a Dictionary -> empty. Unknown item ids are kept.
static func normalize(src: Variant) -> Dictionary:
	var out := {}
	if typeof(src) != TYPE_DICTIONARY:
		return out
	for k in src:
		var key := str(k).strip_edges()
		if key == "":
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
		out[key] = maxi(n, 0)
	return out


## Turns every retired item in `inv` into its grounded equivalent (RETIRED) and leaves the
## retired id at 0. Idempotent. Returns {retired id: how many were converted}. Mutates `inv`.
static func convert_retired(inv: Dictionary) -> Dictionary:
	var done := {}
	for old in RETIRED:
		var n := count(inv, old)
		if n <= 0:
			continue
		var into := str(RETIRED[old].into)
		var give := n * int(RETIRED[old].per)
		if into in ONE_ONLY:
			give = 0 if count(inv, into) > 0 else 1
		inv[into] = mini(count(inv, into) + give, MAX_STACK)
		inv[old] = 0
		done[old] = n
	return done


static func count(inv: Dictionary, item: String) -> int:
	return int(inv.get(item, 0))


static func has(inv: Dictionary, item: String, qty: int = 1) -> bool:
	return qty > 0 and count(inv, item) >= qty


## Adds up to `qty` of a known item, stopping at MAX_STACK. Returns how many were added
## (0 for an unknown item or a full stack). Mutates `inv`.
static func add(inv: Dictionary, item: String, qty: int) -> int:
	if qty <= 0 or not is_item(item):
		return 0
	var have := count(inv, item)
	var added := clampi(MAX_STACK - have, 0, qty)
	if added > 0:
		inv[item] = have + added
	return added


## Removes exactly `qty`, or nothing at all if there isn't that much. Mutates `inv`.
static func remove(inv: Dictionary, item: String, qty: int) -> bool:
	if not has(inv, item, qty):
		return false
	inv[item] = count(inv, item) - qty
	return true


## Item ids with a quantity above 0: known items in ITEM_ORDER first, then unknown ones
## sorted, so lists always come out in the same order.
static func held(inv: Dictionary) -> Array:
	var out: Array = []
	for item in ITEM_ORDER:
		if count(inv, item) > 0:
			out.append(item)
	var extra: Array = []
	for item in inv:
		if not ITEMS.has(item) and count(inv, item) > 0:
			extra.append(item)
	extra.sort()
	out.append_array(extra)
	return out


## The pack as it goes over the wire in s2c_inventory: {item: count} for every item held,
## in held() order, the same shape as the login character's `inventory`.
static func to_wire(inv: Dictionary) -> Dictionary:
	var out := {}
	for item in held(inv):
		out[item] = count(inv, item)
	return out


static func total(inv: Dictionary) -> int:
	var n := 0
	for item in inv:
		n += count(inv, item)
	return n


## "Your pack: 4 ash wood, 2 stone." or "Your pack is empty. ..."
static func describe(inv: Dictionary) -> String:
	var items := held(inv)
	if items.is_empty():
		return "Your pack is empty. Walk up to a tree or stone and press E."
	var parts := PackedStringArray()
	for item in items:
		parts.append("%d %s" % [count(inv, item), label(item)])
	return "Your pack: %s." % ", ".join(parts)
