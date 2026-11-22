class_name Crafting
## Crafting: recipes, the Spawn Meadow workbench, and the replies for /craft. Pure
## functions over an Inventory Dictionary, so the rules are unit tested without a server.
## The server checks with check(), then moves the items with its own take_item/give_item
## (it never trusts the client, which only names a recipe id). Players will craft from a
## window opened with E at the workbench (c2s_craft, a later protocol bump); until then the
## hidden debug command "/craft axe" drives the same server code for bots and developers.
##
## Tools are kept in the pack like any item. A tool (`tool: true`) is never worn out and
## you only ever need one, so crafting a second is refused. Gathering.tool_for() reads the
## pack to make gathering faster and richer when the right tool is in it.

## The workbench at Spawn Meadow: inside the empty centre of the meadow
## (ResourceNodes.SPAWN_CLEAR_RADIUS), a few steps from where every new player arrives.
## World draws it at workbench_pos(); keep the two in step by always using that function.
const WORKBENCH_XZ := Vector2(3.0, -2.0)
const BENCH_RANGE := 6.0 ## metres from the bench's centre to use it

## Recipe and item ids are PERMANENT: products are stored in inventory_items.item.
## `needs`: item id -> quantity used up. `makes`: how many you get. `bench`: needs the
## workbench (a torch can be twisted together anywhere).
const RECIPES := {
	"stone_axe": {"label": "stone axe", "needs": {"ash_wood": 3, "stone": 2}, "makes": 1, "bench": true, "tool": true},
	"stone_pickaxe": {"label": "stone pickaxe", "needs": {"pine_wood": 3, "stone": 3}, "makes": 1, "bench": true, "tool": true},
	"torch": {"label": "torch", "needs": {"pine_wood": 1, "ember_sap": 1}, "makes": 3, "bench": false, "tool": false},
	"campfire": {"label": "campfire", "needs": {"ash_wood": 2, "pine_wood": 2, "stone": 4}, "makes": 1, "bench": true, "tool": false},
}
const RECIPE_ORDER := ["stone_axe", "stone_pickaxe", "torch", "campfire"]

## Plain words players type, to recipe ids.
const WORDS := {
	"axe": "stone_axe", "stone_axe": "stone_axe", "hatchet": "stone_axe",
	"pickaxe": "stone_pickaxe", "pick": "stone_pickaxe", "stone_pickaxe": "stone_pickaxe", "stone_pick": "stone_pickaxe",
	"torch": "torch", "torches": "torch",
	"campfire": "campfire", "fire": "campfire", "camp_fire": "campfire",
}


static func workbench_pos() -> Vector3:
	return Vector3(WORKBENCH_XZ.x, Terrain.height(WORKBENCH_XZ.x, WORKBENCH_XZ.y), WORKBENCH_XZ.y)


static func near_bench(pos: Vector3) -> bool:
	return Vector2(pos.x, pos.z).distance_to(WORKBENCH_XZ) <= BENCH_RANGE


static func is_recipe(id: String) -> bool:
	return RECIPES.has(id)


static func makes_tool(item: String) -> bool:
	return bool(RECIPES.get(item, {}).get("tool", false))


## A /craft argument to a recipe id: "" for nothing typed, null for something unknown.
static func parse_recipe(word: String) -> Variant:
	var w := word.strip_edges().to_lower().replace("-", "_").replace(" ", "_")
	if w == "":
		return ""
	if w.begins_with("a_"):
		w = w.substr(2)
	return WORDS.get(w, null)


## What is still missing to craft `id`: item id -> how many more are needed.
static func missing(inv: Dictionary, id: String) -> Dictionary:
	var out := {}
	var needs: Dictionary = RECIPES.get(id, {}).get("needs", {})
	for item in needs:
		var short := int(needs[item]) - Inventory.count(inv, item)
		if short > 0:
			out[item] = short
	return out


## Why `id` can't be crafted from `inv` by a player at `pos`, or "" if it can.
## Reasons, in the order they are checked: "unknown", "owned" (a tool you already carry),
## "bench" (needs the workbench, which is too far), "missing", "full" (no room for it).
static func check(inv: Dictionary, id: String, pos: Vector3) -> String:
	if not is_recipe(id):
		return "unknown"
	var r: Dictionary = RECIPES[id]
	if r.tool and Inventory.count(inv, id) > 0:
		return "owned"
	if r.bench and not near_bench(pos):
		return "bench"
	if not missing(inv, id).is_empty():
		return "missing"
	if Inventory.count(inv, id) + int(r.makes) > Inventory.MAX_STACK:
		return "full"
	return ""


## Ingredients as words: "3 ash wood and 2 stone".
static func needs_text(needs: Dictionary) -> String:
	var parts := PackedStringArray()
	for item in Inventory.ITEM_ORDER:
		if needs.has(item):
			parts.append("%d %s" % [int(needs[item]), Inventory.label(item)])
	if parts.size() <= 1:
		return "".join(parts)
	return "%s and %s" % [", ".join(parts.slice(0, parts.size() - 1)), parts[parts.size() - 1]]


## "The workbench is 14 m to the north-east, at the heart of Spawn Meadow."
static func bench_hint(pos: Vector3) -> String:
	var off := workbench_pos() - pos
	var dist := roundi(Vector2(off.x, off.z).length())
	return "The workbench is %d m to the %s, at the heart of Spawn Meadow." % [dist, Gathering.direction_name(off)]


## The reply for a refused craft (reason from check()).
static func refusal(reason: String, inv: Dictionary, id: String, pos: Vector3) -> String:
	var label := str(RECIPES.get(id, {}).get("label", id))
	match reason:
		"owned":
			return "You already carry a %s; it never wears out." % label
		"bench":
			return "A %s needs the workbench. %s" % [label, bench_hint(pos)]
		"missing":
			return "You need %s more to make a %s." % [needs_text(missing(inv, id)), label]
		"full":
			return "No room in your pack for another %s." % label
	return "Craft what? %s" % recipes_text(inv)


## "You craft a stone axe. Wood comes faster with it in your pack."
static func success(id: String, made: int, inv: Dictionary) -> String:
	var r: Dictionary = RECIPES[id]
	if made > 1:
		return "You craft %d %ses (%d in your pack)." % [made, r.label, Inventory.count(inv, id)]
	match id:
		"stone_axe":
			return "You craft a stone axe. Ash and pine give more, and faster, with it in your pack."
		"stone_pickaxe":
			return "You craft a stone pickaxe. Stone gives more, and faster, with it in your pack."
	return "You craft a %s (%d in your pack)." % [r.label, Inventory.count(inv, id)]


## "Recipes: stone axe (3 ash wood and 2 stone, at the workbench) ..." with a mark on the
## ones you can make from your pack right now (ignoring where you stand).
static func recipes_text(inv: Dictionary) -> String:
	var parts := PackedStringArray()
	for id in RECIPE_ORDER:
		var r: Dictionary = RECIPES[id]
		var where := ", at the workbench" if r.bench else ", anywhere"
		var ready := ""
		if r.tool and Inventory.count(inv, id) > 0:
			ready = " (have it)"
		elif missing(inv, id).is_empty():
			ready = " (ready)"
		var what := str(r.label) if int(r.makes) == 1 else "%d %ses" % [int(r.makes), r.label]
		parts.append("%s: %s%s%s" % [what, needs_text(r.needs), where, ready])
	return "Recipes: %s." % "; ".join(parts)
