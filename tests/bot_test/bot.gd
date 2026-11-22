extends Node
## A simulated player for the bot test. Logs in, walks around, chats, disconnects,
## reconnects, checks its saved position came back, and writes a JSON verdict.
##
## Args: --bot --name=bot_1 --password=... --address=127.0.0.1:7777 --transport=enet
##       --duration=180 --result=/path/result.json --expect-peers=7

var net: Node
var bot_name := "bot_1"
var password := "botpassword"
var host := "127.0.0.1"
var port := GameConfig.DEFAULT_PORT
var transport := "enet"
var duration := 180.0
var result_path := ""
var expect_peers := 0

var phase := "connecting"
var elapsed := 0.0
var my_id := 0
var my_pos := Vector3.ZERO
var have_pos := false
var seq := 0
var move := Vector2.ZERO
var yaw := 0.0
var rng := RandomNumberGenerator.new()
var next_chat := 0.0
var next_turn := 0.0
var disconnect_at := 0.0
var reconnect_at := 0.0
var last_snapshot_tick := -1

var failures: PackedStringArray = []
var stats := {
	"logins": 0, "snapshots": 0, "chats_sent": 0, "chats_from_others": 0,
	"max_peers_seen": 0, "distance_walked": 0.0, "position_restored": false,
	"spawn_before_disconnect": [], "spawn_after_reconnect": [],
}
var _pos_at_disconnect := Vector3.ZERO
var _others := {}
var _phase_started := 0.0


func start(p_net: Node, args: Dictionary) -> void:
	net = p_net
	bot_name = str(args.get("name", bot_name))
	password = str(args.get("password", password))
	var parsed := Transport.parse_address(str(args.get("address", "127.0.0.1:%d" % GameConfig.DEFAULT_PORT)), str(args.get("transport", "enet")))
	transport = parsed[0]
	host = parsed[1]
	port = parsed[2]
	duration = float(args.get("duration", "180"))
	result_path = str(args.get("result", ""))
	expect_peers = int(args.get("expect-peers", "0"))
	rng.seed = hash(bot_name)
	disconnect_at = duration * rng.randf_range(0.35, 0.55)
	next_chat = rng.randf_range(3.0, 8.0)

	net.login_result.connect(_on_login_result)
	net.snapshot.connect(_on_snapshot)
	net.chat_message.connect(_on_chat)
	net.player_joined.connect(func(id, _n, _s): _others[id] = true)
	net.player_left.connect(func(id): _others.erase(id))
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(func(): _fail("connection failed in phase " + phase))
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	_connect()


func _connect() -> void:
	var made := Transport.create_client(transport, host, port)
	if made[1] != OK:
		_fail("could not create client: " + error_string(made[1]))
		_finish()
		return
	multiplayer.multiplayer_peer = made[0]
	_phase_started = elapsed


func _on_connected() -> void:
	net.c2s_login.rpc_id(1, GameConfig.PROTOCOL_VERSION, bot_name, password)


func _on_login_result(ok: bool, message: String, id: int, character: Dictionary) -> void:
	if not ok:
		_fail("login rejected: " + message)
		_finish()
		return
	stats.logins += 1
	my_id = id
	var p := Vector3(character.x, character.y, character.z)
	if phase == "reconnecting":
		stats.spawn_after_reconnect = [p.x, p.y, p.z]
		if p.distance_to(_pos_at_disconnect) > 0.05:
			_fail("position not restored: had %s at disconnect, got %s" % [_pos_at_disconnect, p])
		else:
			stats.position_restored = true
	my_pos = p
	have_pos = true
	phase = "playing_2" if phase == "reconnecting" else "playing_1"
	_phase_started = elapsed


func _on_snapshot(t: int, entries: Array) -> void:
	if t <= last_snapshot_tick:
		return
	last_snapshot_tick = t
	stats.snapshots += 1
	var peers := 0
	var i := 0
	while i + 4 < entries.size():
		var id: int = entries[i]
		var p := Vector3(entries[i + 1], entries[i + 2], entries[i + 3])
		if not (is_finite(p.x) and is_finite(p.y) and is_finite(p.z)):
			_fail("non-finite position for peer %d" % id)
		elif absf(p.x) > GameConfig.WORLD_HALF_SIZE + 0.01 or absf(p.z) > GameConfig.WORLD_HALF_SIZE + 0.01:
			_fail("peer %d outside world: %s" % [id, p])
		elif absf(p.y - Terrain.height(p.x, p.z)) > 0.01:
			_fail("desync: peer %d at height %.3f but terrain says %.3f" % [id, p.y, Terrain.height(p.x, p.z)])
		if id == my_id:
			if have_pos:
				stats.distance_walked += Vector2(p.x - my_pos.x, p.z - my_pos.z).length()
			my_pos = p
		else:
			peers += 1
		i += 5
	stats.max_peers_seen = maxi(stats.max_peers_seen, peers)


func _on_chat(from_name: String, text: String) -> void:
	if from_name != bot_name and text.begins_with("hello from "):
		stats.chats_from_others += 1


func _on_server_disconnected() -> void:
	if phase != "done":
		_fail("server disconnected us in phase " + phase)
		_finish()


func _process(delta: float) -> void:
	elapsed += delta
	if phase == "done":
		return
	if elapsed > duration + 60.0:
		_fail("bot timed out in phase " + phase)
		_finish()
		return
	if (phase == "connecting" or phase == "reconnecting") and elapsed - _phase_started > 20.0:
		_fail("timed out waiting to log in (%s)" % phase)
		_finish()
		return
	match phase:
		"playing_1":
			_play(delta)
			if elapsed >= disconnect_at:
				_stop_and("pausing_1")
		"pausing_1":
			_send_input()
			if elapsed - _phase_started > 1.5:
				_pos_at_disconnect = my_pos
				stats.spawn_before_disconnect = [my_pos.x, my_pos.y, my_pos.z]
				multiplayer.multiplayer_peer.close()
				multiplayer.multiplayer_peer = null
				phase = "offline"
				_phase_started = elapsed
				reconnect_at = elapsed + rng.randf_range(2.0, 5.0)
		"offline":
			if elapsed >= reconnect_at:
				phase = "reconnecting"
				_connect()
		"playing_2":
			_play(delta)
			if elapsed >= duration:
				_stop_and("pausing_2")
		"pausing_2":
			_send_input()
			if elapsed - _phase_started > 1.5:
				stats.final_position = [my_pos.x, my_pos.y, my_pos.z]
				_finish()


func _stop_and(next_phase: String) -> void:
	move = Vector2.ZERO
	phase = next_phase
	_phase_started = elapsed


func _play(_delta: float) -> void:
	if elapsed >= next_turn:
		next_turn = elapsed + rng.randf_range(1.0, 4.0)
		var a := rng.randf() * TAU
		move = Vector2(cos(a), sin(a)) * rng.randf_range(0.3, 1.0)
		# Drift back toward spawn so bots stay near each other.
		if Vector2(my_pos.x, my_pos.z).length() > 60.0:
			move = -Vector2(my_pos.x, my_pos.z).normalized()
		yaw = atan2(move.x, move.y)
	_send_input()
	if elapsed >= next_chat:
		next_chat = elapsed + rng.randf_range(8.0, 20.0)
		stats.chats_sent += 1
		net.c2s_chat.rpc_id(1, "hello from %s #%d" % [bot_name, stats.chats_sent])


func _send_input() -> void:
	if multiplayer.multiplayer_peer == null:
		return
	seq += 1
	net.c2s_input.rpc_id(1, seq, move, yaw)


func _fail(msg: String) -> void:
	failures.append(msg)
	printerr("[bot %s] FAIL: %s" % [bot_name, msg])


func _finish() -> void:
	if phase == "done":
		return
	var final_phase := phase
	phase = "done"
	if stats.logins < 2:
		_fail("expected 2 logins (initial + reconnect), got %d (ended in phase %s)" % [stats.logins, final_phase])
	if stats.snapshots < 10:
		_fail("received only %d snapshots" % stats.snapshots)
	if stats.distance_walked < 5.0:
		_fail("barely moved: %.2f m" % stats.distance_walked)
	if stats.chats_sent > 0 and expect_peers > 0 and stats.chats_from_others == 0:
		_fail("never received chat from other bots")
	if expect_peers > 0 and stats.max_peers_seen < expect_peers:
		_fail("saw at most %d other players, expected %d" % [stats.max_peers_seen, expect_peers])
	var verdict := {"name": bot_name, "ok": failures.is_empty(), "failures": failures, "stats": stats}
	if result_path != "":
		var f := FileAccess.open(result_path, FileAccess.WRITE)
		f.store_string(JSON.stringify(verdict, "  "))
		f.close()
	print("[bot %s] finished: %s" % [bot_name, "ok" if failures.is_empty() else "FAILED"])
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	get_tree().quit(0 if failures.is_empty() else 1)
