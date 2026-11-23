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
