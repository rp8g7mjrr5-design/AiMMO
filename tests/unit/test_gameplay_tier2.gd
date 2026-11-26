extends TestCase
## Tier-2 nodes gated by stone tools (there are no levels, owner direction 2026-11-26): the old
## ashes and rich stone seams past the meadow (ResourceNodes.TIER2), their placement, the
## "tool" refusal and its words, what they pay (item, bar time), and the whole thing through
## the real server functions (no network: messages land in test_outbox, fake clock test_now).

const ServerScript := preload("res://server/server.gd")
const FIRST_TIER2_ID := 397 ## the list before pass 3 had 397 nodes; ids never move


func _first_tier2(kind: String) -> Dictionary:
	for n in ResourceNodes.tier2():
		if n.kind == kind:
			return n
	return {}


func _server(id: int, pos: Vector3, inv: Dictionary) -> Node:
	var srv: Node = ServerScript.new()
	srv.test_now = 100.0
	var ch := CharacterData.normalize({"name": "P%d" % id, "inventory": inv})
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
		check(Gathering.needs_tool(n), "a tool to work it")
		check(not n.has("min_level"), "no level on the node")
	for n in ResourceNodes.all():
		if n.id < FIRST_TIER2_ID:
			check(n.tier == 1 and Gathering.min_tier(n) <= 1, "node %d stays tier 1: bare hands or a wooden tool" % n.id)


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
	check_eq(info.item, "ash_wood")
	check_eq(info.label, "Old ash")
	check_eq(info.tier, 2)
	check_eq(ResourceNodes.info(_first_tier2("stone")).item, "stone")
	var pine := ResourceNodes.get_by_id(0)
	check_eq(ResourceNodes.info(pine).item, ResourceNodes.kind_info(pine.kind).item, "tier 1 is its kind's values")
	check(ResourceNodes.info({}).is_empty(), "nothing for no node")
	for kind in ResourceNodes.TIER2:
		var item := str(ResourceNodes.TIER2[kind].item)
		check(Inventory.is_item(item), "%s is a real item" % item)
		check(not Inventory.label(item).contains("_"), "%s has a label" % item)
		check(Inventory.ITEMS.has(item) and Inventory.ITEM_ORDER.has(item), "%s is in ITEMS" % item)


func test_tool_gate() -> void:
	var st := Gathering.new_state()
	var ash := _first_tier2("ash")
	var here: Vector3 = ash.pos + Vector3(1.0, 0, 0)
	var far: Vector3 = ash.pos + Vector3(40.0, 0, 0)
	var axe := {"stone_axe": 1}
	check_eq(Gathering.check(st, ash.id, here, 0.0, 0.0, -INF), "tool", "bare hands can't")
	check_eq(Gathering.check(st, ash.id, far, 0.0, 0.0, -INF), "tool", "from afar, the tool answer comes first")
	check_eq(Gathering.check(st, ash.id, here, 0.0, 0.0, -INF, Gathering.COOLDOWN, {"stone_pickaxe": 1}), "tool", "a pickaxe doesn't fell a tree")
	check_eq(Gathering.check(st, ash.id, here, 0.0, 0.0, -INF, Gathering.COOLDOWN, axe), "", "a stone axe can")
	check_eq(Gathering.check(st, ash.id, here, 0.0, 0.0, -INF, Gathering.COOLDOWN, {"wooden_axe": 1}), "tool", "a wooden axe can't")
	check_eq(Gathering.check(st, ash.id, far, 0.0, 0.0, -INF, Gathering.COOLDOWN, axe), "far", "then reach still counts")
	check_eq(Gathering.refusal("tool", st, ash.id, here, 0.0, 0.0), "You need a stone axe to work this old ash.")
	var seam := _first_tier2("stone")
	check_eq(Gathering.refusal("tool", st, seam.id, seam.pos, 0.0, 0.0), "You need a stone pickaxe to work this rich stone seam.")


func test_pick_and_hint_skip_what_you_cannot_work() -> void:
	var st := Gathering.new_state()
	var ash := _first_tier2("ash")
	var here: Vector3 = ash.pos + Vector3(0.5, 0, 0)
	var picked := Gathering.pick_target(st, here, 0.0, 0.0, "ash")
	check_eq(picked, ash.id, "pick still names it, so the refusal can explain")
	check_eq(Gathering.pick_target(st, here, 0.0, 0.0, "ash", {"stone_axe": 1}), ash.id, "with an axe it picks it")
	check(not Gathering.hint(st, here, 0.0, 0.0, "ash").contains("old ash"), "a bare-handed hint never sends you to it")
	check(Gathering.hint(st, here, 0.0, 0.0, "ash", {"stone_axe": 1}).contains("old ash"), "a stone-axe carrier's hint does")


func test_tier2_pays_in_bulk() -> void:
	var ash := _first_tier2("ash")
	var axe := {"stone_axe": 1}
	check_near(GatherChannel.seconds_at(ash.id, axe), GatherChannel.seconds_for("ash", axe) * 1.2, 0.0001, "a bigger tree takes a little longer")
	check_eq(Gathering.amount_at(ash.id, {}), 5)
	check_eq(Gathering.amount_at(ash.id, axe), 6, "the axe helps here too")
	var st := Gathering.new_state()
	for i in 3:
		check(not Gathering.take(st, ash.id, 0.0).depleted, "gather %d leaves some" % (i + 1))
	var last := Gathering.take(st, ash.id, 0.0)
	check(last.depleted, "four charges")
	check_eq(last.item, "ash_wood")
	check_near(last.respawn, 300.0, 0.001)


func test_server_refuses_bare_hands() -> void:
	var ash := _first_tier2("ash")
	var srv := _server(2, ash.pos + Vector3(1.0, 0, 0), {})
	var r: Dictionary = srv.gather_request(2, ash.id)
	check(not r.ok, "refused")
	check_eq(r.reason, "tool")
	check_eq(_sent(srv, "s2c_gather_end"), [[2, ash.id, "tool"]], "the client's bar hears why")
	check(_sent(srv, "s2c_system").has(["You need a stone axe to work this old ash."]), "and the words: %s" % [_sent(srv, "s2c_system")])
	check(_sent(srv, "s2c_gather_begin").is_empty(), "nobody sees a gather start")
	check(srv.gather(2, "ash").begins_with("You need a stone axe"), "/gather says the same: " + srv.gather(2, "ash"))
	srv.free()


func test_server_pays_out_with_the_tool() -> void:
	var seam := _first_tier2("stone")
	var pick := {"stone_pickaxe": 1}
	var srv := _server(2, seam.pos + Vector3(1.0, 0, 0), pick)
	var r: Dictionary = srv.gather_request(2, seam.id)
	check(r.ok, "a pickaxe starts it: %s" % r.reason)
	check_near(r.seconds, GatherChannel.seconds_at(seam.id, pick), 0.0001)
	_run(srv, r.seconds + 0.2)
	check_eq(_sent(srv, "s2c_gather_end").back(), [2, seam.id, "done"])
	check_eq(_sent(srv, "s2c_gather_result"), [["stone", 6]], "stone in bulk, +1 for the pickaxe")
	check_eq(int(srv.sessions[2].character.inventory.get("stone", 0)), 6, "in the pack")
	check(_sent(srv, "s2c_xp").is_empty(), "no XP: there are no levels")
	srv.free()
