extends TestCase
## Protocol v5 (closes Milestone 0, owner direction 1 "chat is for talking"): s2c_roster for
## the client's players panel (replaces /who) and "Return to Spawn Meadow" for the Esc menu
## (c2s_unstuck / s2c_unstuck_result). All three RPCs live on Net/Play, so Net's own RPC
## numbering (and every old client's "please update") is unchanged. Facing yaw was already in
## c2s_input since v1 and the server already faces you where you send it (see the devlog).

const ServerScript := preload("res://server/server.gd")
const NetScript := preload("res://shared/net.gd")
const ProtocolCompat := preload("res://tests/unit/test_qa_protocol_compat.gd")

## A store that accepts every save, so a disconnect can be tested without a database.
class SavesEverything extends PlayerStore:
	func save_character(_ch: Dictionary) -> bool:
		return true


const V5_RPCS := ["c2s_unstuck", "s2c_roster", "s2c_unstuck_result"]


func _server(players: Dictionary) -> Node:
	var srv: Node = ServerScript.new()
	srv.test_now = 100.0
	for id in players:
		var ch := CharacterData.normalize({"name": players[id]})
		ch.x = 40.0
		ch.z = 40.0
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


func test_v5_rpcs_live_on_play_and_v4_is_frozen() -> void:
	check(GameConfig.PROTOCOL_VERSION >= 5, "v5 or later")
	var play := ProtocolCompat.rpc_names("res://tests/protocol/net_play_v5.gd") # as v5 shipped
	var v4_play := ProtocolCompat.rpc_names("res://tests/protocol/net_play_v4.gd")
	var expected := Array(v4_play) + V5_RPCS
	expected.sort()
	check_eq(Array(play), expected, "v5 Play = v4 Play + roster and unstuck")
	check_eq(ProtocolCompat.rpc_names("res://tests/protocol/net_v5.gd"), ProtocolCompat.rpc_names("res://tests/protocol/net_v4.gd"),
		"Net's own RPCs unchanged since v4")
	check(FileAccess.file_exists("res://tests/protocol/net_v4.gd"), "net_v4.gd frozen for the bump")


func test_v5_rpcs_reemit_on_net() -> void:
	var net: Node = NetScript.new()
	net._ready()
	var got := []
	net.roster_changed.connect(func(e): got.append(["roster", e]))
	net.unstuck_requested.connect(func(p): got.append(["ask", p]))
	net.unstuck_result.connect(func(ok, t, w): got.append(["result", ok, t, w]))
	net.play.s2c_roster([{"id": 2, "name": "Ash", "level": 4}])
	net.play.c2s_unstuck()
	net.play.s2c_unstuck_result(true, "Back in Spawn Meadow.", 60.0)
	check_eq(got, [["roster", [{"id": 2, "name": "Ash", "level": 4}]], ["ask", 0],
		["result", true, "Back in Spawn Meadow.", 60.0]])
	net.free()


func test_roster_lists_everyone_sorted_by_name() -> void:
	var srv := _server({3: "mira", 7: "Bram", 9: "Cole"})
	srv.sessions[7].character.skills = {"felling": 1700, "quarrying": 150}
	srv.sessions[10] = {"logged_in": false, "character": {}}
	var r: Array = srv.roster()
	check_eq(r.map(func(e): return e.name), ["Bram", "Cole", "mira"], "sorted by name, any case; not-logged-in left out")
	check_eq(r[0], {"id": 7, "name": "Bram"}, "just who they are: no levels, old XP or not")
	srv.free()


func test_roster_goes_to_everyone_once_per_tick() -> void:
	var srv := _server({1: "Ash", 2: "Bram"})
	srv._roster_dirty = true
	srv._roster_dirty = true
	srv._tick()
	srv._tick()
	check_eq(_sent(srv, 1, "s2c_roster").size(), 1, "one roster to Ash")
	check_eq(_sent(srv, 2, "s2c_roster").size(), 1, "one roster to Bram")
	check_eq((_sent(srv, 1, "s2c_roster")[0][0] as Array).size(), 2)
	srv.free()


func test_disconnect_sends_the_roster_without_them() -> void:
	var srv := _server({1: "Ash", 2: "Bram"})
	srv.store = SavesEverything.new()
	srv._on_peer_disconnected(2)
	srv._tick()
	var got := _sent(srv, 1, "s2c_roster")
	check_eq(got.size(), 1)
	check_eq((got[0][0] as Array).map(func(e): return e.name), ["Ash"])
	srv.free()


func test_unstuck_takes_you_home_then_cools_down() -> void:
	var srv := _server({1: "Ash"})
	var r: Dictionary = srv.unstuck_request(1)
	check(bool(r.ok), "far from spawn: ok")
	var p := CharacterData.position(srv.sessions[1].character)
	var flat := Vector2(p.x, p.z)
	check(flat.length() <= 3.01, "within 3 m of spawn, got %s" % p)
	check(flat.distance_to(Crafting.workbench_xz()) > 3.0, "not on the workbench, got %s" % p)
	check_near(p.y, Terrain.height(p.x, p.z), 0.001, "standing on the ground")
	check_eq(_sent(srv, 1, "s2c_unstuck_result"), [[true, "Back in Spawn Meadow.", GameConfig.UNSTUCK_COOLDOWN]])
	# Walk away and ask again too soon.
	srv.sessions[1].character.x = 50.0
	srv.test_now += 20.0
	r = srv.unstuck_request(1)
	check(not bool(r.ok), "too soon")
	check_eq(str(r.text), "You can return to Spawn Meadow again in 40 s.")
	check_eq(srv.sessions[1].character.x, 50.0, "stayed put")
	srv.test_now += 41.0
	check(bool(srv.unstuck_request(1).ok), "after the cooldown it works again")
	srv.free()


func test_unstuck_near_spawn_says_so_and_keeps_the_cooldown() -> void:
	var srv := _server({1: "Ash"})
	srv.sessions[1].character.x = 5.0
	srv.sessions[1].character.z = 5.0
	var r: Dictionary = srv.unstuck_request(1)
	check(not bool(r.ok), "near spawn: refused")
	check_eq(str(r.text), "You're already in Spawn Meadow.")
	check_eq(float(r.wait), 0.0)
	srv.sessions[1].character.x = 60.0
	check(bool(srv.unstuck_request(1).ok), "the refusal didn't start the cooldown")
	srv.free()


func test_unstuck_cancels_a_running_gather() -> void:
	var node: Dictionary = {}
	for n in ResourceNodes.all():
		if n.kind == "pine" and Vector2(n.pos.x, n.pos.z).length() > GameConfig.UNSTUCK_NEAR:
			node = n
			break
	check(not node.is_empty(), "a pine away from spawn")
	var srv := _server({1: "Ash"})
	srv.sessions[1].character.x = node.pos.x
	srv.sessions[1].character.z = node.pos.z
	srv.gather_request(1, node.id)
	check(GatherChannel.is_active(srv.sessions[1].channel), "gathering")
	srv.unstuck_request(1)
	check(not GatherChannel.is_active(srv.sessions[1].channel), "the gather stopped")
	var ends := _sent(srv, 1, "s2c_gather_end")
	check(ends.size() >= 1 and ends[-1][2] == "moved", "ended as moved: %s" % [ends])
	srv.free()


func test_unstuck_spots_spread_and_stay_off_the_bench() -> void:
	var seen := {}
	for id in range(1, 40):
		var p: Vector3 = ServerScript.unstuck_spot(id)
		check(Vector2(p.x, p.z).distance_to(Crafting.workbench_xz()) > 3.0, "spot %s clear of the bench" % p)
		seen[Vector2i(roundi(p.x * 10), roundi(p.z * 10))] = true
	check(seen.size() >= 5, "a crowd lands on several spots, got %d" % seen.size())


func test_unstuck_ignores_logged_out_peers() -> void:
	var srv := _server({})
	check_eq(srv.unstuck_request(4), {})
	srv.sessions[5] = {"logged_in": false, "character": {}}
	check_eq(srv.unstuck_request(5), {})
	check_eq(srv.test_outbox, [])
	srv.free()
