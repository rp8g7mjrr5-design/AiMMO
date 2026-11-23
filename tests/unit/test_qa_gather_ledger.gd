extends TestCase
## qa_gather_ledger's checks (tests/bot_test/gather_ledger.gd) and the harness's
## --only-behaviour filter.

const GatherLedger := preload("res://tests/bot_test/gather_ledger.gd")
const BotBehaviour := preload("res://tests/bot_test/bot_behaviour.gd")


func test_pack_diff() -> void:
	check_eq(GatherLedger.pack_diff({"stone": 2}, {"stone": 2}), {})
	check_eq(GatherLedger.pack_diff({"stone": 2}, {"stone": 4, "ash_wood": 1}), {"stone": 2, "ash_wood": 1})
	check_eq(GatherLedger.pack_diff({"stone": 2, "pine_wood": 3}, {"stone": 2}), {"pine_wood": -3})
	check_eq(GatherLedger.pack_diff({"stone": 0}, {}), {}, "a zero stack is no stack")


func test_same_pack_is_fine() -> void:
	check_eq(GatherLedger.reconnect_problem({"stone": 2}, {"stone": 2}, -1, 0), "")


func test_lost_items_are_reported() -> void:
	var why := GatherLedger.reconnect_problem({"stone": 4, "ash_wood": 2}, {"stone": 2}, -1, 0)
	check(why.find("stone -2") != -1 and why.find("ash_wood -2") != -1, "names both: %s" % why)


func test_invented_items_without_a_gather_are_reported() -> void:
	check_eq(GatherLedger.reconnect_problem({}, {"stone": 2}, -1, 2), "stone +2")


func test_a_gather_finishing_at_the_hang_up_is_allowed() -> void:
	check_eq(GatherLedger.reconnect_problem({"stone": 2}, {"stone": 4}, 17, 2), "in_flight")


func test_in_flight_allows_only_one_gather() -> void:
	check_eq(GatherLedger.reconnect_problem({"stone": 2}, {"stone": 6}, 17, 2), "stone +4", "two gathers' worth")
	check_eq(GatherLedger.reconnect_problem({"stone": 2}, {"stone": 4, "ash_wood": 2}, 17, 2), "ash_wood +2, stone +2", "two items")
	check_eq(GatherLedger.reconnect_problem({"stone": 4}, {"stone": 2}, 17, 2), "stone -2", "a gather never takes away")


func test_gatherers_on() -> void:
	var ch := {3: 40, 5: 40, 9: 12}
	check_eq(GatherLedger.gatherers_on(ch, 40), 2)
	check_eq(GatherLedger.gatherers_on(ch, 12), 1)
	check_eq(GatherLedger.gatherers_on(ch, 99), 0)


func test_pair_node_is_the_nearest_live_day_node() -> void:
	var spawn := GameConfig.SPAWN_POINT
	var first := GatherLedger.pair_node({}, [], spawn)
	check(first >= 0, "there is a node to share")
	var n := ResourceNodes.get_by_id(first)
	check(not bool(ResourceNodes.kind_info(str(n.kind)).night_only), "never a night-only seep")
	var d := Vector2(n.pos.x, n.pos.z).length()
	for other in ResourceNodes.near(spawn, d - 0.01):
		check(bool(ResourceNodes.kind_info(str(other.kind)).night_only), "only seeps are nearer: %d" % other.id)
	var second := GatherLedger.pair_node({first: true}, [], spawn)
	check(second >= 0 and second != first, "an empty node is skipped")
	check_eq(GatherLedger.pair_node({}, [first], spawn), second, "the probe's node is skipped")


func test_node_at() -> void:
	var n := ResourceNodes.get_by_id(GatherLedger.pair_node({}, [], GameConfig.SPAWN_POINT))
	check_eq(GatherLedger.node_at(n.pos + Vector3(1.0, 0, 0.5), 1.8), int(n.id), "standing next to it")
	check_eq(GatherLedger.node_at(n.pos + Vector3(2.5, 0, 0), 1.8), -1, "too far")


func test_only_behaviour_filter() -> void:
	var loaded: Array = BotBehaviour.load_all()
	check_eq(BotBehaviour.only(loaded[0], PackedStringArray()).size(), loaded[0].size(), "no filter keeps all")
	var just: Array = BotBehaviour.only(loaded[0], PackedStringArray(["qa_gather_ledger"]))
	check_eq(just.size(), 1)
	if just.size() == 1:
		check_eq(just[0].name, "qa_gather_ledger")
	check_eq(BotBehaviour.only(loaded[0], PackedStringArray(["no_such"])).size(), 0)


func test_saved_skills_hold_what_the_bot_knew() -> void:
	var Verify: GDScript = load("res://tests/bot_test/verify_store.gd")
	check_eq(Verify.skills_problem({}, {}), "", "nothing known, nothing to check")
	check_eq(Verify.skills_problem({"felling": 150}, {"felling": 175, "tapping": 30}), "", "more is fine")
	check_eq(Verify.skills_problem({"felling": 150}, {"felling": 150}), "", "exactly the floor")
	var why: String = Verify.skills_problem({"felling": 150, "quarrying": 0}, {"felling": 90})
	check(why.contains("felling 90 XP (level 1)") and why.contains("at least 150 (level 2)"), "names the lost level: " + why)
	check(not why.contains("quarrying"), "0 XP floor is always met")
	check(Verify.skills_problem({"felling": 150}, null) != "", "no skills saved at all")
