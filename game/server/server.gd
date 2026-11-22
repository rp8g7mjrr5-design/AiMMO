extends Node
## Authoritative dedicated server. Clients send movement input and chat; the server owns
## every position, saves characters, and broadcasts snapshots at TICK_RATE.

var net: Node
var store: PlayerStore
var transport := "enet"
var port := GameConfig.DEFAULT_PORT

## peer_id -> session Dictionary
var sessions := {}
var tick := 0
var _accum := 0.0
var _autosave_timer := 0.0
var _stop_file := ""
var _stopping := false
var _stop_check := 0.0
var _clock_sync_timer := 0.0
## Shifts the world clock, for testing and screenshots (e.g. --clock-offset=1200 jumps half a
## day). Leave it at 0 in production so every server restart keeps the same time.
var clock_offset := 0.0


func start(p_net: Node, args: Dictionary) -> void:
	net = p_net
	transport = CliArgs.setting(args, "transport", "AIMMO_TRANSPORT", "enet")
	port = CliArgs.setting(args, "port", "AIMMO_PORT", OS.get_environment("PORT") if OS.get_environment("PORT") != "" else str(GameConfig.DEFAULT_PORT)).to_int()
	_stop_file = CliArgs.setting(args, "stop-file", "AIMMO_STOP_FILE", "")
	clock_offset = CliArgs.setting(args, "clock-offset", "AIMMO_CLOCK_OFFSET", "0").to_float()
	var data_dir := CliArgs.setting(args, "data-dir", "AIMMO_DATA_DIR", OS.get_user_data_dir())

	Engine.max_fps = 60
	store = PlayerStore.create_from_env(data_dir)
	if store is PgStore:
		(store as PgStore).migrations_dir = Migrator.default_dir()
	if not store.open():
		push_error("[server] storage failed to open: " + store.last_error)
		get_tree().quit(2)
		return
	print("[server] storage ready: ", "postgres" if store is PgStore else "json (dev only)")

	var made := Transport.create_server(transport, port)
	if made[1] != OK:
		push_error("[server] could not listen on port %d (%s): %s" % [port, transport, error_string(made[1])])
		get_tree().quit(3)
		return
	multiplayer.multiplayer_peer = made[0]
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	net.login_requested.connect(_on_login)
	net.input_received.connect(_on_input)
	net.chat_requested.connect(_on_chat)
	get_tree().set_auto_accept_quit(false)
	print("[server] listening on port %d via %s, protocol v%d" % [port, transport, GameConfig.PROTOCOL_VERSION])
	print("[server] world clock: ", WorldClock.describe(world_seconds()))


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		shutdown()


func _process(delta: float) -> void:
	if store == null or _stopping:
		return
	_accum += delta
	var steps := 0
	while _accum >= GameConfig.TICK_DT and steps < 5:
		_accum -= GameConfig.TICK_DT
		steps += 1
		_tick()
	if _accum > GameConfig.TICK_DT * 5:
		_accum = 0.0 # fell far behind; drop time rather than spiral
	_autosave_timer += delta
	if _autosave_timer >= GameConfig.AUTOSAVE_SECONDS:
		_autosave_timer = 0.0
		_save_all()
	_clock_sync_timer += delta
	if _clock_sync_timer >= GameConfig.WORLD_TIME_SYNC_SECONDS:
		_clock_sync_timer = 0.0
		_broadcast_world_time()
	_stop_check += delta
	if _stop_file != "" and _stop_check >= 0.5:
		_stop_check = 0.0
		if FileAccess.file_exists(_stop_file):
			shutdown()


func _tick() -> void:
	tick += 1
	var entries: Array = []
	for id in sessions:
		var s: Dictionary = sessions[id]
		if not s.logged_in:
			continue
		var ch: Dictionary = s.character
		var p := Movement.step(CharacterData.position(ch), s.move, GameConfig.TICK_DT)
		ch.x = p.x
		ch.y = p.y
		ch.z = p.z
		ch.yaw = s.yaw
		entries.append_array([id, p.x, p.y, p.z, s.yaw])
	if entries.is_empty():
		return
	for id in sessions:
		if sessions[id].logged_in:
			_send(id, "s2c_snapshot", [tick, entries])


func _on_peer_connected(id: int) -> void:
	sessions[id] = {"logged_in": false, "character": {}, "move": Vector2.ZERO, "yaw": 0.0, "seq": -1, "last_chat": -1000.0, "login_attempts": 0}
	print("[server] peer %d connected" % id)


func _on_peer_disconnected(id: int) -> void:
	if not sessions.has(id):
		return
	var s: Dictionary = sessions[id]
	sessions.erase(id)
	if s.logged_in:
		if not store.save_character(s.character):
			push_error("[server] failed to save %s on disconnect: %s" % [s.character.name, store.last_error])
		for other in sessions:
			if sessions[other].logged_in:
				_send(other, "s2c_player_left", [id])
				_send(other, "s2c_system", ["%s has left." % s.character.name])
		print("[server] %s (peer %d) left, saved at %s" % [s.character.name, id, CharacterData.position(s.character)])
	else:
		print("[server] peer %d disconnected before logging in" % id)


func _on_login(id: int, protocol: int, username: String, password: String) -> void:
	if not sessions.has(id):
		return
	var s: Dictionary = sessions[id]
	if s.logged_in:
		return
	s.login_attempts += 1
	if s.login_attempts > 5:
		_reject(id, "Too many attempts. Reconnect to try again.")
		multiplayer.multiplayer_peer.disconnect_peer(id)
		return
	if protocol != GameConfig.PROTOCOL_VERSION:
		_reject(id, "Your game is out of date. Download the latest client from the Releases page.")
		return
	var name_err := Validation.check_name(username)
	if name_err != "":
		_reject(id, name_err)
		return
	var pw_err := Validation.check_password(password)
	if pw_err != "":
		_reject(id, pw_err)
		return
	var lc := Validation.canonical(username)
	for other in sessions:
		if sessions[other].logged_in and Validation.canonical(sessions[other].character.name) == lc:
			_reject(id, "That character is already online.")
			return

	var account := store.find_account(lc)
	var is_new := false
	if account.is_empty():
		account = store.create_account(username, lc, CryptoUtil.hash_password(password))
		if account.is_empty():
			_reject(id, "Could not create that account. Try another name.")
			if store.last_error != "":
				push_error("[server] create_account failed: " + store.last_error)
			return
		is_new = true
	elif not CryptoUtil.verify_password(password, account.password_hash):
		_reject(id, "Wrong password for that name.")
		return

	var ch := store.load_or_create_character(account)
	if ch.is_empty():
		push_error("[server] could not load character for %s: %s" % [lc, store.last_error])
		_reject(id, "The server could not load your character. Please try again soon.")
		return
	store.touch_login(account.id)
	if not sessions.has(id):
		return # disconnected while we were talking to the database
	s.logged_in = true
	s.character = ch
	s.yaw = ch.yaw
	_send(id, "s2c_login_result", [true, "Welcome to Ashgrove, %s!" % ch.name if is_new else "Welcome back, %s." % ch.name, id, ch])
	_send(id, "s2c_world_time", [world_seconds()])
	# Tell the newcomer about everyone already here, and everyone about the newcomer.
	for other in sessions:
		var o: Dictionary = sessions[other]
		if other == id or not o.logged_in:
			continue
		_send(id, "s2c_player_joined", [other, o.character.name, o.character.appearance_seed])
		_send(other, "s2c_player_joined", [id, ch.name, ch.appearance_seed])
		_send(other, "s2c_system", ["%s has arrived." % ch.name])
	print("[server] %s logged in as peer %d (%s) at %s" % [ch.name, id, "new" if is_new else "returning", CharacterData.position(ch)])


## The authoritative world clock in world seconds (see WorldClock).
func world_seconds() -> float:
	return WorldClock.now_seconds(clock_offset)


func _broadcast_world_time() -> void:
	var t := world_seconds()
	for id in sessions:
		if sessions[id].logged_in:
			_send(id, "s2c_world_time", [t])


func _reject(id: int, msg: String) -> void:
	_send(id, "s2c_login_result", [false, msg, id, {}])


func _on_input(id: int, seq: int, move: Vector2, yaw: float) -> void:
	if not sessions.has(id):
		return
	var s: Dictionary = sessions[id]
	if not s.logged_in or seq <= s.seq:
		return
	s.seq = seq
	if not is_finite(move.x) or not is_finite(move.y):
		move = Vector2.ZERO
	s.move = move.limit_length(1.0)
	s.yaw = wrapf(yaw, -PI, PI) if is_finite(yaw) else s.yaw


func _on_chat(id: int, text: String) -> void:
	if not sessions.has(id):
		return
	var s: Dictionary = sessions[id]
	if not s.logged_in:
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now - s.last_chat < GameConfig.CHAT_COOLDOWN:
		return
	var clean := Validation.clean_chat(text)
	if clean == "":
		return
	s.last_chat = now
	print("[chat] %s: %s" % [s.character.name, clean])
	for other in sessions:
		if sessions[other].logged_in:
			_send(other, "s2c_chat", [s.character.name, clean])


## Sends an RPC only if the peer is still fully connected. A peer that has started
## disconnecting but whose disconnect signal has not fired yet has no channels left.
func _send(id: int, method: StringName, args: Array) -> void:
	if not _is_live(id):
		return
	Callable(net, "rpc_id").callv([id, method] + args)


func _is_live(id: int) -> bool:
	var mp := multiplayer.multiplayer_peer
	if mp is ENetMultiplayerPeer:
		var p: ENetPacketPeer = (mp as ENetMultiplayerPeer).get_peer(id)
		return p != null and p.get_state() == ENetPacketPeer.STATE_CONNECTED
	if mp is WebSocketMultiplayerPeer:
		var w: WebSocketPeer = (mp as WebSocketMultiplayerPeer).get_peer(id)
		return w != null and w.get_ready_state() == WebSocketPeer.STATE_OPEN
	return mp != null


func _save_all() -> void:
	var n := 0
	for id in sessions:
		var s: Dictionary = sessions[id]
		if s.logged_in:
			if store.save_character(s.character):
				n += 1
			else:
				push_error("[server] autosave failed for %s: %s" % [s.character.name, store.last_error])
	if n > 0:
		print("[server] autosaved %d characters" % n)


func shutdown() -> void:
	if _stopping:
		return
	_stopping = true
	print("[server] shutting down, saving everyone")
	_save_all()
	store.close()
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	print("[server] stopped cleanly")
	get_tree().quit(0)
