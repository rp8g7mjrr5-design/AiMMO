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


func test_only_behaviour_filter() -> void:
	var loaded: Array = BotBehaviour.load_all()
	check_eq(BotBehaviour.only(loaded[0], PackedStringArray()).size(), loaded[0].size(), "no filter keeps all")
	var just: Array = BotBehaviour.only(loaded[0], PackedStringArray(["qa_gather_ledger"]))
	check_eq(just.size(), 1)
	if just.size() == 1:
		check_eq(just[0].name, "qa_gather_ledger")
	check_eq(BotBehaviour.only(loaded[0], PackedStringArray(["no_such"])).size(), 0)
