class_name PackGrid
extends RefCounted
## The pack as a grid (owner direction, 2026-11-27: "an inventory that works like Tarkov or
## ARC Raiders", mechanics only; the look is Satchel). Every item takes room by its shape:
## a log is 1x2, a stone 1x1, an axe 1x3, a spear 1x4. A stack holds up to `stack` of one
## item in that shape, so carrying more of something takes more room, and the pack fills.
##
## The counts (Inventory, item id -> how many) stay the truth for what you own; this file
## only says where each stack sits. A layout is `places`: one [item, index, x, y, turned]
## per stack the player has put somewhere (index counts that item's stacks, 0 first).
## layout() lays the pack out from the counts and the places: a stack keeps its place while
## that spot is free and inside the grid, and everything else goes in the first free spot,
## top-left first, standing or turned. A stack with no room is "over": still owned, never
## lost (old saves with 999 of something), but it takes no room and the pack shows it
## below the grid until there is space.
##
## Pure and deterministic: the server lays out every change and the client draws the same
## layout from the same counts and places. Server rules (room_for, move) live here too.

const COLS := 10
const ROWS := 6

## item id -> [width, height, how many one stack holds]. Ids not listed are 1x1, DEFAULT_STACK.
const SHAPES := {
	"ash_wood": [1, 2, 20],
	"pine_wood": [1, 2, 20],
	"stone": [1, 1, 15],
	"plant_fibre": [1, 1, 20],
	"hide": [1, 2, 4],
	"raw_meat": [1, 1, 5],
	"wooden_axe": [1, 3, 1],
	"wooden_pickaxe": [1, 3, 1],
	"stone_axe": [1, 3, 1],
	"stone_pickaxe": [1, 3, 1],
	"wooden_club": [1, 3, 1],
	"wooden_spear": [1, 4, 1],
	"stone_maul": [2, 3, 1],
	"stone_spear": [1, 4, 1],
	"bandage": [1, 1, 10],
	"torch": [1, 2, 4],
	"campfire": [2, 2, 1],
	"cooked_meat": [1, 1, 5],
	"berries": [1, 1, 20],
	"waterskin": [1, 2, 1],
	"full_waterskin": [1, 2, 1],
}
const DEFAULT_STACK := 10


## The item's size standing up: Vector2i(width, height) in cells.
static func shape(item: String) -> Vector2i:
	var s: Array = SHAPES.get(item, [1, 1, DEFAULT_STACK])
	return Vector2i(int(s[0]), int(s[1]))


## How many of `item` one stack holds.
static func stack_size(item: String) -> int:
	if item in Inventory.ONE_ONLY:
		return 1
	var s: Array = SHAPES.get(item, [1, 1, DEFAULT_STACK])
	return maxi(1, int(s[2]))


## The stacks the counts make, in Inventory.held order: [{item, index, n}], full stacks
## first and the part stack last for each item.
static func stacks(inv: Dictionary) -> Array:
	var out: Array = []
	for item in Inventory.held(inv):
		var left := Inventory.count(inv, item)
		var cap := stack_size(item)
		var i := 0
		while left > 0:
			var n := mini(left, cap)
			out.append({"item": item, "index": i, "n": n})
			left -= n
			i += 1
	return out


## The pack laid out: {"placed": [{item, index, n, x, y, w, h, turned}], "over": [{item, index, n}]}.
## `places` is the saved layout (anything malformed in it is ignored).
static func layout(inv: Dictionary, places: Variant) -> Dictionary:
	var want := _place_map(places)
	var grid := _empty_grid()
	var placed: Array = []
	var loose: Array = []
	# Stacks with a saved place keep it while it is free, in saved order.
	for st in stacks(inv):
		var key := _key(str(st.item), int(st.index))
		if want.has(key):
			var p: Array = want[key]
			var sz := _size(str(st.item), bool(p[2]))
			if _free(grid, int(p[0]), int(p[1]), sz):
				_fill(grid, int(p[0]), int(p[1]), sz, true)
				placed.append(_entry(st, int(p[0]), int(p[1]), sz, bool(p[2])))
				continue
		loose.append(st)
	var over: Array = []
	for st in loose:
		var spot := _first_free(grid, str(st.item))
		if spot.is_empty():
			over.append(st)
			continue
		var sz := _size(str(st.item), bool(spot.turned))
		_fill(grid, int(spot.x), int(spot.y), sz, true)
		placed.append(_entry(st, int(spot.x), int(spot.y), sz, bool(spot.turned)))
	return {"placed": placed, "over": over}


## The places of a laid-out pack, to save and send: [[item, index, x, y, turned], ...].
static func places_of(laid: Dictionary) -> Array:
	var out: Array = []
	for p in laid.placed:
		out.append([str(p.item), int(p.index), int(p.x), int(p.y), bool(p.turned)])
	return out


## How many stacks have no room.
static func over_count(laid: Dictionary) -> int:
	return (laid.over as Array).size()


## How many more of `item` fit without pushing anything out of the pack (and under
## Inventory.MAX_STACK): the part stack's free share, then every whole new stack that still
## finds a free spot around what is already laid out. Exact when `places` names every
## stack, which the server keeps true (it saves the layout after every change).
static func room_for(inv: Dictionary, places: Variant, item: String) -> int:
	if not Inventory.is_item(item):
		return 0
	var have := Inventory.count(inv, item)
	var cap := stack_size(item)
	var limit := Inventory.MAX_STACK - have
	if item in Inventory.ONE_ONLY:
		limit = 1 - have
	if limit <= 0:
		return 0
	var laid := layout(inv, places)
	var stuck := false # a stack of this item already waits below the grid: no more of it
	for o in laid.over:
		stuck = stuck or str(o.item) == item
	if stuck:
		return 0
	var grid := _empty_grid()
	for p in laid.placed:
		_fill(grid, int(p.x), int(p.y), Vector2i(int(p.w), int(p.h)), true)
	var room := int(ceil(float(have) / cap)) * cap - have # the part stack's free share
	while room < limit:
		var spot := _first_free(grid, item)
		if spot.is_empty():
			break
		_fill(grid, int(spot.x), int(spot.y), _size(item, bool(spot.turned)), true)
		room += cap
	return mini(room, limit)


## Moves stack (item, index) to (x, y), standing or turned. Returns the new places, or an
## empty Array when the move is refused: no such stack, off the grid, or onto another stack.
static func move(inv: Dictionary, places: Variant, item: String, index: int, x: int, y: int, turned: bool) -> Array:
	var laid := layout(inv, places)
	var grid := _empty_grid()
	var found := false
	for p in laid.placed:
		if str(p.item) == item and int(p.index) == index:
			found = true
			continue
		_fill(grid, int(p.x), int(p.y), Vector2i(int(p.w), int(p.h)), true)
	if not found:
		for o in laid.over:
			if str(o.item) == item and int(o.index) == index:
				found = true
	if not found:
		return []
	var sz := _size(item, turned)
	if not _free(grid, x, y, sz):
		return []
	var out: Array = [[item, index, x, y, turned]]
	for p in places_of(laid):
		if not (str(p[0]) == item and int(p[1]) == index):
			out.append(p)
	return out


## The cell under (x, y) -> that stack's {item, index}, or {} (client hit tests).
static func stack_at(laid: Dictionary, x: int, y: int) -> Dictionary:
	for p in laid.placed:
		if x >= int(p.x) and x < int(p.x) + int(p.w) and y >= int(p.y) and y < int(p.y) + int(p.h):
			return {"item": str(p.item), "index": int(p.index)}
	return {}


## Cleans a saved or received layout: [[item, index, x, y, turned]] with sane types, at most
## one place per stack and never more than the grid could hold. Anything else is dropped
## (the stack just gets packed again).
static func normalize(places: Variant) -> Array:
	var out: Array = []
	if typeof(places) != TYPE_ARRAY:
		return out
	var seen := {}
	for p in places:
		if typeof(p) != TYPE_ARRAY or (p as Array).size() < 5:
			continue
		var item := str(p[0]).strip_edges()
		var key := _key(item, int(p[1]))
		if item == "" or seen.has(key) or int(p[1]) < 0:
			continue
		seen[key] = true
		out.append([item, int(p[1]), clampi(int(p[2]), -1, COLS), clampi(int(p[3]), -1, ROWS), bool(p[4])])
		if out.size() >= COLS * ROWS:
			break
	return out


static func to_json(places: Array) -> String:
	return JSON.stringify(normalize(places))


static func from_json(text: String) -> Array:
	if text.strip_edges() == "":
		return []
	var json := JSON.new()
	if json.parse(text) != OK: # junk in a save: pack it again, quietly
		return []
	return normalize(json.data)


# --- internals ---

static func _key(item: String, index: int) -> String:
	return "%s#%d" % [item, index]


static func _size(item: String, turned: bool) -> Vector2i:
	var s := shape(item)
	return Vector2i(s.y, s.x) if turned else s


static func _entry(st: Dictionary, x: int, y: int, sz: Vector2i, turned: bool) -> Dictionary:
	return {"item": str(st.item), "index": int(st.index), "n": int(st.n), "x": x, "y": y,
		"w": sz.x, "h": sz.y, "turned": turned}


static func _place_map(places: Variant) -> Dictionary:
	var out := {}
	for p in normalize(places):
		out[_key(str(p[0]), int(p[1]))] = [int(p[2]), int(p[3]), bool(p[4])]
	return out


static func _empty_grid() -> PackedByteArray:
	var g := PackedByteArray()
	g.resize(COLS * ROWS)
	return g


static func _free(grid: PackedByteArray, x: int, y: int, sz: Vector2i) -> bool:
	if x < 0 or y < 0 or x + sz.x > COLS or y + sz.y > ROWS:
		return false
	for yy in range(y, y + sz.y):
		for xx in range(x, x + sz.x):
			if grid[yy * COLS + xx] != 0:
				return false
	return true


static func _fill(grid: PackedByteArray, x: int, y: int, sz: Vector2i, on: bool) -> void:
	for yy in range(y, y + sz.y):
		for xx in range(x, x + sz.x):
			grid[yy * COLS + xx] = 1 if on else 0


## The first free spot for `item`, top-left first, standing before turned: {x, y, turned} or {}.
static func _first_free(grid: PackedByteArray, item: String) -> Dictionary:
	var s := shape(item)
	for turned in ([false] if s.x == s.y else [false, true]):
		var sz := _size(item, turned)
		for y in ROWS - sz.y + 1:
			for x in COLS - sz.x + 1:
				if _free(grid, x, y, sz):
					return {"x": x, "y": y, "turned": turned}
	return {}
