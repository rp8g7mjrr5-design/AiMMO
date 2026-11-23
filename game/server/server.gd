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
	get_tree().set_auto_accept_quit(false)
	print("[server] listening on port %d via %s, protocol v%d" % [port, transport, GameConfig.PROTOCOL_VERSION])
	print("[server] world clock: ", WorldClock.describe(world_seconds()))
	print("[server] resource nodes: ", ResourceNodes.describe())


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
	_flush_inventories()
	if entries.is_empty():
		return
	for id in sessions:
		if sessions[id].logged_in:
			_send(id, "s2c_snapshot", [tick, entries])


func _on_peer_connected(id: int) -> void:
	sessions[id] = {"logged_in": false, "character": {}, "move": Vector2.ZERO, "yaw": 0.0, "seq": -1, "last_chat": -1000.0, "last_gather": -1000.0, "channel": {}, "login_attempts": 0, "inv_dirty": false}
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
	_send_world_state(id)
	# Tell the newcomer about everyone already here, and everyone about the newcomer.
	for other in sessions:
		var o: Dictionary = sessions[other]
		if other == id or not o.logged_in:
			continue
		_send(id, "s2c_player_joined", [other, o.character.name, o.character.appearance_seed])
		_send(other, "s2c_player_joined", [id, ch.name, ch.appearance_seed])
		_send(other, "s2c_system", ["%s has arrived." % ch.name])
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
	var now := Time.get_ticks_msec() / 1000.0
	if now - s.last_chat < GameConfig.CHAT_COOLDOWN:
		return
	var clean := Validation.clean_chat(text)
	if clean == "":
		return
	s.last_chat = now
	if ChatCommands.is_gather(clean):
		print("[chat] %s ran %s" % [s.character.name, clean.substr(0, 40)])
		_send(id, "s2c_system", [gather(id, ChatCommands.argument(clean))])
		return
	if ChatCommands.is_channel(clean):
		print("[chat] %s ran %s" % [s.character.name, clean.substr(0, 40)])
		_channel_command(id, ChatCommands.argument(clean))
		return
	if ChatCommands.is_craft(clean):
		print("[chat] %s ran %s" % [s.character.name, clean.substr(0, 40)])
		_send(id, "s2c_system", [craft(id, "" if ChatCommands.name_of(clean) == "recipes" else ChatCommands.argument(clean))])
		return
	if ChatCommands.is_command(clean):
		var online: Array = []
		for other in sessions:
			if sessions[other].logged_in:
				online.append(sessions[other].character.name)
		var reply := ChatCommands.run(clean, {"world_seconds": world_seconds(), "online": online, "inventory": s.character.inventory})
		print("[chat] %s ran %s" % [s.character.name, clean.substr(0, 40)])
		_send(id, "s2c_system", [reply])
		return
	print("[chat] %s: %s" % [s.character.name, clean])
	for other in sessions:
		if sessions[other].logged_in:
			_send(other, "s2c_chat", [s.character.name, clean])


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
	if GatherChannel.is_active(s.channel):
		return Gathering.refusal("cooldown", gathering, -1, CharacterData.position(s.character), now, ws, kind)
	var pos := CharacterData.position(s.character)
	var node_id := Gathering.pick_target(gathering, pos, now, ws, kind)
	if node_id < 0:
		return Gathering.refusal("none", gathering, -1, pos, now, ws, kind)
	var node_kind := str(ResourceNodes.get_by_id(node_id).kind)
	var inv: Dictionary = s.character.inventory
	var why := Gathering.check(gathering, node_id, pos, now, ws, s.last_gather, Gathering.cooldown_for(node_kind, inv))
	if why != "":
		return Gathering.refusal(why, gathering, node_id, pos, now, ws, kind)
	var tool := Gathering.tool_for(node_kind, inv)
	var got := Gathering.take(gathering, node_id, now)
	var added := give_item(id, got.item, Gathering.amount_for(node_kind, inv))
	if added <= 0:
		Gathering.give_back(gathering, node_id)
		return Gathering.refusal("full", gathering, node_id, pos, now, ws, kind)
	s.last_gather = now
	if got.depleted:
		_node_changed(node_id, true, got.respawn)
	return Gathering.success(node_id, added, Inventory.count(s.character.inventory, got.item), got.depleted, tool)


## Starts a timed gather (GatherChannel) on node `node_id` for player `id`: the same checks
## as an instant gather (reach from the server's own position, depletion, night-only, the
## player's cooldown), plus "busy" if a gather is already running and "full" if the pack has
## no room for that node's item. Returns {ok, reason, seconds}. On success the channel runs
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
	var why := Gathering.check(gathering, node_id, pos, now, world_seconds(), s.last_gather, Gathering.cooldown_for(kind, inv))
	if why == "" and Inventory.count(inv, str(ResourceNodes.kind_info(kind).item)) >= Inventory.MAX_STACK:
		why = "full"
	if why != "":
		return {"ok": false, "reason": why, "seconds": 0.0}
	var secs := GatherChannel.seconds_for(kind, inv)
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
	s.channel = {}
	_gather_event(id, "cancelled", node_id, {"reason": reason})


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
	var why := GatherChannel.finish_check(gathering, ch, pos, now, ws)
	if why != "":
		_gather_event(id, "cancelled", node_id, {"reason": why})
		return
	var kind := str(ResourceNodes.get_by_id(node_id).kind)
	var inv: Dictionary = s.character.inventory
	var tool := Gathering.tool_for(kind, inv)
	var got := Gathering.take(gathering, node_id, now)
	var added := give_item(id, got.item, Gathering.amount_for(kind, inv))
	if added <= 0:
		Gathering.give_back(gathering, node_id)
		_gather_event(id, "cancelled", node_id, {"reason": "full"})
		return
	s.last_gather = now
	if got.depleted:
		_node_changed(node_id, true, got.respawn)
	_gather_event(id, "done", node_id, {"item": got.item, "count": added, "tool": tool, "depleted": got.depleted})


## Where a timed gather's begin / cancelled / done is told to players:
## - everyone in view (players_in_view) gets s2c_gather_begin(peer, node, seconds) and
##   s2c_gather_end(peer, node, "done" | reason), so they see the gatherer work;
## - the gatherer also gets s2c_gather_result(item, count) on "done" for the haul toast
##   (s2c_inventory follows from give_item), and a system line, which is what the
##   "/channel" dev command and today's clients read.
## The s2c_gather_* RPCs arrive with protocol v3; until then _send skips them.
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
			for other in players_in_view(pos):
				_send(other, "s2c_gather_begin", [id, node_id, float(info.seconds)])
		"done":
			text = Gathering.success(node_id, int(info.count), Inventory.count(s.character.inventory, str(info.item)), bool(info.depleted), str(info.tool))
			reason = "done"
			_send(id, "s2c_gather_result", [str(info.item), int(info.count)])
		"cancelled":
			reason = str(info.reason)
			if reason in ["moved", "far", "stopped"]:
				text = GatherChannel.cancel_text(reason)
			elif reason != "disconnected":
				text = Gathering.refusal(reason, gathering, node_id, pos, now, world_seconds())
	if reason != "":
		for other in players_in_view(pos):
			if other != id or reason != "disconnected":
				_send(other, "s2c_gather_end", [id, node_id, reason])
	if text != "":
		_send(id, "s2c_system", [text])


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
			_send(id, "s2c_system", [Gathering.refusal(reason, gathering, node_id, pos, now_seconds(), world_seconds())])
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
	sessions[id].inv_dirty = false


## Sends s2c_inventory once to every player whose pack changed since the last tick, so a
## craft that takes three items and gives one is one message, not four.
func _flush_inventories() -> void:
	for id in sessions:
		var s: Dictionary = sessions[id]
		if s.logged_in and s.get("inv_dirty", false):
			s.inv_dirty = false
			_send(id, "s2c_inventory", [Inventory.to_wire(s.character.inventory)])


## The hidden "/channel" dev command: "/channel [kind]" starts a timed gather on the node
## "/gather [kind]" would pick, "/channel stop" cancels. For bots and debugging only (owner
## direction: chat is for talking); players get this through protocol v3's press-E.
func _channel_command(id: int, word: String) -> void:
	var s: Dictionary = sessions[id]
	if word.strip_edges().to_lower() in ["stop", "cancel"]:
		if GatherChannel.is_active(s.channel):
			gather_cancel(id, "stopped")
		else:
			_send(id, "s2c_system", ["You are not gathering."])
		return
	var kind = Gathering.parse_kind(word)
	if kind == null:
		_send(id, "s2c_system", ["Gather what? Try /channel, or /channel ash, pine, stone or sap."])
		return
	var now := now_seconds()
	var ws := world_seconds()
	var pos := CharacterData.position(s.character)
	_respawn_nodes(now)
	var node_id := Gathering.pick_target(gathering, pos, now, ws, kind)
	if node_id < 0:
		_send(id, "s2c_system", [Gathering.refusal("none", gathering, -1, pos, now, ws, kind)])
		return
	var r := gather_start(id, node_id)
	if r.ok:
		return # the "begin" event already told the player
	var reason := "cooldown" if r.reason == "busy" else str(r.reason)
	_send(id, "s2c_system", [Gathering.refusal(reason, gathering, node_id, pos, now, ws, kind)])


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
	return r


## Crafts a known recipe id for player `id`. Returns {ok, reason, text}.
func _craft(id: int, recipe: String) -> Dictionary:
	var s: Dictionary = sessions[id]
	var inv: Dictionary = s.character.inventory
	var pos := CharacterData.position(s.character)
	var why := Crafting.check(inv, recipe, pos)
	if why != "":
		return {"ok": false, "reason": why, "text": Crafting.refusal(why, inv, recipe, pos)}
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
	return {"ok": true, "reason": "", "text": Crafting.success(recipe, made, inv)}


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
