extends TestCase
## The bot test's tool-gate check (tests/bot_test/tool_gate.gd, behaviour qa_tool_gate):
## which node it uses, where and how the veteran is seeded, and the veteran's verdict.

const ToolGate := preload("res://tests/bot_test/tool_gate.gd")


func test_gate_node_is_the_nearest_tool_gated_node() -> void:
	var id := ToolGate.gate_node({}, GameConfig.SPAWN_POINT)
	check(id >= 0, "the world has a tier-2 node")
	var node := ResourceNodes.get_by_id(id)
	check(Gathering.needs_tool(node), "the gate node needs a tool")
	var d := Vector2(node.pos.x - GameConfig.SPAWN_POINT.x, node.pos.z - GameConfig.SPAWN_POINT.z).length()
	for n in ResourceNodes.tier2():
		if Gathering.needs_tool(n):
			check(Vector2(n.pos.x - GameConfig.SPAWN_POINT.x, n.pos.z - GameConfig.SPAWN_POINT.z).length() >= d - 0.001,
				"node %d is nearer spawn than the gate node %d" % [n.id, id])
	var other := ToolGate.gate_node({id: true}, GameConfig.SPAWN_POINT)
	check(other >= 0 and other != id, "an empty gate node is skipped")
	check(Gathering.needs_tool(ResourceNodes.get_by_id(other)), "the next one is gated too")


func test_veteran_is_seeded_out_of_reach_on_the_ground() -> void:
	var id := ToolGate.gate_node({}, GameConfig.SPAWN_POINT)
	var spot := ToolGate.veteran_spot(id, GameConfig.SPAWN_POINT)
	var node := ResourceNodes.get_by_id(id)
	var flat := Vector2(spot.x - node.pos.x, spot.z - node.pos.z).length()
	check(absf(flat - ToolGate.VETERAN_OFFSET) < 0.01, "%.2f m from the node" % flat)
	check(not ResourceNodes.in_range(id, spot), "starts out of reach, so it walks there")
	check(flat > 5.0, "walks more than the 5 m every bot must")
	check(absf(spot.y - Terrain.height(spot.x, spot.z)) < 0.001, "on the ground")
	check(Vector2(spot.x, spot.z).length() < Vector2(node.pos.x, node.pos.z).length(), "on the spawn side")


func test_veteran_has_the_tool_and_the_fresh_player_none() -> void:
	for id in [ToolGate.gate_node({}, GameConfig.SPAWN_POINT)]:
		var node := ResourceNodes.get_by_id(id)
		var pack := ToolGate.veteran_pack(id)
		check_eq(pack.size(), 1, "only the tool")
		check(Crafting.makes_tool(str(pack.keys()[0])), "it is a tool")
		check(Gathering.can_work(node, pack), "the veteran can work it")
		check(not Gathering.can_work(node, {}), "a fresh player is refused")
		check_eq(Gathering.check(Gathering.new_state(), id, node.pos, 0.0, 0.0, -1000.0, Gathering.COOLDOWN, {}), "tool")
		check_eq(Gathering.check(Gathering.new_state(), id, node.pos, 0.0, 0.0, -1000.0, Gathering.COOLDOWN, pack), "")
		var word := "a stone pickaxe" if str(node.kind) == "stone" else "a stone axe"
		check_eq(ToolGate.refusal_text(id), "You need %s to work this %s." % [word, str(ResourceNodes.info(node).label).to_lower()])
	# Both kinds of tier-2 node: a stone axe opens the old ash, a stone pickaxe the seam, never
	# the other (and never a wooden one).
	for n in ResourceNodes.tier2():
		if Gathering.needs_tool(n):
			var p := ToolGate.veteran_pack(int(n.id))
			check(Gathering.can_work(n, p), "node %d opens to %s" % [n.id, p])
			var wrong := {"stone_pickaxe": 1} if str(n.kind) == "ash" else {"stone_axe": 1}
			check(not Gathering.can_work(n, wrong), "node %d stays shut to the wrong tool" % n.id)


func test_veteran_verdict() -> void:
	var id := ToolGate.gate_node({}, GameConfig.SPAWN_POINT)
	var n := ToolGate.charges(id)
	var each := Gathering.amount_at(id, ToolGate.veteran_pack(id))
	check(n >= 2, "a tier-2 node has several charges")
	check_eq(ToolGate.veteran_problem(id, n, true, n * each), "")
	check(ToolGate.veteran_problem(id, n, true, n * each + 3) != "", "no hidden bonus: an over-payout fails")
	check(ToolGate.veteran_problem(id, n - 1, true, (n - 1) * each).contains("did the refusal take one"),
		"a node that empties a gather early fails")
	check(ToolGate.veteran_problem(id, n, false, n * each).contains("never emptied"), "a node that never empties fails")
	check(ToolGate.veteran_problem(id, n, true, n * each - 1).contains("paid"), "a short payout fails")


func test_old_xp_must_be_kept_exactly() -> void:
	var kept := ToolGate.VETERAN_OLD_XP
	check_eq(ToolGate.old_xp_problem(kept, kept.duplicate()), "")
	var more := kept.duplicate()
	more["spearwork"] = 5
	check_eq(ToolGate.old_xp_problem(kept, more), "", "extra old ids are fine")
	var lost := kept.duplicate()
	lost.erase("felling")
	check(ToolGate.old_xp_problem(kept, lost).contains("felling"), "a lost skill fails")
	var changed := kept.duplicate()
	changed["toolcraft"] = int(changed["toolcraft"]) + 8
	check(ToolGate.old_xp_problem(kept, changed).contains("toolcraft"), "changed XP fails: nothing earns it any more")
