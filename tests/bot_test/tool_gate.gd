extends RefCounted
## Pure helpers for the tool-gate check (behaviour qa_tool_gate.gd, seed_veteran.gd and
## run_bot_test.py's gate phase), split out so tests/unit/test_qa_tool_gate.gd can drive
## them without a server.
##
## The check: tier-2 nodes (the old ashes and rich stone seams) refuse bare hands, and only
## that. There are no levels (owner direction, 2026-11-26); the gate is the tool (a stone one
## for tier 2). A fresh player walks to a tier-2 node and presses E: refused "tool", the "You
## need a stone axe to work this old ash." line, nothing paid, no charge used. A veteran carrying the right tool
## then works the same node until it is empty: every charge pays, so the refusal took none.
## Both reconnect: the veteran keeps its tool, the fresh one is still refused.
##
## The veteran also carries XP from the retired leveling system (VETERAN_OLD_XP), the way a
## character saved before 2026-11-26 does, and the save afterwards must still hold exactly that
## XP: hard rule 1, old player data is never lost, even data nothing reads any more.

## Metres the veteran is seeded short of its node, toward spawn, so it walks there like a
## player (the bot harness also wants every bot to walk at least 5 m).
const VETERAN_OFFSET := 10.0
## Old XP from the retired skills, as a character saved before their removal holds it.
const VETERAN_OLD_XP := {"felling": 1700, "quarrying": 1700, "toolcraft": 420}


## The tier-2 node the gate check uses: the one nearest `from` (spawn) that this client
## doesn't show empty (`empty`: node id -> true). -1 when there is none.
static func gate_node(empty: Dictionary, from: Vector3) -> int:
	var best := -1
	var best_d := INF
	for n in ResourceNodes.all():
		if int(n.get("tier", 1)) < 2 or not Gathering.needs_tool(n) or empty.has(int(n.id)):
			continue
		var d := Vector2(n.pos.x - from.x, n.pos.z - from.z).length()
		if d < best_d:
			best_d = d
			best = int(n.id)
	return best


## Where the veteran is seeded: VETERAN_OFFSET short of node `id`, toward `from`, on the ground.
static func veteran_spot(id: int, from: Vector3) -> Vector3:
	var n := ResourceNodes.get_by_id(id)
	var flat := Vector2(from.x - n.pos.x, from.z - n.pos.z)
	var dir := flat.normalized() if flat.length() > 0.01 else Vector2(1, 0)
	var x: float = n.pos.x + dir.x * VETERAN_OFFSET
	var z: float = n.pos.z + dir.y * VETERAN_OFFSET
	return Terrain.clamp_to_world(Vector3(x, Terrain.height(x, z), z))


## The veteran's pack: the plainest tool that opens node `id` (a stone axe for an old ash, a
## stone pickaxe for a rich seam), nothing else.
static func veteran_pack(id: int) -> Dictionary:
	var node := ResourceNodes.get_by_id(id)
	var tools: Array = Gathering.TOOLS.get(str(node.get("kind", "")), [])
	for i in range(tools.size() - 1, -1, -1):
		var pack := {str(tools[i]): 1}
		if Gathering.can_work(node, pack):
			return pack
	return {}


## What the fresh player's refusal must say for node `id` with bare hands.
static func refusal_text(id: int) -> String:
	return Gathering.tool_text(ResourceNodes.get_by_id(id))


## The charges a full tier-2 node has: the veteran must be paid exactly this many times
## before the node empties, or the refusal (or something else) took a charge.
static func charges(id: int) -> int:
	return Gathering.node_charges(ResourceNodes.get_by_id(id))


## Pure verdict on the veteran's run. "" when good, else what went wrong.
## `dones`: gathers that ended "done" before the node emptied; `emptied`: the node went empty
## on our last gather; `paid`: items of the node's item added to the pack across those gathers.
static func veteran_problem(id: int, dones: int, emptied: bool, paid: int) -> String:
	var want := charges(id)
	if not emptied:
		return "node %d never emptied after %d gathers (it has %d charges)" % [id, dones, want]
	if dones != want:
		return "node %d emptied after %d paid gathers, not its %d charges (did the refusal take one?)" % [id, dones, want]
	var each := Gathering.amount_at(id, veteran_pack(id))
	if paid != dones * each:
		return "%d gathers on node %d paid %d items, not %d each" % [dones, id, paid, each]
	return ""


## Pure: "" when `saved` (a character's stored old XP) still holds exactly `kept`, else what
## changed. Ids not in `kept` may be there too; nothing may be lost or altered.
static func old_xp_problem(kept: Dictionary, saved: Variant) -> String:
	var sk := RetiredSkills.normalize(saved)
	var off := PackedStringArray()
	for id in kept:
		if int(sk.get(str(id), -1)) != int(kept[id]):
			off.append("%s %d XP, wanted it kept at %d" % [id, int(sk.get(str(id), 0)), int(kept[id])])
	return "" if off.is_empty() else "old XP changed: " + ", ".join(off)
