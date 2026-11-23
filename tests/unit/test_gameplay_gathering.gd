extends TestCase
## Gathering (game/shared/gathering.gd) and the /gather command's parsing.

const NOON := WorldClock.DAY_SECONDS * 0.25 ## world second 0 is sunrise
const MIDNIGHT := WorldClock.DAY_SECONDS * 0.75


func _first(kind: String) -> Dictionary:
	for n in ResourceNodes.all():
		if n.kind == kind:
			return n
	return {}


func test_gather_until_depleted_then_respawn() -> void:
	var st := Gathering.new_state()
	var n := _first("pine")
	var pos: Vector3 = n.pos + Vector3(1.0, 0, 0)
	var info := ResourceNodes.kind_info("pine")
	var t := 100.0
	for i in Gathering.CHARGES.pine:
		check_eq(Gathering.check(st, n.id, pos, t, NOON, -1000.0), "", "gather %d allowed" % i)
		var got := Gathering.take(st, n.id, t)
		check_eq(got.item, "pine_wood")
		check_eq(got.qty, info.amount)
		check_eq(got.depleted, i == Gathering.CHARGES.pine - 1, "depletes on the last charge only")
		t += Gathering.COOLDOWN
	check(Gathering.is_depleted(st, n.id, t), "depleted")
	check_eq(Gathering.charges_left(st, n.id, t), 0)
	check_eq(Gathering.check(st, n.id, pos, t, NOON, -1000.0), "depleted")
	check_eq(Gathering.depleted_ids(st, t), [n.id])
	var back_at: float = t - Gathering.COOLDOWN + float(info.respawn)
	check(Gathering.respawn_due(st, back_at - 0.1).is_empty(), "not back early")
	check_eq(Gathering.respawn_due(st, back_at), [n.id], "back on time")
	check_eq(Gathering.charges_left(st, n.id, back_at), Gathering.CHARGES.pine, "full charges again")
	check_eq(Gathering.check(st, n.id, pos, back_at, NOON, -1000.0), "")


func test_refusals() -> void:
	var st := Gathering.new_state()
	var n := _first("stone")
	var near: Vector3 = n.pos + Vector3(0, 0, 2.0)
	var far: Vector3 = n.pos + Vector3(0, 0, ResourceNodes.GATHER_RANGE + 0.5)
	check_eq(Gathering.check(st, -1, near, 0.0, NOON, -1000.0), "unknown", "negative id")
	check_eq(Gathering.check(st, 99999, near, 0.0, NOON, -1000.0), "unknown", "id past the end")
	check_eq(Gathering.check(st, n.id, far, 0.0, NOON, -1000.0), "far")
	check_eq(Gathering.check(st, n.id, near, 10.0, NOON, 9.5), "cooldown")
	check_eq(Gathering.check(st, n.id, near, 10.0, NOON, 10.0 - Gathering.COOLDOWN), "", "cooldown over")


func test_ember_sap_only_at_night() -> void:
	var st := Gathering.new_state()
	var n := _first("ember_sap")
	check(not n.is_empty(), "there is a seep")
	var pos: Vector3 = n.pos
	check_eq(Gathering.check(st, n.id, pos, 0.0, NOON, -1000.0), "day", "dry at noon")
	check_eq(Gathering.check(st, n.id, pos, 0.0, MIDNIGHT, -1000.0), "", "seeps at midnight")
	var got := Gathering.take(st, n.id, 0.0)
	check_eq(got.item, "ember_sap")
	check(got.depleted, "one gather empties a seep")
	check(Gathering.refusal("day", st, n.id, pos, 0.0, NOON).contains("night"), "refusal says when")


func test_pick_target_prefers_gatherable_and_kind() -> void:
	var st := Gathering.new_state()
	var n := _first("ash")
	var pos: Vector3 = n.pos
	check_eq(Gathering.pick_target(st, pos, 0.0, NOON), n.id, "the node you stand at")
	check_eq(Gathering.pick_target(st, pos, 0.0, NOON, "stone"), -1, "no stone in reach of a tree")
	for i in Gathering.CHARGES.ash:
		Gathering.take(st, n.id, 0.0)
	check_eq(Gathering.pick_target(st, pos, 1.0, NOON), n.id, "still named when spent, so the refusal can say so")
	check(Gathering.refusal("depleted", st, n.id, pos, 1.0, NOON).begins_with("This ember ash is spent; it comes back in about 3 minutes."), "depleted refusal")


func test_give_back_undoes_take() -> void:
	var st := Gathering.new_state()
	var n := _first("ember_sap")
	Gathering.take(st, n.id, 5.0)
	check(Gathering.is_depleted(st, n.id, 5.0), "depleted after take")
	Gathering.give_back(st, n.id)
	check(not Gathering.is_depleted(st, n.id, 5.0), "a full pack doesn't waste the seep")
	check_eq(Gathering.charges_left(st, n.id, 5.0), 1)


func test_hint_points_at_nearest_live_node() -> void:
	var st := Gathering.new_state()
	var spawn := GameConfig.SPAWN_POINT
	var line := Gathering.hint(st, spawn, 0.0, NOON, "pine")
	var pine: Dictionary = ResourceNodes.nearest(spawn, "pine")
	check(line.begins_with("The nearest pine is %d m to the " % roundi(Vector2(pine.pos.x, pine.pos.z).length())), line)
	for i in Gathering.CHARGES.pine:
		Gathering.take(st, pine.id, 0.0)
	check(Gathering.hint(st, spawn, 1.0, NOON, "pine") != line, "a spent pine is skipped")
	check(Gathering.hint(st, spawn, 0.0, NOON, "ember_sap").begins_with("Nothing"), "no seep hint by day")


func test_direction_names() -> void:
	check_eq(Gathering.direction_name(Vector3(0, 0, -10)), "north", "-Z is north")
	check_eq(Gathering.direction_name(Vector3(10, 0, 0)), "east")
	check_eq(Gathering.direction_name(Vector3(0, 0, 10)), "south")
	check_eq(Gathering.direction_name(Vector3(-10, 0, 0)), "west")
	check_eq(Gathering.direction_name(Vector3(7, 0, -7)), "north-east")
	check_eq(Gathering.direction_name(Vector3(-7, 0, 7)), "south-west")
	check_eq(Gathering.direction_name(Vector3.ZERO), "right here")


func test_parse_kind_and_command() -> void:
	check_eq(Gathering.parse_kind(""), "")
	check_eq(Gathering.parse_kind("Pine"), "pine")
	check_eq(Gathering.parse_kind("ash wood"), "ash")
	check_eq(Gathering.parse_kind("rock"), "stone")
	check_eq(Gathering.parse_kind("sap"), "ember_sap")
	check_eq(Gathering.parse_kind("dragon"), null)
	check(ChatCommands.is_gather("/gather"), "gather")
	check(ChatCommands.is_gather("/G pine"), "alias, any case")
	check(not ChatCommands.is_gather("/bag"), "bag is not gather")
	check(not ChatCommands.is_gather("gather"), "plain chat is not a command")
	check_eq(ChatCommands.argument("/gather  ember sap "), "ember sap")
	check_eq(ChatCommands.argument("/gather"), "")
	check(not ChatCommands.HELP.contains("/gather"), "hidden from /help since v3 (players press E)")


func test_success_line() -> void:
	var n := _first("stone")
	check_eq(Gathering.success(n.id, 2, 6, false), "You gather 2 stone from the stone outcrop (6 in your pack).")
	check(Gathering.success(n.id, 2, 6, true).ends_with("It is spent for now."), "spent note")
