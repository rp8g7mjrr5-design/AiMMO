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
## Unit tests only: when >= 0, now_unix() returns this (Unix seconds) instead of the real date.
var test_unix := -1
## Monthly wipes (WorldWipe): the rule (AIMMO_WIPE / --wipe, "never" unless set), the world
## spec it rolls new worlds from, and the store's record of the world running now ({} with
## wipes off, which is always the case on Ashgrove).
var wipe_rule := WipeSchedule.NEVER
var world_record := {}
var _wipe_cfg := {}
var _wipe_check := 0.0
var _wipe_warned := {}
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
## Someone joined or left since the last tick: send everyone the new roster
## (once per tick, so eight players logging in at once is eight rosters, not 36).
var _roster_dirty := false
## How many players may be logged in at once (owner direction 8: a world for 2 to 8 friends).
## From --max-players or MAX_PLAYERS; 0 (unset) means no cap, so local runs and the bot test
## (8 main bots plus the extra ones) are never turned away. A login past the cap is refused
## with world_full_text() and never kicks anyone already in.
var max_players := 0
## The Zombai walkers (Gloam in the code): stepped every tick. Walkers rise near players on
## their own when gloam_on: on by default since the client draws them (owner, 2026-11-25:
## "we just need the Zombai"); `--gloam=0` / AIMMO_GLOAM=0 turns them off. The hidden /gloam
## dev command raises one bound to its caller either way. On the wire since v10, not saved.
var gloam := Gloam.new_state()
var gloam_on := false
## Placed campfires (Phase 2 build-ahead, Campfires): set down from the pack (place_request,
## through c2s_place from protocol v9, or the /place and /kindle dev commands), burn out on
## their own, and keep the Gloam walkers away (gloam_fires). s2c_campfires goes out to
## everyone on every change and at login.
## Not saved yet: a restart puts every fire out.
var campfires := Campfires.new_state()
## Ruin loot (Loot, step 2 of the survival plan): which loot spots were searched and when.
## `loot_spots` is RuinLayout.all_loot_spots() for the running world, `loot_ruins` Ruins.all().
## Not saved: a restart refills every spot.
var loot := Loot.new_state()
var loot_spots: Array = []
var loot_ruins: Array = []
var loot_rng := RandomNumberGenerator.new()
## A swing landing is a noise this loud (m), a finished gather this loud.
const SWING_NOISE := Gloam.NOISE_RADIUS
const GATHER_NOISE := Gloam.NOISE_RADIUS


func start(p_net: Node, args: Dictionary) -> void:
	net = p_net
	use_world(WorldGen.parse(CliArgs.setting(args, "world", "AIMMO_WORLD", "")))
	transport = CliArgs.setting(args, "transport", "AIMMO_TRANSPORT", "enet")
	port = CliArgs.setting(args, "port", "AIMMO_PORT", OS.get_environment("PORT") if OS.get_environment("PORT") != "" else str(GameConfig.DEFAULT_PORT)).to_int()
	_stop_file = CliArgs.setting(args, "stop-file", "AIMMO_STOP_FILE", "")
	clock_offset = CliArgs.setting(args, "clock-offset", "AIMMO_CLOCK_OFFSET", "0").to_float()
	var dev: Array = ChatCommands.dev_commands_on(args)
	dev_commands = dev[0]
	max_players = parse_max_players(CliArgs.setting(args, "max-players", "MAX_PLAYERS", ""))
	gloam_on = parse_gloam(args)
	print("[server] player cap: %s" % (str(max_players) if max_players > 0 else "none"))
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
	start_wipes(WipeSchedule.parse(CliArgs.setting(args, "wipe", "AIMMO_WIPE", "")), WorldGen.config())

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
	net.place_requested.connect(_on_place)
	net.pack_move_requested.connect(_on_pack_move)
	net.pack_drop_requested.connect(_on_pack_drop)
	get_tree().set_auto_accept_quit(false)
	print("[server] listening on port %d via %s, protocol v%d" % [port, transport, GameConfig.PROTOCOL_VERSION])
	print("[server] world clock: ", WorldClock.describe(world_seconds()))
	print("[server] world: ", describe_world())
	print("[server] resource nodes: ", ResourceNodes.describe())
	print("[server] wildlife: ", Wildlife.describe())
	print("[server] gloam: ", Gloam.describe(gloam_on))


## Runs this server on the world `cfg` names ({seed, size_m, gen_version}, as WorldGen.parse
## and WorldGen.config give it; from --world=seed:gen:size or AIMMO_WORLD). Unset or junk is
## Ashgrove (gen_version 0), today's world, exactly as before. A generated kingdom (gen 1) puts
## nodes, the tier-2 ring, herds, the bench and spawn where its seed says (Phase 1 part 3).
## Call before any player logs in: node ids and positions follow the world.
func use_world(cfg: Dictionary) -> void:
	WorldGen.apply(cfg)
	ResourceNodes.reset()
	gathering = Gathering.new_state()
	wildlife = Wildlife.new_state()
	gloam = Gloam.new_state()
	campfires = Campfires.new_state()
	loot = Loot.new_state()
	loot_ruins = Ruins.all()
	loot_spots = RuinLayout.all_loot_spots()
	loot_rng.randomize()


## Turns monthly wipes on for world spec `cfg` when `rule` asks and the world is generated
## (WorldWipe.enabled), and runs the store's current world, or a new one if it is due. Needs the
## store open. Off, nothing changes.
func start_wipes(rule: String, cfg: Dictionary) -> void:
	wipe_rule = rule
	world_record = {}
	_wipe_warned.clear()
	if not WorldWipe.enabled(rule, cfg):
		print("[server] wipes: off" if rule == WipeSchedule.NEVER else "[server] wipes: off (Ashgrove never wipes; they need a generated world)")
		return
	_wipe_cfg = cfg.duplicate()
	var rec := WorldWipe.choose(store, cfg, now_unix())
	if rec.is_empty():
		push_error("[server] wipes: could not read or record the world (%s); running without wipes" % store.last_error)
		return
	world_record = rec
	use_world(WorldWipe.config_of(rec))
	print("[server] wipes: %s, world %d (seed %d), next wipe %s" % [rule, int(rec.id), int(rec.seed), WipeSchedule.describe(int(rec.wipes_at))])


## Unix seconds (UTC) now, for the wipe schedule.
func now_unix() -> int:
	return test_unix if test_unix >= 0 else int(Time.get_unix_time_from_system())


## Warns everyone online at 60, 10 and 1 minutes, and wipes when the time comes.
func _tick_wipe(now: int) -> void:
	if world_record.is_empty():
		return
	var left := int(world_record.wipes_at) - now
	if left <= 0:
		wipe_now(now)
		return
	var say := 0
	for m in WipeSchedule.WARN_MINUTES:
		if left <= m * 60 and not _wipe_warned.has(m):
			_wipe_warned[m] = true
			say = m
	if say > 0:
		_broadcast_system(WipeSchedule.warning(say))


## The wipe: saves everyone, sends them off with a line saying why, and rolls the next world
## (new seed). Their packs are emptied when they come back (WorldWipe.on_login); the old world's
## record and everything they had stay in the store.
func wipe_now(now: int) -> void:
	print("[server] wipe: world %d ends, saving and sending everyone off" % int(world_record.id))
	_save_all()
	for id in sessions.keys():
		if sessions.has(id) and sessions[id].logged_in:
			_send(id, "s2c_system", [WIPE_TEXT])
			_on_peer_disconnected(id)
			if net != null and multiplayer.multiplayer_peer != null:
				multiplayer.multiplayer_peer.disconnect_peer(id)
	var rec := WorldWipe.roll(store, _wipe_cfg, now, false)
	if rec.is_empty():
		push_error("[server] wipe: could not record the new world (%s); trying again in an hour" % store.last_error)
		world_record.wipes_at = now + 3600
		return
	world_record = rec
	_wipe_warned.clear()
	use_world(WorldWipe.config_of(rec))
	print("[server] wipe: new world %d, %s; next wipe %s" % [int(rec.id), describe_world(), WipeSchedule.describe(int(rec.wipes_at))])


const WIPE_TEXT := "The island is wiped. Log back in to wash up on a new one."
const WASHED_UP_TEXT := "A new island. You wash up with nothing."


func _broadcast_system(text: String) -> void:
	for id in sessions:
		if sessions[id].logged_in:
			_send(id, "s2c_system", [text])


## Whether walkers rise on their own: `--gloam` (or `--gloam=0/1`) wins, then AIMMO_GLOAM
## (0/false/off turns them off). Unset is on (the Zombai are in the game, 2026-11-25). `env`
## is a name -> value lookup, for tests.
static func parse_gloam(args: Dictionary, env: Callable = Callable(OS, "get_environment")) -> bool:
	if args.has("gloam"):
		var v = args["gloam"]
		return true if typeof(v) == TYPE_BOOL else ChatCommands._truthy(str(v))
	var e := str(env.call("AIMMO_GLOAM")).strip_edges()
	return e == "" or ChatCommands._truthy(e)


## A character saved somewhere this world has no dry land for (out past its border, in a
## river, a lake or the sea) comes to at this world's spawn instead. Only position changes:
## pack and everything else are untouched. On Ashgrove nobody is ever moved, so the
## live world behaves exactly as before; on a kingdom it keeps a character from another world
## (or an old save) from logging in under water. Returns true if it moved them.
static func place_on_this_world(ch: Dictionary) -> bool:
	if not WorldGen.is_kingdom():
		return false
	var x := float(ch.get("x", 0.0))
	var z := float(ch.get("z", 0.0))
	var lim := WorldGen.half_size() - 2.0
	if absf(x) <= lim and absf(z) <= lim and Terrain.height(x, z) >= Terrain.water_level() + 0.3:
		return false
	var sp := WorldGen.spawn_point()
	ch.x = sp.x
	ch.y = sp.y
	ch.z = sp.z
	return true


## One line for the log: which world this is, where its spawn is and what ruins it has.
static func describe_world() -> String:
	var c := WorldGen.config()
	if not WorldGen.is_kingdom():
		return "Ashgrove (gen 0, 512 m)"
	var sp := WorldGen.spawn_point()
	return "kingdom seed %d, %d m (gen %d), spawn (%.0f, %.0f), %s" % [int(c.seed), int(c.size_m),
		int(c.gen_version), sp.x, sp.z, Ruins.describe()]


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
	_wipe_check += delta
	if _wipe_check >= 5.0:
		_wipe_check = 0.0
		_tick_wipe(now_unix())
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
	_tick_searches(now_seconds())
	_tick_vitals(now_seconds())
	_tick_swings(now_seconds())
	_tick_wildlife(now_seconds())
	_tick_campfires(now_seconds())
	_tick_gloam(now_seconds())
	if tick % WILDLIFE_SEND_TICKS == 0:
		_send_wildlife()
		_send_gloam()
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


## Every logged-in player as Gloam.step wants them: [{id, pos}].
func gloam_players() -> Array:
	var out: Array = []
	for id in sessions:
		if sessions[id].logged_in:
			out.append({"id": id, "pos": CharacterData.position(sessions[id].character)})
	return out


## Lit fires the walkers keep away from (Gloam.FIRE_KEEPAWAY): every placed campfire still
## burning. (A held torch joins them once torches can be held; backlog.)
func gloam_fires() -> Array:
	return Campfires.positions(campfires)


## --- Placed campfires (Phase 2 build-ahead) ---

## Player `id` sets down a campfire from their pack, in front of them (Campfires.place). Only
## "campfire" can be placed today. On success one campfire leaves the pack, everyone gets the
## new list (s2c_campfires) and the placer a line; a refusal costs nothing. This is what the
## /place dev command and c2s_place (protocol v9) run.
## Returns {ok, reason, text, fire_id}.
func place_request(id: int, item: String) -> Dictionary:
	if not sessions.has(id) or not sessions[id].logged_in:
		return {"ok": false, "reason": "down", "text": Campfires.refusal_text("down"), "fire_id": -1}
	var s: Dictionary = sessions[id]
	var word := item.strip_edges().to_lower()
	if word in ["", "fire", "camp_fire"]:
		word = Campfires.ITEM
	if word in [Vitals.BANDAGE_ITEM, "bandages"]:
		return use_bandage(id)
	if word == "eat":
		return eat_request(id)
	if Needs.is_food(word):
		return eat_request(id, word)
	if word == "cook":
		return cook_request(id)
	if word == "search":
		return search_start(id)
	if word != Campfires.ITEM:
		return _refuse_place("unknown")
	if Vitals.is_dead(vitals_of(id)):
		return _refuse_place("down")
	if not Inventory.has(s.character.inventory, Campfires.ITEM):
		return _refuse_place("no_item")
	var r := Campfires.place(campfires, str(s.character.name), CharacterData.position(s.character), float(s.get("yaw", 0.0)), now_seconds())
	if not r.ok:
		return _refuse_place(str(r.reason))
	take_item(id, Campfires.ITEM, 1)
	_lit(r.fire, s.character.name)
	return {"ok": true, "reason": "", "text": PLACED_TEXT, "fire_id": int(r.fire.id)}


## Player `id` puts a bandage from their pack on (owner direction, 2026-11-26: bandages).
## c2s_place("bandage") runs this (protocol v9's "use this from my pack", so no protocol
## bump); the client sends it on H. Refused ("no_item", "full", "busy", "dead") it costs
## nothing; on success one bandage leaves the pack and Vitals heals BANDAGE_HEAL over
## BANDAGE_SECONDS (the bar fills up through s2c_vitals). Returns {ok, reason, text, fire_id: -1}.
func use_bandage(id: int) -> Dictionary:
	var s: Dictionary = sessions[id]
	var why := ""
	if not Inventory.has(s.character.inventory, Vitals.BANDAGE_ITEM):
		why = "dead" if Vitals.is_dead(vitals_of(id)) else "no_item"
	else:
		why = Vitals.apply_bandage(vitals_of(id))
	if why == "":
		take_item(id, Vitals.BANDAGE_ITEM, 1)
	return {"ok": why == "", "reason": why, "text": Vitals.bandage_text(why), "fire_id": -1}


## What the placer is told when a fire catches.
const PLACED_TEXT := "You set down a campfire. It catches and will burn for about four hours."


func _refuse_place(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason, "text": Campfires.refusal_text(reason), "fire_id": -1}


func _lit(fire: Dictionary, who: String) -> void:
	print("[campfire] %s lit campfire %d at (%.1f, %.1f), %d burning" % [who, int(fire.id), fire.pos.x, fire.pos.z, Campfires.count(campfires)])
	_broadcast_campfires()


## The hidden dev command /kindle (bot test, dev servers only): lights a campfire in front of
## you without using one from the pack (the placement rules still apply). "/kindle status"
## says how the nearest fire within 20 m is doing. Returns the reply.
func kindle_command(id: int, arg: String) -> String:
	var s: Dictionary = sessions[id]
	var pos := CharacterData.position(s.character)
	if arg.strip_edges().to_lower() == "status":
		var close := Campfires.near(campfires, pos, 20.0)
		return "No campfire is burning near you." if close.is_empty() else Campfires.describe_fire(close[0], pos, now_seconds())
	var r := Campfires.place(campfires, str(s.character.name), pos, float(s.get("yaw", 0.0)), now_seconds())
	if not r.ok:
		return Campfires.refusal_text(str(r.reason))
	_lit(r.fire, s.character.name)
	return "A campfire catches in front of you (campfire %d)." % int(r.fire.id)


## Every tick: fires that burned down go out; everyone gets the new list, and their owner (if
## online) is told. Returns the fires that went out.
func _tick_campfires(now: float) -> Array:
	var out := Campfires.step(campfires, now)
	if out.is_empty():
		return out
	for f in out:
		print("[campfire] campfire %d burned down" % int(f.id))
		for pid in sessions:
			var s: Dictionary = sessions[pid]
			if s.logged_in and str(s.character.name).to_lower() == str(f.owner):
				_send(pid, "s2c_system", [BURNED_DOWN_TEXT])
	_broadcast_campfires()
	return out


const BURNED_DOWN_TEXT := "Your campfire has burned down to ash."


## s2c_campfires(entries) to every logged-in player: the whole list (Campfires.to_wire),
## empty when the last one burns down.
func _broadcast_campfires() -> void:
	var entries := Campfires.to_wire(campfires, now_seconds())
	for pid in sessions:
		if sessions[pid].logged_in:
			_send(pid, "s2c_campfires", [entries])


## The walkers take one step: they rise near players (only when gloam_on), hunt, and grab.
## A grab hurts its player through Vitals (hurt), which can knock them down. Returns
## Gloam.step's result plus "risen".
func _tick_gloam(now: float) -> Dictionary:
	var players := gloam_players()
	var night := WorldClock.is_night(world_seconds())
	var risen: Array = Gloam.rise_near_players(gloam, players, now, night) if gloam_on else []
	var r := Gloam.step(gloam, players, gloam_fires(), now, GameConfig.TICK_DT, night)
	r.risen = risen
	for g in r.grabs:
		var pid := int(g.player)
		if not sessions.has(pid) or not sessions[pid].logged_in:
			continue
		var s: Dictionary = sessions[pid]
		s.gloam_grabbed = int(s.get("gloam_grabbed", 0)) + 1
		var hit := hurt(pid, float(g.damage))
		print("[gloam] walker %d grabbed %s for %d%s" % [int(g.walker), s.character.name, roundi(float(hit.get("taken", 0.0))),
			" and knocked them down" if bool(hit.get("knocked_down", false)) else ""])
	return r


## s2c_gloam to every logged-in player (protocol v10): the walkers within GameConfig.VIEW_RANGE
## of them, with the grab's windup, on the same 5 Hz beat and goodbye rule as s2c_wildlife.
## Nothing goes out while nobody has a walker in view.
func _send_gloam() -> void:
	var now := now_seconds()
	for id in sessions:
		var s: Dictionary = sessions[id]
		if not s.logged_in:
			continue
		var entries := Gloam.to_wire_near(gloam, CharacterData.position(s.character), GameConfig.VIEW_RANGE, now)
		if entries.is_empty():
			var bye := int(s.get("gloam_bye", 0))
			if bye <= 0:
				continue
			s.gloam_bye = bye - 1
		else:
			s.gloam_bye = WILDLIFE_GOODBYES
		_send(id, "s2c_gloam", [entries])


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
	s.erase("search")
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
	if is_world_full():
		_reject(id, world_full_text())
		print("[server] turned a login away: the world is full (%d / %d)" % [players_online(), max_players])
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
	var washed := WorldWipe.on_login(store, ch, world_record)
	if washed and not store.save_character(ch):
		push_error("[server] could not save %s after the wipe: %s" % [ch.name, store.last_error])
	place_on_this_world(ch)
	s.character = ch
	_relayout(ch) # an older save gets its grid places here (PackGrid)
	s.yaw = ch.yaw
	s.vitals = Vitals.full() # not saved: every login starts at full health
	s.vitals_shown = Vitals.shown(s.vitals)
	_send(id, "s2c_login_result", [true, "Welcome to Ashgrove, %s!" % ch.name if is_new else "Welcome back, %s." % ch.name, id, ch])
	_send(id, "s2c_world", [WorldGen.config()]) # v9: build this world before anything in it
	_send(id, "s2c_world_time", [world_seconds()])
	_send_vitals(id) # the bar starts right, before anything changes it
	s.hunger_tier = Needs.tier_of(ch)
	_send_needs(id) # v12: hunger, once, then on every whole-point change
	_send_world_state(id)
	if washed and not is_new:
		_send(id, "s2c_system", [WASHED_UP_TEXT])
	if not world_record.is_empty():
		_send(id, "s2c_system", [WipeSchedule.notice(int(world_record.wipes_at), now_unix())])
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


## The player cap from its setting: a whole number above 0, or 0 for no cap (unset, junk, 0
## or negative all mean no cap, so a typo never locks everyone out).
static func parse_max_players(raw: String) -> int:
	var t := raw.strip_edges()
	if not t.is_valid_int():
		return 0
	return maxi(t.to_int(), 0)


## Players logged in right now (a peer still at the login screen doesn't count).
func players_online() -> int:
	var n := 0
	for other in sessions:
		if sessions[other].logged_in:
			n += 1
	return n


func is_world_full() -> bool:
	return max_players > 0 and players_online() >= max_players


## What a player turned away by the cap reads on the login screen.
func world_full_text() -> String:
	return "The world is full (%d / %d). Try again soon." % [players_online(), max_players]


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
	s.yaw = wrapf(yaw, -PI, PI) if is_finite(yaw) else s.yaw
	# Full speed only where you face: a backpedal is a walk (Movement.limit_for_facing).
	s.move = Movement.limit_for_facing(move, float(s.yaw))


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
		return
	if ChatCommands.is_hurt(clean) or ChatCommands.is_vitals(clean):
		print("[chat] %s ran %s" % [s.character.name, clean.substr(0, 40)])
		var reply := vitals_command(id, clean)
		if reply != "": # a knock-down already said what happened
			_send(id, "s2c_system", [reply])
		return
	if ChatCommands.is_gloam(clean):
		print("[chat] %s ran %s" % [s.character.name, clean.substr(0, 40)])
		_send(id, "s2c_system", [gloam_command(id, ChatCommands.argument(clean))])
		return
	if ChatCommands.is_place(clean):
		print("[chat] %s ran %s" % [s.character.name, clean.substr(0, 40)])
		_send(id, "s2c_system", [place_request(id, ChatCommands.argument(clean)).text])
		return
	if ChatCommands.is_loot(clean):
		print("[chat] %s ran %s" % [s.character.name, clean.substr(0, 40)])
		_send(id, "s2c_system", [loot_command(id, ChatCommands.argument(clean))])
		return
	if ChatCommands.is_kindle(clean):
		print("[chat] %s ran %s" % [s.character.name, clean.substr(0, 40)])
		_send(id, "s2c_system", [kindle_command(id, ChatCommands.argument(clean))])
		return
	if ChatCommands.is_lure(clean):
		print("[chat] %s ran %s" % [s.character.name, clean.substr(0, 40)])
		_send(id, "s2c_system", [lure_command(id)])
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


## c2s_place(item): set a campfire down from the pack, or put a bandage on (protocol v9). The answer goes to the
## placer as s2c_place_result; a fire that catches reaches everyone as s2c_campfires.
func _on_place(id: int, item: String) -> void:
	if not _play_allowed(id, "_last_place"):
		return
	var r := place_request(id, item)
	var word := item.strip_edges().to_lower().left(32)
	if word == "search":
		if not r.ok:
			_send(id, "s2c_place_result", ["search", false, str(r.reason), str(r.text)])
		return # a search that started answers when it ends (_finish_search)
	if r.ok:
		if word in [Vitals.BANDAGE_ITEM, "bandages"]:
			word = Vitals.BANDAGE_ITEM
		elif word == "eat" or Needs.is_food(word):
			word = "eat"
		elif word != "cook":
			word = Campfires.ITEM
	_send(id, "s2c_place_result", [word, r.ok, str(r.reason), str(r.text)])


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
	var inv: Dictionary = s.character.inventory
	if GatherChannel.is_active(s.channel):
		return Gathering.refusal("cooldown", gathering, -1, CharacterData.position(s.character), now, ws, kind, inv)
	var pos := CharacterData.position(s.character)
	var node_id := Gathering.pick_target(gathering, pos, now, ws, kind, inv)
	if node_id < 0:
		return Gathering.refusal("none", gathering, -1, pos, now, ws, kind, inv)
	var node := ResourceNodes.get_by_id(node_id)
	var node_kind := str(node.kind)
	var why := Gathering.check(gathering, node_id, pos, now, ws, s.last_gather, Gathering.cooldown_for(node_kind, inv), inv)
	if why != "":
		return Gathering.refusal(why, gathering, node_id, pos, now, ws, kind, inv)
	var tool := Gathering.tool_for(node_kind, inv)
	var got := Gathering.take(gathering, node_id, now)
	var added := give_item(id, got.item, Gathering.amount_at(node_id, inv))
	if added <= 0:
		Gathering.give_back(gathering, node_id)
		return Gathering.refusal("full", gathering, node_id, pos, now, ws, kind, inv)
	s.last_gather = now
	if got.depleted:
		_node_changed(node_id, true, got.respawn)
	return Gathering.success(node_id, added, Inventory.count(s.character.inventory, got.item), got.depleted, tool)


## Starts a timed gather (GatherChannel) on node `node_id` for player `id`: the same checks
## as an instant gather (reach from the server's own position, depletion, night-only; not
## the instant gather's cooldown, the bar itself paces it), plus "busy" if a gather is already
## running and "full" when the pack can't hold one more of what the node gives (there is no
## XP any more, so a gather that can pay nothing would be dead time). Returns {ok, reason,
## seconds}. On success the channel runs
## in _tick_channels and ends in _gather_event "done" or "cancelled".
## Protocol v3's c2s_gather_start calls this directly.
func gather_start(id: int, node_id: int) -> Dictionary:
	if not sessions.has(id) or not sessions[id].logged_in:
		return {"ok": false, "reason": "offline", "seconds": 0.0}
	var s: Dictionary = sessions[id]
	if GatherChannel.is_active(s.channel):
		return {"ok": false, "reason": "busy", "seconds": 0.0}
	if not s.get("search", {}).is_empty():
		search_cancel(id, "stopped") # walking up to a node and pressing E again moves on
	var now := now_seconds()
	_respawn_nodes(now)
	var pos := CharacterData.position(s.character)
	var node := ResourceNodes.get_by_id(node_id)
	var inv: Dictionary = s.character.inventory
	var kind := str(node.get("kind", ""))
	# No gather cooldown here: the channel's own server-timed bar is the pacing, so a player
	# who keeps pressing E goes straight from one gather into the next (no dead time). The
	# cooldown stays for the instant /gather dev command.
	var why := Gathering.check(gathering, node_id, pos, now, world_seconds(), -INF, 0.0, inv)
	if why == "" and PackGrid.room_for(inv, s_pack(id), str(ResourceNodes.info(node).get("item", ""))) <= 0:
		why = "full" # the grid pack has no room for what this node gives (or the stack is at MAX_STACK)
	if why != "":
		return {"ok": false, "reason": why, "seconds": 0.0}
	var secs := GatherChannel.seconds_at(node_id, inv)
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
	var why := GatherChannel.finish_check(gathering, ch, pos, now, ws, s.character.inventory)
	if why != "":
		_gather_event(id, "cancelled", node_id, {"reason": why, "audience": audience})
		return
	var node := ResourceNodes.get_by_id(node_id)
	var kind := str(node.kind)
	var inv: Dictionary = s.character.inventory
	var tool := Gathering.tool_for(kind, inv)
	var got := Gathering.take(gathering, node_id, now)
	# A stack that filled up while the bar ran (another gather or a craft can't, but be
	# safe) takes nothing, but the gather still happened: the charge is used. "done" with
	# count 0: no haul toast, a system line.
	var added := give_item(id, got.item, Gathering.amount_at(node_id, inv))
	var also: Dictionary = ResourceNodes.kind_info(kind).get("also", {})
	var extras := {}
	for extra in also:
		extras[str(extra)] = give_item(id, str(extra), int(also[extra]))
	if kind == "wreck_crate":
		var found := Loot.roll_beach(loot_rng)
		for extra in found:
			extras[str(extra)] = int(extras.get(str(extra), 0)) + give_item(id, str(extra), int(found[extra]))
	s.last_gather = now
	if got.depleted:
		_node_changed(node_id, true, got.respawn)
	Gloam.noise(gloam, pos, now, GATHER_NOISE) # chopping and mining carry
	_gather_event(id, "done", node_id, {"item": got.item, "count": added, "tool": tool, "depleted": got.depleted, "audience": audience})
	for extra in extras:
		if int(extras[extra]) > 0:
			_send(id, "s2c_gather_result", [extra, int(extras[extra])]) # a second haul toast


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
				text = Gathering.refusal(reason, gathering, node_id, pos, now, world_seconds(), "", s.character.inventory)
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
			_send(id, "s2c_system", [Gathering.refusal(reason, gathering, node_id, pos, now_seconds(), world_seconds(), "", s.character.inventory)])
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
	_send(id, "s2c_pack", [sessions[id].character.get("pack", [])])
	_send(id, "s2c_inventory", [Inventory.to_wire(sessions[id].character.inventory)])
	_send(id, "s2c_nodes", [Gathering.depleted_ids(gathering, now_seconds())])
	if Campfires.count(campfires) > 0:
		_send(id, "s2c_campfires", [Campfires.to_wire(campfires, now_seconds())])
	sessions[id].inv_dirty = false


## Sends s2c_inventory once to every player whose pack changed since the last tick, so a
## craft that takes three items and gives one is one message, not four.
func _flush_inventories() -> void:
	for id in sessions:
		var s: Dictionary = sessions[id]
		if s.logged_in and s.get("inv_dirty", false):
			s.inv_dirty = false
			_send(id, "s2c_pack", [s.character.get("pack", [])])
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
				give_item(id, back, int(taken[back]), true)
			return {"ok": false, "reason": "missing", "text": Crafting.refusal("missing", inv, recipe, pos)}
		taken[item] = int(r.needs[item])
	# All of it or none: the grid pack must hold the whole batch (PackGrid.room_for).
	var made := 0
	if PackGrid.room_for(inv, s.character.get("pack", []), recipe) >= int(r.makes):
		made = give_item(id, recipe, int(r.makes))
	if made <= 0:
		for back in taken:
			give_item(id, back, int(taken[back]), true)
		return {"ok": false, "reason": "full", "text": Crafting.refusal("full", inv, recipe, pos)}
	print("[craft] %s made %d %s" % [s.character.name, made, recipe])
	return {"ok": true, "reason": "", "text": Crafting.success(recipe, made, inv)}


## Everyone online for the players panel (s2c_roster): [{id, name}, ...] sorted by name,
## case-insensitively.
func roster() -> Array:
	var out: Array = []
	for id in sessions:
		var s: Dictionary = sessions[id]
		if s.logged_in:
			out.append({"id": int(id), "name": str(s.character.name)})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.name.nocasecmp_to(b.name) < 0)
	return out


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
	elif Vector2(pos.x - WorldGen.spawn_point().x, pos.z - WorldGen.spawn_point().z).length() < GameConfig.UNSTUCK_NEAR:
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
		var s: Dictionary = sessions[id]
		var v := vitals_of(id)
		var tier := Needs.tick(s.character, v, GameConfig.TICK_DT)
		Vitals.tick(v, now, GameConfig.TICK_DT, Needs.stamina_regen(s.character), Needs.can_heal(s.character))
		_send_vitals_if_changed(id)
		_tick_needs(id, tier)


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


## --- Hunger, the first survival need (Needs; the owner's survival plan, 2026-11-27) ---

## After each tick's Needs.tick: a tier that got worse is told once (getting hungry,
## starving), and s2c_needs goes out when the whole number changed.
func _tick_needs(id: int, tier: String) -> void:
	var s: Dictionary = sessions[id]
	var was := str(s.get("hunger_tier", "fine"))
	if tier != was:
		s.hunger_tier = tier
		if Needs.TIERS.find(tier) > Needs.TIERS.find(was) and Needs.text(tier) != "":
			_send(id, "s2c_system", [Needs.text(tier)])
	if Needs.to_wire(s.character) != s.get("needs_shown", {}):
		_send_needs(id)


## s2c_needs({"hunger": 0..100}) (protocol v12), and remember what was shown.
func _send_needs(id: int) -> void:
	var s: Dictionary = sessions[id]
	var wire := Needs.to_wire(s.character)
	s.needs_shown = wire
	_send(id, "s2c_needs", [wire])


## Player `id` eats `food` (an Inventory id), or the best food in their pack for "".
## c2s_place("eat") / c2s_place("<food>") runs this, so there is no new client message.
## Refused ("no_food", "full", "dead") it costs nothing. Returns {ok, reason, text, fire_id: -1}.
func eat_request(id: int, food: String = "") -> Dictionary:
	var s: Dictionary = sessions[id]
	var v := vitals_of(id)
	var why := Needs.eat_check(s.character, v, food)
	if why != "":
		return {"ok": false, "reason": why, "text": Needs.text(why), "fire_id": -1}
	var item := food if food != "" else Needs.best_food(s.character.inventory)
	if not take_item(id, item, 1):
		return {"ok": false, "reason": "no_food", "text": Needs.text("no_food"), "fire_id": -1}
	var r := Needs.eat(s.character, v, item)
	print("[needs] %s ate %s, hunger %d" % [s.character.name, item, Needs.shown(s.character)])
	_send_vitals_if_changed(id)
	_tick_needs(id, Needs.tier_of(s.character))
	return {"ok": true, "reason": "", "text": Needs.ate_text(item), "fire_id": -1, "item": item}


## --- Ruin loot (Loot; step 2 of the survival plan) ---

## Player `id` starts searching the loot spot they stand at (Loot.REACH). c2s_place("search")
## runs this, so there is no new client message. The search runs Loot.SEARCH_SECONDS on the
## server and ends in _finish_search (or search_cancel when they walk off). Refused ("none",
## "empty", "busy", "dead") it costs nothing. Returns {ok, reason, text, fire_id: -1, seconds}.
func search_start(id: int) -> Dictionary:
	var s: Dictionary = sessions[id]
	if Vitals.is_dead(vitals_of(id)):
		return {"ok": false, "reason": "dead", "text": "", "fire_id": -1}
	if GatherChannel.is_active(s.channel) or not s.get("search", {}).is_empty():
		return {"ok": false, "reason": "busy", "text": Loot.text("busy"), "fire_id": -1}
	var pos := CharacterData.position(s.character)
	var spot := Loot.nearest(loot_spots, pos)
	if spot.is_empty():
		return {"ok": false, "reason": "none", "text": Loot.text("none"), "fire_id": -1}
	var now := now_seconds()
	var k := Loot.key(spot)
	if Loot.is_empty(loot, k, now):
		return {"ok": false, "reason": "empty", "text": Loot.text("empty", str(spot.kind)), "fire_id": -1}
	s.search = {"key": k, "spot": spot, "from": pos, "due": now + Loot.SEARCH_SECONDS}
	return {"ok": true, "reason": "", "text": Loot.text("begin", str(spot.kind)), "fire_id": -1, "seconds": Loot.SEARCH_SECONDS}


## Stops player `id`'s search with nothing found. `reason` "moved", "stopped" or "dead".
func search_cancel(id: int, reason: String) -> void:
	if not sessions.has(id):
		return
	var s: Dictionary = sessions[id]
	if s.get("search", {}).is_empty():
		return
	s.erase("search")
	_send(id, "s2c_place_result", ["search", false, reason, Loot.text(reason)])


## Every tick: stop searches whose player walked off or went down, finish the ones that are due.
func _tick_searches(now: float) -> void:
	for id in sessions.keys():
		var s: Dictionary = sessions[id]
		if not s.logged_in or s.get("search", {}).is_empty():
			continue
		var from: Vector3 = s.search.from
		var pos := CharacterData.position(s.character)
		if Vitals.is_dead(vitals_of(id)):
			search_cancel(id, "dead")
		elif Vector2(pos.x - from.x, pos.z - from.z).length() > Loot.MOVE_TOLERANCE:
			search_cancel(id, "moved")
		elif now >= float(s.search.due):
			_finish_search(id, now)


## A search ran its full time: roll the spot's ruin grade and kind (Loot.roll), fill the pack,
## mark the spot searched, make a little noise, and answer with haul toasts
## (s2c_gather_result per item) and s2c_place_result("search", true, "", the found line).
## Someone else who emptied the spot meanwhile leaves this one with nothing.
func _finish_search(id: int, now: float) -> void:
	var s: Dictionary = sessions[id]
	var sr: Dictionary = s.search
	s.erase("search")
	var spot: Dictionary = sr.spot
	var k := str(sr.key)
	var found := {}
	if not Loot.is_empty(loot, k, now):
		var rolled := Loot.roll(Loot.grade_of(spot, loot_ruins), str(spot.kind), loot_rng)
		for item in rolled:
			var added := give_item(id, str(item), int(rolled[item]))
			if added > 0:
				found[str(item)] = added
		Loot.mark_searched(loot, k, now)
	Gloam.noise(gloam, CharacterData.position(s.character), now, Loot.NOISE)
	print("[loot] %s searched %s (%s): %s" % [s.character.name, k, spot.kind, str(found)])
	for item in Inventory.ITEM_ORDER:
		if found.has(item):
			_send(id, "s2c_gather_result", [item, int(found[item])])
	_send(id, "s2c_place_result", ["search", true, "", Loot.found_text(str(spot.kind), found)])


## The hidden /loot dev and bot command: searches the nearest loot spot in the whole world at
## once (no walk, no bar), or a stand-in grade 1 chest ("test:0") on a world without ruins
## (Ashgrove), through the same tables and searched state. "/loot refill" empties the state.
func loot_command(id: int, arg: String) -> String:
	var s: Dictionary = sessions[id]
	var now := now_seconds()
	if arg.strip_edges().to_lower() == "refill":
		loot = Loot.new_state()
		return "Every loot spot is full again."
	var spot := Loot.nearest(loot_spots, CharacterData.position(s.character), INF)
	if spot.is_empty():
		spot = {"ruin_id": -1, "index": 0, "kind": "chest", "pos": Vector3.ZERO}
	var k := Loot.key(spot) if int(spot.ruin_id) >= 0 else "test:0"
	if Loot.is_empty(loot, k, now):
		return Loot.text("empty", str(spot.kind))
	var rolled := Loot.roll(Loot.grade_of(spot, loot_ruins), str(spot.kind), loot_rng)
	var found := {}
	for item in rolled:
		var added := give_item(id, str(item), int(rolled[item]))
		if added > 0:
			found[str(item)] = added
	Loot.mark_searched(loot, k, now)
	return Loot.found_text(str(spot.kind), found)


## Player `id` cooks every raw meat in their pack over a lit campfire they stand at
## (Campfires.is_warm). c2s_place("cook") runs this. Returns {ok, reason, text, fire_id: -1, cooked}.
func cook_request(id: int) -> Dictionary:
	var s: Dictionary = sessions[id]
	if Vitals.is_dead(vitals_of(id)):
		return {"ok": false, "reason": "dead", "text": "", "fire_id": -1, "cooked": 0}
	if not Campfires.is_warm(campfires, CharacterData.position(s.character)):
		return {"ok": false, "reason": "no_fire", "text": Needs.text("no_fire"), "fire_id": -1, "cooked": 0}
	var cooked := 0
	for raw in Needs.COOKS:
		var n := Inventory.count(s.character.inventory, raw)
		if n <= 0:
			continue
		var into := str(Needs.COOKS[raw])
		var room := Inventory.MAX_STACK - Inventory.count(s.character.inventory, into)
		n = mini(n, room)
		if n > 0 and take_item(id, raw, n):
			var got := give_item(id, into, n)
			if got < n: # no room in the grid for all of it cooked: the rest stays raw
				give_item(id, raw, n - got, true)
			cooked += got
	if cooked <= 0:
		return {"ok": false, "reason": "no_raw", "text": Needs.text("no_raw"), "fire_id": -1, "cooked": 0}
	print("[needs] %s cooked %d meat" % [s.character.name, cooked])
	return {"ok": true, "reason": "", "text": Needs.text("cooked") % cooked, "fire_id": -1, "cooked": cooked}


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
## Spawn Meadow arc (unstuck_spot), full, with their pack untouched, and are told so.
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
	Needs.after_knockdown(s.character)
	s.swing = {}
	s.knocked_down_at = now_seconds()
	s.knockdowns = int(s.get("knockdowns", 0)) + 1
	_send_vitals_if_changed(id)
	_send(id, "s2c_system", [Vitals.KNOCKED_DOWN_TEXT])
	print("[combat] %s was knocked down at %s and came to in Spawn Meadow" % [s.character.name, pos])


## --- The first swing (protocol v7, roadmap Milestone 2 "First blood") ---

## What player `id` swings: the best weapon in their pack (Weapons.ORDER, last is best), or
## bare hands. Weapons are crafted (Crafting: club and spear in wood, then stone).
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
	var all_hits := Weapons.targets_hit(pos, float(sw.yaw), str(sw.weapon), str(sw.kind), Wildlife.targets(wildlife) + Gloam.targets(gloam))
	var damage := Weapons.damage(str(sw.weapon), str(sw.kind))
	# Grazers keep their int ids (s2c_swing_hits names only them, as since v7); walkers are
	# "w<id>" here and go out by their int id in s2c_gloam_hits (v10).
	var hits: Array = []
	var walkers: Array = []
	for t in all_hits:
		if typeof(t) == TYPE_STRING:
			walkers.append(Gloam.id_of_key(t))
		else:
			hits.append(t)
	for cid in hits:
		Wildlife.strike(wildlife, int(cid), pos, now, damage)
		if Wildlife.is_down(wildlife, int(cid)):
			_hunted(id, int(cid))
	var stagger := str(sw.kind) == "heavy"
	var downed: Array = []
	for wid in walkers:
		var r := Gloam.strike(gloam, int(wid), id, pos, now, damage, stagger)
		if bool(r.get("down", false)):
			downed.append(int(wid))
			s.gloam_downs = int(s.get("gloam_downs", 0)) + 1
			print("[gloam] %s put walker %d down" % [s.character.name, int(wid)])
	if not all_hits.is_empty():
		Vitals.dealt(vitals_of(id), now)
		s.swing_hits = int(s.get("swing_hits", 0)) + all_hits.size()
	if not hits.is_empty():
		print("[combat] %s's %s %s struck grazer %s" % [s.character.name, Weapons.label(str(sw.weapon)).to_lower(), sw.kind, hits])
	if not walkers.is_empty():
		print("[combat] %s's %s %s struck walker %s" % [s.character.name, Weapons.label(str(sw.weapon)).to_lower(), sw.kind, walkers])
	# Fighting is loud: every swing draws the Gloam, hit or miss.
	Gloam.noise(gloam, pos, now, SWING_NOISE)
	for other in players_in_view(pos):
		if other == id or not hits.is_empty():
			_send(other, "s2c_swing_hits", [id, str(sw.kind), hits])
		if not walkers.is_empty():
			_send(other, "s2c_gloam_hits", [id, str(sw.kind), walkers.duplicate(), downed.duplicate()])
	return hits


## The first hunt (2026-11-24): player `id`'s blow brought creature `cid` down, so its drops
## (Wildlife.drops) go into their pack; s2c_inventory follows at the end of the tick. The
## hunter also gets one s2c_gather_result(item, count) per drop that fit (the hunt toast,
## 2026-11-24, once world drew the hide and meat icons, #200), so a kill pops "+1 Hide" and
## "+2 Raw meat" with the haul sound, exactly like a gather. No new RPC: it has been on
## Net/Play since v3. Returns {item: count added}.
func _hunted(id: int, cid: int) -> Dictionary:
	var s: Dictionary = sessions[id]
	var c := Wildlife.get_by_id(wildlife, cid)
	var got := {}
	var words: Array = []
	for d in Wildlife.drops(str(c.get("kind", "grazer"))):
		var added := give_item(id, str(d[0]), int(d[1]))
		if added > 0:
			got[str(d[0])] = added
			_send(id, "s2c_gather_result", [str(d[0]), added])
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


## The hidden dev command /gloam (bot test, dev servers only): with no walker of yours
## standing, one rises Gloam.SUMMON_DISTANCE in front of you, bound to you (it hunts only you
## and crumbles when you leave). "/gloam status" (or /gloam with yours still standing) says
## how it is; once you put it down it says so. Returns the reply.
func gloam_command(id: int, arg: String) -> String:
	var s: Dictionary = sessions[id]
	var pos := CharacterData.position(s.character)
	var mine := Gloam.get_by_id(gloam, int(s.get("gloam_summoned", -1)))
	if not mine.is_empty():
		return Gloam.describe_walker(mine, pos)
	if arg.strip_edges().to_lower() == "status":
		if int(s.get("gloam_summoned", -1)) >= 0:
			return "Your walker %d is down." % int(s.gloam_summoned)
		return "No walker of yours is standing."
	var w := Gloam.summon(gloam, id, pos, float(s.get("yaw", 0.0)), now_seconds())
	s.gloam_summoned = int(w.id)
	return "A Zombai rises %d m in front of you (walker %d)." % [roundi(Gloam.SUMMON_DISTANCE), int(w.id)]


## The hidden dev commands /hurt N (1 to 1000 damage, default 10) and /vitals. Returns the
## reply ("" after a knock-down, whose own line is the answer).
func vitals_command(id: int, line: String) -> String:
	if ChatCommands.is_vitals(line):
		var arg := ChatCommands.argument(line).to_lower().split(" ", false)
		if arg.size() >= 1 and arg[0] == "hunger":
			# "/vitals hunger" reads hunger, "/vitals hunger 30" sets it (bots, dev servers).
			if arg.size() == 2 and arg[1].is_valid_float():
				Needs.set_hunger(sessions[id].character, arg[1].to_float())
				_tick_needs(id, Needs.tier_of(sessions[id].character))
			return "%s %s" % [Vitals.describe(vitals_of(id), now_seconds()), Needs.describe(sessions[id].character)]
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
	return Terrain.clamp_to_world(WorldGen.spawn_point() + Vector3(cos(a), 0.0, sin(a)) * 3.0)


## Server-authoritative inventory changes. Every system that hands out or uses up items
## (gathering, crafting, quests) goes through these two, never edits the Dictionary itself.
## The change is saved with the character (autosave, logout, shutdown), and the player gets
## their new pack as s2c_inventory at the end of the tick (_flush_inventories).
## Returns how many were added: only what the grid pack has room for (PackGrid.room_for),
## and stacks cap at Inventory.MAX_STACK. `force` skips the room check, only for handing back
## what was just taken (a craft that failed), so nothing is ever lost.
func give_item(id: int, item: String, qty: int, force := false) -> int:
	if not sessions.has(id) or not sessions[id].logged_in:
		return 0
	var ch: Dictionary = sessions[id].character
	if not force:
		qty = mini(qty, PackGrid.room_for(ch.inventory, ch.get("pack", []), item))
	var added := Inventory.add(ch.inventory, item, qty)
	if added > 0:
		_relayout(ch)
		sessions[id].inv_dirty = true
		print("[inventory] %s +%d %s" % [sessions[id].character.name, added, item])
	return added


## Lays `ch`'s pack out again after a change and keeps every stack's place, so the
## saved layout always names every stack (PackGrid.room_for relies on that).
func s_pack(id: int) -> Array:
	return sessions[id].character.get("pack", []) if sessions.has(id) else []


static func _relayout(ch: Dictionary) -> void:
	ch.pack = PackGrid.places_of(PackGrid.layout(ch.get("inventory", {}), ch.get("pack", [])))


## c2s_pack_move (v13): moves one stack in player `id`'s grid pack. Returns whether it moved;
## the layout goes back to the player either way, so a refused drag snaps back.
func pack_move(id: int, item: String, index: int, x: int, y: int, turned: bool) -> bool:
	if not sessions.has(id) or not sessions[id].logged_in:
		return false
	var ch: Dictionary = sessions[id].character
	var places := PackGrid.move(ch.inventory, ch.get("pack", []), item.left(32), index, x, y, turned)
	if not places.is_empty():
		ch.pack = places
		_relayout(ch)
	_send(id, "s2c_pack", [ch.pack])
	return not places.is_empty()


## c2s_pack_drop (v13): player `id` drops one whole stack of their pack (it is gone).
## Returns how many were dropped.
func pack_drop(id: int, item: String, index: int) -> int:
	if not sessions.has(id) or not sessions[id].logged_in:
		return 0
	var ch: Dictionary = sessions[id].character
	var laid := PackGrid.layout(ch.inventory, ch.get("pack", []))
	for st in (laid.placed as Array) + (laid.over as Array):
		if str(st.item) == item and int(st.index) == index:
			# The stack's own place goes too, and the stacks after it keep theirs.
			var places: Array = []
			for p in ch.get("pack", []):
				if str(p[0]) != item or int(p[1]) < index:
					places.append(p)
				elif int(p[1]) > index:
					places.append([p[0], int(p[1]) - 1, p[2], p[3], p[4]])
			var was: Array = ch.pack
			ch.pack = places
			if take_item(id, item, int(st.n)):
				print("[pack] %s dropped %d %s" % [ch.name, int(st.n), item])
				return int(st.n)
			ch.pack = was
	return 0


func _on_pack_move(id: int, item: String, index: int, x: int, y: int, turned: bool) -> void:
	if not _play_allowed(id, "_last_pack"):
		return
	pack_move(id, item, index, x, y, turned)


func _on_pack_drop(id: int, item: String, index: int) -> void:
	if not _play_allowed(id, "_last_pack"):
		return
	pack_drop(id, item, index)


## Removes exactly qty of item, or nothing. Returns whether it was removed.
func take_item(id: int, item: String, qty: int) -> bool:
	if not sessions.has(id) or not sessions[id].logged_in:
		return false
	var ok := Inventory.remove(sessions[id].character.inventory, item, qty)
	if ok:
		_relayout(sessions[id].character)
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
