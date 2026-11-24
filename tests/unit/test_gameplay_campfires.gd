extends TestCase
## Placed campfires (Phase 2 build-ahead): a crafted campfire is set down in front of you on
## dry ground, clear of nodes, the bench and other fires, burns about four world hours, goes
## out on its own, and the Gloam walkers keep their distance from it. Server side only for now
## (/place and /kindle dev commands; s2c_campfires waits for a bump).

const ServerScript := preload("res://server/server.gd")
const DT := 0.05


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


## Somewhere a fire can go: standing here facing yaw 0 puts it on good ground. Searches outward
## from `from` (default: just outside the bench's corner of Spawn Meadow).
func _open_spot(state: Dictionary = {}, from := Vector3(-5, 0, 4), owner := "tester") -> Vector3:
	var st := state if not state.is_empty() else Campfires.new_state()
	for r in range(0, 200, 2):
		for a in 12:
			var ang := TAU * a / 12.0
			var x := from.x + cos(ang) * r
			var z := from.z + sin(ang) * r
			var at := Campfires.spot_in_front(Vector3(x, 0, z), 0.0)
			if Campfires.check_spot(st, owner, at) == "" and Gloam.good_ground(x, z) and Gloam.good_ground(x + 10, z):
				return Vector3(x, Terrain.height(x, z), z)
			if r == 0:
				break
	return from


func _server(players: Dictionary) -> Node:
	var srv: Node = ServerScript.new()
	srv.test_now = 100.0
	srv.dev_commands = true
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


func _chat(srv: Node, id: int, line: String) -> String:
	srv.sessions[id].last_command = -1000.0
	var before := _sent(srv, id, "s2c_system").size()
	srv._on_chat(id, line)
	var lines := _sent(srv, id, "s2c_system")
	return str(lines[lines.size() - 1][0]) if lines.size() > before else ""


func test_numbers_hold_together() -> void:
	var secs := Campfires.burn_seconds()
	check(secs >= 5.0 * 60.0 and secs <= 10.0 * 60.0, "a fire burns a few real minutes: %.0f s" % secs)
	check_near(secs, WorldClock.DAY_SECONDS / 6.0, 0.01, "four world hours")
	check(Campfires.WARM_RADIUS < Gloam.FIRE_KEEPAWAY, "where you stand warm, a walker won't come")
	check(Campfires.PLACE_DISTANCE < Campfires.WARM_RADIUS, "you are at the fire you just set down")
	check(Campfires.MIN_SPACING <= Gloam.FIRE_KEEPAWAY, "a ring of fires can close a gap")
	check(Inventory.is_item(Campfires.ITEM), "a campfire is a real pack item")
	check(Crafting.RECIPES.has(Campfires.ITEM), "and players can make one")


func test_set_down_in_front_on_the_ground() -> void:
	var st := Campfires.new_state()
	var at := _open_spot(st)
	var yaw := 0.7
	var r := Campfires.place(st, "Ash", at, yaw, 10.0)
	check(r.ok, "placed: %s" % [r])
	var f: Dictionary = r.fire
	check_near(_flat(f.pos, at), Campfires.PLACE_DISTANCE, 0.001, "PLACE_DISTANCE in front")
	check_near(f.pos.x - at.x, sin(yaw) * Campfires.PLACE_DISTANCE, 0.001, "forward is (sin yaw, cos yaw)")
	check_near(f.pos.y, Terrain.height(f.pos.x, f.pos.z), 0.001, "on the ground")
	check_eq(str(f.owner), "ash", "owner kept lower-case")
	check_eq(Campfires.count(st), 1)
	check_eq(Campfires.positions(st), [f.pos])
	check(Campfires.is_warm(st, at), "standing where you set it down is warm")
	check(not Campfires.is_warm(st, at + Vector3(20, 0, 0)), "20 m off is not")


func test_refusals_change_nothing() -> void:
	var st := Campfires.new_state()
	var at := _open_spot(st)
	check(Campfires.place(st, "a", at, 0.0, 0.0).ok, "Campfires.place(st, 'a', at, 0.0, 0.0).ok")
	var r := Campfires.place(st, "b", at, 0.0, 1.0)
	check_eq(r.reason, "crowded", "a second fire on the same spot")
	check_eq(Campfires.count(st), 1)
	check_eq(int(st.next_id), 2, "a refusal doesn't use up an id")
	# The bench: stand so the fire would land on it.
	var bench := Crafting.workbench_pos()
	check_eq(Campfires.check_spot(Campfires.new_state(), "a", bench), "bench")
	# A resource node.
	var node: Dictionary = ResourceNodes.nearest(Vector3.ZERO)
	check(not node.is_empty(), "there are nodes")
	check_eq(Campfires.check_spot(Campfires.new_state(), "a", node.pos), "node")
	# The edge of the world.
	var lim := WorldGen.half_size()
	check_eq(Campfires.check_spot(Campfires.new_state(), "a", Vector3(lim - 1.0, 0, 0)), "edge")
	# Water, if this world has any.
	var wet := Vector3.INF
	for x in range(-240, 240, 8):
		for z in range(-240, 240, 8):
			if Terrain.height(x, z) < Terrain.water_level() - 0.5:
				wet = Vector3(x, 0, z)
				break
		if wet != Vector3.INF:
			break
	if wet != Vector3.INF:
		check_eq(Campfires.check_spot(Campfires.new_state(), "a", wet), "water")
	for reason in ["no_item", "water", "edge", "crowded", "node", "bench", "too_many", "world_full", "down"]:
		check(Campfires.refusal_text(reason) != Campfires.refusal_text("unknown"), "%s has its own words" % reason)


func test_caps_per_player_and_world() -> void:
	var st := Campfires.new_state()
	var placed := 0
	var from := _open_spot(st)
	for i in Campfires.MAX_PER_PLAYER:
		var at := _open_spot(st, from + Vector3(0, 0, 4.0 * i), "Ash")
		check(Campfires.place(st, "Ash", at, 0.0, 0.0).ok, "fire %d" % i)
		placed += 1
	var spare := _open_spot(st, from + Vector3(0, 0, 40), "bryn")
	check_eq(Campfires.check_spot(st, "ASH", Campfires.spot_in_front(spare, 0.0)), "too_many", "owner match ignores case")
	check(Campfires.place(st, "Bryn", spare, 0.0, 0.0).ok, "someone else still can")
	check_eq(Campfires.count_owned(st, "ash"), Campfires.MAX_PER_PLAYER)
	# The world cap.
	var full := Campfires.new_state()
	for i in Campfires.MAX_FIRES:
		full.fires[i + 1] = {"id": i + 1, "pos": Vector3(1000 + i * 10, 0, 1000), "owner": "p%d" % i, "lit_at": 0.0, "out_at": 999.0}
	check_eq(Campfires.check_spot(full, "new", Campfires.spot_in_front(from, 0.0)), "world_full")


func test_burns_down_on_its_own() -> void:
	var st := Campfires.new_state()
	var at := _open_spot(st)
	var f: Dictionary = Campfires.place(st, "a", at, 0.0, 50.0).fire
	var w := Campfires.to_wire(st, 50.0)
	check_eq(w.size(), 5, "[id, x, y, z, seconds_left]")
	check_eq(int(w[0]), int(f.id))
	check_near(w[1], f.pos.x, 0.01)
	check_near(w[3], f.pos.z, 0.01)
	check_near(w[4], Campfires.burn_seconds(), 0.01)
	check(Campfires.step(st, 50.0 + Campfires.burn_seconds() - 1.0).is_empty(), "still burning a second before")
	var out := Campfires.step(st, 50.0 + Campfires.burn_seconds())
	check_eq(out.size(), 1, "then it goes out")
	check_eq(Campfires.count(st), 0)
	check_eq(Campfires.to_wire(st, 0.0).size(), 0)
	check(Campfires.describe_fire(f, at, 50.0).begins_with("Campfire %d:" % int(f.id)), "Campfires.describe_fire(f, at, 50.0).begins_with('Campfire %")


func test_chat_command_names() -> void:
	check(ChatCommands.is_place("/place campfire"), "ChatCommands.is_place('/place campfire')")
	check(ChatCommands.is_place("/PLACE"), "ChatCommands.is_place('/PLACE')")
	check(not ChatCommands.is_place("place campfire"), "not ChatCommands.is_place('place campfire')")
	check(ChatCommands.is_kindle("/kindle status"), "ChatCommands.is_kindle('/kindle status')")
	check(not ChatCommands.is_kindle("/kind"), "not ChatCommands.is_kindle('/kind')")
	check(not ChatCommands.HELP.contains("/place"), "hidden from /help")


func test_place_from_the_pack() -> void:
	var at := _open_spot()
	var srv := _server({1: at, 2: at + Vector3(30, 0, 0)})
	var r: Dictionary = srv.place_request(1, "campfire")
	check(not r.ok and r.reason == "no_item", "nothing to set down: %s" % [r])
	check_eq(Campfires.count(srv.campfires), 0)
	srv.give_item(1, "campfire", 2)
	r = srv.place_request(1, "campfire")
	check(r.ok, "set down: %s" % [r])
	check_eq(str(r.text), srv.PLACED_TEXT)
	check_eq(Inventory.count(srv.sessions[1].character.inventory, "campfire"), 1, "one left the pack")
	check_eq(Campfires.count(srv.campfires), 1)
	for pid in [1, 2]:
		var sent := _sent(srv, pid, "s2c_campfires")
		check_eq(sent.size(), 1, "player %d hears of it" % pid)
		check_eq(int(sent[0][0][0]), int(r.fire_id))
	# A refusal (same spot) keeps the second campfire in the pack.
	r = srv.place_request(1, "fire")
	check_eq(r.reason, "crowded")
	check_eq(Inventory.count(srv.sessions[1].character.inventory, "campfire"), 1, "refusal costs nothing")
	check_eq(srv.place_request(1, "torch").reason, "unknown", "only campfires can be placed")
	srv.free()


func test_burned_down_tells_the_owner_and_everyone() -> void:
	var at := _open_spot()
	var srv := _server({1: at, 2: at + Vector3(30, 0, 0)})
	srv.give_item(1, "campfire", 1)
	check(srv.place_request(1, "campfire").ok, "srv.place_request(1, 'campfire').ok")
	srv.test_outbox.clear()
	srv.test_now += Campfires.burn_seconds() - 1.0
	check(srv._tick_campfires(srv.test_now).is_empty(), "not yet")
	srv.test_now += 1.5
	check_eq(srv._tick_campfires(srv.test_now).size(), 1)
	check_eq(Campfires.count(srv.campfires), 0)
	check(_sent(srv, 1, "s2c_system").has([srv.BURNED_DOWN_TEXT]), "the owner is told")
	check(not _sent(srv, 2, "s2c_system").has([srv.BURNED_DOWN_TEXT]), "nobody else is")
	for pid in [1, 2]:
		var sent := _sent(srv, pid, "s2c_campfires")
		check(sent.size() == 1 and (sent[0][0] as PackedFloat32Array).is_empty(), "player %d sees it gone" % pid)
	srv.free()


func test_a_newcomer_hears_of_burning_fires() -> void:
	var at := _open_spot()
	var srv := _server({1: at, 2: at})
	srv._send_world_state(2)
	check(_sent(srv, 2, "s2c_campfires").is_empty(), "no fires, nothing extra on login")
	srv.give_item(1, "campfire", 1)
	check(srv.place_request(1, "campfire").ok, "srv.place_request(1, 'campfire').ok")
	srv.test_outbox.clear()
	srv._send_world_state(2)
	check_eq(_sent(srv, 2, "s2c_campfires").size(), 1, "the fire list comes with the world state")
	srv.free()


func test_dev_commands() -> void:
	var at := _open_spot()
	var srv := _server({1: at})
	check_eq(_chat(srv, 1, "/place campfire"), Campfires.refusal_text("no_item"))
	check_eq(_chat(srv, 1, "/kindle status"), "No campfire is burning near you.")
	var line := _chat(srv, 1, "/kindle")
	check(line.begins_with("A campfire catches in front of you (campfire "), line)
	check_eq(Inventory.count(srv.sessions[1].character.inventory, "campfire"), 0, "/kindle is free")
	check(_chat(srv, 1, "/kindle status").begins_with("Campfire 1: 1.5 m from you, burns "), "status")
	check_eq(_chat(srv, 1, "/kindle"), Campfires.refusal_text("crowded"), "rules still apply")
	srv.dev_commands = false
	check_eq(_chat(srv, 1, "/kindle"), ChatCommands.NOT_FOR_CHAT, "a player server runs none of it")
	check_eq(Campfires.count(srv.campfires), 1)
	srv.free()


## The point of it: stand by your fire and the walker can't get to you.
func test_a_fire_keeps_the_walker_off_you() -> void:
	var at := _open_spot()
	var srv := _server({1: at})
	srv.give_item(1, "campfire", 1)
	check(srv.place_request(1, "campfire").ok, "srv.place_request(1, 'campfire').ok")
	var fire: Vector3 = Campfires.positions(srv.campfires)[0]
	check_eq(srv.gloam_fires(), [fire], "walkers are handed the fire")
	# The walker comes at you from beyond the fire (it was set down 1.5 m in front of you).
	srv.test_outbox.clear()
	var w: Dictionary = Gloam.summon(srv.gloam, 1, at, 0.0, srv.test_now)
	w.pos = Vector3(at.x, 0, at.z + 12.0)
	w.pos.y = Terrain.height(w.pos.x, w.pos.z)
	var hp0 := float(srv.vitals_of(1).hp)
	var closest := INF
	var t := 0.0
	while t < 20.0:
		t += DT
		srv.test_now += DT
		srv._tick_gloam(srv.test_now)
		if Gloam.count(srv.gloam) == 0:
			break
		closest = minf(closest, _flat(srv.gloam.walkers[0].pos, fire))
	check(closest < Gloam.FIRE_KEEPAWAY + 1.5, "it did come for you, up to the ring's edge: %.2f m" % closest)
	check(closest >= Gloam.FIRE_KEEPAWAY - 0.3, "the walker stays out of the fire's ring: %.2f m" % closest)
	check_eq(float(srv.vitals_of(1).hp), hp0, "and never grabs you")
	srv.free()
