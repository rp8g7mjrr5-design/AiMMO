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
## workbench (wooden things, a bandage and a torch are made in your hands anywhere).
## `upgrades`: the tool or weapon this one replaces; it is used up by the recipe, and once
## you carry the better one the old one counts as owned too. `tool`: you only ever carry one
## (tools and weapons; Inventory.ONE_ONLY). There are no levels (owner direction,
## 2026-11-26): a recipe is gated only by its materials, the tools it eats and the bench.
##
## The progression (owner direction, 2026-11-26: "wooden pick and axe first, then stone",
## Minecraft's tiers in our own grounded world): wood you can pull by hand makes the wooden
## axe, pickaxe, club and spear on the spot; the wooden pickaxe opens stone; stone and plant
## fibre (from scrub) at the bench turn each wooden one into its stone version. Plant fibre
## also makes bandages and torches.
const RECIPES := {
	"wooden_axe": {"label": "wooden axe", "needs": {"ash_wood": 3}, "makes": 1, "bench": false, "tool": true},
	"wooden_pickaxe": {"label": "wooden pickaxe", "needs": {"ash_wood": 2, "pine_wood": 2}, "makes": 1, "bench": false, "tool": true},
	"wooden_club": {"label": "wooden club", "needs": {"ash_wood": 3}, "makes": 1, "bench": false, "tool": true},
	"wooden_spear": {"label": "wooden spear", "needs": {"pine_wood": 3}, "makes": 1, "bench": false, "tool": true},
	"bandage": {"label": "bandage", "needs": {"plant_fibre": 3}, "makes": 1, "bench": false, "tool": false},
	"torch": {"label": "torch", "needs": {"pine_wood": 1, "plant_fibre": 1}, "makes": 2, "bench": false, "tool": false},
	"stone_axe": {"label": "stone axe", "needs": {"wooden_axe": 1, "stone": 3, "plant_fibre": 2}, "makes": 1, "bench": true, "tool": true,
		"upgrades": "wooden_axe"},
	"stone_pickaxe": {"label": "stone pickaxe", "needs": {"wooden_pickaxe": 1, "stone": 3, "plant_fibre": 2}, "makes": 1, "bench": true, "tool": true,
		"upgrades": "wooden_pickaxe"},
	"stone_maul": {"label": "stone maul", "needs": {"wooden_club": 1, "stone": 4, "plant_fibre": 2}, "makes": 1, "bench": true, "tool": true,
		"upgrades": "wooden_club"},
	"stone_spear": {"label": "stone spear", "needs": {"wooden_spear": 1, "stone": 2, "plant_fibre": 2}, "makes": 1, "bench": true, "tool": true,
		"upgrades": "wooden_spear"},
	"campfire": {"label": "campfire", "needs": {"ash_wood": 2, "pine_wood": 2, "stone": 4}, "makes": 1, "bench": true, "tool": false},
	# Thirst (Needs, step 3 of the survival plan): carry water away from the lakes and rivers.
	# The hunt's hide and the scrub's fibre; no bench, so you can make one where you need it.
	"waterskin": {"label": "waterskin", "needs": {"hide": 2, "plant_fibre": 2}, "makes": 1, "bench": false, "tool": false},
}
const RECIPE_ORDER := ["wooden_axe", "wooden_pickaxe", "wooden_club", "wooden_spear", "bandage", "torch",
	"stone_axe", "stone_pickaxe", "stone_maul", "stone_spear", "campfire", "waterskin"]

## Plain words players type, to recipe ids. A bare "axe" or "pickaxe" means the wooden one.
const WORDS := {
	"axe": "wooden_axe", "wooden_axe": "wooden_axe", "wood_axe": "wooden_axe", "hatchet": "wooden_axe",
	"pickaxe": "wooden_pickaxe", "pick": "wooden_pickaxe", "wooden_pickaxe": "wooden_pickaxe", "wooden_pick": "wooden_pickaxe", "wood_pickaxe": "wooden_pickaxe",
	"stone_axe": "stone_axe", "stone_hatchet": "stone_axe",
	"stone_pickaxe": "stone_pickaxe", "stone_pick": "stone_pickaxe",
	"club": "wooden_club", "wooden_club": "wooden_club",
	"spear": "wooden_spear", "wooden_spear": "wooden_spear",
	"maul": "stone_maul", "stone_maul": "stone_maul",
	"stone_spear": "stone_spear",
	"bandage": "bandage", "bandages": "bandage",
	"torch": "torch", "torches": "torch",
	"campfire": "campfire", "fire": "campfire", "camp_fire": "campfire",
	"waterskin": "waterskin", "skin": "waterskin", "water_skin": "waterskin",
}


## The bench stands WORKBENCH_XZ from the world's spawn point (Ashgrove's is the origin, so
## there it is exactly where it always was; on a generated kingdom it follows the spawn plot).
static func workbench_xz() -> Vector2:
	var sp := WorldGen.spawn_point()
	return Vector2(sp.x, sp.z) + WORKBENCH_XZ


static func workbench_pos() -> Vector3:
	var xz := workbench_xz()
	return Vector3(xz.x, Terrain.height(xz.x, xz.y), xz.y)


static func near_bench(pos: Vector3) -> bool:
	return Vector2(pos.x, pos.z).distance_to(workbench_xz()) <= BENCH_RANGE


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


## The tool you carry that makes crafting `id` pointless: `id` itself, or a better tool
## that upgrades it (a stone axe means you never need a wooden axe again). "" for none.
static func owned_tool(inv: Dictionary, id: String) -> String:
	if not makes_tool(id):
		return ""
	if Inventory.count(inv, id) > 0:
		return id
	for other in RECIPE_ORDER:
		if str(RECIPES[other].get("upgrades", "")) == id and Inventory.count(inv, other) > 0:
			return other
	return ""


## Why `id` can't be crafted from `inv` by a player at `pos`, or "" if it can.
## Reasons, in the order they are checked: "unknown", "owned" (a tool you already carry,
## or a better one), "bench" (needs the workbench, which is too far), "missing", "full" (no
## room for it).
static func check(inv: Dictionary, id: String, pos: Vector3) -> String:
	if not is_recipe(id):
		return "unknown"
	var r: Dictionary = RECIPES[id]
	if owned_tool(inv, id) != "":
		return "owned"
	if r.bench and not near_bench(pos):
		return "bench"
	if not missing(inv, id).is_empty():
		return "missing"
	if Inventory.count(inv, id) + int(r.makes) > Inventory.MAX_STACK:
		return "full"
	return ""


## "a" or "an" for a recipe's label.
static func article(id: String) -> String:
	var label := str(RECIPES.get(id, {}).get("label", id))
	return "an" if "aeiou".contains(label.left(1)) else "a"


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
			var have := owned_tool(inv, id)
			if have != "" and have != id:
				return "You already carry %s %s, which does a %s's work better." % [article(have), Inventory.label(have), label]
			return "You already carry %s %s; it never wears out." % [article(id), label]
		"bench":
			return "%s %s needs the workbench. %s" % [article(id).capitalize(), label, bench_hint(pos)]
		"missing":
			return "You need %s more to make %s %s." % [needs_text(missing(inv, id)), article(id), label]
		"full":
			return "No room in your pack for another %s." % label
	return "Craft what? %s" % recipes_text(inv)


## "You craft a stone axe. Wood comes faster with it in your pack."
static func success(id: String, made: int, inv: Dictionary) -> String:
	var r: Dictionary = RECIPES[id]
	if made > 1:
		return "You craft %d %ses (%d in your pack)." % [made, r.label, Inventory.count(inv, id)]
	match id:
		"wooden_axe":
			return "You craft a wooden axe. Ash and pine come quicker with it in your pack."
		"wooden_pickaxe":
			return "You craft a wooden pickaxe. Now you can break stone."
		"stone_axe":
			return "You lash a stone head onto your axe: a stone axe. Wood comes faster, and the old ashes open to you."
		"stone_pickaxe":
			return "You lash a stone head onto your pick: a stone pickaxe. Stone comes faster, and the rich seams open to you."
		"wooden_club":
			return "You craft a wooden club. You swing it now instead of your fists."
		"wooden_spear":
			return "You craft a wooden spear. Long reach: keep them at arm's length."
		"stone_maul":
			return "You weight your club with stone: a stone maul. Slow, wide and heavy."
		"stone_spear":
			return "You knap a stone point onto your spear: a stone spear."
		"bandage":
			return "You twist a bandage from plant fibre (%d in your pack). Press H to use one when you're hurt." % Inventory.count(inv, id)
	return "You craft %s %s (%d in your pack)." % [article(id), r.label, Inventory.count(inv, id)]


## "Recipes: stone axe (3 ash wood and 2 stone, at the workbench) ..." with a mark on the
## ones you can make from your pack right now (ignoring where you stand).
static func recipes_text(inv: Dictionary) -> String:
	var parts := PackedStringArray()
	for id in RECIPE_ORDER:
		var r: Dictionary = RECIPES[id]
		var where := ", at the workbench" if r.bench else ", anywhere"
		var ready := ""
		if owned_tool(inv, id) != "":
			ready = " (have it)"
		elif missing(inv, id).is_empty():
			ready = " (ready)"
		var what := str(r.label) if int(r.makes) == 1 else "%d %ses" % [int(r.makes), r.label]
		parts.append("%s: %s%s%s" % [what, needs_text(r.needs), where, ready])
	return "Recipes: %s." % "; ".join(parts)
