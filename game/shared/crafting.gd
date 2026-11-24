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
## workbench (a torch can be twisted together anywhere). `level`: [skill, level] needed to
## make it (Skills, Toolcraft unlocks). `upgrades`: the tool this one replaces; it is used up
## by the recipe, and once you carry the better tool the old one counts as owned too.
## `xp_scale`: multiplies the Toolcraft XP a craft pays (Skills.craft_xp); 1.0 when absent.
const RECIPES := {
	"stone_axe": {"label": "stone axe", "needs": {"ash_wood": 3, "stone": 2}, "makes": 1, "bench": true, "tool": true},
	"stone_pickaxe": {"label": "stone pickaxe", "needs": {"pine_wood": 3, "stone": 3}, "makes": 1, "bench": true, "tool": true},
	"torch": {"label": "torch", "needs": {"pine_wood": 1, "ember_sap": 1}, "makes": 3, "bench": false, "tool": false},
	"campfire": {"label": "campfire", "needs": {"ash_wood": 2, "pine_wood": 2, "stone": 4}, "makes": 1, "bench": true, "tool": false},
	"ember_axe": {"label": "ember axe", "needs": {"ember_sap": 1, "ember_heartwood": 4, "stone_axe": 1}, "makes": 1, "bench": true, "tool": true,
		"level": ["toolcraft", 5], "upgrades": "stone_axe"},
	"ember_pickaxe": {"label": "ember pickaxe", "needs": {"ember_sap": 1, "veinstone": 4, "stone_pickaxe": 1}, "makes": 1, "bench": true, "tool": true,
		"level": ["toolcraft", 5], "upgrades": "stone_pickaxe"},
	"ember_lantern": {"label": "ember lantern", "needs": {"ash_wood": 3, "pine_wood": 3, "stone": 2, "ember_sap": 1}, "makes": 1, "bench": true, "tool": false,
		"level": ["toolcraft", 3], "xp_scale": 1.5},
}
const RECIPE_ORDER := ["stone_axe", "stone_pickaxe", "torch", "campfire", "ember_lantern", "ember_axe", "ember_pickaxe"]

## Plain words players type, to recipe ids.
const WORDS := {
	"axe": "stone_axe", "stone_axe": "stone_axe", "hatchet": "stone_axe",
	"pickaxe": "stone_pickaxe", "pick": "stone_pickaxe", "stone_pickaxe": "stone_pickaxe", "stone_pick": "stone_pickaxe",
	"torch": "torch", "torches": "torch",
	"campfire": "campfire", "fire": "campfire", "camp_fire": "campfire",
	"ember_axe": "ember_axe", "ember_hatchet": "ember_axe",
	"ember_pickaxe": "ember_pickaxe", "ember_pick": "ember_pickaxe",
	"lantern": "ember_lantern", "ember_lantern": "ember_lantern", "lanterns": "ember_lantern",
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


## [skill, level] needed to make `id`, or [] when anyone can.
static func required(id: String) -> Array:
	return RECIPES.get(id, {}).get("level", [])


## True when `skills` (skill id -> XP) is high enough to make `id`.
static func level_ok(id: String, skills: Dictionary) -> bool:
	var need := required(id)
	return need.is_empty() or Skills.level_of(skills, str(need[0])) >= int(need[1])


## The tool you carry that makes crafting `id` pointless: `id` itself, or a better tool
## that upgrades it (an ember axe means you never need a stone axe again). "" for none.
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
## Reasons, in the order they are checked: "unknown", "level" (a Toolcraft level you don't
## have yet; only checked when `skills` is given, so the server always passes them),
## "owned" (a tool you already carry, or a better one), "bench" (needs the workbench, which
## is too far), "missing", "full" (no room for it).
static func check(inv: Dictionary, id: String, pos: Vector3, skills: Variant = null) -> String:
	if not is_recipe(id):
		return "unknown"
	var r: Dictionary = RECIPES[id]
	if skills is Dictionary and not level_ok(id, skills):
		return "level"
	if owned_tool(inv, id) != "":
		return "owned"
	if r.bench and not near_bench(pos):
		return "bench"
	if not missing(inv, id).is_empty():
		return "missing"
	if Inventory.count(inv, id) + int(r.makes) > Inventory.MAX_STACK:
		return "full"
	return ""


## "An ember axe needs Toolcraft 5. You're Toolcraft 3."
static func level_text(id: String, skills: Dictionary) -> String:
	var need := required(id)
	if need.is_empty():
		return ""
	var skill := str(need[0])
	return "%s %s needs %s %d. You're %s %d." % [article(id).capitalize(), str(RECIPES[id].label),
		Skills.label(skill), int(need[1]), Skills.label(skill), Skills.level_of(skills, skill)]


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


## The reply for a refused craft (reason from check(); pass the player's skills for "level").
static func refusal(reason: String, inv: Dictionary, id: String, pos: Vector3, skills: Dictionary = {}) -> String:
	var label := str(RECIPES.get(id, {}).get("label", id))
	match reason:
		"level":
			return level_text(id, skills)
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
		"stone_axe":
			return "You craft a stone axe. Ash and pine give more, and faster, with it in your pack."
		"stone_pickaxe":
			return "You craft a stone pickaxe. Stone gives more, and faster, with it in your pack."
		"ember_axe":
			return "You harden your axe in ember sap: an ember axe! Every chop is quicker and gives more."
		"ember_pickaxe":
			return "You harden your pickaxe in ember sap: an ember pickaxe! Every strike is quicker and gives more."
	return "You craft %s %s (%d in your pack)." % [article(id), r.label, Inventory.count(inv, id)]


## "Recipes: stone axe (3 ash wood and 2 stone, at the workbench) ..." with a mark on the
## ones you can make from your pack right now (ignoring where you stand and your level),
## and the Toolcraft level the later ones need.
static func recipes_text(inv: Dictionary) -> String:
	var parts := PackedStringArray()
	for id in RECIPE_ORDER:
		var r: Dictionary = RECIPES[id]
		var where := ", at the workbench" if r.bench else ", anywhere"
		var need := required(id)
		if not need.is_empty():
			where += ", %s %d" % [Skills.label(str(need[0])), int(need[1])]
		var ready := ""
		if owned_tool(inv, id) != "":
			ready = " (have it)"
		elif missing(inv, id).is_empty():
			ready = " (ready)"
		var what := str(r.label) if int(r.makes) == 1 else "%d %ses" % [int(r.makes), r.label]
		parts.append("%s: %s%s%s" % [what, needs_text(r.needs), where, ready])
	return "Recipes: %s." % "; ".join(parts)
