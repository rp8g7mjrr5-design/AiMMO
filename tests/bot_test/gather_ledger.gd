extends RefCounted
## Pure checks for qa_gather_ledger.gd, split out so tests/unit/test_qa_gather_ledger.gd can
## drive them without a server.


## Items whose count differs between two packs: item -> after - before (zeros left out).
static func pack_diff(before: Dictionary, after: Dictionary) -> Dictionary:
	var out := {}
	for k in before:
		var d := int(after.get(k, 0)) - int(before[k])
		if d != 0:
			out[k] = d
	for k in after:
		if not before.has(k) and int(after[k]) != 0:
			out[k] = int(after[k])
	return out


## Why the pack after a reconnect may not be the pack before it. "" when they match.
## "in_flight" when the only difference is one item going up by at most `amount` and a gather
## of ours (on node `running_node`) was still running at the hang-up: it finished in the last
## moments and its s2c_inventory was lost with the connection, which the server's save is
## right about. Anything else is a description of the mismatch.
static func reconnect_problem(before: Dictionary, after: Dictionary, running_node: int, amount: int) -> String:
	var d := pack_diff(before, after)
	if d.is_empty():
		return ""
	if running_node >= 0 and d.size() == 1:
		var item: String = d.keys()[0]
		if int(d[item]) > 0 and int(d[item]) <= amount:
			return "in_flight"
	var parts := PackedStringArray()
	var keys := d.keys()
	keys.sort()
	for k in keys:
		parts.append("%s %+d" % [k, int(d[k])])
	return ", ".join(parts)


## How many peers in `channels` (peer -> node id) are gathering `node_id` right now.
static func gatherers_on(channels: Dictionary, node_id: int) -> int:
	var n := 0
	for peer in channels:
		if int(channels[peer]) == node_id:
			n += 1
	return n


## The pair check (qa_gather_ledger's `--gather-pair=lead`): the node two players gather
## together. The live node nearest `from` (spawn) that is not in `empty` (node id -> true, as
## this client sees it) or `avoid`, never a night-only one (a seep gives nothing by day).
## -1 when there is none.
static func pair_node(empty: Dictionary, avoid: Array, from: Vector3) -> int:
	var best := -1
	var best_d := INF
	for n in ResourceNodes.all():
		var id := int(n.id)
		if empty.has(id) or avoid.has(id):
			continue
		if bool(ResourceNodes.kind_info(str(n.kind)).get("night_only", false)):
			continue
		# Pair bots are fresh, bare-handed characters: a tier-2 node would refuse them ("tool").
		if Gathering.needs_tool(n):
			continue
		var d := Vector2(n.pos.x - from.x, n.pos.z - from.z).length()
		if d < best_d:
			best_d = d
			best = id
	return best


## The node a player standing at `pos` is waiting at: the nearest node centre within `reach`
## flat metres, or -1. The follower uses it to see where its leader stopped.
static func node_at(pos: Vector3, reach: float) -> int:
	var near := ResourceNodes.near(pos, reach)
	return int(near[0].id) if not near.is_empty() else -1


## The group check's ledger (qa_gather_ledger pair mode with `--pair-size=3`): what one client
## saw happen on the shared node, in arrival order. Each entry is ["empty"] (s2c_node_state
## said the node is now empty) or ["end", peer, reason] (s2c_gather_end). The server sends a
## node's s2c_node_state right before the s2c_gather_end of the gather that took its last
## charge, and both go out on the same reliable channel, so every client sees one order.
## Returns "" when the node's charges were shared fairly, else what went wrong:
##   - nobody is told "depleted" before the node was announced empty (turned away while a
##     charge was left);
##   - after "empty", only the gather that emptied it may still be paid, and its "done" comes
##     straight after the announcement (anyone else paid then got a charge that didn't exist).
static func share_problem(log: Array) -> String:
	var seen_empty := false
	var prev := ""
	var paid_after := 0
	for e in log:
		var what := str(e[0])
		if what == "empty":
			seen_empty = true
		elif what == "end":
			var reason := str(e[2])
			if reason == "depleted" and not seen_empty:
				return "peer %d was told 'depleted' before the node was announced empty" % int(e[1])
			if reason == "done" and seen_empty:
				paid_after += 1
				if prev != "empty" or paid_after > 1:
					return "peer %d was paid after the node was already empty" % int(e[1])
		prev = what
	return ""


## Ends of gathers on the shared node in `log` (see share_problem), as reason -> count.
static func share_ends(log: Array) -> Dictionary:
	var out := {}
	for e in log:
		if str(e[0]) == "end":
			out[str(e[2])] = int(out.get(str(e[2]), 0)) + 1
	return out


## The press after the group's gathers: an emptied node must turn it away ("depleted"); a node
## with a charge left must let it begin ("began"). "" when `result` matches what this client
## saw, else why not.
static func after_press_problem(seen_empty: bool, result: String) -> String:
	var want := "depleted" if seen_empty else "began"
	if result == want:
		return ""
	return "the press after the shared gathers got '%s', expected '%s' (node %s)" % [result, want, "empty" if seen_empty else "not empty"]


## Whether the shared node was announced empty in `log` (see share_problem).
static func share_emptied(log: Array) -> bool:
	for e in log:
		if str(e[0]) == "empty":
			return true
	return false
