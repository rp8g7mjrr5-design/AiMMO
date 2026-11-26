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
## The four raw materials match ResourceNodes.KINDS[*].item; the rest are made with
## Crafting.RECIPES (whose ids are the same as the item they make).
const ITEMS := {
	"ash_wood": {"label": "ash wood"},
	"pine_wood": {"label": "pine wood"},
	"stone": {"label": "stone"},
	"ember_sap": {"label": "ember sap"},
	"ember_heartwood": {"label": "ember heartwood"},
	"veinstone": {"label": "veinstone"},
	"stone_axe": {"label": "stone axe"},
	"stone_pickaxe": {"label": "stone pickaxe"},
	"ember_axe": {"label": "ember axe"},
	"ember_pickaxe": {"label": "ember pickaxe"},
	"torch": {"label": "torch"},
	"campfire": {"label": "campfire"},
	"ember_lantern": {"label": "ember lantern"},
}
const ITEM_ORDER := ["ash_wood", "pine_wood", "stone", "ember_sap", "ember_heartwood", "veinstone", "stone_axe", "stone_pickaxe", "ember_axe", "ember_pickaxe", "torch", "campfire", "ember_lantern"]
## Items that are drawn (world's ItemIcons has them) but not moved into ITEMS yet. The
## tier-2 materials waited here until PR #108. The first hunt's hide and raw meat wait here
## now (2026-11-24, world drew them in #200): they are real, toasted and saved, and the pack
## shows them after the ITEM_ORDER stacks. They move into ITEMS and ITEM_ORDER (after
## veinstone) once client's pack-window test no longer hard-codes how many items exist
## (request filed with client); moving them is a one-line change with no save impact.
## tests/unit/test_world_item_icons checks every id here has its own icon.
const NEW_ITEMS := {
	"hide": {"label": "hide"},
	"raw_meat": {"label": "raw meat"},
}
## Items that are real (crafted, saved, named) before world has drawn their icon. A client
## shows them with the fallback bundle until then. When ItemIcons draws one, gameplay moves
## it into ITEMS and ITEM_ORDER. Ids are PERMANENT like ITEMS'. Empty today: the ember
## tools moved into ITEMS (after the stone tools) once world drew them (#118's run, world's
## ember tool icons). The first hunt's drops waited here until world drew them (#200); they
## are in NEW_ITEMS now. Kept as the waiting room for the next undrawn item.
const UNDRAWN := {}


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
