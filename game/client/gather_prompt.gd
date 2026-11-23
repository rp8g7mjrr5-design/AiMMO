class_name GatherPrompt
extends Control
## Gathering as a game action: when you stand within reach of a tree, rock or seep, a small
## prompt above the chat says "[E] Chop Ember Ash". Press (or hold) E and the client sends
## "/gather <kind>" for that node, a short bar fills while you gather, and the server's
## answer pops up as a toast like "+2 Ash wood".
##
## The server still decides everything: reach, depletion, night-only seeps, the cooldown,
## pack room. Until protocol v3 brings c2s_gather and s2c_nodes the client can't know which
## nodes are spent, so the prompt shows for a spent node too and the server's reply (in chat)
## says so. All the rules are static functions so they are unit tested headless.

const WIDTH := 300.0
const HEIGHT := 64.0
const KEY_LABEL := "E"
## The action word per node kind, as in the design bible ("[E] Chop Ember Ash").
const VERBS := {"ash": "Chop", "pine": "Chop", "stone": "Mine", "ember_sap": "Collect"}
## Seconds between two presses: the server's gather cooldown plus a little slack for the
## round trip, and never faster than the chat cooldown (gathers travel as chat until v3).
const PRESS_INTERVAL := 1.6
const TOAST_SECONDS := 2.2
const TOAST_RISE := 26.0 ## px the toast floats up while it fades
const ACCENT := Color(1.0, 0.56, 0.24) ## ember orange, the ash leaves
const DIM := Color(0.85, 0.85, 0.85, 0.75)

var prompt_label: Label
var bar: ProgressBar
var toast_label: Label
var _target := {}
var _last_press := -INF
var _toast_age := INF


## What the prompt shows for a player at `pos` at world time `world_seconds`: the node within
## ResourceNodes.GATHER_RANGE under the reticle (look-to-interact, when `look` is given: the
## camera's eye and look direction), else the nearest one in reach, or {} for none.
## {id, kind, label, can: bool (false for a seep in daylight), text, command}.
static func target(pos: Vector3, world_seconds: float, eye := Vector3.ZERO, look := Vector3.ZERO) -> Dictionary:
	var in_reach := ResourceNodes.near(pos, ResourceNodes.GATHER_RANGE)
	if in_reach.is_empty():
		return {}
	var n: Dictionary = pick(in_reach, eye, look)
	var info := ResourceNodes.kind_info(n.kind)
	var can: bool = not (bool(info.get("night_only", false)) and not WorldClock.is_night(world_seconds))
	var label := str(info.get("label", n.kind))
	var what := "Ember Sap" if n.kind == "ember_sap" else label.capitalize()
	return {
		"id": int(n.id),
		"kind": str(n.kind),
		"label": label,
		"can": can,
		"text": ("[%s] %s %s" % [KEY_LABEL, VERBS.get(n.kind, "Gather"), what]) if can else ("%s only seeps at night" % label),
		"command": "/gather %s" % n.kind,
	}


## Look-to-interact: from `in_reach` (nearest first), the node under the reticle, falling
## back to the nearest. Until protocol v3 gathers by node id, the server picks the nearest node
## of the asked kind, so an aimed node only wins if no closer node of its kind is in reach
## (otherwise the prompt would name one node and the server would take another).
static func pick(in_reach: Array, eye: Vector3, look: Vector3) -> Dictionary:
	if look == Vector3.ZERO:
		return in_reach[0]
	var aimed := ActionCamera.aimed_node(eye, look.normalized(), in_reach)
	if aimed.is_empty():
		return in_reach[0]
	for n in in_reach:
		if n.kind == aimed.kind:
			return aimed if int(n.id) == int(aimed.id) else in_reach[0]
	return in_reach[0]


## True if a press at real time `now` may send a gather (one per PRESS_INTERVAL).
static func can_press(now: float, last_press: float) -> bool:
	return now - last_press >= PRESS_INTERVAL - 0.0001 # float slack: 11.6 - 10.0 < 1.6


## How full the gathering bar is, 0..1, `since` seconds after a press (1 = ready again).
static func progress(since: float) -> float:
	return clampf(since / PRESS_INTERVAL, 0.0, 1.0)


## Reads the server's success line ("You gather 2 ash wood from the ember ash (6 in your
## pack).", see Gathering.success) into {qty, item, label, in_pack}, or {} for any other line.
static func parse_gain(text: String) -> Dictionary:
	var m := RegEx.create_from_string("^You gather (\\d+) (.+?) from the .+? \\((\\d+) in your pack\\)").search(text)
	if m == null:
		return {}
	var label := m.get_string(2)
	var item := ""
	for id in Inventory.ITEM_ORDER:
		if Inventory.label(id).to_lower() == label.to_lower():
			item = id
	return {"qty": m.get_string(1).to_int(), "item": item, "label": label, "in_pack": m.get_string(3).to_int()}


## "+2 Ash wood  (6)" for a parsed gain.
static func toast_text(gain: Dictionary) -> String:
	var label := str(gain.label)
	return "+%d %s  (%d)" % [int(gain.qty), label.left(1).to_upper() + label.substr(1), int(gain.in_pack)]


## Toast opacity `age` seconds after it appeared: holds, then fades over the last third.
static func toast_alpha(age: float) -> float:
	if age < 0.0 or age >= TOAST_SECONDS:
		return 0.0
	var fade_from := TOAST_SECONDS * 2.0 / 3.0
	if age <= fade_from:
		return 1.0
	return 1.0 - smoothstep(fade_from, TOAST_SECONDS, age)


func setup(theme: Theme) -> void:
	self.theme = theme
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(WIDTH, HEIGHT)
	toast_label = _make_label(18, ACCENT)
	toast_label.position = Vector2(0, 0)
	toast_label.modulate.a = 0.0
	prompt_label = _make_label(16, Color.WHITE)
	prompt_label.position = Vector2(0, 26)
	bar = ProgressBar.new()
	bar.show_percentage = false
	bar.min_value = 0.0
	bar.max_value = 1.0
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.position = Vector2(WIDTH * 0.25, 52)
	bar.size = Vector2(WIDTH * 0.5, 6)
	var fill := StyleBoxFlat.new()
	fill.bg_color = ACCENT
	bar.add_theme_stylebox_override("fill", fill)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.45)
	bar.add_theme_stylebox_override("background", bg)
	bar.visible = false
	add_child(bar)
	prompt_label.visible = false


func _make_label(font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.size = Vector2(WIDTH, 24)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", 6)
	add_child(l)
	return l


## Called every logged-in frame with where you stand, whether E is held, and (optionally) the
## camera's eye and look direction for look-to-interact. Returns the
## chat command to send now ("/gather pine"), or "" for nothing.
func update(delta: float, pos: Vector3, world_seconds: float, now: float, interact_held: bool, eye := Vector3.ZERO, look := Vector3.ZERO) -> String:
	_target = target(pos, world_seconds, eye, look)
	var since := now - _last_press
	var busy := since < PRESS_INTERVAL
	prompt_label.visible = not _target.is_empty()
	if not _target.is_empty():
		prompt_label.text = _target.text
		prompt_label.add_theme_color_override("font_color", Color.WHITE if _target.can else DIM)
	bar.visible = busy and not _target.is_empty()
	bar.value = progress(since)
	_toast_age += delta
	toast_label.modulate.a = toast_alpha(_toast_age)
	toast_label.position.y = -TOAST_RISE * clampf(_toast_age / TOAST_SECONDS, 0.0, 1.0)
	if interact_held and not _target.is_empty() and _target.can and can_press(now, _last_press):
		_last_press = now
		return str(_target.command)
	return ""


## Shows "+2 Ash wood" if `text` is a gather success line. Returns whether it was.
func on_system(text: String) -> bool:
	var gain := parse_gain(text)
	if gain.is_empty():
		return false
	toast_label.text = toast_text(gain)
	_toast_age = 0.0
	toast_label.modulate.a = 1.0
	return true


func current_target() -> Dictionary:
	return _target


func hide_all() -> void:
	_target = {}
	prompt_label.visible = false
	bar.visible = false
	_toast_age = INF
	toast_label.modulate.a = 0.0
