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

const MAX_STACK := 99 ## per item id; picked so a pack of raw materials stays readable

## Every item that exists. Ids are PERMANENT: they are stored in inventory_items.item.
## The four raw materials match ResourceNodes.KINDS[*].item.
const ITEMS := {
	"ash_wood": {"label": "ash wood"},
	"pine_wood": {"label": "pine wood"},
	"stone": {"label": "stone"},
	"ember_sap": {"label": "ember sap"},
}
const ITEM_ORDER := ["ash_wood", "pine_wood", "stone", "ember_sap"]


static func is_item(item: String) -> bool:
	return ITEMS.has(item)


static func label(item: String) -> String:
	return str(ITEMS[item].label) if ITEMS.has(item) else item.replace("_", " ")


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


static func total(inv: Dictionary) -> int:
	var n := 0
	for item in inv:
		n += count(inv, item)
	return n


## "Your pack: 4 ash wood, 2 stone." or "Your pack is empty. ..."
static func describe(inv: Dictionary) -> String:
	var items := held(inv)
	if items.is_empty():
		return "Your pack is empty. Stand at a tree or stone and type /gather."
	var parts := PackedStringArray()
	for item in items:
		parts.append("%d %s" % [count(inv, item), label(item)])
	return "Your pack: %s." % ", ".join(parts)
