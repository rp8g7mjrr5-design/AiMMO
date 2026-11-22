extends Node
## Desktop client: login screen, 3D world, avatars, camera, movement input, and chat.
## The client never decides where anyone is; it renders the server's snapshots.

const CONFIG_PATH := "user://client.cfg"

var net: Node
var world: Node3D
var camera: Camera3D
var avatars := {} ## peer id -> {node, body: Node3D, anim: WalkAnim, target: Vector3, yaw: float, name: String}
var my_id := 0
var logged_in := false
var seq := 0
var cam_yaw := 0.0
var cam_pitch := -0.35
var cam_dist := 9.0
var _send_accum := 0.0
var _last_sent := Vector2(INF, INF)

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
var time_dial: TimeDial


func start(p_net: Node, args: Dictionary) -> void:
	net = p_net
	settings = ClientSettings.load_from()
	_setup_input()
	_build_ui()
	_build_audio()
	world = WorldBuilder.build()
	add_child(world)
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
	if args.has("autoconnect"):
		_on_connect_pressed.call_deferred()
	if args.has("screenshot"):
		_screenshot_later(str(args.screenshot), float(args.get("quit-after", "8")))


func _screenshot_later(path: String, wait: float) -> void:
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
	var binds := {
		"move_forward": [KEY_W, KEY_UP],
		"move_back": [KEY_S, KEY_DOWN],
		"move_left": [KEY_A, KEY_LEFT],
		"move_right": [KEY_D, KEY_RIGHT],
	}
	for action in binds:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for k in binds[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = k
			InputMap.action_add_event(action, ev)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		if chat_edit.has_focus():
			chat_edit.release_focus()
		else:
			settings_menu.toggle()
		get_viewport().set_input_as_handled()
		return
	if not logged_in or settings_menu.visible:
		return
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		var look := look_delta(event.relative, settings)
		cam_yaw += look.x
		cam_pitch = clampf(cam_pitch + look.y, -1.2, 0.15)
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			cam_dist = maxf(3.0, cam_dist - 0.8)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			cam_dist = minf(30.0, cam_dist + 0.8)
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
			chat_feed.wake()
			chat_edit.grab_focus()
			get_viewport().set_input_as_handled()


## Camera yaw and pitch change for a mouse drag, after sensitivity and invert Y.
static func look_delta(relative: Vector2, s: ClientSettings) -> Vector2:
	return Vector2(-relative.x * 0.006, -relative.y * 0.004 * s.pitch_sign()) * s.mouse_sensitivity


func _apply_settings(s: ClientSettings) -> void:
	AudioServer.set_bus_volume_db(0, s.volume_db())
	AudioServer.set_bus_mute(0, s.master_volume <= 0.0)
	camera.far = s.draw_distance
	for sun in world.find_children("*", "DirectionalLight3D", true, false):
		sun.shadow_enabled = s.shadow_quality > 0
		if s.shadow_quality > 0:
			sun.directional_shadow_max_distance = s.shadow_distance()


func _move_vector() -> Vector2:
	if chat_edit.has_focus() or settings_menu.visible:
		return Vector2.ZERO
	var f := Input.get_action_strength("move_forward") - Input.get_action_strength("move_back")
	var r := Input.get_action_strength("move_right") - Input.get_action_strength("move_left")
	if f == 0.0 and r == 0.0:
		return Vector2.ZERO
	var forward := Vector3(-sin(cam_yaw), 0, -cos(cam_yaw))
	var right := Vector3(cos(cam_yaw), 0, -sin(cam_yaw))
	var m := (forward * f + right * r)
	m = m.normalized() if m.length() > 1.0 else m
	return Vector2(m.x, m.z)


func _process(delta: float) -> void:
	var t := 1.0 - exp(-14.0 * delta)
	for id in avatars:
		var a: Dictionary = avatars[id]
		var n: Node3D = a.node
		n.position = n.position.lerp(a.target, t)
		n.rotation.y = lerp_angle(n.rotation.y, a.yaw, t)
		var anim: WalkAnim = a.anim
		anim.step(n.position, delta)
		anim.apply(a.body)
	if not logged_in:
		# Slow orbit over the world behind the login screen.
		cam_yaw += delta * 0.05
		camera.position = Vector3(sin(cam_yaw) * 60.0, 32.0, cos(cam_yaw) * 60.0)
		camera.look_at(Vector3(0, 2, 0))
		return
	_update_chat_fade(delta)
	var move := _move_vector()
	_send_accum += delta
	if _send_accum >= GameConfig.TICK_DT:
		_send_accum = 0.0
		if move != _last_sent or move != Vector2.ZERO or seq % 10 == 0:
			seq += 1
			var yaw: float = atan2(move.x, move.y) if move != Vector2.ZERO else (avatars[my_id].yaw if avatars.has(my_id) else 0.0)
			net.c2s_input.rpc_id(1, seq, move, yaw)
			_last_sent = move
		else:
			seq += 1
	if avatars.has(my_id):
		var me: Node3D = avatars[my_id].node
		var focus := me.position + Vector3.UP * 1.6
		var offset := Vector3(sin(cam_yaw) * cos(cam_pitch), -sin(cam_pitch), cos(cam_yaw) * cos(cam_pitch)) * cam_dist
		var cam_pos := focus + offset
		cam_pos.y = maxf(cam_pos.y, Terrain.height(cam_pos.x, cam_pos.z) + 0.6)
		camera.position = camera.position.lerp(cam_pos, 1.0 - exp(-10.0 * delta))
		camera.look_at(focus)
		hud_label.text = "Ashgrove  ·  %d online  ·  %.0f, %.0f" % [avatars.size(), me.position.x, me.position.z]


## Fades the chat panel (and the time dial's readout, keeping its disk) when chat is quiet.
func _update_chat_fade(delta: float) -> void:
	var a := chat_feed.step(delta, chat_awake())
	chat_panel.modulate.a = a
	time_dial.label.modulate.a = a / ChatFeed.FULL_ALPHA


## Chat stays fully visible while you type in it, have a menu open, or point at it.
func chat_awake() -> bool:
	if chat_edit.has_focus() or settings_menu.visible:
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
	hud_label.visible = true
	help_label.visible = true
	_spawn(id, character.name, character.appearance_seed, Vector3(character.x, character.y, character.z), character.yaw)
	cam_yaw = character.yaw + PI
	_on_system(message)
	sfx_arrive.play()


func _on_server_disconnected() -> void:
	for id in avatars.keys():
		_on_player_left(id)
	logged_in = false
	DayNight.clear_sync() # back to this machine's clock (same epoch, so the sky doesn't jump)
	multiplayer.multiplayer_peer = null
	login_panel.visible = true
	chat_panel.visible = false
	time_dial.visible = false
	hud_label.visible = false
	help_label.visible = false
	connect_button.disabled = false
	_set_status("Disconnected from the server.", true)


func _on_player_joined(id: int, player_name: String, appearance_seed: int) -> void:
	if not avatars.has(id):
		_spawn(id, player_name, appearance_seed, Vector3(0, -100, 0), 0.0)


func _on_player_left(id: int) -> void:
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
			a.yaw = entries[i + 4]
			if a.node.position.y < -50.0:
				a.node.position = a.target # first sighting: no slide-in from nowhere
		i += 5


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
	chat_feed.append(chat_log, ChatFeed.system_line(TimeDial.current_seconds(), text))


func _on_chat_submitted(text: String) -> void:
	var clean := Validation.clean_chat(text)
	chat_edit.text = ""
	chat_edit.release_focus()
	if clean != "" and logged_in:
		net.c2s_chat.rpc_id(1, clean)


func _spawn(id: int, player_name: String, appearance_seed: int, pos: Vector3, yaw: float) -> void:
	var node := wrap_avatar(AvatarBuilder.build(player_name, appearance_seed, id == my_id))
	node.position = pos
	node.rotation.y = yaw
	world.add_child(node)
	avatars[id] = {"node": node, "body": node.get_node("Body"), "anim": WalkAnim.new(), "target": pos, "yaw": yaw, "name": player_name}


## Puts the built avatar under a steady root so the walk cycle can bob and sway the body
## ("Body") while the name tag stays level above it.
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
	var theme := Theme.new()
	theme.default_font_size = 16

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
	title.text = "AiMMO · Ashgrove"
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
	ui.add_child(chat_panel)
	var chat_box := VBoxContainer.new()
	chat_panel.add_child(chat_box)
	chat_log = RichTextLabel.new()
	chat_log.bbcode_enabled = true
	chat_log.scroll_following = true
	chat_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	chat_box.add_child(chat_log)
	chat_edit = LineEdit.new()
	chat_edit.placeholder_text = "Press Enter to chat · /help for commands"
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

	hud_label = Label.new()
	hud_label.theme = theme
	hud_label.position = Vector2(16, 12)
	hud_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	hud_label.add_theme_constant_override("outline_size", 6)
	hud_label.visible = false
	ui.add_child(hud_label)

	help_label = Label.new()
	help_label.theme = theme
	help_label.text = "WASD to walk · hold right mouse to look · wheel to zoom · Enter to chat · Esc for settings"
	help_label.anchor_left = 1.0
	help_label.anchor_right = 1.0
	help_label.offset_left = -760
	help_label.offset_right = -16
	help_label.offset_top = 12
	help_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	help_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	help_label.add_theme_constant_override("outline_size", 6)
	help_label.visible = false
	ui.add_child(help_label)

	settings_menu = SettingsMenu.new()
	settings_menu.setup(settings, theme)
	settings_menu.changed.connect(_apply_settings)
	settings_menu.closed.connect(func(): sfx_chime.play())
	ui.add_child(settings_menu)


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
	sfx_arrive = AudioStreamPlayer.new()
	sfx_arrive.stream = Sfx.arrive()
	sfx_arrive.volume_db = -6.0
	add_child(sfx_arrive)
