extends Node
## Desktop client: login screen, 3D world, avatars, camera, movement input, and chat.
## The client never decides where anyone is; it renders the server's snapshots.

const CONFIG_PATH := "user://client.cfg"

var net: Node
var world: Node3D
var camera: Camera3D
var avatars := {} ## peer id -> {node, body: Node3D, skel: Skeleton3D, anim: AvatarAnimator, target: Vector3, yaw: float, name: String}
var my_id := 0
var logged_in := false
var seq := 0
var cam_yaw := 0.0 ## the slow orbit behind the login screen
var cam := ActionCamera.new() ## the over-the-shoulder camera while playing
var _send_accum := 0.0
var _last_sent := Vector2(INF, INF)
## Your own avatar walks the moment you press a key and is reconciled with the server's
## snapshots (client-side prediction); everyone else is eased toward their snapshots.
var prediction := Prediction.new()

var ui: CanvasLayer
var login_panel: PanelContainer
var address_edit: LineEdit
var name_edit: LineEdit
var password_edit: LineEdit
var connect_button: Button
var status_label: Label
var chat_panel: PanelContainer
var chat_log: RichTextLabel
var chat_edit: LineEdit
var chat_feed := ChatFeed.new()
var hud_label: Label
var help_label: Label
var sfx_chime: AudioStreamPlayer
var sfx_arrive: AudioStreamPlayer
var settings: ClientSettings
var settings_menu: SettingsMenu
var look_window: LookWindow ## character creation (first login) and "Change appearance"
var time_dial: TimeDial
var compass: CompassStrip
var gather_prompt: GatherPrompt
var xp_meter: XpMeter
var vitals_bar: VitalsBar ## health and stamina, under the XP bar (protocol v7 s2c_vitals)
var level_up_banner: LevelUpBanner
var sfx_level_up: AudioStreamPlayer
var gather_watch := GatherWatch.new() ## everyone's gathers -> node hits and empty looks
var sfx_haul := {} ## node kind -> AudioStreamPlayer for Sfx.haul(kind)
var craft_window: CraftWindow
var sfx_craft: AudioStreamPlayer
var notice_line: NoticeLine ## centre-screen system notices (chat is for talking)
var sfx_nope: AudioStreamPlayer
var sfx_miss: AudioStreamPlayer ## a left-click that did nothing (GatherPrompt.click_missed)
var sfx_hurt: AudioStreamPlayer ## you lost health (VitalsBar thump)
var footsteps: Footsteps ## turf steps in time with every avatar's walk cycle
var reticle: Reticle
## Left-click gathering: a press the game itself took (cursor captured, no window or button
## under it) since the last frame, and whether that press is still held.
var _click_tap := false
var _click_down := false
var controls_overlay: ControlsOverlay
var skills_window: SkillsWindow
var pack_window: PackWindow
var pack_button: Button
var skills_button: Button
var players_panel: PlayersPanel
var players_button: Button
var goal_label: Label
var _goal_key := "" ## which unlock the goal line names ("felling:5")
var _goal_flash := 0.0 ## seconds left on the goal line's gold flash after a new goal
var controls_button: Button
var perf_overlay: PerfOverlay
## Item icons, drawn on a background thread from the moment the game starts.
var icon_shelf := IconShelf.new()
var herd := HerdView.new() ## the grazers in view (protocol v6), smoothed
var grazers: GrazerFigures ## draws them, in the world
var _args := {} ## command-line test hooks


func start(p_net: Node, args: Dictionary) -> void:
	net = p_net
	settings = ClientSettings.load_from()
	# The saved Graphics level must be in force before the world is built: flora and motes
	# read Quality.level when they build, so a saved Low starts thin instead of building the
	# full Medium world and thinning it afterwards (qa's request, 2026-11-23).
	Quality.use(settings.graphics_quality)
	icon_shelf.start() # draws while you're on the login screen, so the first toast never hitches
	_setup_input()
	_build_ui()
	_build_audio()
	world = WorldBuilder.build()
	add_child(world)
	grazers = GrazerFigures.new()
	grazers.setup()
	world.add_child(grazers)
	camera = Camera3D.new()
	camera.far = 600.0
	camera.fov = 65.0
	add_child(camera)
	camera.position = Vector3(30, 25, 30)
	camera.look_at(Vector3(0, 2, 0))
	_apply_settings(settings)

	net.login_result.connect(_on_login_result)
	net.player_joined.connect(_on_player_joined)
	net.player_left.connect(_on_player_left)
	net.snapshot.connect(_on_snapshot)
	net.chat_message.connect(_on_chat)
	net.system_message.connect(_on_system)
	net.world_time.connect(_on_world_time)
	net.gather_begun.connect(_on_gather_begun)
	net.gather_ended.connect(_on_gather_ended)
	net.gather_result.connect(_on_gather_result)
	net.inventory_changed.connect(_on_inventory)
	net.nodes_depleted.connect(_on_nodes_depleted)
	net.node_state.connect(_on_node_state)
	net.craft_result.connect(_on_craft_result)
	net.skills_changed.connect(_on_skills)
	net.xp_gained.connect(_on_xp)
	net.level_up.connect(_on_level_up)
	net.level_up_seen.connect(_on_level_up_seen)
	net.roster_changed.connect(_on_roster)
	net.unstuck_result.connect(_on_unstuck)
	net.wildlife_changed.connect(_on_wildlife)
	net.vitals_changed.connect(_on_vitals)
	net.attack_refused.connect(_on_attack_refused)
	net.swing_begun.connect(_on_swing_begun)
	net.look_changed.connect(_on_look)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(func(): _set_status("Could not reach the server.", true))
	multiplayer.server_disconnected.connect(_on_server_disconnected)

	var cfg := ConfigFile.new()
	cfg.load(CONFIG_PATH)
	address_edit.text = str(args.get("address", cfg.get_value("login", "address", _default_address())))
	name_edit.text = cfg.get_value("login", "name", "")
	# Test hooks: --name=X --password=Y --autoconnect --screenshot=path.png --quit-after=8
	if args.has("name"):
		name_edit.text = str(args.name)
	if args.has("password"):
		password_edit.text = str(args.password)
	if args.has("open-settings"):
		settings_menu.open()
	if args.has("open-workbench"):
		_open_workbench_after_login.call_deferred()
	if args.has("show-perf"):
		perf_overlay.toggle() # test hook: the F3 overlay in a screenshot
	if args.has("open-controls"):
		_open_controls_after_login.call_deferred()
	if args.has("open-skills"):
		_open_skills_after_login.call_deferred()
	if args.has("open-pack"):
		_open_pack_after_login.call_deferred()
	if args.has("open-players"):
		_open_players_after_login.call_deferred()
	if args.has("open-look"):
		_open_look_after_login.call_deferred()
	if args.has("autoconnect"):
		_on_connect_pressed.call_deferred()
	_args = args
	if args.has("screenshot"):
		_screenshot_later(str(args.screenshot), float(args.get("quit-after", "8")))


## Test hook (--open-workbench): opens the workbench window once logged in, as E would.
func _open_workbench_after_login() -> void:
	while not logged_in or not avatars.has(my_id):
		await get_tree().process_frame
	await get_tree().create_timer(1.0).timeout
	craft_window.open(avatars[my_id].node.position)


## Test hook (--open-controls): opens the F1 controls overlay once logged in, as F1 would.
func _open_controls_after_login() -> void:
	while not logged_in:
		await get_tree().process_frame
	await get_tree().create_timer(1.0).timeout
	controls_overlay.open()


## Test hook (--open-skills): opens the K skills window once logged in, as K would.
func _open_skills_after_login() -> void:
	while not logged_in:
		await get_tree().process_frame
	await get_tree().create_timer(1.0).timeout
	skills_window.open()


## Test hook (--open-pack): opens the I pack window once logged in, as I would.
func _open_pack_after_login() -> void:
	while not logged_in:
		await get_tree().process_frame
	await get_tree().create_timer(1.0).timeout
	var spec := str(_args.get("open-pack", ""))
	if spec.contains(":"):
		# Test hook (--open-pack=ash_wood:12,stone:4): show that pack (display only, never sent),
		# and just before a --screenshot one more of the first item arrives, so the shot catches
		# that slot's gold glow and "+1" (see _screenshot_later).
		pack_window.seed_pack(_pack_spec(spec))
	pack_window.open()


## Test hook (--open-players): opens the O players panel once logged in, as O would.
## --open-players=Ash:9,Wren:14 adds those names to the real roster (display only), and just
## before a --screenshot the first of them levels up, so the shot catches the gold "+1".
func _open_players_after_login() -> void:
	while not logged_in:
		await get_tree().process_frame
	await get_tree().create_timer(1.0).timeout
	var spec := str(_args.get("open-players", ""))
	if spec.contains(":"):
		players_panel.on_roster(_players_spec(spec, players_panel.entries, false))
	players_panel.open()


## Test hook (--open-look, or --open-look=roll for a random look): opens the appearance
## window once logged in, as the Esc menu's "Change appearance" would.
func _open_look_after_login() -> void:
	while not logged_in or not avatars.has(my_id):
		await get_tree().process_frame
	await get_tree().create_timer(1.0).timeout
	if not look_window.visible:
		_open_look(false)
	if str(_args.get("open-look", "")) == "roll":
		var r := RandomNumberGenerator.new()
		r.seed = 11
		look_window.set_look(Appearance.random(r))


## The real roster plus "Ash:9,Wren:14" as made-up players (negative ids, which no real peer
## has), for the test hook; `level_first` adds one level to the first made-up player.
static func _players_spec(spec: String, real: Array, level_first: bool) -> Array:
	var out: Array = []
	for r in real:
		if int(r.id) > 0:
			out.append({"id": int(r.id), "name": str(r.name), "level": int(r.level)})
	var i := 0
	for part in spec.split(","):
		var kv := part.split(":")
		if kv.size() == 2:
			out.append({"id": -1 - i, "name": kv[0], "level": kv[1].to_int() + (1 if level_first and i == 0 else 0)})
			i += 1
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a.name).nocasecmp_to(str(b.name)) < 0)
	return out


## "ash_wood:12,stone:4" -> {"ash_wood": 12, "stone": 4} (the --open-pack test hook).
static func _pack_spec(spec: String) -> Dictionary:
	var inv := {}
	for part in spec.split(","):
		var kv := part.split(":")
		if kv.size() == 2:
			inv[kv[0]] = kv[1].to_int()
	return inv


func _screenshot_later(path: String, wait: float) -> void:
	if str(_args.get("open-pack", "")).contains(":"):
		await get_tree().create_timer(maxf(0.0, wait - 0.4)).timeout
		var inv := _pack_spec(str(_args["open-pack"]))
		if not inv.is_empty():
			var first := str(inv.keys()[0])
			inv[first] = int(inv[first]) + 1
			pack_window.seed_pack(inv)
		await get_tree().create_timer(0.4).timeout
	elif str(_args.get("open-players", "")).contains(":"):
		await get_tree().create_timer(maxf(0.0, wait - 0.4)).timeout
		players_panel.on_roster(_players_spec(str(_args["open-players"]), players_panel.entries, true))
		await get_tree().create_timer(0.4).timeout
	elif _args.has("show-notice"):
		# Test hook (--show-notice): a centre-screen refusal notice, just before the shot.
		await get_tree().create_timer(maxf(0.0, wait - 0.4)).timeout
		var words = _args["show-notice"]
		notice_line.show_notice(words if words is String and words != "" else "This ember ash is spent; it comes back in about 3 minutes. The nearest ember ash is 23 m to the north-east.")
		await get_tree().create_timer(0.4).timeout
	elif _args.has("show-vitals"):
		# Test hook (--show-vitals=hp:stamina, default 34:20): the health and stamina bar just
		# after a hit from full, caught with the chip still showing.
		await get_tree().create_timer(maxf(0.0, wait - 0.3)).timeout
		var parts := str(_args["show-vitals"]).split(":")
		var hp := int(parts[0]) if parts.size() > 0 and parts[0].is_valid_int() else 34
		var st := int(parts[1]) if parts.size() > 1 and parts[1].is_valid_int() else 20
		vitals_bar.visible = true
		vitals_bar.on_vitals(100, 100, 100, 100)
		_on_vitals(hp, 100, st, 100)
		await get_tree().create_timer(0.3).timeout
	elif _args.has("show-toast"):
		# Test hook (--show-toast=ash_wood): a "+2 Ash wood" toast with its icon, just before the shot.
		await get_tree().create_timer(maxf(0.0, wait - 0.4)).timeout
		var item := str(_args["show-toast"])
		gather_prompt.show_toast(GatherPrompt.toast_text({"qty": 2, "label": Inventory.label(item), "in_pack": 6}), item)
		if _args.has("show-xp"):
			# Test hook (--show-xp): the "+10 Felling" floater and bar that come with the haul.
			xp_meter.on_gain("felling", 10, 260)
		if _args.has("show-level-up"):
			# Test hook (--show-level-up): the level-up banner and burst, caught mid-moment.
			_on_level_up("felling", 5, [Skills.unlock_at("felling", 5)])
		await get_tree().create_timer(0.4).timeout
	else:
		await get_tree().create_timer(wait).timeout
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	print("[client] screenshot saved to ", path)
	get_tree().quit(0)


func _default_address() -> String:
	var f := "res://client/default_server.txt"
	if FileAccess.file_exists(f):
		var t := FileAccess.get_file_as_string(f).strip_edges()
		if t != "":
			return t
	return "127.0.0.1:%d" % GameConfig.DEFAULT_PORT


# --- input ---

func _setup_input() -> void:
	ControlsOverlay.install_input() # every default key lives in one table, shown by the F1 overlay


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		if look_window.visible:
			look_window.cancel()
		elif controls_overlay.visible:
			controls_overlay.close()
		elif skills_window.visible:
			skills_window.close()
		elif pack_window.visible:
			pack_window.close()
		elif players_panel.visible:
			players_panel.close()
		elif craft_window.visible:
			craft_window.close()
		elif chat_edit.has_focus():
			chat_edit.release_focus()
		else:
			settings_menu.toggle()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo and event.is_action("toggle_perf"):
		perf_overlay.toggle() # works anywhere, even on the login screen, and never takes the cursor
		get_viewport().set_input_as_handled()
		return
	if not logged_in or settings_menu.visible:
		return
	if look_window.visible:
		# Drag anywhere off the window to turn the camera round your traveller.
		if event is InputEventMouseMotion and (event.button_mask & (MOUSE_BUTTON_MASK_LEFT | MOUSE_BUTTON_MASK_RIGHT)) != 0:
			look_window.drag(event.relative.x)
		return
	if event is InputEventKey and event.pressed and not event.echo and event.is_action("toggle_controls"):
		if not craft_window.visible and not skills_window.visible and not pack_window.visible and not players_panel.visible:
			controls_overlay.toggle()
			if controls_overlay.visible:
				chat_edit.release_focus()
				sfx_chime.play()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo and event.is_action("toggle_skills"):
		_toggle_skills()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo and event.is_action("toggle_pack"):
		_toggle_pack()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo and event.is_action("toggle_players"):
		_toggle_players()
		get_viewport().set_input_as_handled()
		return
	if controls_overlay.visible or skills_window.visible or pack_window.visible or players_panel.visible:
		return
	if craft_window.visible:
		if event is InputEventKey and event.pressed and not event.echo and event.is_action("interact"):
			craft_window.close()
			get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		cam.turn(look_delta(event.relative, settings))
	elif event is InputEventMouseButton and event.pressed:
		if event.is_action("click_use") and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			_click_tap = true
			_click_down = true
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			cam.zoom(-1.0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			cam.zoom(1.0)
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
			chat_feed.wake()
			chat_edit.grab_focus()
			get_viewport().set_input_as_handled()
		elif event.is_action("swap_shoulder"):
			settings.shoulder_right = not settings.shoulder_right
			cam.side = settings.shoulder_side()
			settings.save_to()
			get_viewport().set_input_as_handled()


## Camera yaw and pitch change for a mouse movement, after sensitivity and invert Y.
static func look_delta(relative: Vector2, s: ClientSettings) -> Vector2:
	return Vector2(-relative.x * 0.006, -relative.y * 0.004 * s.pitch_sign()) * s.mouse_sensitivity


func _apply_settings(s: ClientSettings) -> void:
	AudioServer.set_bus_volume_db(0, s.volume_db())
	AudioServer.set_bus_mute(0, s.master_volume <= 0.0)
	camera.far = s.draw_distance
	camera.fov = s.field_of_view
	cam.side = s.shoulder_side()
	Quality.use(s.graphics_quality)
	for sun in world.find_children("*", "DirectionalLight3D", true, false):
		sun.shadow_enabled = s.shadow_quality > 0
		if s.shadow_quality > 0:
			sun.directional_shadow_max_distance = s.shadow_distance()


## True while a window that frees the cursor is open (Settings, the workbench, the F1 controls).
func window_open() -> bool:
	return settings_menu.visible or craft_window.visible or controls_overlay.visible or skills_window.visible or pack_window.visible or players_panel.visible or look_window.visible


## K or the Skills button: open or shut the skills window (not over another window).
func _toggle_skills() -> void:
	if craft_window.visible or controls_overlay.visible or settings_menu.visible or pack_window.visible or players_panel.visible:
		return
	skills_window.toggle()
	if skills_window.visible:
		chat_edit.release_focus()
		sfx_chime.play()


## I or the Pack button: open or shut the pack window (not over another window).
func _toggle_pack() -> void:
	if craft_window.visible or controls_overlay.visible or settings_menu.visible or skills_window.visible or players_panel.visible:
		return
	pack_window.toggle()
	if pack_window.visible:
		chat_edit.release_focus()
		sfx_chime.play()


## O or the Players button: open or shut the players panel (not over another window).
func _toggle_players() -> void:
	if craft_window.visible or controls_overlay.visible or settings_menu.visible or skills_window.visible or pack_window.visible:
		return
	players_panel.toggle()
	if players_panel.visible:
		chat_edit.release_focus()
		sfx_chime.play()


func _move_vector() -> Vector2:
	if chat_edit.has_focus() or window_open():
		return Vector2.ZERO
	var f := Input.get_action_strength("move_forward") - Input.get_action_strength("move_back")
	var r := Input.get_action_strength("move_right") - Input.get_action_strength("move_left")
	return ActionCamera.move_vector(f, r, cam.move_yaw())


func _process(delta: float) -> void:
	perf_overlay.step(delta)
	xp_meter.step(delta)
	vitals_bar.step(delta)
	level_up_banner.step(delta)
	notice_line.step(delta)
	if settings_menu.visible and settings_menu.in_game:
		settings_menu.refresh_home(Time.get_ticks_msec())
	pack_window.step(delta)
	players_panel.step(delta)
	_step_goal(delta)
	grazers.sync(herd, _now(), delta)
	var move := _move_vector() if logged_in else Vector2.ZERO
	if logged_in and prediction.has_position:
		# seq + 1 is the input that will carry this frame's walk to the server.
		prediction.advance(seq + 1, move, delta)
	var t := 1.0 - exp(-14.0 * delta)
	var ear: Vector3 = prediction.position if logged_in and prediction.has_position else camera.position
	for id in avatars:
		var a: Dictionary = avatars[id]
		var n: Node3D = a.node
		if id == my_id and prediction.has_position:
			n.position = prediction.position
		else:
			n.position = n.position.lerp(a.target, t)
		n.rotation.y = lerp_angle(n.rotation.y, a.yaw, t)
		# The whole body moves on its skeleton: idle, walk and run by rendered speed; while
		# gathering it turns to the node and works it (AvatarAnimator).
		var anim: AvatarAnimator = a.anim
		var gathering: Dictionary = ResourceNodes.get_by_id(int(gather_watch.running[id])) if gather_watch.running.has(id) else {}
		anim.step(delta, {"pos": n.position, "yaw": n.rotation.y, "gather": gathering})
		anim.apply(a.skel)
		footsteps.step(id, n, anim, my_id, ear)
	if not logged_in:
		# Slow orbit over the world behind the login screen.
		cam_yaw += delta * 0.05
		camera.position = Vector3(sin(cam_yaw) * 60.0, 32.0, cos(cam_yaw) * 60.0)
		camera.look_at(Vector3(0, 2, 0))
		return
	_update_chat_fade(delta)
	_update_mouse_capture()
	cam.set_free_look(Input.is_action_pressed("free_look") and not chat_edit.has_focus() and not window_open())
	_send_accum += delta
	if _send_accum >= GameConfig.TICK_DT:
		_send_accum = 0.0
		if move != _last_sent or move != Vector2.ZERO or seq % 10 == 0:
			seq += 1
			# While moving you face where the camera looks (or your kept heading in free-look).
			var yaw: float = ActionCamera.facing_yaw(cam.move_yaw()) if move != Vector2.ZERO else (avatars[my_id].yaw if avatars.has(my_id) else 0.0)
			net.c2s_input.rpc_id(1, seq, move, yaw)
			_last_sent = move
			if avatars.has(my_id):
				avatars[my_id].yaw = yaw # turn now; the server only echoes what we sent
		else:
			seq += 1
	if avatars.has(my_id):
		var me: Node3D = avatars[my_id].node
		var xf := cam.step(me.position, delta, Callable(Terrain, "height"), ActionCamera.camera_solids(me.position))
		if look_window.visible:
			# The appearance window: face your traveller from the front, a little to one side.
			var portrait := look_camera(me.position, avatars[my_id].yaw + look_window.orbit)
			camera.transform = camera.transform.interpolate_with(portrait, 1.0 - exp(-8.0 * delta))
		else:
			camera.transform = xf
		if compass.due(delta):
			compass.feed(cam.yaw, me.position, other_positions())
		_update_gather(delta, me.position, xf.origin, -xf.basis.z)
		_update_bench(delta, me.position)
		hud_label.text = "Ashgrove  ·  %d online  ·  %.0f, %.0f" % [avatars.size(), me.position.x, me.position.z]


## The "[E] Chop Ember Ash" prompt: press or hold E near a node to start a timed gather on
## it (c2s_gather_start), E again or moving stops it (c2s_gather_cancel). The node it targets
## is the one under the reticle (look-to-interact), else the nearest live one. Left-click
## does the same on the node under the reticle only; only a click the game took counts (see
## _unhandled_input), so the click that closes a window or presses a button never gathers.
func _update_gather(delta: float, my_pos: Vector3, eye: Vector3, look: Vector3) -> void:
	var free := not chat_edit.has_focus() and not window_open()
	var held := Input.is_action_pressed("interact") and free
	var pressed := Input.is_action_just_pressed("interact") and free
	_click_down = _click_down and free and Input.is_action_pressed("click_use")
	var click_pressed := _click_tap and free
	_click_tap = false
	var now := Time.get_ticks_msec() / 1000.0
	var op := gather_prompt.update(delta, my_pos, TimeDial.current_seconds(), now, held, pressed, _move_vector() != Vector2.ZERO, eye, look, _click_down, click_pressed)
	if gather_prompt.click_missed and sfx_miss != null:
		sfx_miss.play()
	var t := gather_prompt.current_target()
	reticle.active = not t.is_empty() and bool(t.can)
	_highlight_target(-1 if t.is_empty() or chat_edit.has_focus() else int(t.id))
	match str(op.get("op", "")):
		"start":
			net.play.c2s_gather_start.rpc_id(1, int(op.node))
		"cancel":
			net.play.c2s_gather_cancel.rpc_id(1)
	_apply_node_ops(gather_watch.tick(now))


## The workbench: "[E] Use Workbench" when you stand at it (and no node is in reach), E opens
## the crafting window. Its Craft presses go out as c2s_craft (see _setup_ui).
func _update_bench(delta: float, my_pos: Vector3) -> void:
	var at_bench := CraftWindow.near_bench(my_pos) and gather_prompt.current_target().is_empty()
	var free := not chat_edit.has_focus() and not window_open()
	gather_prompt.show_hint("[E] Use Workbench" if at_bench and free else "")
	# The bench glows warm exactly while its prompt shows (a no-op when nothing changes).
	Workbench.set_highlight(world.get_node_or_null("Workbench"), at_bench and free)
	if at_bench and free and Input.is_action_just_pressed("interact"):
		craft_window.open(my_pos)
		sfx_chime.play()
	craft_window.tick(delta, my_pos)


## World's warm glow on the node E would gather (the one under the reticle, else the nearest).
func _highlight_target(id: int) -> void:
	var nodes := world.get_node_or_null("ResourceNodes") as Node3D
	if nodes == null:
		return
	if id >= 0:
		NodeProps.set_highlight(nodes, id, true)
	else:
		var lit := NodeProps.highlighted(nodes)
		if lit >= 0:
			NodeProps.set_highlight(nodes, lit, false)


## The cursor is captured (hidden, mouse turns the camera) while you play, and freed while you
## type in chat, have Settings open, or the game window is in the background.
func _update_mouse_capture() -> void:
	var want := ActionCamera.wants_capture(logged_in, chat_edit.has_focus(), window_open(), get_window().has_focus())
	var mode := Input.MOUSE_MODE_CAPTURED if want else Input.MOUSE_MODE_VISIBLE
	if Input.mouse_mode != mode:
		Input.mouse_mode = mode
	reticle.visible = logged_in and not window_open()


## Rendered positions of every other player in the world (for the compass strip).
func other_positions() -> Array:
	var out: Array = []
	for id in avatars:
		if id == my_id:
			continue
		var n: Node3D = avatars[id].node
		if n.position.y > -50.0: # not yet placed by a snapshot
			out.append(n.position)
	return out


## Fades the chat panel (and the time dial's readout, keeping its disk) when chat is quiet.
func _update_chat_fade(delta: float) -> void:
	var a := chat_feed.step(delta, chat_awake())
	chat_panel.modulate.a = a
	time_dial.label.modulate.a = a / ChatFeed.FULL_ALPHA


## Chat stays fully visible while you type in it, have a menu open, or point at it.
func chat_awake() -> bool:
	if chat_edit.has_focus() or window_open():
		return true
	return chat_panel.get_global_rect().has_point(get_viewport().get_mouse_position())


# --- network events ---

func _on_connect_pressed() -> void:
	var n := name_edit.text.strip_edges()
	var e := Validation.check_name(n)
	if e == "":
		e = Validation.check_password(password_edit.text)
	if e != "":
		_set_status(e, true)
		return
	var parsed := Transport.parse_address(address_edit.text, "enet")
	var made := Transport.create_client(parsed[0], parsed[1], parsed[2])
	if made[1] != OK:
		_set_status("Could not start a connection: %s" % error_string(made[1]), true)
		return
	multiplayer.multiplayer_peer = made[0]
	connect_button.disabled = true
	_set_status("Connecting to %s..." % address_edit.text, false)
	var cfg := ConfigFile.new()
	cfg.set_value("login", "address", address_edit.text)
	cfg.set_value("login", "name", n)
	cfg.save(CONFIG_PATH)


func _on_connected() -> void:
	_set_status("Connected. Logging in...", false)
	net.c2s_login.rpc_id(1, GameConfig.PROTOCOL_VERSION, name_edit.text.strip_edges(), password_edit.text)


func _on_login_result(ok: bool, message: String, id: int, character: Dictionary) -> void:
	if not ok:
		if message.contains("out of date") and Updater.restart_for_update(get_tree()):
			_set_status("A new version is out. Restarting to update...", false)
			return
		_set_status(message, true)
		connect_button.disabled = false
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
		return
	my_id = id
	logged_in = true
	password_edit.text = ""
	login_panel.visible = false
	chat_panel.visible = true
	chat_feed.wake()
	time_dial.visible = true
	time_dial.refresh()
	compass.visible = true
	gather_prompt.visible = true
	xp_meter.visible = true
	vitals_bar.visible = true
	hud_label.visible = true
	help_label.visible = true
	controls_button.visible = true
	skills_button.visible = true
	pack_button.visible = true
	players_button.visible = true
	players_panel.set_me(id)
	settings_menu.set_in_game(true)
	goal_label.visible = true
	_spawn(id, character.name, character.appearance_seed, Vector3(character.x, character.y, character.z), character.yaw, Appearance.normalize(character.get("look", {})))
	# First time here (or never chose): make your traveller. Not for the automated test
	# clients (--autoconnect), which must start playing at once; --open-look shows it to them.
	if not Appearance.is_chosen(character.get("look", {})) and not _args.has("autoconnect"):
		_open_look.call_deferred(true)
	herd.clear()
	grazers.clear()
	prediction.reset()
	prediction.place(Terrain.clamp_to_world(Vector3(character.x, character.y, character.z)))
	cam.place(Vector3(character.x, character.y, character.z), character.yaw + PI)
	craft_window.seed_pack(character.get("inventory"))
	pack_window.seed_pack(character.get("inventory"))
	notice_line.show_notice(message, false) # "Welcome back, Ash." centre screen, not in chat
	sfx_arrive.play()


func _on_server_disconnected() -> void:
	for id in avatars.keys():
		_on_player_left(id)
	logged_in = false
	prediction.reset()
	DayNight.clear_sync() # back to this machine's clock (same epoch, so the sky doesn't jump)
	multiplayer.multiplayer_peer = null
	login_panel.visible = true
	chat_panel.visible = false
	time_dial.visible = false
	compass.visible = false
	gather_prompt.visible = false
	gather_prompt.hide_all()
	xp_meter.visible = false
	xp_meter.hide_all()
	vitals_bar.visible = false
	vitals_bar.hide_all()
	level_up_banner.hide_all()
	notice_line.hide_all()
	gather_watch.reset()
	herd.clear()
	grazers.clear()
	craft_window.reset()
	_highlight_target(-1)
	hud_label.visible = false
	help_label.visible = false
	controls_button.visible = false
	controls_overlay.visible = false
	skills_window.reset()
	skills_button.visible = false
	pack_window.reset()
	pack_button.visible = false
	players_panel.reset()
	settings_menu.set_in_game(false)
	look_window.reset()
	players_button.visible = false
	players_button.text = PlayersPanel.button_text(0)
	goal_label.visible = false
	goal_label.text = ""
	_goal_key = ""
	reticle.visible = false
	reticle.active = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	connect_button.disabled = false
	_set_status("Disconnected from the server.", true)


func _on_player_joined(id: int, player_name: String, appearance_seed: int) -> void:
	if not avatars.has(id):
		_spawn(id, player_name, appearance_seed, Vector3(0, -100, 0), 0.0)


func _on_player_left(id: int) -> void:
	gather_watch.forget(id)
	footsteps.forget(id)
	if avatars.has(id):
		avatars[id].node.queue_free()
		avatars.erase(id)


func _on_snapshot(_tick: int, entries: Array) -> void:
	var i := 0
	while i + 4 < entries.size():
		var id: int = entries[i]
		if avatars.has(id):
			var a: Dictionary = avatars[id]
			a.target = Vector3(entries[i + 1], entries[i + 2], entries[i + 3])
			if id == my_id:
				# Replay the walk the server hasn't seen on top of where it has you.
				var snaps_before := prediction.snaps
				prediction.reconcile(a.target, net.last_ack_seq)
				if prediction.snaps != snaps_before:
					# A teleport (Return to Spawn Meadow): the camera goes with you, not across the map.
					cam.jump_to(prediction.position)
				i += 5
				continue
			a.yaw = entries[i + 4]
			if a.node.position.y < -50.0:
				a.node.position = a.target # first sighting: no slide-in from nowhere
		i += 5


## The grazers in view (protocol v6, about 5 a second): smoothed by HerdView, drawn by
## GrazerFigures; a bolt kicks up dust and snorts where it happens.
func _on_wildlife(entries: PackedFloat32Array) -> void:
	if not logged_in:
		return
	var now := _now()
	grazers.play_events(herd.feed(entries, now), herd, now)


static func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


## The server's clock (at login and every WORLD_TIME_SYNC_SECONDS). DayNight keeps it and
## runs it on between syncs; the sky and the time dial both read it from there.
func _on_world_time(world_seconds: float) -> void:
	DayNight.set_world_seconds(world_seconds)
	if time_dial and time_dial.visible:
		time_dial.refresh()


func _on_chat(from_name: String, text: String) -> void:
	chat_feed.append(chat_log, ChatFeed.chat_line(TimeDial.current_seconds(), from_name, text))
	sfx_chime.play()


func _on_system(text: String) -> void:
	if level_up_banner != null and level_up_banner.consume_system(text):
		return # the banner already said it (chat is for talking)
	var echo := gather_prompt != null and gather_prompt.on_system(text)
	if echo:
		return # the bar and the toast already said it
	if notice_line == null: # not set up (unit tests of the chat handlers): chat as before
		chat_feed.append(chat_log, ChatFeed.system_line(TimeDial.current_seconds(), text))
		return
	var paired := notice_line.paired_reason() != "" # its refusal already played the nope
	match notice_line.on_system(text):
		"chat": # someone arrived or left (or a long dev answer): about people, so chat
			chat_feed.append(chat_log, ChatFeed.system_line(TimeDial.current_seconds(), text))
		"notice":
			if not paired and sfx_nope != null:
				sfx_nope.play()


# --- timed gathering (protocol v3, Net/Play) ---

func _on_gather_begun(peer: int, node_id: int, seconds: float) -> void:
	gather_watch.begun(peer, node_id)
	if peer == my_id:
		gather_prompt.on_begun(node_id, seconds, Time.get_ticks_msec() / 1000.0)


func _on_gather_ended(peer: int, node_id: int, reason: String) -> void:
	_apply_node_ops(gather_watch.ended(peer, node_id, reason))
	if peer == my_id:
		if gather_prompt.on_ended(node_id, reason) != "":
			notice_line.note_refusal(reason) # the server's longer line may only repeat it
			sfx_nope.play()


func _on_gather_result(item_id: String, count: int) -> void:
	gather_prompt.on_result(item_id, count)
	var kind := ""
	for k in ResourceNodes.KINDS:
		if str(ResourceNodes.KINDS[k].item) == item_id:
			kind = k
	var p: AudioStreamPlayer = sfx_haul.get(kind, sfx_haul.get("ash"))
	if p:
		p.play()


# --- skills and XP (protocol v4, Net/Play) ---

func _on_skills(skills: Dictionary) -> void:
	xp_meter.on_skills(skills)
	skills_window.on_skills(skills)
	_share_skills()
	_update_goal(false)


## s2c_xp arrives right after the gather/craft result, so the "+10 Felling" pops in the same
## frame as the haul toast.
func _on_xp(skill: String, gained: int, total_xp: int) -> void:
	xp_meter.on_gain(skill, gained, total_xp)
	skills_window.on_gain(skill, total_xp)
	_share_skills()
	_update_goal(true)


## The gather prompt and the workbench read your levels too: a tier-2 node or an ember tool
## above your level says what it needs instead of offering E or Craft.
## s2c_roster: everyone online, for the players panel and the count on its button.
func _on_roster(entries: Array) -> void:
	players_panel.on_roster(entries)
	players_button.text = PlayersPanel.button_text(players_panel.entries.size())


func _share_skills() -> void:
	gather_prompt.skills = skills_window.skills.duplicate()
	craft_window.on_skills(skills_window.skills)


## The goal line under the compass: the closest named unlock. When it moves on to a new goal
## (you just reached the old one), it flashes gold for a moment.
func _update_goal(flash: bool) -> void:
	var before := _goal_key
	_goal_key = SkillsWindow.goal_key(skills_window.skills)
	goal_label.text = SkillsWindow.goal_text(skills_window.skills)
	if flash and before != "" and before != _goal_key:
		_goal_flash = SkillsWindow.GOAL_FLASH_SECONDS


## The goal line steps aside while the level-up banner (just below it) is up, and its gold
## "new goal" flash waits for the banner to go, so the two read one after the other.
func _step_goal(delta: float) -> void:
	var banner_a := level_up_banner.current_alpha()
	goal_label.modulate.a = SkillsWindow.goal_alpha(banner_a)
	if _goal_flash <= 0.0:
		return
	_goal_flash = SkillsWindow.goal_flash_after(_goal_flash, delta, banner_a > 0.0)
	goal_label.add_theme_color_override("font_color", SkillsWindow.goal_colour(_goal_flash / SkillsWindow.GOAL_FLASH_SECONDS))


## s2c_level_up: the banner, the rising chord and world's burst on your own avatar, together.
func _on_level_up(skill: String, level: int, unlocks: Array) -> void:
	level_up_banner.on_level_up(skill, level, unlocks)
	sfx_level_up.play()
	if avatars.has(my_id):
		LevelUpFx.play(avatars[my_id].node, level)


## s2c_level_up_seen: someone near you levelled; the same burst over them, no banner or sound.
func _on_level_up_seen(peer_id: int, _skill: String, level: int) -> void:
	if avatars.has(peer_id) and peer_id != my_id:
		LevelUpFx.play(avatars[peer_id].node, peer_id * 31 + level)


## The bench's answer to a Craft press: the window shows the server's words; a success also
## gets the toast with the product's icon and the craft sound (the Toolcraft "+N" floater
## comes from s2c_xp, sent with it).
## The answer to the Esc menu's "Return to Spawn Meadow". On ok the next snapshot carries
## you home (prediction snaps, the camera jumps with it in _on_snapshot); the menu closes so
## you see the meadow, and the words show centre screen, never in chat.
func _on_unstuck(ok: bool, text: String, wait_seconds: float) -> void:
	settings_menu.home.answered(ok, wait_seconds, Time.get_ticks_msec())
	settings_menu.refresh_home(Time.get_ticks_msec())
	notice_line.show_notice(text, not ok)
	if ok:
		settings_menu.close(true)
		sfx_arrive.play()
	else:
		sfx_nope.play()


func _on_craft_result(recipe_id: String, ok: bool, text: String) -> void:
	var r := craft_window.on_craft_result(recipe_id, ok, text)
	if str(r.crafted) != "":
		gather_prompt.show_toast(CraftWindow.toast_text(str(r.crafted)), str(r.crafted))
		sfx_craft.play()


func _on_inventory(items: Dictionary) -> void:
	gather_prompt.pack = items
	craft_window.seed_pack(items)
	pack_window.seed_pack(items)


## At login: every node that is empty right now (the rest show live, in case they were
## empty in an earlier session).
func _on_nodes_depleted(ids: Array) -> void:
	var dead := {}
	for id in ids:
		dead[int(id)] = true
	gather_prompt.spent = dead
	var nodes := world.get_node_or_null("ResourceNodes") as Node3D
	if nodes == null:
		return
	for n in ResourceNodes.all():
		NodeProps.set_depleted(nodes, int(n.id), dead.has(int(n.id)))


func _on_node_state(node_id: int, depleted: bool) -> void:
	# The prompt stops offering it at once; its empty look may wait for the last hit.
	if depleted:
		gather_prompt.spent[node_id] = true
	else:
		gather_prompt.spent.erase(node_id)
	_apply_node_ops(gather_watch.node_state(node_id, depleted, Time.get_ticks_msec() / 1000.0))


func _apply_node_ops(ops: Array) -> void:
	var nodes := world.get_node_or_null("ResourceNodes") as Node3D
	if nodes == null:
		return
	for op in ops:
		if op[0] == "hit":
			NodeProps.play_hit(nodes, int(op[1]))
		elif op[0] == "deplete":
			NodeProps.set_depleted(nodes, int(op[1]), bool(op[2]))


func _on_chat_submitted(text: String) -> void:
	var clean := Validation.clean_chat(text)
	chat_edit.text = ""
	chat_edit.release_focus()
	if clean != "" and logged_in:
		net.c2s_chat.rpc_id(1, clean)


func _spawn(id: int, player_name: String, appearance_seed: int, pos: Vector3, yaw: float, look: Dictionary = {}) -> void:
	var node := wrap_avatar(AvatarBuilder.build(player_name, appearance_seed, id == my_id, look))
	node.position = pos
	node.rotation.y = yaw
	if id == my_id:
		# Your own name would hang right in front of the over-the-shoulder camera.
		for tag in node.find_children("*", "Label3D", false, false):
			tag.visible = false
	world.add_child(node)
	avatars[id] = {"node": node, "body": node.get_node("Body"), "skel": node.get_node("Body/Skeleton"), "anim": AvatarAnimator.new(), "target": pos, "yaw": yaw, "name": player_name, "seed": appearance_seed, "look": look}


## Redraws avatar `id` in `look` (Appearance; {} = their seed look) where it stands, keeping
## its name tag and its animation state.
func _restyle(id: int, look: Dictionary) -> void:
	if not avatars.has(id):
		return
	var a: Dictionary = avatars[id]
	var node: Node3D = a.node
	var old: Node3D = a.body
	var body := AvatarBuilder.build(str(a.name), int(a.seed), id == my_id, look)
	for tag in body.find_children("*", "Label3D", false, false):
		body.remove_child(tag)
		tag.free()
	body.name = "Body"
	node.remove_child(old)
	old.queue_free()
	node.add_child(body)
	a.body = body
	a.skel = body.get_node("Skeleton")


## s2c_look (v8): peer_id saved a look, or this is the look of someone who just came into the
## world. Your own, while the window is open, only updates what Cancel goes back to.
func _on_look(peer_id: int, look: Dictionary) -> void:
	if not avatars.has(peer_id):
		return
	var lk := Appearance.normalize(look)
	avatars[peer_id].look = lk
	if peer_id == my_id and look_window.visible:
		look_window.original = lk
		return
	_restyle(peer_id, lk)


## Opens the appearance window on your current look (`creating` on first login).
func _open_look(creating: bool) -> void:
	if not logged_in or not avatars.has(my_id):
		return
	for w in [craft_window, controls_overlay, skills_window, pack_window, players_panel]:
		if w.visible:
			w.close()
	chat_edit.release_focus()
	look_window.open(avatars[my_id].look, int(avatars[my_id].seed), creating)


## The appearance window's camera: in front of a traveller at `pos` facing `yaw`, at chest
## height a little over two metres off, looking at their upper body (the window sits on the
## left, so the figure is framed right of centre).
static func look_camera(pos: Vector3, yaw: float) -> Transform3D:
	var fwd := Vector3(sin(yaw), 0.0, cos(yaw))
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))
	var eye := pos + fwd * 2.5 + right * 0.55 + Vector3(0, 1.45, 0)
	var target := pos + right * 0.55 + Vector3(0, 1.15, 0)
	return Transform3D.IDENTITY.looking_at(target - eye, Vector3.UP).translated(eye)


## Puts the built avatar ("Body", holding its Skeleton) under a steady root, with the name tag
## moved up to that root so it stays level whatever the body is doing.
static func wrap_avatar(body: Node3D) -> Node3D:
	var root := Node3D.new()
	body.name = "Body"
	root.add_child(body)
	for tag in body.find_children("*", "Label3D", false, false):
		body.remove_child(tag)
		root.add_child(tag)
	return root


func _set_status(text: String, is_error: bool) -> void:
	status_label.text = text
	status_label.modulate = Color(1, 0.55, 0.5) if is_error else Color(0.85, 0.95, 1.0)


# --- UI construction ---

func _build_ui() -> void:
	ui = CanvasLayer.new()
	add_child(ui)
	var theme := HudStyle.theme() # one quiet look for every window and button (art bible section 9)

	login_panel = PanelContainer.new()
	login_panel.theme = theme
	login_panel.position = Vector2(40, 40)
	login_panel.custom_minimum_size = Vector2(420, 0)
	ui.add_child(login_panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 18)
	login_panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	margin.add_child(box)

	var title := Label.new()
	title.text = "ZombAi · Ashgrove"
	title.add_theme_font_size_override("font_size", 30)
	box.add_child(title)
	var sub := Label.new()
	sub.text = "A world built and run by AI."
	sub.modulate = Color(1, 1, 1, 0.7)
	box.add_child(sub)

	address_edit = _field(box, "Server", "host:port, or ws://host:port")
	name_edit = _field(box, "Name", "3 to 16 letters, numbers, or _")
	password_edit = _field(box, "Password", "New name? This sets your password.")
	password_edit.secret = true
	password_edit.text_submitted.connect(func(_t): _on_connect_pressed())
	connect_button = Button.new()
	connect_button.text = "Enter the world"
	connect_button.pressed.connect(_on_connect_pressed)
	box.add_child(connect_button)
	var settings_button := Button.new()
	settings_button.text = "Settings"
	settings_button.flat = true
	settings_button.pressed.connect(func(): settings_menu.open())
	box.add_child(settings_button)
	status_label = Label.new()
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(status_label)

	var notes_title := Label.new()
	notes_title.text = "Patch notes"
	notes_title.add_theme_font_size_override("font_size", 20)
	box.add_child(notes_title)
	var notes := RichTextLabel.new()
	notes.bbcode_enabled = true
	notes.custom_minimum_size = Vector2(0, 200)
	notes.text = PatchNotes.to_bbcode(PatchNotes.load_text())
	box.add_child(notes)

	# Chat, bottom-left.
	chat_panel = PanelContainer.new()
	chat_panel.theme = theme
	chat_panel.anchor_top = 1.0
	chat_panel.anchor_bottom = 1.0
	chat_panel.offset_left = 16
	chat_panel.offset_top = -260
	chat_panel.offset_right = 476
	chat_panel.offset_bottom = -16
	chat_panel.visible = false
	chat_panel.modulate = Color(1, 1, 1, ChatFeed.FULL_ALPHA)
	# Chat sits over the world all the time, so it is the quietest panel: lighter, no edge.
	var chat_bg := HudStyle.panel(0.5)
	chat_bg.border_color = Color(0, 0, 0, 0)
	chat_panel.add_theme_stylebox_override("panel", chat_bg)
	ui.add_child(chat_panel)
	var chat_box := VBoxContainer.new()
	chat_panel.add_child(chat_box)
	chat_log = RichTextLabel.new()
	chat_log.bbcode_enabled = true
	chat_log.scroll_following = true
	chat_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	chat_box.add_child(chat_log)
	chat_edit = LineEdit.new()
	chat_edit.placeholder_text = "Press Enter to chat · %s for controls" % ControlsOverlay.key_text("toggle_controls")
	chat_edit.max_length = GameConfig.CHAT_MAX
	chat_edit.text_submitted.connect(_on_chat_submitted)
	chat_box.add_child(chat_edit)

	# Sun/moon dial with the in-game time, just above the chat.
	time_dial = TimeDial.new()
	time_dial.anchor_top = 1.0
	time_dial.anchor_bottom = 1.0
	time_dial.offset_left = 16
	time_dial.offset_top = -316
	time_dial.offset_right = 476
	time_dial.offset_bottom = -266
	time_dial.visible = false
	ui.add_child(time_dial)
	time_dial.setup(theme)

	# Compass strip, top centre: cardinal points, other players, and the way home.
	compass = CompassStrip.new()
	compass.anchor_left = 0.5
	compass.anchor_right = 0.5
	compass.offset_left = -CompassStrip.WIDTH * 0.5
	compass.offset_right = CompassStrip.WIDTH * 0.5
	compass.offset_top = 44
	compass.offset_bottom = 44 + CompassStrip.HEIGHT
	compass.visible = false
	ui.add_child(compass)
	compass.setup(theme)

	# The next goal, just under the compass: "Next: Felling 5 unlocks Old ember ash (240 XP)".
	goal_label = Label.new()
	goal_label.theme = theme
	goal_label.anchor_left = 0.5
	goal_label.anchor_right = 0.5
	goal_label.offset_left = -CompassStrip.WIDTH * 0.5 - 60
	goal_label.offset_right = CompassStrip.WIDTH * 0.5 + 60
	goal_label.offset_top = 76
	goal_label.offset_bottom = 96
	goal_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	HudStyle.quiet_label(goal_label, 13, SkillsWindow.goal_colour(0.0))
	goal_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	goal_label.visible = false
	ui.add_child(goal_label)

	# Gather prompt and "+2 ash wood" toasts, bottom centre.
	gather_prompt = GatherPrompt.new()
	gather_prompt.anchor_left = 0.5
	gather_prompt.anchor_right = 0.5
	gather_prompt.anchor_top = 1.0
	gather_prompt.anchor_bottom = 1.0
	gather_prompt.offset_left = -GatherPrompt.WIDTH * 0.5
	gather_prompt.offset_right = GatherPrompt.WIDTH * 0.5
	gather_prompt.offset_top = -170
	gather_prompt.offset_bottom = -170 + GatherPrompt.HEIGHT
	gather_prompt.visible = false
	gather_prompt.icons = icon_shelf
	ui.add_child(gather_prompt)
	gather_prompt.setup(theme)

	# XP you can see: "+10 Felling" and that skill's bar, just under the gather prompt.
	xp_meter = XpMeter.new()
	xp_meter.anchor_left = 0.5
	xp_meter.anchor_right = 0.5
	xp_meter.anchor_top = 1.0
	xp_meter.anchor_bottom = 1.0
	xp_meter.offset_left = -XpMeter.WIDTH * 0.5
	xp_meter.offset_right = XpMeter.WIDTH * 0.5
	xp_meter.offset_top = -100
	xp_meter.offset_bottom = -100 + XpMeter.HEIGHT
	xp_meter.visible = false
	ui.add_child(xp_meter)
	xp_meter.setup(theme)
	# Health and stamina, bottom centre under the XP bar: where an action MMO keeps them.
	vitals_bar = VitalsBar.new()
	vitals_bar.anchor_left = 0.5
	vitals_bar.anchor_right = 0.5
	vitals_bar.anchor_top = 1.0
	vitals_bar.anchor_bottom = 1.0
	vitals_bar.offset_left = -VitalsBar.WIDTH * 0.5 + 30.0 # the bars centre; the number hangs right
	vitals_bar.offset_right = VitalsBar.WIDTH * 0.5 + 30.0
	vitals_bar.offset_top = -44
	vitals_bar.offset_bottom = -44 + VitalsBar.HEIGHT
	vitals_bar.visible = false
	ui.add_child(vitals_bar)
	vitals_bar.setup(theme)
	# System notices and refusals, centre screen just above the reticle (chat is for talking).
	notice_line = NoticeLine.new()
	notice_line.anchor_left = 0.5
	notice_line.anchor_right = 0.5
	notice_line.anchor_top = 0.5
	notice_line.anchor_bottom = 0.5
	notice_line.offset_left = -NoticeLine.WIDTH * 0.5
	notice_line.offset_right = NoticeLine.WIDTH * 0.5
	notice_line.offset_top = -150
	notice_line.offset_bottom = -150 + NoticeLine.HEIGHT
	ui.add_child(notice_line)
	notice_line.setup(theme)
	level_up_banner = LevelUpBanner.new()
	level_up_banner.anchor_left = 0.5
	level_up_banner.anchor_right = 0.5
	level_up_banner.offset_left = -LevelUpBanner.WIDTH * 0.5
	level_up_banner.offset_right = LevelUpBanner.WIDTH * 0.5
	level_up_banner.offset_top = 96
	level_up_banner.offset_bottom = 96 + LevelUpBanner.HEIGHT
	ui.add_child(level_up_banner)
	level_up_banner.setup(theme)

	# Centre reticle for the action camera: what you look at is what E gathers.
	reticle = Reticle.new()
	reticle.setup()
	reticle.visible = false
	ui.add_child(reticle)

	hud_label = Label.new()
	hud_label.theme = theme
	hud_label.position = Vector2(16, 12)
	HudStyle.quiet_label(hud_label, 15, HudStyle.TEXT)
	hud_label.visible = false
	ui.add_child(hud_label)

	help_label = Label.new()
	help_label.theme = theme
	help_label.text = ControlsOverlay.corner_hint()
	help_label.anchor_left = 1.0
	help_label.anchor_right = 1.0
	help_label.offset_left = -610
	help_label.offset_right = -270
	help_label.offset_top = 12
	help_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	HudStyle.quiet_label(help_label, 15, HudStyle.TEXT)
	help_label.visible = false
	ui.add_child(help_label)

	# "?" button beside the corner hint: the same controls list as F1, for mouse players.
	controls_button = Button.new()
	controls_button.theme = theme
	controls_button.text = "?"
	controls_button.tooltip_text = "Controls (%s)" % ControlsOverlay.key_text("toggle_controls")
	controls_button.focus_mode = Control.FOCUS_NONE
	controls_button.anchor_left = 1.0
	controls_button.anchor_right = 1.0
	controls_button.offset_left = -44
	controls_button.offset_right = -16
	controls_button.offset_top = 10
	controls_button.offset_bottom = 38
	controls_button.visible = false
	controls_button.pressed.connect(func():
		if not craft_window.visible and not settings_menu.visible and not skills_window.visible and not pack_window.visible and not players_panel.visible:
			controls_overlay.toggle()
			sfx_chime.play())
	ui.add_child(controls_button)

	# "Skills" button left of the "?": the same window as K, for mouse players.
	skills_button = Button.new()
	skills_button.theme = theme
	skills_button.text = "Skills"
	skills_button.tooltip_text = "Skills (%s)" % ControlsOverlay.key_text("toggle_skills")
	skills_button.focus_mode = Control.FOCUS_NONE
	skills_button.anchor_left = 1.0
	skills_button.anchor_right = 1.0
	skills_button.offset_left = -112
	skills_button.offset_right = -52
	skills_button.offset_top = 10
	skills_button.offset_bottom = 38
	skills_button.visible = false
	skills_button.pressed.connect(_toggle_skills)
	ui.add_child(skills_button)

	# "Pack" button left of "Skills": the same window as I, for mouse players.
	pack_button = Button.new()
	pack_button.theme = theme
	pack_button.text = "Pack"
	pack_button.tooltip_text = "Pack (%s)" % ControlsOverlay.key_text("toggle_pack")
	pack_button.focus_mode = Control.FOCUS_NONE
	pack_button.anchor_left = 1.0
	pack_button.anchor_right = 1.0
	pack_button.offset_left = -172
	pack_button.offset_right = -120
	pack_button.offset_top = 10
	pack_button.offset_bottom = 38
	pack_button.visible = false
	pack_button.pressed.connect(_toggle_pack)
	ui.add_child(pack_button)

	# "Players 5" button left of "Pack": the same panel as O, with the live head count.
	players_button = Button.new()
	players_button.theme = theme
	players_button.text = PlayersPanel.button_text(0)
	players_button.tooltip_text = "Who is online (%s)" % ControlsOverlay.key_text("toggle_players")
	players_button.focus_mode = Control.FOCUS_NONE
	players_button.anchor_left = 1.0
	players_button.anchor_right = 1.0
	players_button.offset_left = -262
	players_button.offset_right = -180
	players_button.offset_top = 10
	players_button.offset_bottom = 38
	players_button.visible = false
	players_button.pressed.connect(_toggle_players)
	ui.add_child(players_button)

	# The F1 controls overlay, centre screen.
	perf_overlay = PerfOverlay.new()
	perf_overlay.setup(theme)
	ui.add_child(perf_overlay)
	controls_overlay = ControlsOverlay.new()
	controls_overlay.setup(theme)
	controls_overlay.closed.connect(func(): sfx_chime.play())
	ui.add_child(controls_overlay)

	# The K skills window, centre screen.
	skills_window = SkillsWindow.new()
	skills_window.setup(theme)
	skills_window.closed.connect(func(): sfx_chime.play())
	ui.add_child(skills_window)

	# The I pack window, centre screen.
	pack_window = PackWindow.new()
	pack_window.icons = icon_shelf
	pack_window.setup(theme)
	pack_window.closed.connect(func(): sfx_chime.play())
	ui.add_child(pack_window)

	# The O players panel, centre screen.
	players_panel = PlayersPanel.new()
	players_panel.setup(theme)
	players_panel.closed.connect(func(): sfx_chime.play())
	ui.add_child(players_panel)

	# The workbench window, centre screen (E at the Spawn Meadow workbench).
	craft_window = CraftWindow.new()
	craft_window.icons = icon_shelf
	craft_window.setup(theme)
	craft_window.closed.connect(func(): sfx_chime.play())
	craft_window.craft_requested.connect(func(id: String):
		if multiplayer.multiplayer_peer != null and logged_in:
			net.play.c2s_craft.rpc_id(1, id))
	ui.add_child(craft_window)

	settings_menu = SettingsMenu.new()
	settings_menu.setup(settings, theme)
	settings_menu.changed.connect(_apply_settings)
	settings_menu.closed.connect(func():
		if not settings_menu.quiet_close:
			sfx_chime.play())
	settings_menu.home_requested.connect(func(): net.play.c2s_unstuck.rpc_id(1))
	settings_menu.look_requested.connect(func(): _open_look(false))
	ui.add_child(settings_menu)

	look_window = LookWindow.new()
	look_window.setup(theme)
	look_window.previewed.connect(func(lk: Dictionary): _restyle(my_id, lk))
	look_window.saved.connect(func(lk: Dictionary):
		if multiplayer.multiplayer_peer != null and logged_in:
			net.play.c2s_set_look.rpc_id(1, lk)
			avatars[my_id].look = lk)
	look_window.closed.connect(func(): sfx_chime.play())
	ui.add_child(look_window)


func _field(parent: Control, label_text: String, placeholder: String) -> LineEdit:
	var l := Label.new()
	l.text = label_text
	parent.add_child(l)
	var e := LineEdit.new()
	e.placeholder_text = placeholder
	parent.add_child(e)
	return e


func _build_audio() -> void:
	sfx_chime = AudioStreamPlayer.new()
	sfx_chime.stream = Sfx.chime()
	sfx_chime.volume_db = -8.0
	add_child(sfx_chime)
	for kind in ResourceNodes.KINDS:
		var p := AudioStreamPlayer.new()
		p.stream = Sfx.haul(kind)
		p.volume_db = -6.0
		add_child(p)
		sfx_haul[kind] = p
	sfx_craft = AudioStreamPlayer.new()
	sfx_craft.stream = Sfx.craft()
	sfx_craft.volume_db = -4.0
	add_child(sfx_craft)
	sfx_nope = AudioStreamPlayer.new()
	sfx_nope.stream = Sfx.nope()
	sfx_nope.volume_db = -9.0
	add_child(sfx_nope)
	sfx_miss = AudioStreamPlayer.new()
	sfx_miss.stream = Sfx.miss()
	sfx_miss.volume_db = -12.0
	add_child(sfx_miss)
	sfx_hurt = AudioStreamPlayer.new()
	sfx_hurt.stream = Sfx.hurt()
	sfx_hurt.volume_db = -8.0
	add_child(sfx_hurt)
	sfx_level_up = AudioStreamPlayer.new()
	sfx_level_up.stream = Sfx.level_up()
	sfx_level_up.volume_db = -3.0
	add_child(sfx_level_up)
	sfx_arrive = AudioStreamPlayer.new()
	sfx_arrive.stream = Sfx.arrive()
	sfx_arrive.volume_db = -6.0
	add_child(sfx_arrive)
	footsteps = Footsteps.new()
	footsteps.build(self)


func _exit_tree() -> void:
	icon_shelf.finish() # join the icon thread so quitting never leaves it running


## s2c_vitals (protocol v7): once at login, then on every whole-point change.
func _on_vitals(hp: int, max_hp: int, stamina: int, max_stamina: int) -> void:
	var c := vitals_bar.on_vitals(hp, max_hp, stamina, max_stamina)
	if c.thump:
		sfx_hurt.play()


## s2c_swing (v7): someone in view, maybe you, started a swing. Their body plays it: the
## wind-up, the blow and the recovery, timed by the weapon's numbers and stretched to the
## server's `seconds` so the blow lands on screen when the server lands it.
func _on_swing_begun(peer_id: int, weapon: String, kind: String, seconds: float) -> void:
	if not avatars.has(peer_id):
		return
	var a := Weapons.attack(weapon, kind)
	if a.is_empty():
		return
	var total := float(a.windup) + float(a.active) + float(a.recovery)
	var k := seconds / total if seconds > 0.0 and total > 0.0 else 1.0
	(avatars[peer_id].anim as AvatarAnimator).swing(kind, float(a.windup) * k, float(a.active) * k, float(a.recovery) * k)


## s2c_attack_refused: "busy" is dropped quietly (a mashed button); being winded or tired
## reddens the stamina bar and says why centre screen, so the "no" points at the bar.
func _on_attack_refused(_kind: String, reason: String) -> void:
	if reason == "winded" or reason == "tired":
		vitals_bar.flash_stamina()
		notice_line.show_notice(Weapons.refusal_text(reason), true)
		sfx_nope.play()
