class_name ControlsOverlay
extends PanelContainer
## The controls overlay (F1, or the "?" button top right): every key the game uses, drawn as
## keycaps, read live from the InputMap so a rebound key shows its new name. It replaces typing
## "/help" in chat (owner direction 1: chat is for talking). Opening it frees the cursor like
## any other window; F1, Esc or the Close button shut it.

signal closed

const WIDTH := 460.0
const ACCENT := Color(1.0, 0.56, 0.24) ## ember orange, as the workbench window
const DIM := Color(1, 1, 1, 0.6)

## The game's default key for every rebindable action. `install_input()` puts them in the
## InputMap; the overlay (and later the rebinding window) read the InputMap, never this table.
const DEFAULT_BINDS := {
	"move_forward": [KEY_W, KEY_UP],
	"move_back": [KEY_S, KEY_DOWN],
	"move_left": [KEY_A, KEY_LEFT],
	"move_right": [KEY_D, KEY_RIGHT],
	"interact": [KEY_E],
	"free_look": [KEY_ALT],
	"swap_shoulder": [KEY_V],
	"toggle_controls": [KEY_F1],
	"toggle_skills": [KEY_K],
	"toggle_pack": [KEY_I],
	"toggle_players": [KEY_O],
	"toggle_perf": [KEY_F3],
}

## What the overlay lists, in order: [section title, [[what it does, keys], ...]].
## A key entry is an InputMap action name (shown as its first bound key), or "=Text" for a
## fixed input that isn't an action (the mouse, Enter, Esc).
const SECTIONS := [
	["Moving", [
		["Move", ["move_forward", "move_left", "move_back", "move_right"]],
		["Look around", ["=Mouse"]],
		["Free look (camera only)", ["free_look"]],
		["Swap shoulder", ["swap_shoulder"]],
		["Zoom the camera", ["=Wheel"]],
	]],
	["Doing", [
		["Gather what you look at", ["interact"]],
		["Use the workbench", ["interact"]],
	]],
	["Talking and menus", [
		["Chat", ["=Enter"]],
		["Your pack", ["toggle_pack"]],
		["Your skills and next goal", ["toggle_skills"]],
		["Who is online", ["toggle_players"]],
		["Settings, or close a window", ["=Esc"]],
		["This list", ["toggle_controls"]],
		["Frame rate and draw stats", ["toggle_perf"]],
	]],
]

var _keys_box: VBoxContainer


## Adds every default binding to the InputMap (once; existing actions keep their keys).
static func install_input() -> void:
	for action in DEFAULT_BINDS:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		for k in DEFAULT_BINDS[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = k
			InputMap.action_add_event(action, ev)


## The name of the first key bound to `action` ("W", "Alt", "F1"), "=Text" entries as their
## text, and "?" for an action with no key (so a broken binding shows, not vanishes).
static func key_text(entry: String) -> String:
	if entry.begins_with("="):
		return entry.substr(1)
	if not InputMap.has_action(entry):
		return "?"
	for ev in InputMap.action_get_events(entry):
		if ev is InputEventKey:
			var code: int = ev.physical_keycode if ev.physical_keycode != KEY_NONE else ev.keycode
			var s := OS.get_keycode_string(code)
			if s != "":
				return s
		elif ev is InputEventMouseButton:
			return "Mouse %d" % ev.button_index
	return "?"


## Every row as [section, what it does, [key names]], in display order (unit tested).
static func rows() -> Array:
	var out: Array = []
	for section in SECTIONS:
		for row in section[1]:
			var keys: Array = []
			for k in row[1]:
				keys.append(key_text(k))
			out.append([section[0], row[0], keys])
	return out


## Every InputMap action the overlay shows (so a test can check each one is bound).
static func listed_actions() -> Array:
	var out: Array = []
	for section in SECTIONS:
		for row in section[1]:
			for k in row[1]:
				if not str(k).begins_with("=") and not out.has(k):
					out.append(k)
	return out


## The one-line hint in the top-right corner while you play.
static func corner_hint() -> String:
	return "%s controls  ·  Esc settings" % key_text("toggle_controls")


func setup(theme_res: Theme) -> void:
	theme = theme_res
	visible = false
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 0.5
	anchor_bottom = 0.5
	offset_left = -WIDTH * 0.5
	offset_right = WIDTH * 0.5
	offset_top = -230
	offset_bottom = 230
	grow_vertical = Control.GROW_DIRECTION_BOTH
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.09, 0.08, 0.07, 0.9)
	bg.border_color = Color(ACCENT, 0.6)
	bg.set_border_width_all(1)
	bg.set_corner_radius_all(6)
	add_theme_stylebox_override("panel", bg)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 18)
	add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	margin.add_child(box)
	var title := Label.new()
	title.text = "Controls"
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", ACCENT)
	box.add_child(title)
	_keys_box = VBoxContainer.new()
	_keys_box.add_theme_constant_override("separation", 6)
	box.add_child(_keys_box)
	var foot := HBoxContainer.new()
	box.add_child(foot)
	var note := Label.new()
	note.text = "Key rebinding is coming to Settings."
	note.modulate = DIM
	note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(note)
	var done := Button.new()
	done.text = "Close"
	done.pressed.connect(close)
	foot.add_child(done)
	_fill()


## Rebuilds the rows from the InputMap (called on every open, so rebinds show at once).
func _fill() -> void:
	for c in _keys_box.get_children():
		_keys_box.remove_child(c)
		c.queue_free()
	var last_section := ""
	for r in rows():
		if r[0] != last_section:
			last_section = r[0]
			var head := Label.new()
			head.text = last_section
			head.add_theme_color_override("font_color", Color(ACCENT, 0.85))
			_keys_box.add_child(head)
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 4)
		_keys_box.add_child(line)
		var what := Label.new()
		what.text = r[1]
		what.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(what)
		for k in r[2]:
			line.add_child(_keycap(k))


## One key drawn as a small keycap: a dark rounded box with a lighter bottom edge.
func _keycap(text: String) -> PanelContainer:
	var cap := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.2, 0.18, 0.16, 0.95)
	sb.border_color = Color(1, 0.95, 0.88, 0.35)
	sb.set_border_width_all(1)
	sb.border_width_bottom = 3
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 1
	sb.content_margin_bottom = 2
	cap.add_theme_stylebox_override("panel", sb)
	cap.custom_minimum_size = Vector2(30, 0)
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cap.add_child(l)
	return cap


func open() -> void:
	_fill()
	visible = true


func close() -> void:
	if not visible:
		return
	visible = false
	closed.emit()


func toggle() -> void:
	if visible:
		close()
	else:
		open()
