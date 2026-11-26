class_name Gathering
## Gathering from resource nodes (ResourceNodes): the rules, as pure functions over a small
## state Dictionary, so they are unit tested without a running server.
##
## The server keeps one state for the whole world (made by new_state()) and one
## "last gather" time per player. A node gives ResourceNodes.KINDS[kind].amount items per
## gather, can be gathered CHARGES[kind] times, then is depleted until its respawn timer
## (KINDS[kind].respawn real seconds) runs out. Ember-sap seeps only give at night.
##
## State lives in server memory only: every node comes back on a restart, which is fine for
## things that respawn anyway, and keeps player tables free of world state.
##
## Times (`now`) are real seconds on one monotonic clock (the server uses ticks_msec / 1000).

const COOLDOWN := 1.5 ## real seconds between two gathers by the same player
## Gathers a node gives before it is depleted. Wood and stone are shared by everyone at
## Spawn Meadow, so they last a few gathers; a seep gives once and is gone for a while.
const CHARGES := {"ash": 3, "pine": 3, "stone": 3, "ember_sap": 1}
const DEFAULT_CHARGES := 1
const HINT_RADIUS := 80.0 ## how far "the nearest pine is 14 m north-east" looks
## Tools (see Crafting): carrying the right one gives more per gather (tool_extra) and
## shortens both the gather bar (GatherChannel) and the cooldown by tool_speed. Each kind
## lists its tools best first; the best one you carry is the one used. A stone tool gives
## TOOL_EXTRA more and runs at TOOL_SPEED; the ember-hardened tools give
## EMBER_EXTRA more and run at EMBER_SPEED, so the bar is visibly shorter on the very next
## gather. Seeps take no tool: sap is collected by hand.
const TOOLS := {
	"ash": ["ember_axe", "stone_axe"],
	"pine": ["ember_axe", "stone_axe"],
	"stone": ["ember_pickaxe", "stone_pickaxe"],
}
const TOOL_EXTRA := 1
const TOOL_SPEED := 0.5
const EMBER_EXTRA := 2
const EMBER_SPEED := 0.35
const TOOL_POWER := {
	"stone_axe": {"speed": TOOL_SPEED, "extra": TOOL_EXTRA},
	"stone_pickaxe": {"speed": TOOL_SPEED, "extra": TOOL_EXTRA},
	"ember_axe": {"speed": EMBER_SPEED, "extra": EMBER_EXTRA},
	"ember_pickaxe": {"speed": EMBER_SPEED, "extra": EMBER_EXTRA},
}


## {taken: {node_id: gathers so far}, respawn_at: {node_id: time it comes back}}
static func new_state() -> Dictionary:
	return {"taken": {}, "respawn_at": {}}


static func charges(kind: String) -> int:
	return int(CHARGES.get(kind, DEFAULT_CHARGES))


## Gathers node `node` gives before it is depleted (a tier-2 node has its own number).
static func node_charges(node: Dictionary) -> int:
	return int(ResourceNodes.info(node).get("charges", charges(str(node.get("kind", "")))))


## True when working `node` takes a tool (a tier-2 node: ResourceNodes.TIER2 `needs_tool`).
static func needs_tool(node: Dictionary) -> bool:
	return bool(ResourceNodes.info(node).get("needs_tool", false))


## True if a player carrying `inv` may work `node`: anyone for a tier-1 node, and for a
## tool-gated one only with one of TOOLS[kind] in the pack.
static func can_work(node: Dictionary, inv: Dictionary) -> bool:
	return not needs_tool(node) or tool_for(str(node.get("kind", "")), inv) != ""


## Brings back every node whose respawn time has passed. Returns the ids that came back
## (protocol v3's s2c_nodes will tell clients about them).
static func respawn_due(state: Dictionary, now: float) -> Array:
	var back: Array = []
	for id in state.respawn_at.keys():
		if now >= float(state.respawn_at[id]):
			back.append(id)
	for id in back:
		state.respawn_at.erase(id)
		state.taken.erase(id)
	return back


static func is_depleted(state: Dictionary, id: int, now: float) -> bool:
	return state.respawn_at.has(id) and now < float(state.respawn_at[id])


## Ids of every node depleted right now.
static func depleted_ids(state: Dictionary, now: float) -> Array:
	var out: Array = []
	for id in state.respawn_at:
		if now < float(state.respawn_at[id]):
			out.append(id)
	out.sort()
	return out


## Gathers left on a node before it is depleted (0 while depleted).
static func charges_left(state: Dictionary, id: int, now: float) -> int:
	var node := ResourceNodes.get_by_id(id)
	if node.is_empty() or is_depleted(state, id, now):
		return 0
	return maxi(0, node_charges(node) - int(state.taken.get(id, 0)))


## Why `id` can't be gathered by a player at `player_pos` right now, or "" if it can.
## Reasons: "unknown", "tool" (a tier-2 node and no axe or pickaxe for it in the pack),
## "far", "depleted", "day" (night-only node in daylight), "cooldown".
## `cooldown` is the player's own (see cooldown_for); it defaults to the bare-handed one.
## `inv` is the player's pack; left out it means bare hands.
## "tool" comes before "far": the requirement doesn't depend on where you stand, so the
## answer to "can I work that old ash?" is the same from across the meadow.
static func check(state: Dictionary, id: int, player_pos: Vector3, now: float, world_seconds: float, last_gather: float, cooldown: float = COOLDOWN, inv: Dictionary = {}) -> String:
	var node := ResourceNodes.get_by_id(id)
	if node.is_empty():
		return "unknown"
	if not can_work(node, inv):
		return "tool"
	if not ResourceNodes.in_range(id, player_pos):
		return "far"
	if is_depleted(state, id, now):
		return "depleted"
	if ResourceNodes.info(node).get("night_only", false) and not WorldClock.is_night(world_seconds):
		return "day"
	if now - last_gather < cooldown:
		return "cooldown"
	return ""


## Which node "/gather" (optionally "/gather <kind>") means: the nearest node in reach that
## can be gathered now, else the nearest in reach at all (so the refusal names it), else -1.
static func pick_target(state: Dictionary, player_pos: Vector3, now: float, world_seconds: float, kind: String = "", inv: Dictionary = {}) -> int:
	var in_reach := ResourceNodes.near(player_pos, ResourceNodes.GATHER_RANGE, kind)
	for n in in_reach:
		if check(state, n.id, player_pos, now, world_seconds, -INF, COOLDOWN, inv) == "":
			return n.id
	return in_reach[0].id if not in_reach.is_empty() else -1


## Uses one charge of node `id`. Call only after check() returned "". Returns
## {item, qty, depleted: bool, respawn: seconds}. The caller puts the items in the pack.
static func take(state: Dictionary, id: int, now: float) -> Dictionary:
	var node := ResourceNodes.get_by_id(id)
	var info := ResourceNodes.info(node)
	var used := int(state.taken.get(id, 0)) + 1
	state.taken[id] = used
	var depleted := used >= node_charges(node)
	if depleted:
		state.respawn_at[id] = now + float(info.respawn)
	return {"item": str(info.item), "qty": int(info.amount), "depleted": depleted, "respawn": float(info.respawn)}


## Undoes take() when the pack could not hold anything, so a full pack never wastes a node.
static func give_back(state: Dictionary, id: int) -> void:
	var used := int(state.taken.get(id, 0)) - 1
	state.respawn_at.erase(id)
	if used <= 0:
		state.taken.erase(id)
	else:
		state.taken[id] = used


## The tool in `inv` that helps with a node of `kind` (the best one carried), or "" if none
## does / none is carried.
static func tool_for(kind: String, inv: Dictionary) -> String:
	for tool in TOOLS.get(kind, []):
		if Inventory.count(inv, str(tool)) > 0:
			return str(tool)
	return ""


## How much a tool shortens the bar and cooldown (multiply by this); 1.0 for no tool.
static func tool_speed(tool: String) -> float:
	return float(TOOL_POWER.get(tool, {}).get("speed", 1.0))


## Extra items per gather a tool gives; 0 for no tool.
static func tool_extra(tool: String) -> int:
	return int(TOOL_POWER.get(tool, {}).get("extra", 0))


## The cooldown after gathering a node of `kind` with this pack.
static func cooldown_for(kind: String, inv: Dictionary) -> float:
	return COOLDOWN * tool_speed(tool_for(kind, inv))


## How many items one gather of `kind` gives with this pack (the kind's amount plus what the
## best tool carried adds).
static func amount_for(kind: String, inv: Dictionary) -> int:
	return int(ResourceNodes.kind_info(kind).get("amount", 1)) + tool_extra(tool_for(kind, inv))


## amount_for, for one node (a tier-2 node has its own base amount).
static func amount_at(id: int, inv: Dictionary) -> int:
	var node := ResourceNodes.get_by_id(id)
	var kind := str(node.get("kind", ""))
	return int(ResourceNodes.info(node).get("amount", 1)) + tool_extra(tool_for(kind, inv))


## "north-east" for a flat offset (north is -Z, east is +X, as on the client's compass).
static func direction_name(offset: Vector3) -> String:
	if Vector2(offset.x, offset.z).length() < 0.5:
		return "right here"
	var deg := fposmod(rad_to_deg(atan2(offset.x, -offset.z)), 360.0)
	var names := ["north", "north-east", "east", "south-east", "south", "south-west", "west", "north-west"]
	return names[int(floor((deg + 22.5) / 45.0)) % 8]


## "The nearest pine is 14 m to the north-east." Skips depleted nodes and, in daylight,
## night-only ones. Pass kind to look for one kind only.
## Skips nodes the pack has no tool for too (`inv` as in check()).
static func hint(state: Dictionary, player_pos: Vector3, now: float, world_seconds: float, kind: String = "", inv: Dictionary = {}) -> String:
	for n in ResourceNodes.near(player_pos, HINT_RADIUS, kind):
		if is_depleted(state, n.id, now) or not can_work(n, inv):
			continue
		var info := ResourceNodes.info(n)
		if info.get("night_only", false) and not WorldClock.is_night(world_seconds):
			continue
		var off: Vector3 = n.pos - player_pos
		var dist := roundi(Vector2(off.x, off.z).length())
		return "The nearest %s is %d m to the %s." % [str(info.label).to_lower(), dist, direction_name(off)]
	return "Nothing to gather nearby; try another part of Ashgrove."


## Turns a "/gather" argument into a node kind: "" for any, or a key of ResourceNodes.KINDS,
## or null for something unknown. Accepts kind ids, item ids and plain words.
static func parse_kind(word: String) -> Variant:
	var w := word.strip_edges().to_lower().replace("-", "_").replace(" ", "_")
	if w == "":
		return ""
	const WORDS := {
		"ash": "ash", "ash_wood": "ash", "ember_ash": "ash", "pine": "pine", "pine_wood": "pine",
		"stone": "stone", "rock": "stone", "outcrop": "stone",
		"sap": "ember_sap", "ember_sap": "ember_sap", "seep": "ember_sap", "ember": "ember_sap",
	}
	return WORDS.get(w, null)


## The reply for a refused gather (reason from check(), or "none" when nothing is in reach,
## or "full" when the pack has no room). `inv` as in check().
static func refusal(reason: String, state: Dictionary, id: int, player_pos: Vector3, now: float, world_seconds: float, kind: String = "", inv: Dictionary = {}) -> String:
	var node := ResourceNodes.get_by_id(id)
	var label := str(ResourceNodes.info(node).get("label", "node")).to_lower() if not node.is_empty() else "node"
	match reason:
		"tool":
			return tool_text(node)
		"depleted":
			var mins := maxi(1, ceili((float(state.respawn_at.get(id, now)) - now) / 60.0))
			return "This %s is spent; it comes back in about %d minute%s. %s" % [
				label, mins, "" if mins == 1 else "s", hint(state, player_pos, now, world_seconds, kind, inv)]
		"day":
			return "The %s is dry by daylight. Ember sap only seeps at night." % label
		"cooldown":
			return "Easy; you're still gathering."
		"full":
			var item := str(ResourceNodes.info(node).get("item", ""))
			return "Your pack can't hold any more %s." % Inventory.label(item).to_lower()
	return "Nothing to gather within reach. %s" % hint(state, player_pos, now, world_seconds, kind, inv)


## "You need an axe to work this old ember ash." for a tool-gated node and bare hands.
static func tool_text(node: Dictionary) -> String:
	var label := str(ResourceNodes.info(node).get("label", "node")).to_lower()
	return "You need %s to work this %s." % [tool_word(str(node.get("kind", ""))), label]


## "an axe" or "a pickaxe": what a tool-gated node of `kind` takes.
static func tool_word(kind: String) -> String:
	return "a pickaxe" if kind == "stone" else "an axe"


## "Your pack can't hold any more ash wood, so you leave it." for a timed gather that
## finished with a full stack: no items.
static func full_text(id: int, depleted: bool = false) -> String:
	var item := str(ResourceNodes.info(ResourceNodes.get_by_id(id)).get("item", ""))
	var line := "Your pack can't hold any more %s, so you leave it." % Inventory.label(item).to_lower()
	if depleted:
		line += " It is spent for now."
	return line


## "You gather 2 ash wood from the ember ash (6 in your pack). It is spent for now."
## Pass the tool's item id (from tool_for) to say it was used.
static func success(id: int, got: int, in_pack: int, depleted: bool, tool: String = "") -> String:
	var node := ResourceNodes.get_by_id(id)
	var info := ResourceNodes.info(node)
	var with := " with your %s" % Inventory.label(tool) if tool != "" else ""
	var line := "You gather %d %s from the %s%s (%d in your pack)." % [
		got, Inventory.label(str(info.item)).to_lower(), str(info.label).to_lower(), with, in_pack]
	if depleted:
		line += " It is spent for now."
	return line
