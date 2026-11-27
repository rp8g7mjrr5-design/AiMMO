class_name LookWindow
extends PanelContainer
## The character-creation window: how your traveller looks on the road (Appearance). It opens
## by itself the first time you log in (and at every login until you pick a look), and again
## from the Esc menu's "Change appearance" whenever you like.
##
## One row per option (build, height, skin, face, hair, hair colour, beard, head, tunic,
## trousers), each with ◀ and ▶ arrows that step through its choices. Every step redraws your
## own character at once (`previewed`), and the camera swings round in front of you so you
## see the face you're making; drag anywhere off the window to turn round them. "Roll" picks
## a random look. Nothing is sent until "Set out" (first time) or "Save": that emits `saved`
## and the client sends c2s_set_look; the server stores it and shows it to everyone.
## "Cancel" or Esc puts your old look back.
##
## The texts are static over a look Dictionary, so unit tests check them without a window.

signal previewed(look: Dictionary)
signal saved(look: Dictionary)
signal closed

const WIDTH := 360.0
const ACCENT := Color(1.0, 0.56, 0.24) ## ember orange, as the other windows
const DIM := Color(1, 1, 1, 0.6)
const CREATE_TITLE := "Make your traveller"
const EDIT_TITLE := "Your appearance"
const CREATE_HINT := "How you look on the road. You can change it any time from the Esc menu."
const EDIT_HINT := "Everyone sees your new look as soon as you save."
const TURN_HINT := "Drag to turn around your traveller."

var look: Dictionary = {} ## what the rows show now (always complete while open)
var original: Dictionary = {} ## what to put back on Cancel ({} = the seed look)
var creating := false ## first time: "Set out" and no Cancel
var orbit := 0.0 ## radians the camera has been dragged round the traveller
var rng := RandomNumberGenerator.new()
var _title: Label
var _hint: Label
var _values := {} ## option key -> its value Label
var _cancel: Button
var _save: Button


## The rows the window shows for `look`: [{key, label, value}] in Appearance.ORDER.
static func rows(look_in: Dictionary) -> Array:
	var lk := Appearance.normalize(look_in) if Appearance.is_chosen(look_in) else Appearance.DEFAULT.duplicate()
	var out: Array = []
	for key in Appearance.ORDER:
		out.append({"key": key, "label": str(Appearance.OPTIONS[key].label), "value": Appearance.choice_name(key, int(lk[key]))})
	return out


static func title_text(is_creating: bool) -> String:
	return CREATE_TITLE if is_creating else EDIT_TITLE


static func save_text(is_creating: bool) -> String:
	return "Set out" if is_creating else "Save"


func setup(theme_res: Theme) -> void:
	theme = theme_res
	visible = false
	rng.randomize()
	anchor_left = 0.0
	anchor_right = 0.0
	anchor_top = 0.5
	anchor_bottom = 0.5
	offset_left = 40
	offset_right = 40 + WIDTH
	offset_top = -250
	offset_bottom = 250
	grow_vertical = Control.GROW_DIRECTION_BOTH
	add_theme_stylebox_override("panel", HudStyle.panel())
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 18)
	add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	margin.add_child(box)
	_title = Label.new()
	HudStyle.title(_title, 24)
	box.add_child(_title)
	_hint = Label.new()
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.add_theme_font_size_override("font_size", 13)
	_hint.modulate = DIM
	box.add_child(_hint)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 6)
	box.add_child(grid)
	for key in Appearance.ORDER:
		var name_label := Label.new()
		name_label.text = str(Appearance.OPTIONS[key].label)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(name_label)
		grid.add_child(_arrow("◀", key, -1))
		var value := Label.new()
		value.custom_minimum_size = Vector2(130, 0)
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		grid.add_child(value)
		_values[key] = value
		grid.add_child(_arrow("▶", key, 1))
	var turn := Label.new()
	turn.text = TURN_HINT
	turn.add_theme_font_size_override("font_size", 13)
	turn.modulate = DIM
	box.add_child(turn)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	buttons.add_theme_constant_override("separation", 8)
	box.add_child(buttons)
	var roll := Button.new()
	roll.text = "Roll"
	roll.tooltip_text = "A random look"
	roll.focus_mode = Control.FOCUS_NONE
	roll.pressed.connect(func(): set_look(Appearance.random(rng)))
	buttons.add_child(roll)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons.add_child(spacer)
	_cancel = Button.new()
	_cancel.text = "Cancel"
	_cancel.focus_mode = Control.FOCUS_NONE
	_cancel.pressed.connect(cancel)
	buttons.add_child(_cancel)
	_save = Button.new()
	_save.focus_mode = Control.FOCUS_NONE
	_save.pressed.connect(save)
	buttons.add_child(_save)


func _arrow(text: String, key: String, delta: int) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(30, 0)
	b.pressed.connect(func(): step(key, delta))
	return b


## Opens on `current` (the saved look, or {} for "never chosen", which starts from the look
## `appearance_seed` has always drawn). `is_creating` is the first-login version.
func open(current: Dictionary, appearance_seed: int, is_creating: bool) -> void:
	creating = is_creating
	original = current.duplicate()
	orbit = 0.0
	look = Appearance.normalize(current) if Appearance.is_chosen(current) else Appearance.from_seed(appearance_seed)
	if _title != null:
		_title.text = HudStyle.title_case(title_text(creating))
		_hint.text = CREATE_HINT if creating else EDIT_HINT
		_save.text = save_text(creating)
		_cancel.text = "Later" if creating else "Cancel"
	_refresh()
	visible = true
	previewed.emit(look)


func step(key: String, delta: int) -> void:
	set_look(Appearance.stepped(look, key, delta))


func set_look(new_look: Dictionary) -> void:
	look = Appearance.normalize(new_look)
	_refresh()
	previewed.emit(look)


## Sends the look (the client turns `saved` into c2s_set_look) and closes.
func save() -> void:
	if not visible:
		return
	visible = false
	saved.emit(look.duplicate())
	closed.emit()


## Puts the old look back on your character and closes (Cancel, "Later", Esc).
func cancel() -> void:
	if not visible:
		return
	visible = false
	previewed.emit(original)
	closed.emit()


## Turns the camera round the traveller by a mouse drag.
func drag(relative_x: float) -> void:
	orbit = wrapf(orbit - relative_x * 0.01, -PI, PI)


func reset() -> void:
	visible = false
	look = {}
	original = {}


func _refresh() -> void:
	for r in rows(look):
		if _values.has(r.key):
			(_values[r.key] as Label).text = r.value
