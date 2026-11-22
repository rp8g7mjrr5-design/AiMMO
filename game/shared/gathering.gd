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


## {taken: {node_id: gathers so far}, respawn_at: {node_id: time it comes back}}
static func new_state() -> Dictionary:
	return {"taken": {}, "respawn_at": {}}


static func charges(kind: String) -> int:
	return int(CHARGES.get(kind, DEFAULT_CHARGES))


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
	return maxi(0, charges(node.kind) - int(state.taken.get(id, 0)))


## Why `id` can't be gathered by a player at `player_pos` right now, or "" if it can.
## Reasons: "unknown", "far", "depleted", "day" (night-only node in daylight), "cooldown".
static func check(state: Dictionary, id: int, player_pos: Vector3, now: float, world_seconds: float, last_gather: float) -> String:
	var node := ResourceNodes.get_by_id(id)
	if node.is_empty():
		return "unknown"
	if not ResourceNodes.in_range(id, player_pos):
		return "far"
	if is_depleted(state, id, now):
		return "depleted"
	if ResourceNodes.kind_info(node.kind).get("night_only", false) and not WorldClock.is_night(world_seconds):
		return "day"
	if now - last_gather < COOLDOWN:
		return "cooldown"
	return ""


## Which node "/gather" (optionally "/gather <kind>") means: the nearest node in reach that
## can be gathered now, else the nearest in reach at all (so the refusal names it), else -1.
static func pick_target(state: Dictionary, player_pos: Vector3, now: float, world_seconds: float, kind: String = "") -> int:
	var in_reach := ResourceNodes.near(player_pos, ResourceNodes.GATHER_RANGE, kind)
	for n in in_reach:
		if check(state, n.id, player_pos, now, world_seconds, -INF) == "":
			return n.id
	return in_reach[0].id if not in_reach.is_empty() else -1


## Uses one charge of node `id`. Call only after check() returned "". Returns
## {item, qty, depleted: bool, respawn: seconds}. The caller puts the items in the pack.
static func take(state: Dictionary, id: int, now: float) -> Dictionary:
	var node := ResourceNodes.get_by_id(id)
	var info := ResourceNodes.kind_info(node.kind)
	var used := int(state.taken.get(id, 0)) + 1
	state.taken[id] = used
	var depleted := used >= charges(node.kind)
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


## "north-east" for a flat offset (north is -Z, east is +X, as on the client's compass).
static func direction_name(offset: Vector3) -> String:
	if Vector2(offset.x, offset.z).length() < 0.5:
		return "right here"
	var deg := fposmod(rad_to_deg(atan2(offset.x, -offset.z)), 360.0)
	var names := ["north", "north-east", "east", "south-east", "south", "south-west", "west", "north-west"]
	return names[int(floor((deg + 22.5) / 45.0)) % 8]


## "The nearest pine is 14 m to the north-east." Skips depleted nodes and, in daylight,
## night-only ones. Pass kind to look for one kind only.
static func hint(state: Dictionary, player_pos: Vector3, now: float, world_seconds: float, kind: String = "") -> String:
	for n in ResourceNodes.near(player_pos, HINT_RADIUS, kind):
		if is_depleted(state, n.id, now):
			continue
		var info := ResourceNodes.kind_info(n.kind)
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
## or "full" when the pack has no room).
static func refusal(reason: String, state: Dictionary, id: int, player_pos: Vector3, now: float, world_seconds: float, kind: String = "") -> String:
	var node := ResourceNodes.get_by_id(id)
	var label := str(ResourceNodes.kind_info(node.kind).get("label", "node")).to_lower() if not node.is_empty() else "node"
	match reason:
		"depleted":
			var mins := maxi(1, ceili((float(state.respawn_at.get(id, now)) - now) / 60.0))
			return "This %s is spent; it comes back in about %d minute%s. %s" % [
				label, mins, "" if mins == 1 else "s", hint(state, player_pos, now, world_seconds, kind)]
		"day":
			return "The %s is dry by daylight. Ember sap only seeps at night." % label
		"cooldown":
			return "Easy; you're still gathering."
		"full":
			var item := str(ResourceNodes.kind_info(node.kind).get("item", ""))
			return "Your pack can't hold any more %s." % Inventory.label(item).to_lower()
	return "Nothing to gather within reach. %s" % hint(state, player_pos, now, world_seconds, kind)


## "You gather 2 ash wood from the ember ash (6 in your pack). It is spent for now."
static func success(id: int, got: int, in_pack: int, depleted: bool) -> String:
	var node := ResourceNodes.get_by_id(id)
	var info := ResourceNodes.kind_info(node.kind)
	var line := "You gather %d %s from the %s (%d in your pack)." % [
		got, Inventory.label(str(info.item)).to_lower(), str(info.label).to_lower(), in_pack]
	if depleted:
		line += " It is spent for now."
	return line
