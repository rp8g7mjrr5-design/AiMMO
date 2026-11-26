extends TestCase
## The first hunt (2026-11-24): grazers have health, a wounded one limps off slower than you
## walk so you can chase it down, a downed one gives its hunter hide and raw meat and is gone
## from the hills until it gets up at home RESPAWN_SECONDS later. At night a resting herd is
## drowsy enough that a patient stalker gets within bare-handed reach.

const ServerScript := preload("res://server/server.gd")
const DT := 0.05


func _server(players: Dictionary) -> Node:
	var srv: Node = ServerScript.new()
	srv.test_now = 100.0
	for id in players:
		var ch := CharacterData.normalize({"name": "p%d" % id})
		var pos: Vector3 = players[id]
		ch.x = pos.x
		ch.y = pos.y
		ch.z = pos.z
		srv.sessions[id] = {"logged_in": true, "character": ch, "move": Vector2.ZERO, "yaw": 0.0, "seq": -1,
			"last_chat": -1000.0, "last_command": -1000.0, "last_too_fast": -1000.0, "last_gather": -1000.0,
			"channel": {}, "login_attempts": 0, "inv_dirty": false}
	return srv


func _sent(srv: Node, id: int, method: String) -> Array:
	var out: Array = []
	for m in srv.test_outbox:
		if m[0] == id and m[1] == method:
			out.append(m[2])
	return out


## Swings land; the grazers stay put (no wildlife step), like test_gameplay_protocol_v7.
func _advance(srv: Node, seconds: float) -> void:
	srv.test_now += seconds
	srv._tick_swings(srv.test_now)


## A spot 1 m south of grazer `cid`, and the yaw that faces it from there.
func _next_to(srv: Node, cid: int) -> Array:
	var c: Dictionary = Wildlife.get_by_id(srv.wildlife, cid)
	var at: Vector3 = c.pos + Vector3(0, 0, -1.0)
	return [at, atan2(c.pos.x - at.x, c.pos.z - at.z)]


func _flat_dist(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


## Swing `kind` at grazer 0 from right beside it (re-placing the swinger next to it first)
## and let the blow land. Returns the swinger's s2c_swing_hits.
func _hit(srv: Node, kind: String) -> Array:
	var spot: Array = _next_to(srv, 0)
	var ch: Dictionary = srv.sessions[1].character
	ch.x = spot[0].x
	ch.y = spot[0].y
	ch.z = spot[0].z
	srv.sessions[1].swing = {}
	srv.vitals_of(1).stamina = 100.0
	var before := _sent(srv, 1, "s2c_swing_hits").size()
	check_eq(srv.attack_request(1, kind, spot[1]).ok, true, "%s swing goes" % kind)
	_advance(srv, Weapons.swing_seconds(Weapons.FISTS, kind) + 0.01)
	var hits := _sent(srv, 1, "s2c_swing_hits")
	return hits.slice(before)


func test_kinds_have_health_and_drops_that_are_items() -> void:
	check_eq(Wildlife.max_hp("grazer"), 12.0)
	for d in Wildlife.drops("grazer"):
		check(Inventory.is_item(str(d[0])), "%s is an item" % d[0])
		check(int(d[1]) > 0, "int(d[1]) > 0")
	var w := Wildlife.new_state()
	for c in w.creatures:
		check_eq(float(c.hp), Wildlife.max_hp(str(c.kind)), "creature %d starts whole" % c.id)


func test_two_bare_handed_blows_bring_a_grazer_down() -> void:
	# A haymaker alone doesn't, three jabs do: the stalk earns one swing, the chase the rest.
	var heavy := Weapons.damage(Weapons.FISTS, "heavy")
	var light := Weapons.damage(Weapons.FISTS, "light")
	var hp := Wildlife.max_hp("grazer")
	check(heavy < hp, "a haymaker alone isn't enough")
	check(heavy + light >= hp, "a haymaker and a jab are")
	check(2.0 * light < hp and 3.0 * light >= hp, "three jabs are")
	check(Weapons.damage("stone_spear", "heavy") >= hp, "a spear's lunge downs one outright")


func test_a_wounded_grazer_limps_slower_than_you_walk() -> void:
	check(Wildlife.WOUNDED_FLEE_SPEED < GameConfig.WALK_SPEED, "you can catch a wounded one")
	check(Wildlife.FLEE_SPEED > GameConfig.WALK_SPEED, "but not a whole one")
	var w := Wildlife.new_state()
	var c: Dictionary = Wildlife.get_by_id(w, 0)
	var start: Vector3 = c.pos
	Wildlife.strike(w, 0, c.pos + Vector3(0, 0, -1), 10.0, 4.0)
	check_eq(str(c.state), "flee")
	check_eq(float(c.hp), 8.0)
	Wildlife.step(w, [], 10.0, 1.0, false)
	check(_flat_dist(c.pos, start) <= Wildlife.WOUNDED_FLEE_SPEED + 0.01, "it ran at most %.1f m in a second: %.2f" % [Wildlife.WOUNDED_FLEE_SPEED, _flat_dist(c.pos, start)])
	check(_flat_dist(c.pos, start) > 1.0, "but it ran")


func test_a_chaser_catches_a_wounded_grazer() -> void:
	var w := Wildlife.new_state()
	var c: Dictionary = Wildlife.get_by_id(w, 0)
	var p: Vector3 = c.pos + Vector3(0, 0, -1.0)
	Wildlife.strike(w, 0, p, 0.0, Weapons.damage(Weapons.FISTS, "heavy"))
	var t := 0.0
	var caught := false
	while t < 4.0:
		t += DT
		var chase := Vector3(c.pos.x - p.x, 0, c.pos.z - p.z)
		if chase.length() > 0.5:
			p += chase.normalized() * GameConfig.WALK_SPEED * DT
		Wildlife.step(w, [p], t, DT, false)
		if _flat_dist(p, c.pos) <= Weapons.data(Weapons.FISTS).reach + Wildlife.BODY_RADIUS - 0.1:
			caught = true
			break
	check(caught, "within a jab's reach inside 4 s (%.1f m)" % _flat_dist(p, c.pos))


func test_a_wound_heals_if_left_alone() -> void:
	var w := Wildlife.new_state()
	var c: Dictionary = Wildlife.get_by_id(w, 0)
	Wildlife.strike(w, 0, c.pos + Vector3(0, 0, -1), 10.0, 4.0)
	Wildlife.step(w, [], 10.0 + Wildlife.HEAL_SECONDS * 0.5, DT, false)
	check_eq(float(c.hp), 8.0, "still hurt halfway")
	Wildlife.step(w, [], 10.0 + Wildlife.HEAL_SECONDS + 0.1, DT, false)
	check_eq(float(c.hp), 12.0, "whole again")


func test_a_downed_grazer_leaves_the_hills_and_gets_up_at_home() -> void:
	var w := Wildlife.new_state()
	var c: Dictionary = Wildlife.get_by_id(w, 0)
	var n := Wildlife.count(w)
	var bolted := Wildlife.strike(w, 0, c.pos + Vector3(0, 0, -1), 10.0, 50.0)
	check_eq(bolted[0], 0, "the downed one first, then its herd scatters")
	check(Wildlife.is_down(w, 0), "Wildlife.is_down(w, 0)")
	check_eq(int(c.downs), 1)
	check_eq(Wildlife.targets(w).size(), n - 1, "no longer a target")
	check_eq(Wildlife.to_wire(w).size(), (n - 1) * Wildlife.WIRE_STRIDE, "off the wire")
	var near := Wildlife.to_wire_near(w, c.pos, 50.0)
	for i in range(0, near.size(), Wildlife.WIRE_STRIDE):
		check(int(near[i]) != 0, "not sent nearby either")
	check_eq(Wildlife.strike(w, 0, c.pos, 11.0, 50.0), [], "can't be struck again")
	var at: Vector3 = c.pos
	Wildlife.step(w, [], 20.0, 1.0, false)
	check_eq(c.pos, at, "lies still")
	Wildlife.step(w, [], 10.0 + Wildlife.RESPAWN_SECONDS + 0.1, DT, false)
	check(not Wildlife.is_down(w, 0), "up again")
	check_eq(float(c.hp), 12.0, "whole")
	check(_flat_dist(c.pos, c.home) < 0.5, "at home")
	check_eq(Wildlife.to_wire(w).size(), n * Wildlife.WIRE_STRIDE, "back on the wire")


func test_at_night_a_patient_stalker_gets_within_reach() -> void:
	var w := Wildlife.new_state()
	var c: Dictionary = Wildlife.get_by_id(w, 0)
	var t := 0.0
	while t < 40.0: # everyone home and lying down
		t += 0.25
		Wildlife.step(w, [], t, 0.25, true)
	check_eq(str(c.state), "rest")
	var reach: float = Weapons.data(Weapons.FISTS).reach + Wildlife.BODY_RADIUS
	var p: Vector3 = c.pos + Vector3(0, 0, -12.0)
	var closest := INF
	var t_end := t + 60.0
	while t < t_end:
		t += DT
		var watched := false
		for o in w.creatures:
			if o.herd == c.herd and o.state == "alert":
				watched = true
		var nearest := INF
		for o in w.creatures:
			if o.herd == c.herd:
				nearest = minf(nearest, _flat_dist(p, o.pos))
		if not watched and _flat_dist(p, c.pos) > reach - 0.3 and nearest > Wildlife.NIGHT_BOLT_RADIUS + 0.3:
			p += Vector3(c.pos.x - p.x, 0, c.pos.z - p.z).normalized() * 1.0 * DT
		Wildlife.step(w, [p], t, DT, true)
		if c.state == "flee":
			break
		closest = minf(closest, _flat_dist(p, c.pos))
	check(c.state != "flee", "a patient night stalker never startles it")
	check(closest <= reach, "got within a bare-handed swing: %.2f m (reach %.1f)" % [closest, reach])
	check(Wildlife.NIGHT_BOLT_RADIUS < reach - 0.3, "drowsy herds let you inside your reach")


func test_by_day_you_cannot_walk_into_reach() -> void:
	check(Wildlife.BOLT_RADIUS > Weapons.data(Weapons.FISTS).reach + Wildlife.BODY_RADIUS, "day herds bolt first")
	check_eq(Wildlife.bolt_distance(false), Wildlife.BOLT_RADIUS)
	check_eq(Wildlife.bolt_distance(true), Wildlife.NIGHT_BOLT_RADIUS)


func test_the_server_hands_the_hunter_hide_and_meat() -> void:
	var srv := _server({})
	var spot: Array = _next_to(srv, 0)
	srv.free()
	srv = _server({1: spot[0], 2: spot[0] + Vector3(6, 0, 0)})
	check_eq(_hit(srv, "heavy"), [[1, "heavy", [0]]], "the haymaker lands")
	var c: Dictionary = Wildlife.get_by_id(srv.wildlife, 0)
	check_eq(float(c.hp), 12.0 - Weapons.damage(Weapons.FISTS, "heavy"), "and hurts")
	check(not Wildlife.is_down(srv.wildlife, 0), "still up")
	check_eq(Inventory.count(srv.sessions[1].character.inventory, "hide"), 0, "nothing yet")
	check_eq(_hit(srv, "light"), [[1, "light", [0]]], "the jab finishes it")
	check(Wildlife.is_down(srv.wildlife, 0), "down")
	var inv: Dictionary = srv.sessions[1].character.inventory
	check_eq(Inventory.count(inv, "hide"), 1, "one hide")
	check_eq(Inventory.count(inv, "raw_meat"), 2, "two raw meat")
	check_eq(Inventory.count(srv.sessions[2].character.inventory, "hide"), 0, "the onlooker gets nothing")
	check_eq(int(srv.sessions[1].hunted), 1)
	check(bool(srv.sessions[1].inv_dirty), "s2c_inventory goes out this tick")
	check_eq(_sent(srv, 1, "s2c_gather_result"), [["hide", 1], ["raw_meat", 2]], "the hunt toast: one per drop")
	srv.free()


## The hunt toast (2026-11-24): the haul pops like a gather's, only on the blow that downs it,
## only for the hunter, and only for what fit in the pack.
func test_the_kill_pops_a_toast_for_the_hunter_only() -> void:
	var srv := _server({})
	var spot: Array = _next_to(srv, 0)
	srv.free()
	srv = _server({1: spot[0], 2: spot[0] + Vector3(6, 0, 0)})
	_hit(srv, "heavy")
	check_eq(_sent(srv, 1, "s2c_gather_result"), [], "a wound pays nothing yet")
	_hit(srv, "light")
	check_eq(_sent(srv, 1, "s2c_gather_result"), [["hide", 1], ["raw_meat", 2]], "+1 Hide, +2 Raw meat")
	check_eq(_sent(srv, 2, "s2c_gather_result"), [], "the onlooker gets no toast")
	srv.free()


func test_a_full_stack_gets_no_toast_for_that_drop() -> void:
	var srv := _server({})
	var spot: Array = _next_to(srv, 0)
	srv.free()
	srv = _server({1: spot[0]})
	srv.sessions[1].character.inventory["hide"] = Inventory.MAX_STACK
	srv.sessions[1].character.inventory["raw_meat"] = Inventory.MAX_STACK - 1
	_hit(srv, "heavy")
	_hit(srv, "light")
	check(Wildlife.is_down(srv.wildlife, 0), "down")
	check_eq(_sent(srv, 1, "s2c_gather_result"), [["raw_meat", 1]], "only what fit")
	srv.free()


func test_the_drops_are_drawn_items_in_pack_order() -> void:
	for d in Wildlife.drops("grazer"):
		var item := str(d[0])
		check(Inventory.ITEMS.has(item) or Inventory.NEW_ITEMS.has(item), "%s is a drawn item" % item)
		check(not Inventory.UNDRAWN.has(item), "%s no longer waits for an icon" % item)
		check_eq(Inventory.label(item), item.replace("_", " "), "%s has its label" % item)
		check(ItemIcons.has_icon(item), "%s has its own icon for the toast" % item)
	check(ItemIcons.tint("hide") != ItemIcons.tint("raw_meat"), "the two toasts read apart")
	var held := Inventory.held({"stone_axe": 1, "raw_meat": 2, "hide": 1, "ash_wood": 3})
	check_eq(held, ["ash_wood", "hide", "raw_meat", "stone_axe"], "the haul sits with the raw materials, hide first")


func test_a_downed_grazer_is_gone_from_the_server_wire() -> void:
	var srv := _server({})
	var spot: Array = _next_to(srv, 0)
	srv.free()
	srv = _server({1: spot[0]})
	Wildlife.strike(srv.wildlife, 0, spot[0], srv.test_now, 100.0)
	for i in 4:
		srv._tick()
	var wires := _sent(srv, 1, "s2c_wildlife")
	check(not wires.is_empty(), "the hunter still gets the herd")
	for wv in wires:
		var e: PackedFloat32Array = wv[0]
		for i in range(0, e.size(), Wildlife.WIRE_STRIDE):
			check(int(e[i]) != 0, "grazer 0 is not on the wire")
	check_eq(_hit(srv, "light"), [[1, "light", []]], "a swing at where it lay whiffs")
	srv.free()


func test_lure_lays_the_nearest_grazer_down_in_front_of_you() -> void:
	var srv := _server({1: Vector3(0, 0, 0)})
	srv.sessions[1].yaw = 0.0
	srv.dev_commands = true
	var reply: String = srv.lure_command(1)
	check(reply.begins_with("Grazer "), reply)
	var cid := int(reply.split(" ")[1])
	var c: Dictionary = Wildlife.get_by_id(srv.wildlife, cid)
	check(absf(c.pos.z - Wildlife.LURE_DISTANCE) < 0.01 and absf(c.pos.x) < 0.01, "in front: %s" % c.pos)
	for i in 10:
		srv._tick()
	check_eq(str(c.state), "rest", "lies drowsy, blind to you")
	srv.attack_request(1, "heavy", 0.0)
	_advance(srv, 1.0)
	check_eq(_sent(srv, 1, "s2c_swing_hits"), [[1, "heavy", [cid]]], "the haymaker lands on it")
	check_eq(str(c.state), "flee", "and it limps off")
	# A wounded one is lured first, so a bot can finish what it started.
	srv.test_now += 3.0
	var again: String = srv.lure_command(1)
	check(again.begins_with("Grazer %d " % cid), "the wounded one again: %s" % again)
	srv.free()


func test_lure_is_a_hidden_dev_command() -> void:
	check(ChatCommands.is_lure("/lure"), "ChatCommands.is_lure('/lure')")
	check(ChatCommands.is_lure("/LURE now"), "ChatCommands.is_lure('/LURE now')")
	check(not ChatCommands.is_lure("lure"), "not ChatCommands.is_lure('lure')")
	check(not ChatCommands.HELP.contains("lure"), "never listed")
