extends TestCase
## Tier-2 nodes gated by level (roadmap Milestone 1 part 3): the old ember ashes and rich
## stone seams past the meadow (ResourceNodes.TIER2), their placement, the "level" refusal
## and its words, what they pay (item, XP, bar time), and the whole thing through the real
## server functions (no network: messages land in test_outbox, fake clock test_now).

const ServerScript := preload("res://server/server.gd")
const FIRST_TIER2_ID := 397 ## the list before pass 3 had 397 nodes; ids never move


func _skills_at(skill: String, level: int) -> Dictionary:
	return {skill: Skills.xp_for_level(level)}


func _first_tier2(kind: String) -> Dictionary:
	for n in ResourceNodes.tier2():
		if n.kind == kind:
			return n
	return {}


func _server(id: int, pos: Vector3, skills: Dictionary) -> Node:
	var srv: Node = ServerScript.new()
	srv.test_now = 100.0
	var ch := CharacterData.normalize({"name": "P%d" % id, "skills": skills})
	ch.x = pos.x
	ch.y = pos.y
	ch.z = pos.z
	srv.sessions[id] = {"logged_in": true, "character": ch, "move": Vector2.ZERO, "yaw": 0.0, "seq": -1,
		"last_chat": -1000.0, "last_gather": -1000.0, "channel": {}, "login_attempts": 0, "inv_dirty": false}
	return srv


func _sent(srv: Node, method: String) -> Array:
	var out: Array = []
	for m in srv.test_outbox:
		if m[1] == method:
			out.append(m[2])
	return out


func _run(srv: Node, seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		srv.test_now += GameConfig.TICK_DT
		t += GameConfig.TICK_DT
		srv._tick_channels(srv.test_now)
		srv._flush_inventories()


func test_the_ring_is_appended_after_every_old_node() -> void:
	var t2 := ResourceNodes.tier2()
	check_eq(t2.size(), ResourceNodes.TIER2_RING.size(), "every slot of the ring found ground")
	check_eq(ResourceNodes.count(), FIRST_TIER2_ID + t2.size(), "only the ring was added")
	for i in t2.size():
		var n: Dictionary = t2[i]
		check_eq(n.id, FIRST_TIER2_ID + i, "tier-2 ids follow the old list")
		check_eq(n.kind, ResourceNodes.TIER2_RING[i], "kind follows the ring")
		check_eq(n.tier, 2)
		check_eq(n.min_level, 5, "level 5 to work it")
		check_eq(n.skill, Skills.skill_for_kind(n.kind))
	for n in ResourceNodes.all():
		if n.id < FIRST_TIER2_ID:
			check(n.tier == 1 and n.min_level == 1, "node %d stays tier 1, open to all" % n.id)


func test_a_short_walk_from_the_meadow_with_room_around() -> void:
	var by_kind := {}
	for n in ResourceNodes.tier2():
		by_kind[n.kind] = by_kind.get(n.kind, 0) + 1
		var r := Vector2(n.pos.x, n.pos.z).length()
		check(r >= ResourceNodes.TIER2_MIN_RADIUS and r <= ResourceNodes.TIER2_MAX_RADIUS + 6.0, "node %d is %.1f m out" % [n.id, r])
		check(n.pos.y > Terrain.water_level() + 0.9, "node %d is on dry ground" % n.id)
		for o in ResourceNodes.near(n.pos, ResourceNodes.TIER2_SPACING):
			check(o.id == n.id, "node %d has room: %d is too close" % [n.id, o.id])
		check(n.scale >= 0.95 and n.scale <= 1.05, "scale near 1 (world's request)")
	check_eq(by_kind.get("ash", 0), 4, "four old ashes")
	check_eq(by_kind.get("stone", 0), 4, "four rich seams")


func test_info_gives_the_tier2_values() -> void:
	var ash := _first_tier2("ash")
	var info := ResourceNodes.info(ash)
	check_eq(info.item, "ember_heartwood")
	check_eq(info.label, "Old ember ash")
	check_eq(info.tier, 2)
	check_eq(ResourceNodes.info(_first_tier2("stone")).item, "veinstone")
	var pine := ResourceNodes.get_by_id(0)
	check_eq(ResourceNodes.info(pine).item, ResourceNodes.kind_info(pine.kind).item, "tier 1 is its kind's values")
	check(ResourceNodes.info({}).is_empty(), "nothing for no node")
	for kind in ResourceNodes.TIER2:
		var item := str(ResourceNodes.TIER2[kind].item)
		check(Inventory.is_item(item), "%s is a real item" % item)
		check(not Inventory.label(item).contains("_"), "%s has a label" % item)
		check(not Inventory.ITEMS.has(item), "%s waits in NEW_ITEMS until world draws its icon" % item)


func test_level_gate() -> void:
	var st := Gathering.new_state()
	var ash := _first_tier2("ash")
	var here: Vector3 = ash.pos + Vector3(1.0, 0, 0)
	var far: Vector3 = ash.pos + Vector3(40.0, 0, 0)
	check_eq(Gathering.check(st, ash.id, here, 0.0, 0.0, -INF), "level", "a new character can't")
	check_eq(Gathering.check(st, ash.id, far, 0.0, 0.0, -INF), "level", "from afar, the level answer comes first")
	check_eq(Gathering.check(st, ash.id, here, 0.0, 0.0, -INF, Gathering.COOLDOWN, _skills_at("felling", 4)), "level", "Felling 4 can't")
	check_eq(Gathering.check(st, ash.id, here, 0.0, 0.0, -INF, Gathering.COOLDOWN, _skills_at("quarrying", 9)), "level", "the wrong skill doesn't count")
	check_eq(Gathering.check(st, ash.id, here, 0.0, 0.0, -INF, Gathering.COOLDOWN, _skills_at("felling", 5)), "", "Felling 5 can")
	check_eq(Gathering.check(st, ash.id, far, 0.0, 0.0, -INF, Gathering.COOLDOWN, _skills_at("felling", 5)), "far", "then reach still counts")
	check_eq(Gathering.check(st, 0, ResourceNodes.get_by_id(0).pos, 0.0, 0.0, -INF), "" if not ResourceNodes.kind_info(ResourceNodes.get_by_id(0).kind).night_only else "day", "tier 1 is open to level 1")
	var text := Gathering.refusal("level", st, ash.id, here, 0.0, 0.0, "", _skills_at("felling", 3))
	check_eq(text, "Needs Felling 5. You're Felling 3.")
	var seam := _first_tier2("stone")
	check_eq(Gathering.refusal("level", st, seam.id, seam.pos, 0.0, 0.0), "Needs Quarrying 5. You're Quarrying 1.")


func test_pick_and_hint_skip_what_you_cannot_work() -> void:
	var st := Gathering.new_state()
	var ash := _first_tier2("ash")
	var here: Vector3 = ash.pos + Vector3(0.5, 0, 0)
	var picked := Gathering.pick_target(st, here, 0.0, 0.0, "ash")
	check_eq(picked, ash.id, "pick still names it, so the refusal can explain")
	check_eq(Gathering.pick_target(st, here, 0.0, 0.0, "ash", _skills_at("felling", 5)), ash.id, "Felling 5 picks it")
	check(not Gathering.hint(st, here, 0.0, 0.0, "ash").contains("old ember ash"), "a level-1 hint never sends you to it")
	check(Gathering.hint(st, here, 0.0, 0.0, "ash", _skills_at("felling", 5)).contains("old ember ash"), "a Felling 5 hint does")


func test_tier2_pays_more() -> void:
	var ash := _first_tier2("ash")
	check_eq(Skills.gather_xp("ash", false, 2), 20, "an old ash pays 2x")
	check_eq(Skills.gather_xp("stone", false, 2), 24, "a rich seam pays 2x")
	check_eq(Skills.gather_xp("ash", true, 2), 25, "together bonus on top")
	check_eq(Skills.gather_xp("ash"), 10, "tier 1 unchanged")
	check_near(GatherChannel.seconds_at(ash.id, {}, 1), GatherChannel.seconds_for("ash", {}, 1) * 1.2, 0.0001, "a bigger tree takes a little longer")
	check_eq(Gathering.amount_at(ash.id, {}, 5), 2)
	check_eq(Gathering.amount_at(ash.id, {"stone_axe": 1}, 5), 3, "the axe helps here too")
	var xp_rate_1 := Skills.gather_xp("ash") / GatherChannel.seconds_for("ash", {}, 5)
	var xp_rate_2 := Skills.gather_xp("ash", false, 2) / GatherChannel.seconds_at(ash.id, {}, 5)
	check(xp_rate_2 > xp_rate_1 * 1.5, "levels come about 1.7x as fast: %.2f vs %.2f XP/s" % [xp_rate_2, xp_rate_1])
	var st := Gathering.new_state()
	for i in 3:
		check(not Gathering.take(st, ash.id, 0.0).depleted, "gather %d leaves some" % (i + 1))
	var last := Gathering.take(st, ash.id, 0.0)
	check(last.depleted, "four charges")
	check_eq(last.item, "ember_heartwood")
	check_near(last.respawn, 300.0, 0.001)


func test_server_refuses_below_the_level() -> void:
	var ash := _first_tier2("ash")
	var srv := _server(2, ash.pos + Vector3(1.0, 0, 0), _skills_at("felling", 3))
	var r: Dictionary = srv.gather_request(2, ash.id)
	check(not r.ok, "refused")
	check_eq(r.reason, "level")
	check_eq(_sent(srv, "s2c_gather_end"), [[2, ash.id, "level"]], "the client's bar hears why")
	check(_sent(srv, "s2c_system").has(["Needs Felling 5. You're Felling 3."]), "and the words: %s" % [_sent(srv, "s2c_system")])
	check(_sent(srv, "s2c_gather_begin").is_empty(), "nobody sees a gather start")
	check(srv.gather(2, "ash").begins_with("Needs Felling 5"), "/gather says the same: " + srv.gather(2, "ash"))
	srv.free()


func test_server_pays_out_at_the_level() -> void:
	var seam := _first_tier2("stone")
	var srv := _server(2, seam.pos + Vector3(1.0, 0, 0), _skills_at("quarrying", 5))
	var r: Dictionary = srv.gather_request(2, seam.id)
	check(r.ok, "Quarrying 5 starts it: %s" % r.reason)
	check_near(r.seconds, GatherChannel.seconds_at(seam.id, {}, 5), 0.0001)
	_run(srv, r.seconds + 0.2)
	check_eq(_sent(srv, "s2c_gather_end").back(), [2, seam.id, "done"])
	check_eq(_sent(srv, "s2c_gather_result"), [["veinstone", 2]], "a new material")
	check_eq(int(srv.sessions[2].character.inventory.get("veinstone", 0)), 2, "in the pack")
	var xp := _sent(srv, "s2c_xp")
	check(not xp.is_empty() and xp[0][0] == "quarrying" and int(xp[0][1]) == 24, "24 Quarrying XP: %s" % [xp])
	srv.free()
