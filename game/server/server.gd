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
## Slash commands run only when this is on (ChatCommands.dev_commands_on, set in start()).
## Off, a "/" line gets ChatCommands.NOT_FOR_CHAT and nothing else (chat is for talking).
## Unit tests set it themselves.
var dev_commands := false
## Which resource nodes are used up, and when they come back (see Gathering).
var gathering := Gathering.new_state()
## Unit tests only: when >= 0, now_seconds() returns this instead of the real clock, and with
## no net every message goes to test_outbox instead of the network.
var test_now := -1.0
var test_outbox: Array = []
## Seconds until the next respawn sweep (see _respawn_nodes).
var _respawn_timer := 0.0
## Messages the server already produces but the current protocol has no RPC for yet (see
## _send). Logged once each so the gap is visible, never an error.
var _not_in_protocol := {}
## The grazers outside the meadow (Wildlife): stepped every tick, sent to whoever can see
## them every WILDLIFE_SEND_TICKS ticks (s2c_wildlife, protocol v6).
var wildlife := Wildlife.new_state()
## Ticks between s2c_wildlife sends: 4 at 20 Hz is 5 a second, plenty for animals that the
## client interpolates, at a quarter of the snapshot's bandwidth.
const WILDLIFE_SEND_TICKS := 4
## After the last grazer leaves a player's view, the empty s2c_wildlife goes out this many
## sends in a row (it is unreliable, so one lost packet must not leave a herd frozen on screen).
const WILDLIFE_GOODBYES := 3
## Someone joined, left or levelled up since the last tick: send everyone the new roster
## (once per tick, so eight players logging in at once is eight rosters, not 36).
var _roster_dirty := false


func start(p_net: Node, args: Dictionary) -> void:
	net = p_net
	transport = CliArgs.setting(args, "transport", "AIMMO_TRANSPORT", "enet")
	port = CliArgs.setting(args, "port", "AIMMO_PORT", OS.get_environment("PORT") if OS.get_environment("PORT") != "" else str(GameConfig.DEFAULT_PORT)).to_int()
	_stop_file = CliArgs.setting(args, "stop-file", "AIMMO_STOP_FILE", "")
	clock_offset = CliArgs.setting(args, "clock-offset", "AIMMO_CLOCK_OFFSET", "0").to_float()
	var dev: Array = ChatCommands.dev_commands_on(args)
	dev_commands = dev[0]
	print("[server] dev commands: %s (%s)" % ["on" if dev_commands else "off", dev[1]])
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
	# No client-to-client relay: clients only ever talk to the server, and the relay's own
	# ADD/DEL_PEER notices are sent without our _is_live() guard, so a peer that drops while
	# another joins or leaves logged "Unable to send packet on channel 0, max channels: 0".
	(multiplayer as SceneMultiplayer).server_relay = false
	multiplayer.multiplayer_peer = made[0]
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	net.login_requested.connect(_on_login)
	net.input_received.connect(_on_input)
	net.chat_requested.connect(_on_chat)
	net.gather_start_requested.connect(_on_gather_start)
	net.gather_cancel_requested.connect(_on_gather_cancel)
	net.craft_requested.connect(_on_craft)
	net.unstuck_requested.connect(_on_unstuck)
	net.attack_requested.connect(_on_attack)
	net.look_requested.connect(_on_set_look)
	get_tree().set_auto_accept_quit(false)
	print("[server] listening on port %d via %s, protocol v%d" % [port, transport, GameConfig.PROTOCOL_VERSION])
	print("[server] world clock: ", WorldClock.describe(world_seconds()))
	print("[server] resource nodes: ", ResourceNodes.describe())
	print("[server] wildlife: ", Wildlife.describe())


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
	_respawn_timer -= delta
	if _respawn_timer <= 0.0:
		_respawn_timer = RESPAWN_SWEEP_SECONDS
		_respawn_nodes(now_seconds())
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
	_tick_channels(now_seconds())
	_tick_vitals(now_seconds())
	_tick_swings(now_seconds())
	_tick_wildlife(now_seconds())
	if tick % WILDLIFE_SEND_TICKS == 0:
		_send_wildlife()
	_flush_inventories()
	_flush_roster()
	if entries.is_empty():
		return
	for id in sessions:
		if sessions[id].logged_in:
			_send(id, "s2c_snapshot", [tick, entries, int(sessions[id].seq)])


## Every logged-in player's position, for the grazers to watch.
func player_positions() -> Array:
	var out: Array = []
	for id in sessions:
		if sessions[id].logged_in:
			out.append(CharacterData.position(sessions[id].character))
	return out


## The grazers take one step (Wildlife.step). Returns the ids that bolted.
func _tick_wildlife(now: float) -> Array:
	return Wildlife.step(wildlife, player_positions(), now, GameConfig.TICK_DT, WorldClock.is_night(world_seconds()))


## s2c_wildlife to every logged-in player: the grazers within GameConfig.VIEW_RANGE of them.
## Nothing to players with none in view, except WILDLIFE_GOODBYES empty sends once the last
## one leaves. A new login starts with none seen, so its first send is the herd in view.
func _send_wildlife() -> void:
	for id in sessions:
		var s: Dictionary = sessions[id]
		if not s.logged_in:
			continue
		var entries := Wildlife.to_wire_near(wildlife, CharacterData.position(s.character), GameConfig.VIEW_RANGE)
		if entries.is_empty():
			var bye := int(s.get("wildlife_bye", 0))
			if bye <= 0:
				continue
			s.wildlife_bye = bye - 1
		else:
			s.wildlife_bye = WILDLIFE_GOODBYES
		_send(id, "s2c_wildlife", [entries])


func _on_peer_connected(id: int) -> void:
	sessions[id] = {"logged_in": false, "character": {}, "move": Vector2.ZERO, "yaw": 0.0, "seq": -1, "last_chat": -1000.0, "last_command": -1000.0, "last_too_fast": -1000.0, "last_gather": -1000.0, "channel": {}, "login_attempts": 0, "inv_dirty": false}
	print("[server] peer %d connected" % id)


func _on_peer_disconnected(id: int) -> void:
	if not sessions.has(id):
		return
	var s: Dictionary = sessions[id]
	if GatherChannel.is_active(s.channel):
		gather_cancel(id, "disconnected")
	sessions.erase(id)
	if s.logged_in:
		if not store.save_character(s.character):
			push_error("[server] failed to save %s on disconnect: %s" % [s.character.name, store.last_error])
		for other in sessions:
			if sessions[other].logged_in:
				_send(other, "s2c_player_left", [id])
				_send(other, "s2c_system", ["%s has left." % s.character.name])
		_roster_dirty = true
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
	s.vitals = Vitals.full() # not saved: every login starts at full health
	s.vitals_shown = Vitals.shown(s.vitals)
	_send(id, "s2c_login_result", [true, "Welcome to Ashgrove, %s!" % ch.name if is_new else "Welcome back, %s." % ch.name, id, ch])
	_send(id, "s2c_world_time", [world_seconds()])
	_send_vitals(id) # the bar starts right, before anything changes it
	_send_world_state(id)
	# Tell the newcomer about everyone already here, and everyone about the newcomer.
	for other in sessions:
		var o: Dictionary = sessions[other]
		if other == id or not o.logged_in:
			continue
		_send(id, "s2c_player_joined", [other, o.character.name, o.character.appearance_seed])
		_send(id, "s2c_look", [other, o.character.get("look", {})])
		_send(other, "s2c_player_joined", [id, ch.name, ch.appearance_seed])
		_send(other, "s2c_look", [id, ch.get("look", {})])
		_send(other, "s2c_system", ["%s has arrived." % ch.name])
	_roster_dirty = true
	print("[server] %s logged in as peer %d (%s) at %s" % [ch.name, id, "new" if is_new else "returning", CharacterData.position(ch)])


## Real seconds on the server's monotonic clock (what Gathering and GatherChannel call `now`).
func now_seconds() -> float:
	return test_now if test_now >= 0.0 else Time.get_ticks_msec() / 1000.0


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
	var now := now_seconds()
	var clean := Validation.clean_chat(text)
	if clean == "":
		return
	# Talk and slash commands have separate cooldowns: a press of E (sent as /gather until
	# protocol v3) must not eat the line a player just typed, and the other way round.
	var key := "last_command" if ChatCommands.is_command(clean) else "last_chat"
	if now - float(s.get(key, -1000.0)) < GameConfig.CHAT_COOLDOWN:
		# Never drop a line silently: say so, at most once per cooldown window.
		if now - float(s.get("last_too_fast", -1000.0)) >= GameConfig.CHAT_COOLDOWN:
			s.last_too_fast = now
			_send(id, "s2c_system", [ChatCommands.TOO_FAST])
		return
	s[key] = now
	if ChatCommands.is_command(clean) and not dev_commands:
		# Chat is for talking (owner direction 1): nothing runs, nothing is broadcast.
		_send(id, "s2c_system", [ChatCommands.NOT_FOR_CHAT])
		return
	if ChatCommands.is_gather(clean):
		print("[chat] %s ran %s" % [s.character.name, clean.substr(0, 40)])
		_send(id, "s2c_system", [gather(id, ChatCommands.argument(clean))])
		_send_queued_lines(id)
		return
	if ChatCommands.is_hurt(clean) or ChatCommands.is_vitals(clean):
		print("[chat] %s ran %s" % [s.character.name, clean.substr(0, 40)])
		var reply := vitals_command(id, clean)
		if reply != "": # a knock-down already said what happened
			_send(id, "s2c_system", [reply])
		return
	if ChatCommands.is_lure(clean):
		print("[chat] %s ran %s" % [s.character.name, clean.substr(0, 40)])
		_send(id, "s2c_system", [lure_command(id)])
		return
	if ChatCommands.is_craft(clean):
		print("[chat] %s ran %s" % [s.character.name, clean.substr(0, 40)])
		_send(id, "s2c_system", [craft(id, "" if ChatCommands.name_of(clean) == "recipes" else ChatCommands.argument(clean))])
		_send_queued_lines(id)
		return
	if ChatCommands.is_command(clean):
		var online: Array = []
		for other in sessions:
			if sessions[other].logged_in:
				online.append(sessions[other].character.name)
		var reply := ChatCommands.run(clean, {"world_seconds": world_seconds(), "online": online, "inventory": s.character.inventory, "skills": s.character.get("skills", {})})
		print("[chat] %s ran %s" % [s.character.name, clean.substr(0, 40)])
		_send(id, "s2c_system", [reply])
		return
	print("[chat] %s: %s" % [s.character.name, clean])
	for other in sessions:
		if sessions[other].logged_in:
			_send(other, "s2c_chat", [s.character.name, clean])


## c2s_gather_start(node_id): press E at a node. Only logged-in players; a bad id is
## answered like any refusal (gather_request).
func _on_gather_start(id: int, node_id: int) -> void:
	if not _play_allowed(id, "_last_gather_start"):
		return
	gather_request(id, node_id)


## c2s_gather_cancel(): the player let go. No charge used, no cooldown spent.
func _on_gather_cancel(id: int) -> void:
	if not sessions.has(id) or not sessions[id].logged_in:
		return
	gather_cancel(id, "stopped")


## c2s_unstuck(): the Esc menu's "Return to Spawn Meadow".
func _on_unstuck(id: int) -> void:
	if not _play_allowed(id, "_last_unstuck"):
		return
	unstuck_request(id)


## c2s_craft(recipe_id): the crafting window's Make button.
func _on_craft(id: int, recipe_id: String) -> void:
	if not _play_allowed(id, "_last_craft"):
		return
	craft_request(id, recipe_id)


## c2s_attack(kind, yaw): a swing (protocol v7).
func _on_attack(id: int, kind: String, yaw: float) -> void:
	if not _play_allowed(id, "_last_attack"):
		return
	attack_request(id, kind, yaw)


## c2s_set_look(look): the character-creation window saved a look (protocol v8).
func _on_set_look(id: int, look: Dictionary) -> void:
	if not _play_allowed(id, "_last_look"):
		return
	set_look(id, look)


## Seconds between two saved looks per player: the window sends one per click of Save, so
## this only stops a broken or hostile client from making the server save and broadcast in a
## loop.
const LOOK_GAP := 1.0


## Checks and stores `look` as player `id`'s, saves the character at once (a look is chosen
## rarely and should survive a crash a moment later), and tells everyone online, `id`
## included. Returns "" when saved, else why not (the player gets Appearance.REFUSED).
func set_look(id: int, look: Variant) -> String:
	if not sessions.has(id) or not sessions[id].logged_in:
		return "not logged in"
	var s: Dictionary = sessions[id]
	var now := now_seconds()
	if now - float(s.get("_look_saved", -1000.0)) < LOOK_GAP:
		return "too soon"
	var why := Appearance.check(look)
	if why != "":
		print("[server] refused a look from %s: %s" % [s.character.name, why])
		_send(id, "s2c_system", [Appearance.REFUSED])
		return why
	s._look_saved = now
	s.character.look = Appearance.normalize(look)
	if store != null and not store.save_character(s.character):
		push_error("[server] failed to save %s's look: %s" % [s.character.name, store.last_error])
	for other in sessions:
		if sessions[other].logged_in:
			_send(other, "s2c_look", [id, s.character.look])
	return ""


## Requests that make the server answer (gather start, craft; gather start also tells
## everyone in view) are taken at most once every PLAY_REQUEST_GAP per player and kind, and
## the rest are dropped silently, so a flooding client can't make the server spam back. A
## real key press or button click is never that fast.
const PLAY_REQUEST_GAP := 0.1


func _play_allowed(id: int, key: String) -> bool:
	if not sessions.has(id) or not sessions[id].logged_in:
		return false
	var s: Dictionary = sessions[id]
	var now := now_seconds()
	if now - float(s.get(key, -1000.0)) < PLAY_REQUEST_GAP:
		return false
	s[key] = now
	return true


## A player gathers from the node they stand at ("/gather", or "/gather pine" for one kind).
## The server checks reach (from its own copy of the position), depletion, night-only
## nodes and the per-player cooldown, then puts the items in the pack via give_item.
## Returns the reply for the player.
func gather(id: int, kind_word: String = "") -> String:
	if not sessions.has(id) or not sessions[id].logged_in:
		return ""
	var s: Dictionary = sessions[id]
	var now := now_seconds()
	var ws := world_seconds()
	_respawn_nodes(now)
	var kind = Gathering.parse_kind(kind_word)
	if kind == null:
		return "Gather what? Try /gather, or /gather ash, pine, stone or sap."
	var skills := skills_of(id)
	if GatherChannel.is_active(s.channel):
		return Gathering.refusal("cooldown", gathering, -1, CharacterData.position(s.character), now, ws, kind, skills)
	var pos := CharacterData.position(s.character)
	var node_id := Gathering.pick_target(gathering, pos, now, ws, kind, skills)
	if node_id < 0:
		return Gathering.refusal("none", gathering, -1, pos, now, ws, kind, skills)
	var node := ResourceNodes.get_by_id(node_id)
	var node_kind := str(node.kind)
	var inv: Dictionary = s.character.inventory
	var why := Gathering.check(gathering, node_id, pos, now, ws, s.last_gather, Gathering.cooldown_for(node_kind, inv), skills)
	if why != "":
		return Gathering.refusal(why, gathering, node_id, pos, now, ws, kind, skills)
	var tool := Gathering.tool_for(node_kind, inv)
	var got := Gathering.take(gathering, node_id, now)
	var added := give_item(id, got.item, Gathering.amount_at(node_id, inv, skill_level(id, Skills.skill_for_kind(node_kind))))
	if added <= 0:
		Gathering.give_back(gathering, node_id)
		return Gathering.refusal("full", gathering, node_id, pos, now, ws, kind, skills)
	s.last_gather = now
	if got.depleted:
		_node_changed(node_id, true, got.respawn)
	award_xp(id, Skills.skill_for_kind(node_kind), Skills.gather_xp(node_kind, has_company(id), int(node.get("tier", 1))))
	return Gathering.success(node_id, added, Inventory.count(s.character.inventory, got.item), got.depleted, tool)


## Starts a timed gather (GatherChannel) on node `node_id` for player `id`: the same checks
## as an instant gather (reach from the server's own position, depletion, night-only; not
## the instant gather's cooldown, the bar itself paces it), plus "busy" if a gather is already running. A full stack still
## starts (it pays XP, not items). Returns {ok, reason, seconds}. On success the channel runs
## in _tick_channels and ends in _gather_event "done" or "cancelled".
## Protocol v3's c2s_gather_start calls this directly.
func gather_start(id: int, node_id: int) -> Dictionary:
	if not sessions.has(id) or not sessions[id].logged_in:
		return {"ok": false, "reason": "offline", "seconds": 0.0}
	var s: Dictionary = sessions[id]
	if GatherChannel.is_active(s.channel):
		return {"ok": false, "reason": "busy", "seconds": 0.0}
	var now := now_seconds()
	_respawn_nodes(now)
	var pos := CharacterData.position(s.character)
	var node := ResourceNodes.get_by_id(node_id)
	var inv: Dictionary = s.character.inventory
	var kind := str(node.get("kind", ""))
	# No gather cooldown here: the channel's own server-timed bar is the pacing, so a player
	# who keeps pressing E goes straight from one gather into the next (no dead time). The
	# cooldown stays for the instant /gather dev command.
	# A full stack doesn't stop the gather either: the work still teaches the skill (see
	# _finish_channel), so a full pack is never a wall on the road to the next level.
	var why := Gathering.check(gathering, node_id, pos, now, world_seconds(), -INF, 0.0, skills_of(id))
	if why != "":
		return {"ok": false, "reason": why, "seconds": 0.0}
	var secs := GatherChannel.seconds_at(node_id, inv, skill_level(id, Skills.skill_for_kind(kind)))
	s.channel = GatherChannel.start(node_id, pos, now, secs)
	_gather_event(id, "begin", node_id, {"seconds": secs})
	return {"ok": true, "reason": "", "seconds": secs}


## Stops player `id`'s running gather: no charge used, no cooldown spent. `reason` is
## "moved", "far", "stopped" (the player asked) or "disconnected".
func gather_cancel(id: int, reason: String = "stopped") -> void:
	if not sessions.has(id):
		return
	var s: Dictionary = sessions[id]
	if not GatherChannel.is_active(s.channel):
		return
	var node_id := int(s.channel.node_id)
	var audience: Array = s.channel.get("audience", [])
	s.channel = {}
	_gather_event(id, "cancelled", node_id, {"reason": reason, "audience": audience})


## Every tick: cancel gathers whose player walked off, finish the ones that are due.
func _tick_channels(now: float) -> void:
	for id in sessions.keys():
		var s: Dictionary = sessions[id]
		if not s.logged_in or not GatherChannel.is_active(s.channel):
			continue
		var pos := CharacterData.position(s.character)
		var why := GatherChannel.cancel_reason(s.channel, pos)
		if why != "":
			gather_cancel(id, why)
		elif GatherChannel.is_due(s.channel, now):
			_finish_channel(id, now)


## A gather ran its full time: re-check the node (someone may have emptied it meanwhile),
## then take a charge and fill the pack. A node that went away ends the gather with nothing
## taken and no cooldown, like a cancel.
func _finish_channel(id: int, now: float) -> void:
	var s: Dictionary = sessions[id]
	var ch: Dictionary = s.channel
	s.channel = {}
	var node_id := int(ch.node_id)
	var pos := CharacterData.position(s.character)
	var ws := world_seconds()
	_respawn_nodes(now)
	var audience: Array = ch.get("audience", [])
	var why := GatherChannel.finish_check(gathering, ch, pos, now, ws, skills_of(id))
	if why != "":
		_gather_event(id, "cancelled", node_id, {"reason": why, "audience": audience})
		return
	var node := ResourceNodes.get_by_id(node_id)
	var kind := str(node.kind)
	var inv: Dictionary = s.character.inventory
	var tool := Gathering.tool_for(kind, inv)
	var got := Gathering.take(gathering, node_id, now)
	# A full stack takes nothing, but the gather still happened: the charge is used and the
	# XP is paid (Milestone 1: the first session must reach level 5, and a fresh feller fills
	# both wood stacks well before that). "done" with count 0: no haul toast, a system line.
	var added := give_item(id, got.item, Gathering.amount_at(node_id, inv, skill_level(id, Skills.skill_for_kind(kind))))
	s.last_gather = now
	if got.depleted:
		_node_changed(node_id, true, got.respawn)
	award_xp(id, Skills.skill_for_kind(kind), Skills.gather_xp(kind, has_company(id), int(node.get("tier", 1))))
	_gather_event(id, "done", node_id, {"item": got.item, "count": added, "tool": tool, "depleted": got.depleted, "audience": audience})


## Where a timed gather's begin / cancelled / done is told to players:
## - everyone in view (players_in_view) gets s2c_gather_begin(peer, node, seconds), and
##   s2c_gather_end(peer, node, "done" | reason) goes to everyone who got the begin (kept in
##   the channel's "audience", even if they walked out of view meanwhile, so nobody is left
##   watching a gather that never ends) plus anyone in view now;
## - the gatherer also gets s2c_gather_result(item, count) on "done" for the haul toast
##   (s2c_inventory follows from give_item), and a system line, which the client's
##   chat feed reads today.
## The s2c_gather_* RPCs are on Net/Play since protocol v3.
func _gather_event(id: int, event: String, node_id: int, info: Dictionary) -> void:
	if not sessions.has(id):
		return
	var s: Dictionary = sessions[id]
	var now := now_seconds()
	var pos := CharacterData.position(s.character)
	var text := ""
	var reason := ""
	match event:
		"begin":
			text = GatherChannel.begin_text(node_id, float(info.seconds))
			var watchers := players_in_view(pos)
			if GatherChannel.is_active(s.channel):
				s.channel.audience = watchers
			for other in watchers:
				_send(other, "s2c_gather_begin", [id, node_id, float(info.seconds)])
		"done":
			reason = "done"
			if int(info.count) > 0:
				text = Gathering.success(node_id, int(info.count), Inventory.count(s.character.inventory, str(info.item)), bool(info.depleted), str(info.tool))
				_send(id, "s2c_gather_result", [str(info.item), int(info.count)])
			else:
				text = Gathering.full_text(node_id, bool(info.depleted))
		"cancelled":
			reason = str(info.reason)
			if reason in ["moved", "far", "stopped"]:
				text = GatherChannel.cancel_text(reason)
			elif reason != "disconnected":
				text = Gathering.refusal(reason, gathering, node_id, pos, now, world_seconds(), "", skills_of(id))
	if reason != "":
		var to := players_in_view(pos)
		for other in info.get("audience", []):
			if not to.has(other) and sessions.has(other) and sessions[other].logged_in:
				to.append(other)
		to.sort()
		for other in to:
			if other != id or reason != "disconnected":
				_send(other, "s2c_gather_end", [id, node_id, reason])
	if text != "":
		_send(id, "s2c_system", [text])
	_send_queued_lines(id)


## What protocol v3's c2s_gather_start(node_id) does: start a timed gather on that node.
## A refusal goes back to the gatherer only, as s2c_gather_end(peer, node, reason) for the
## client's bar and a system line saying why. Returns gather_start's result.
func gather_request(id: int, node_id: int) -> Dictionary:
	if not sessions.has(id) or not sessions[id].logged_in:
		return {"ok": false, "reason": "offline", "seconds": 0.0}
	var r := gather_start(id, node_id)
	if not r.ok:
		var s: Dictionary = sessions[id]
		var pos := CharacterData.position(s.character)
		var reason := "cooldown" if r.reason == "busy" else str(r.reason)
		_send(id, "s2c_gather_end", [id, node_id, str(r.reason)])
		if ResourceNodes.get_by_id(node_id).is_empty():
			_send(id, "s2c_system", ["There is nothing to gather there."])
		else:
			_send(id, "s2c_system", [Gathering.refusal(reason, gathering, node_id, pos, now_seconds(), world_seconds(), "", skills_of(id))])
	return r


## Logged-in players close enough to `pos` to see something happen there (flat distance,
## GameConfig.VIEW_RANGE), sorted by peer id.
func players_in_view(pos: Vector3) -> Array:
	var out: Array = []
	var here := Vector2(pos.x, pos.z)
	for other in sessions:
		var o: Dictionary = sessions[other]
		if not o.logged_in:
			continue
		var p := CharacterData.position(o.character)
		if here.distance_to(Vector2(p.x, p.z)) <= GameConfig.VIEW_RANGE:
			out.append(other)
	out.sort()
	return out


## How often depleted nodes are checked for respawn when nobody is gathering.
const RESPAWN_SWEEP_SECONDS := 1.0


## The only place nodes come back: every gather path and the once-a-second sweep in
## _process call this, so each respawn is announced exactly once. Returns the ids.
func _respawn_nodes(now: float) -> Array:
	var back := Gathering.respawn_due(gathering, now)
	for node_id in back:
		_node_changed(int(node_id), false)
	return back


## A node emptied (`depleted`, back in `respawn` seconds) or came back. Everyone online
## hears s2c_node_state(node, depleted) so their world shows it (NodeProps.set_depleted):
## a node is a landmark, and players far away plan their route by it.
func _node_changed(node_id: int, depleted: bool, respawn: float = 0.0) -> void:
	if depleted:
		print("[gather] node %d depleted for %ds" % [node_id, int(respawn)])
	for other in sessions:
		if sessions[other].logged_in:
			_send(other, "s2c_node_state", [node_id, depleted])


## Right after login: the player's pack and which nodes are empty right now.
func _send_world_state(id: int) -> void:
	_send(id, "s2c_inventory", [Inventory.to_wire(sessions[id].character.inventory)])
	_send(id, "s2c_nodes", [Gathering.depleted_ids(gathering, now_seconds())])
	_send(id, "s2c_skills", [skills_wire(sessions[id].character.get("skills", {}))])
	sessions[id].inv_dirty = false


## What s2c_skills carries: every known skill id -> total XP (0 for untouched skills), so
## the client's skills window always has all four. Unknown ids kept in the save stay there
## but are not sent (the client has no row for them).
static func skills_wire(skills: Variant) -> Dictionary:
	var src := Skills.normalize(skills)
	var out := {}
	for skill in Skills.ORDER:
		out[skill] = Skills.xp_of(src, skill)
	return out


## Sends s2c_inventory once to every player whose pack changed since the last tick, so a
## craft that takes three items and gives one is one message, not four.
func _flush_inventories() -> void:
	for id in sessions:
		var s: Dictionary = sessions[id]
		_send_queued_lines(id)
		if s.logged_in and s.get("inv_dirty", false):
			s.inv_dirty = false
			_send(id, "s2c_inventory", [Inventory.to_wire(s.character.inventory)])


## A player crafts ("/craft axe"), or lists the recipes ("/craft" or "/recipes"). The
## server checks the recipe against its own copy of the pack and position (Crafting.check),
## then uses up the ingredients and hands over the product through take_item/give_item.
## check() already made sure everything is there and there is room, so this can't half-run;
## if it ever does, the ingredients taken so far go back. Returns the reply for the player.
func craft(id: int, recipe_word: String = "") -> String:
	if not sessions.has(id) or not sessions[id].logged_in:
		return ""
	var inv: Dictionary = sessions[id].character.inventory
	var recipe = Crafting.parse_recipe(recipe_word)
	if recipe == null:
		return "Unknown recipe \"%s\". %s" % [recipe_word.substr(0, 20), Crafting.recipes_text(inv)]
	if recipe == "":
		return Crafting.recipes_text(inv)
	return _craft(id, recipe).text


## What protocol v3/v4's c2s_craft(recipe_id) does, for the crafting window: the id must be
## an exact recipe id (no word guessing, that is only for the dev command). Answers with
## s2c_craft_result(recipe_id, ok, text); the pack follows as s2c_inventory on the next
## tick. Returns {ok, reason, text}.
func craft_request(id: int, recipe_id: String) -> Dictionary:
	if not sessions.has(id) or not sessions[id].logged_in:
		return {"ok": false, "reason": "offline", "text": ""}
	var r: Dictionary
	if not Crafting.is_recipe(recipe_id):
		r = {"ok": false, "reason": "unknown", "text": "You don't know how to make that."}
	else:
		r = _craft(id, recipe_id)
	_send(id, "s2c_craft_result", [recipe_id.substr(0, 32), bool(r.ok), str(r.text)])
	_send_queued_lines(id)
	return r


## Crafts a known recipe id for player `id`. Returns {ok, reason, text}.
func _craft(id: int, recipe: String) -> Dictionary:
	var s: Dictionary = sessions[id]
	var inv: Dictionary = s.character.inventory
	var pos := CharacterData.position(s.character)
	var skills := skills_of(id)
	var why := Crafting.check(inv, recipe, pos, skills)
	if why != "":
		return {"ok": false, "reason": why, "text": Crafting.refusal(why, inv, recipe, pos, skills)}
	var r: Dictionary = Crafting.RECIPES[recipe]
	var taken := {}
	for item in r.needs:
		if not take_item(id, item, int(r.needs[item])):
			for back in taken:
				give_item(id, back, int(taken[back]))
			return {"ok": false, "reason": "missing", "text": Crafting.refusal("missing", inv, recipe, pos)}
		taken[item] = int(r.needs[item])
	var made := give_item(id, recipe, int(r.makes))
	if made <= 0:
		for back in taken:
			give_item(id, back, int(taken[back]))
		return {"ok": false, "reason": "full", "text": Crafting.refusal("full", inv, recipe, pos)}
	print("[craft] %s made %d %s" % [s.character.name, made, recipe])
	award_xp(id, "toolcraft", Skills.craft_xp(recipe, has_company(id)))
	return {"ok": true, "reason": "", "text": Crafting.success(recipe, made, inv)}


## Player `id`'s skills (skill id -> XP; empty for a player who is not here, which is level 1
## everywhere). Gathering.check uses it for tier-2 nodes.
func skills_of(id: int) -> Dictionary:
	if not sessions.has(id) or not sessions[id].logged_in:
		return {}
	return sessions[id].character.get("skills", {})


## Player `id`'s level in `skill` (1 for an unknown skill or a player who is not here).
func skill_level(id: int, skill: String) -> int:
	if skill == "" or not sessions.has(id) or not sessions[id].logged_in:
		return 1
	return Skills.level_of(sessions[id].character.get("skills", {}), skill)


## True when another logged-in player is within Skills.TOGETHER_RANGE of player `id`
## (better together: their gathers and crafts pay Skills.TOGETHER_BONUS more XP).
func has_company(id: int) -> bool:
	if not sessions.has(id) or not sessions[id].logged_in:
		return false
	var p := CharacterData.position(sessions[id].character)
	var here := Vector2(p.x, p.z)
	for other in sessions:
		if other == id or not sessions[other].logged_in:
			continue
		var o := CharacterData.position(sessions[other].character)
		if here.distance_to(Vector2(o.x, o.z)) <= Skills.TOGETHER_RANGE:
			return true
	return false


## Server-authoritative XP. Every system that teaches a skill (gathering, crafting, later
## combat) goes through this, never edits CharacterData.skills itself. Saved with the
## character like the pack. A level-up queues a system line ("Felling is now level 2! ...")
## that goes out right after the reply it came with (_send_queued_lines), so it always reads
## after "You gather ...". Protocol v4 queues the same way, in this order: s2c_xp(skill,
## gained, total) to the player, and on a level-up s2c_level_up(skill, level, unlocks) to
## the player, s2c_level_up_seen(peer, skill, level) to everyone else in view, then the line.
## Returns Skills.gain()'s result.
func award_xp(id: int, skill: String, amount: int) -> Dictionary:
	if not sessions.has(id) or not sessions[id].logged_in or skill == "":
		return {}
	var s: Dictionary = sessions[id]
	if typeof(s.character.get("skills")) != TYPE_DICTIONARY:
		s.character.skills = {}
	var r := Skills.gain(s.character.skills, skill, amount)
	if int(r.gained) <= 0:
		return r
	print("[xp] %s +%d %s (%d total, level %d)" % [s.character.name, int(r.gained), skill, int(r.xp), int(r.level)])
	var queued: Array = s.get("queued_lines", [])
	queued.append([id, "s2c_xp", [skill, int(r.gained), int(r.xp)]])
	if int(r.level) > int(r.level_before):
		print("[xp] %s reached %s %d" % [s.character.name, skill, int(r.level)])
		queued.append([id, "s2c_level_up", [skill, int(r.level), Array(r.unlocks).duplicate(true)]])
		for other in players_in_view(CharacterData.position(s.character)):
			if other != id:
				queued.append([other, "s2c_level_up_seen", [id, skill, int(r.level)]])
		queued.append([id, "s2c_system", [Skills.level_up_text(r)]])
		_roster_dirty = true # the players panel shows everyone's level
	s.queued_lines = queued
	return r


## Sends the messages award_xp queued for player `id`'s action, in order: [to, method, args]
## (to is usually `id`; s2c_level_up_seen goes to the players around them).
func _send_queued_lines(id: int) -> void:
	if not sessions.has(id):
		return
	var s: Dictionary = sessions[id]
	var queued: Array = s.get("queued_lines", [])
	if queued.is_empty():
		return
	s.queued_lines = []
	for m in queued:
		if int(m[0]) == id or (sessions.has(int(m[0])) and sessions[int(m[0])].logged_in):
			_send(int(m[0]), StringName(m[1]), m[2])


## Everyone online for the players panel (s2c_roster): [{id, name, level}, ...] sorted by
## name, case-insensitively. level is the total of every skill's level (4 for a new
## character), the one number that says how far along someone is.
func roster() -> Array:
	var out: Array = []
	for id in sessions:
		var s: Dictionary = sessions[id]
		if s.logged_in:
			out.append({"id": int(id), "name": str(s.character.name), "level": total_level(s.character.get("skills", {}))})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.name.nocasecmp_to(b.name) < 0)
	return out


## The sum of every skill's level (unknown ids in an old save don't count).
static func total_level(skills: Variant) -> int:
	var src := Skills.normalize(skills)
	var total := 0
	for skill in Skills.ORDER:
		total += Skills.level_of(src, skill)
	return total


func _flush_roster() -> void:
	if not _roster_dirty:
		return
	_roster_dirty = false
	var r := roster()
	for id in sessions:
		if sessions[id].logged_in:
			_send(id, "s2c_roster", [r])


## "Return to Spawn Meadow" (c2s_unstuck): puts a player who is stuck, lost or far from the
## bench back at spawn, once every GameConfig.UNSTUCK_COOLDOWN seconds. A running gather is
## cancelled ("moved"). Players already near spawn are told so and keep their cooldown.
## Always answers with s2c_unstuck_result. Returns {ok, text, wait}.
func unstuck_request(id: int) -> Dictionary:
	if not sessions.has(id) or not sessions[id].logged_in:
		return {}
	var s: Dictionary = sessions[id]
	var now := now_seconds()
	var wait := float(s.get("unstuck_at", -1000.0)) + GameConfig.UNSTUCK_COOLDOWN - now
	var pos := CharacterData.position(s.character)
	var r := {}
	var fight := Vitals.combat_left(vitals_of(id), now)
	if fight > 0.0:
		# Never an escape button: you can go home only once nothing has hit you for a while.
		r = {"ok": false, "text": "You can't return to Spawn Meadow mid-fight. Try again in %d s." % ceili(fight), "wait": fight}
	elif wait > 0.0:
		r = {"ok": false, "text": "You can return to Spawn Meadow again in %d s." % ceili(wait), "wait": wait}
	elif Vector2(pos.x - GameConfig.SPAWN_POINT.x, pos.z - GameConfig.SPAWN_POINT.z).length() < GameConfig.UNSTUCK_NEAR:
		r = {"ok": false, "text": "You're already in Spawn Meadow.", "wait": 0.0}
	else:
		if GatherChannel.is_active(s.channel):
			gather_cancel(id, "moved")
		var spot := unstuck_spot(id)
		s.character.x = spot.x
		s.character.y = spot.y
		s.character.z = spot.z
		s.move = Vector2.ZERO
		s.swing = {}
		s.unstuck_at = now
		r = {"ok": true, "text": "Back in Spawn Meadow.", "wait": GameConfig.UNSTUCK_COOLDOWN}
		print("[server] %s returned to Spawn Meadow from %s" % [s.character.name, pos])
	_send(id, "s2c_unstuck_result", [bool(r.ok), str(r.text), float(r.wait)])
	return r


## --- Health and stamina (Vitals, roadmap Milestone 2 "First blood") ---

## Player `id`'s Vitals state ({} for a player who is not here). Made full on login; a
## session built without one (unit tests) gets a full one on first use.
func vitals_of(id: int) -> Dictionary:
	if not sessions.has(id) or not sessions[id].logged_in:
		return {}
	var s: Dictionary = sessions[id]
	if not s.has("vitals"):
		s.vitals = Vitals.full()
		s.vitals_shown = Vitals.shown(s.vitals)
	return s.vitals


## Every tick: stamina and health come back (Vitals.tick), and a player whose whole points
## changed gets s2c_vitals(hp, max_hp, stamina, max_stamina) (protocol v7, also sent once at login).
func _tick_vitals(now: float) -> void:
	for id in sessions:
		if not sessions[id].logged_in:
			continue
		Vitals.tick(vitals_of(id), now, GameConfig.TICK_DT)
		_send_vitals_if_changed(id)


func _send_vitals_if_changed(id: int) -> void:
	var s: Dictionary = sessions[id]
	var v := vitals_of(id)
	var shown := Vitals.shown(v)
	if shown == s.get("vitals_shown", []):
		return
	_send_vitals(id)


## s2c_vitals(hp, max_hp, stamina, max_stamina) in whole points, and remember what was shown.
func _send_vitals(id: int) -> void:
	var v := vitals_of(id)
	if v.is_empty():
		return
	var shown := Vitals.shown(v)
	sessions[id].vitals_shown = shown
	_send(id, "s2c_vitals", [shown[0], roundi(float(v.max_hp)), shown[1], roundi(float(v.max_stamina))])


## A hit of `amount` damage on player `id` (Vitals.hit; `blocking` takes most of it on
## stamina). At 0 health they are knocked down (knock_down). The only source today is the
## hidden /hurt dev command; creatures call this once they fight. Returns Vitals.hit's
## {taken, blocked, dead} plus "knocked_down", or {} for a player who is not here.
func hurt(id: int, amount: float, blocking: bool = false) -> Dictionary:
	var v := vitals_of(id)
	if v.is_empty() or not is_finite(amount):
		return {}
	var r := Vitals.hit(v, amount, now_seconds(), blocking)
	r.knocked_down = false
	if bool(r.dead):
		knock_down(id)
		r.knocked_down = true
	else:
		_send_vitals_if_changed(id)
	return r


## Fair failure: player `id` hit 0 health. Any gather stops, they come to at once on the
## Spawn Meadow arc (unstuck_spot), full, with their pack and XP untouched, and are told so.
## Doesn't touch the Return to Spawn Meadow cooldown.
func knock_down(id: int) -> void:
	if not sessions.has(id) or not sessions[id].logged_in:
		return
	var s: Dictionary = sessions[id]
	var pos := CharacterData.position(s.character)
	if GatherChannel.is_active(s.channel):
		gather_cancel(id, "moved")
	var spot := unstuck_spot(id)
	s.character.x = spot.x
	s.character.y = spot.y
	s.character.z = spot.z
	s.move = Vector2.ZERO
	s.vitals = Vitals.full()
	s.swing = {}
	s.knocked_down_at = now_seconds()
	s.knockdowns = int(s.get("knockdowns", 0)) + 1
	_send_vitals_if_changed(id)
	_send(id, "s2c_system", [Vitals.KNOCKED_DOWN_TEXT])
	print("[combat] %s was knocked down at %s and came to in Spawn Meadow" % [s.character.name, pos])


## --- The first swing (protocol v7, roadmap Milestone 2 "First blood") ---

## What player `id` swings: the best weapon in their pack (Weapons.ORDER, last is best), or
## bare hands. Nobody can make a weapon yet, so today this is always Weapons.FISTS.
func weapon_of(id: int) -> String:
	if not sessions.has(id) or not sessions[id].logged_in:
		return Weapons.FISTS
	var inv: Dictionary = sessions[id].character.get("inventory", {})
	for i in range(Weapons.ORDER.size() - 1, -1, -1):
		if int(inv.get(Weapons.ORDER[i], 0)) > 0:
			return Weapons.ORDER[i]
	return Weapons.FISTS


## A swing (c2s_attack): `kind` "light" or "heavy", facing `yaw`. Refused ("unknown", "busy"
## while the last swing is still going, "gathering" while your hands are on a node, or
## Vitals' "dead", "winded", "tired") with s2c_attack_refused to the swinger alone. A client
## that wants the swing to win sends c2s_gather_cancel first (both are reliable and ordered,
## so the cancel lands first); the server never cuts a gather short on its own, so no
## gather is lost to a stray click. Otherwise the stamina is spent (Weapons.stamina_cost),
## you turn to face `yaw`, and everyone in view gets s2c_swing; the blow lands Weapons.hit_at later
## in _tick_swings. Returns {ok, reason}.
func attack_request(id: int, kind: String, yaw: float) -> Dictionary:
	if not sessions.has(id) or not sessions[id].logged_in:
		return {}
	var s: Dictionary = sessions[id]
	var now := now_seconds()
	var weapon := weapon_of(id)
	var why := ""
	if not Weapons.is_attack(kind) or not is_finite(yaw):
		why = "unknown"
	elif not s.get("swing", {}).is_empty() and now < float(s.swing.done_at):
		why = "busy"
	elif GatherChannel.is_active(s.channel):
		why = "gathering"
	else:
		var r := Vitals.spend_cost(vitals_of(id), kind, Weapons.stamina_cost(weapon, kind), now)
		why = str(r.reason)
	if why != "":
		_send(id, "s2c_attack_refused", [kind if Weapons.is_attack(kind) else "", why])
		return {"ok": false, "reason": why}
	yaw = wrapf(yaw, -PI, PI)
	s.yaw = yaw
	s.swing = {"weapon": weapon, "kind": kind, "yaw": yaw, "started": now,
		"lands_at": now + Weapons.hit_at(weapon, kind), "done_at": now + Weapons.swing_seconds(weapon, kind), "landed": false}
	s.swings = int(s.get("swings", 0)) + 1
	_send_vitals_if_changed(id)
	var secs := Weapons.swing_seconds(weapon, kind)
	for other in players_in_view(CharacterData.position(s.character)):
		_send(other, "s2c_swing", [id, weapon, kind, secs])
	return {"ok": true, "reason": ""}


## Every tick: swings whose windup is over land. The blow is checked from where the swinger
## stands now, facing the way they swung (Weapons.targets_hit against every grazer); each
## grazer struck bolts with its herd (Wildlife.strike) and a hit puts the swinger in combat.
## The swinger always hears back (s2c_swing_hits, maybe empty); everyone else in view only
## on a hit.
func _tick_swings(now: float) -> void:
	for id in sessions.keys():
		var s: Dictionary = sessions[id]
		if not s.logged_in or s.get("swing", {}).is_empty():
			continue
		var sw: Dictionary = s.swing
		if not bool(sw.landed) and now >= float(sw.lands_at):
			sw.landed = true
			_land_swing(id, sw, now)
		if bool(sw.landed) and now >= float(sw.done_at):
			s.swing = {}


func _land_swing(id: int, sw: Dictionary, now: float) -> Array:
	var s: Dictionary = sessions[id]
	var pos := CharacterData.position(s.character)
	var hits := Weapons.targets_hit(pos, float(sw.yaw), str(sw.weapon), str(sw.kind), Wildlife.targets(wildlife))
	var damage := Weapons.damage(str(sw.weapon), str(sw.kind))
	for cid in hits:
		Wildlife.strike(wildlife, int(cid), pos, now, damage)
		if Wildlife.is_down(wildlife, int(cid)):
			_hunted(id, int(cid))
	if not hits.is_empty():
		Vitals.dealt(vitals_of(id), now)
		s.swing_hits = int(s.get("swing_hits", 0)) + hits.size()
		print("[combat] %s's %s %s struck grazer %s" % [s.character.name, Weapons.label(str(sw.weapon)).to_lower(), sw.kind, hits])
	for other in players_in_view(pos):
		if other == id or not hits.is_empty():
			_send(other, "s2c_swing_hits", [id, str(sw.kind), hits])
	return hits


## The first hunt (2026-11-24): player `id`'s blow brought creature `cid` down, so its drops
## (Wildlife.drops) go into their pack; s2c_inventory follows at the end of the tick. No
## toast yet: s2c_gather_result waits until world has drawn the hide and meat icons (a
## client's toast and the bot test's icon check want one), so today the pack shows the haul.
## Returns {item: count added}.
func _hunted(id: int, cid: int) -> Dictionary:
	var s: Dictionary = sessions[id]
	var c := Wildlife.get_by_id(wildlife, cid)
	var got := {}
	var words: Array = []
	for d in Wildlife.drops(str(c.get("kind", "grazer"))):
		var added := give_item(id, str(d[0]), int(d[1]))
		if added > 0:
			got[str(d[0])] = added
			words.append("+%d %s" % [added, Inventory.label(str(d[0]))])
	s.hunted = int(s.get("hunted", 0)) + 1
	print("[hunt] %s brought down %s %d: %s" % [s.character.name, Wildlife.KINDS.get(str(c.get("kind", "grazer")), {}).get("label", "creature"), cid, ", ".join(words) if not words.is_empty() else "pack full"])
	return got


## The hidden dev command /lure (bot test only): the nearest standing grazer lies down drowsy
## just in front of you (Wildlife.lure), so a bot can land the blows of a hunt without a
## minute-long night stalk. Returns the reply.
func lure_command(id: int) -> String:
	var s: Dictionary = sessions[id]
	var cid := Wildlife.lure(wildlife, CharacterData.position(s.character), float(s.get("yaw", 0.0)), now_seconds())
	if cid < 0:
		return "No grazer is standing to lure."
	return "Grazer %d lies down in front of you." % cid


## The hidden dev commands /hurt N (1 to 1000 damage, default 10) and /vitals. Returns the
## reply ("" after a knock-down, whose own line is the answer).
func vitals_command(id: int, line: String) -> String:
	if ChatCommands.is_vitals(line):
		return Vitals.describe(vitals_of(id), now_seconds())
	var amount := ChatCommands.hurt_amount(line)
	if amount <= 0:
		return "Hurt how much? Try /hurt 30 (1 to %d)." % ChatCommands.HURT_MAX
	var r := hurt(id, float(amount))
	if r.is_empty():
		return ""
	if bool(r.knocked_down):
		return "" # knock_down sent Vitals.KNOCKED_DOWN_TEXT, which says it all
	return "You take %d damage. %s" % [amount, Vitals.describe(vitals_of(id), now_seconds())]


## Where "Return to Spawn Meadow" puts player `id`: on a 3 m arc south of spawn, away from
## the workbench (3, -2), spread by peer id so a crowd doesn't land in one spot.
static func unstuck_spot(id: int) -> Vector3:
	var a := PI / 6.0 + float(absi(id) % 5) * (PI * 2.0 / 3.0) / 4.0 # PI/6 .. 5PI/6
	return Terrain.clamp_to_world(GameConfig.SPAWN_POINT + Vector3(cos(a), 0.0, sin(a)) * 3.0)


## Server-authoritative inventory changes. Every system that hands out or uses up items
## (gathering, crafting, quests) goes through these two, never edits the Dictionary itself.
## The change is saved with the character (autosave, logout, shutdown), and the player gets
## their new pack as s2c_inventory at the end of the tick (_flush_inventories).
## Returns how many were added (stacks cap at Inventory.MAX_STACK).
func give_item(id: int, item: String, qty: int) -> int:
	if not sessions.has(id) or not sessions[id].logged_in:
		return 0
	var added := Inventory.add(sessions[id].character.inventory, item, qty)
	if added > 0:
		sessions[id].inv_dirty = true
		print("[inventory] %s +%d %s" % [sessions[id].character.name, added, item])
	return added


## Removes exactly qty of item, or nothing. Returns whether it was removed.
func take_item(id: int, item: String, qty: int) -> bool:
	if not sessions.has(id) or not sessions[id].logged_in:
		return false
	var ok := Inventory.remove(sessions[id].character.inventory, item, qty)
	if ok:
		sessions[id].inv_dirty = true
		print("[inventory] %s -%d %s" % [sessions[id].character.name, qty, item])
	return ok


## Sends an RPC only if the peer is still fully connected. A peer that has started
## disconnecting but whose disconnect signal has not fired yet has no channels left.
## The RPC lives on Net itself or on one of Net's child nodes (new RPCs go on a child, so
## old clients' RPC numbering stays the same; see tests/protocol/README.md). A message the
## running protocol has no RPC for yet is skipped, so the server can produce v3 messages
## before the v3 bump without old clients ever receiving an unknown RPC.
func _send(id: int, method: StringName, args: Array) -> void:
	if net == null:
		test_outbox.append([id, str(method), args])
		return
	var target := _rpc_node(method)
	if target == null:
		if not _not_in_protocol.has(method):
			_not_in_protocol[method] = true
			print("[server] %s is not in protocol v%d yet; not sent" % [method, GameConfig.PROTOCOL_VERSION])
		return
	if not _is_live(id):
		return
	Callable(target, "rpc_id").callv([id, method] + args)


func _rpc_node(method: StringName) -> Node:
	if net.has_method(method):
		return net
	for child in net.get_children():
		if child.has_method(method):
			return child
	return null


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
