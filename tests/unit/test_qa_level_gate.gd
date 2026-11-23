extends TestCase
## The bot test's level-gate check (tests/bot_test/level_gate.gd, behaviour qa_level_gate):
## which node it uses, where and how the veteran is seeded, and the veteran's verdict.

const LevelGate := preload("res://tests/bot_test/level_gate.gd")


func test_gate_node_is_the_nearest_level_gated_node() -> void:
	var id := LevelGate.gate_node({}, GameConfig.SPAWN_POINT)
	check(id >= 0, "the world has a tier-2 node")
	var node := ResourceNodes.get_by_id(id)
	check(Gathering.required_level(node) > 1, "the gate node needs a level")
	var d := Vector2(node.pos.x - GameConfig.SPAWN_POINT.x, node.pos.z - GameConfig.SPAWN_POINT.z).length()
	for n in ResourceNodes.all():
		if Gathering.required_level(n) > 1:
			check(Vector2(n.pos.x - GameConfig.SPAWN_POINT.x, n.pos.z - GameConfig.SPAWN_POINT.z).length() >= d - 0.001,
				"node %d is nearer spawn than the gate node %d" % [n.id, id])
	var other := LevelGate.gate_node({id: true}, GameConfig.SPAWN_POINT)
	check(other >= 0 and other != id, "an empty gate node is skipped")
	check(Gathering.required_level(ResourceNodes.get_by_id(other)) > 1, "the next one is gated too")


func test_veteran_is_seeded_out_of_reach_on_the_ground() -> void:
	var id := LevelGate.gate_node({}, GameConfig.SPAWN_POINT)
	var spot := LevelGate.veteran_spot(id, GameConfig.SPAWN_POINT)
	var node := ResourceNodes.get_by_id(id)
	var flat := Vector2(spot.x - node.pos.x, spot.z - node.pos.z).length()
	check(absf(flat - LevelGate.VETERAN_OFFSET) < 0.01, "%.2f m from the node" % flat)
	check(not ResourceNodes.in_range(id, spot), "starts out of reach, so it walks there")
	check(flat > 5.0, "walks more than the 5 m every bot must")
	check(absf(spot.y - Terrain.height(spot.x, spot.z)) < 0.001, "on the ground")
	check(Vector2(spot.x, spot.z).length() < Vector2(node.pos.x, node.pos.z).length(), "on the spawn side")


func test_veteran_has_exactly_the_level_and_the_fresh_player_none() -> void:
	var id := LevelGate.gate_node({}, GameConfig.SPAWN_POINT)
	var node := ResourceNodes.get_by_id(id)
	var sk := LevelGate.veteran_skills(id)
	check_eq(sk.size(), 1, "only the node's skill")
	check_eq(Skills.level_of(sk, str(node.skill)), Gathering.required_level(node))
	check(Gathering.can_work(node, sk), "the veteran can work it")
	var one_short := {str(node.skill): int(sk[str(node.skill)]) - 1}
	check(not Gathering.can_work(node, one_short), "one XP short of the level is refused")
	check(not Gathering.can_work(node, {}), "a fresh player is refused")
	check_eq(Gathering.check(Gathering.new_state(), id, node.pos, 0.0, 0.0, -1000.0, Gathering.COOLDOWN, {}), "level")
	check_eq(LevelGate.refusal_text(id), "Needs %s %d. You're %s 1." % [
		Skills.label(str(node.skill)), Gathering.required_level(node), Skills.label(str(node.skill))])


func test_veteran_verdict() -> void:
	var id := LevelGate.gate_node({}, GameConfig.SPAWN_POINT)
	var n := LevelGate.charges(id)
	var each := int(ResourceNodes.info(ResourceNodes.get_by_id(id)).amount)
	check(n >= 2, "a tier-2 node has several charges")
	check_eq(LevelGate.veteran_problem(id, n, true, n * each), "")
	check_eq(LevelGate.veteran_problem(id, n, true, n * each + 3), "", "yield bonus is fine")
	check(LevelGate.veteran_problem(id, n - 1, true, (n - 1) * each).contains("did the refusal take one"),
		"a node that empties a gather early fails")
	check(LevelGate.veteran_problem(id, n, false, n * each).contains("never emptied"), "a node that never empties fails")
	check(LevelGate.veteran_problem(id, n, true, n * each - 1).contains("paid only"), "a short payout fails")
