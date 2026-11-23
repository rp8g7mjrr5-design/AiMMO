extends RefCounted
## Pure helpers for the level-gate check (behaviour qa_level_gate.gd, seed_veteran.gd and
## run_bot_test.py's gate phase), split out so tests/unit/test_qa_level_gate.gd can drive
## them without a server.
##
## The check (roadmap Milestone 1, "tier-2 nodes refuse a too-low level"): a fresh player
## walks to a tier-2 node and presses E: refused "level", the "Needs <Skill> N. You're
## <Skill> 1." line, nothing paid, no charge used. A veteran (seeded at exactly the level)
## then works the same node until it is empty: every charge pays, so the refusal took none.
## Both reconnect: the veteran keeps its level and XP, the fresh one is still refused.

## Metres the veteran is seeded short of its node, toward spawn, so it walks there like a
## player (the bot harness also wants every bot to walk at least 5 m).
const VETERAN_OFFSET := 10.0


## The tier-2 node the gate check uses: the one nearest `from` (spawn) that this client
## doesn't show empty (`empty`: node id -> true). -1 when there is none.
static func gate_node(empty: Dictionary, from: Vector3) -> int:
	var best := -1
	var best_d := INF
	for n in ResourceNodes.all():
		if Gathering.required_level(n) <= 1 or empty.has(int(n.id)):
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


## The veteran's skills: exactly the level node `id` needs in its skill (the first XP of that
## level, so "exactly at the gate" is what is tested), nothing else.
static func veteran_skills(id: int) -> Dictionary:
	var n := ResourceNodes.get_by_id(id)
	return {str(n.skill): Skills.xp_for_level(Gathering.required_level(n))}


## What the fresh player's refusal must say for node `id` at level 1 everywhere.
static func refusal_text(id: int) -> String:
	return Gathering.level_text(ResourceNodes.get_by_id(id), {})


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
	var each := int(ResourceNodes.info(ResourceNodes.get_by_id(id)).get("amount", 1))
	if paid < dones * each:
		return "%d gathers on node %d paid only %d items (at least %d each)" % [dones, id, paid, each]
	return ""
