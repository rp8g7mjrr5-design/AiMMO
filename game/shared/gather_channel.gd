class_name GatherChannel
## The timed gather: a player starts gathering a node, stands still for a moment while the
## server counts it down, and only then do the items land in the pack (design bible, "How
## gathering feels"). Pure functions over a small channel Dictionary, so the rules are unit
## tested without a running server; the server keeps one channel per player in its session.
##
## Protocol v3 wires this to c2s_gather_start / c2s_gather_cancel and the s2c_gather_* events
## (players' press-E). The instant "/gather" stays as a dev and bot command.
##
## Times (`now`) are real seconds on the server's monotonic clock, like Gathering.

## How long one gather takes, bare-handed (or, for stone, with the least pickaxe), per node
## kind. Rocks are a little slower, scrub a little quicker (fibre is pulled, not chopped). A
## tool (Gathering.tool_for) scales it by Gathering.tool_speed (wood 0.75, stone 0.5).
const SECONDS := {"ash": 2.0, "pine": 2.0, "stone": 2.4, "scrub": 1.6,
	# The starting beaches: quick pickings by hand, so the first minute is all payoff.
	"driftwood": 1.6, "beach_stones": 1.4, "kelp": 1.3, "wreck_crate": 1.8}
const DEFAULT_SECONDS := 2.0
## Moving further than this (flat metres) from where the gather started cancels it. Small
## enough that walking off always cancels, big enough that a server tick of drift doesn't.
const MOVE_TOLERANCE := 0.5


## Seconds a gather of `kind` takes with this pack (the best tool carried shortens it).
static func seconds_for(kind: String, inv: Dictionary) -> float:
	var base := float(SECONDS.get(kind, DEFAULT_SECONDS))
	return base * Gathering.tool_speed(Gathering.tool_for(kind, inv))


## seconds_for, for one node: a tier-2 node's bar is ResourceNodes.TIER2's seconds_scale
## longer.
static func seconds_at(id: int, inv: Dictionary) -> float:
	var node := ResourceNodes.get_by_id(id)
	var scale := float(ResourceNodes.info(node).get("seconds_scale", 1.0))
	return seconds_for(str(node.get("kind", "")), inv) * scale


## A new channel on node `id`, started at `now` from `pos`, lasting `seconds`.
static func start(id: int, pos: Vector3, now: float, seconds: float) -> Dictionary:
	return {"node_id": id, "from": pos, "started": now, "ends": now + seconds, "seconds": seconds}


static func is_active(ch: Dictionary) -> bool:
	return not ch.is_empty()


## Why the channel must stop now, from the player's current position: "moved" (walked more
## than MOVE_TOLERANCE from the start), "far" (out of reach of the node), or "" to go on.
static func cancel_reason(ch: Dictionary, pos: Vector3) -> String:
	if ch.is_empty():
		return ""
	var from: Vector3 = ch.from
	if Vector2(pos.x - from.x, pos.z - from.z).length() > MOVE_TOLERANCE:
		return "moved"
	if not ResourceNodes.in_range(int(ch.node_id), pos):
		return "far"
	return ""


## True once the countdown has run out.
static func is_due(ch: Dictionary, now: float) -> bool:
	return not ch.is_empty() and now >= float(ch.ends)


## 0..1, how far along the gather is (for the client's bar and for logs).
static func progress(ch: Dictionary, now: float) -> float:
	if ch.is_empty():
		return 0.0
	var secs := float(ch.seconds)
	if secs <= 0.0:
		return 1.0
	return clampf((now - float(ch.started)) / secs, 0.0, 1.0)


## Why a finished channel gives nothing after all, re-checked at the end because another
## player may have emptied the node, or dawn dried the seep, meanwhile. The cooldown was
## checked when the channel started, so it is not checked again. "" means take it.
## `inv` is the player's pack (it only matters for tool-gated tier-2 nodes).
static func finish_check(state: Dictionary, ch: Dictionary, pos: Vector3, now: float, world_seconds: float, inv: Dictionary = {}) -> String:
	return Gathering.check(state, int(ch.node_id), pos, now, world_seconds, -INF, Gathering.COOLDOWN, inv)


## "You start gathering the pine (2.0 s)."
static func begin_text(id: int, seconds: float) -> String:
	var node := ResourceNodes.get_by_id(id)
	var label := str(ResourceNodes.info(node).get("label", "node")).to_lower() if not node.is_empty() else "node"
	return "You start gathering the %s (%.1f s)." % [label, seconds]


## "You stop gathering: you moved." for reasons from cancel_reason, plus "stopped" (the
## player asked) and "replaced".
static func cancel_text(reason: String) -> String:
	match reason:
		"moved":
			return "You stop gathering: you moved."
		"far":
			return "You stop gathering: it is out of reach."
	return "You stop gathering."
