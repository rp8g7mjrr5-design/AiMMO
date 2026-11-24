class_name SettingsMenu
extends PanelContainer
## The settings window (Esc in game, or the button on the login screen). It edits a
## ClientSettings in place, emits `changed` on every tweak so the effect is visible at once,
## and saves to disk when closed.

signal changed(settings: ClientSettings)
signal closed
## The in-game "Return to Spawn Meadow" button was pressed (and `home` let it through).
signal home_requested
## The in-game "Change appearance" button was pressed: open the character-creation window.
signal look_requested

var settings: ClientSettings
var _sens: HSlider
var _sens_value: Label
var _invert: CheckBox
var _volume: HSlider
var _volume_value: Label
var _graphics: OptionButton
var _shadows: OptionButton
var _draw: HSlider
var _draw_value: Label
var _fov: HSlider
var _fov_value: Label
var _shoulder: OptionButton
## "Return to Spawn Meadow": shown only while playing (`set_in_game`), drawn from `home`.
var home := SpawnReturn.new()
var home_button: Button
var look_button: Button
var in_game := false


func setup(p_settings: ClientSettings, theme_res: Theme) -> void:
	settings = p_settings
	theme = theme_res
	visible = false
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 0.5
	anchor_bottom = 0.5
	offset_left = -220
	offset_right = 220
	offset_top = -210
	offset_bottom = 210
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 18)
	add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	margin.add_child(box)

	var title := Label.new()
	title.text = "Settings"
	title.add_theme_font_size_override("font_size", 24)
	box.add_child(title)

	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 10)
	box.add_child(grid)

	_sens = _slider(grid, "Mouse sensitivity", ClientSettings.SENS_MIN, ClientSettings.SENS_MAX, 0.05)
	_sens_value = grid.get_child(grid.get_child_count() - 1)
	_sens.value_changed.connect(_on_sens)

	_label(grid, "Invert look up/down")
	_invert = CheckBox.new()
	_invert.toggled.connect(_on_invert)
	grid.add_child(_invert)
	grid.add_child(Control.new())

	_fov = _slider(grid, "Field of view", ClientSettings.FOV_MIN, ClientSettings.FOV_MAX, 1.0)
	_fov_value = grid.get_child(grid.get_child_count() - 1)
	_fov.value_changed.connect(_on_fov)

	_label(grid, "Camera shoulder")
	_shoulder = OptionButton.new()
	_shoulder.add_item("Right")
	_shoulder.add_item("Left")
	_shoulder.item_selected.connect(_on_shoulder)
	grid.add_child(_shoulder)
	grid.add_child(Control.new())

	_volume = _slider(grid, "Volume", 0.0, 1.0, 0.05)
	_volume_value = grid.get_child(grid.get_child_count() - 1)
	_volume.value_changed.connect(_on_volume)

	_label(grid, "Graphics")
	_graphics = OptionButton.new()
	for n in Quality.NAMES:
		_graphics.add_item(n)
	_graphics.tooltip_text = "Low runs smoothest on older laptops. Sets shadows and draw distance below."
	_graphics.item_selected.connect(_on_graphics)
	grid.add_child(_graphics)
	grid.add_child(Control.new())

	_label(grid, "Shadows")
	_shadows = OptionButton.new()
	for n in ClientSettings.SHADOW_NAMES:
		_shadows.add_item(n)
	_shadows.item_selected.connect(_on_shadows)
	grid.add_child(_shadows)
	grid.add_child(Control.new())

	_draw = _slider(grid, "Draw distance", ClientSettings.DRAW_MIN, ClientSettings.DRAW_MAX, 10.0)
	_draw_value = grid.get_child(grid.get_child_count() - 1)
	_draw.value_changed.connect(_on_draw)

	home_button = Button.new()
	home_button.text = SpawnReturn.LABEL
	home_button.tooltip_text = SpawnReturn.TOOLTIP
	home_button.visible = false
	home_button.pressed.connect(_on_home)
	box.add_child(home_button)

	look_button = Button.new()
	look_button.text = "Change appearance"
	look_button.tooltip_text = "Your build, face, hair, beard and clothes. Everyone sees the change."
	look_button.visible = false
	look_button.pressed.connect(func():
		if in_game:
			close(true)
			look_requested.emit())
	box.add_child(look_button)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	buttons.add_theme_constant_override("separation", 8)
	box.add_child(buttons)
	var reset := Button.new()
	reset.text = "Defaults"
	reset.pressed.connect(_on_reset)
	buttons.add_child(reset)
	var done := Button.new()
	done.text = "Done"
	done.pressed.connect(close)
	buttons.add_child(done)


func open() -> void:
	_sync_controls()
	refresh_home(Time.get_ticks_msec())
	visible = true


## Show the "Return to Spawn Meadow" button only while logged in (not on the login screen).
func set_in_game(on: bool) -> void:
	in_game = on
	home_button.visible = on
	look_button.visible = on
	offset_top = -250 if on else -210
	offset_bottom = 250 if on else 210
	if not on:
		home.reset()
	refresh_home(Time.get_ticks_msec())


## Redraws the button's countdown; client.gd calls it every frame while the menu is open.
func refresh_home(now_ms: int) -> void:
	if home_button == null:
		return
	home_button.text = home.label(now_ms)
	home_button.disabled = not home.enabled(now_ms)


func _on_home() -> void:
	if in_game and home.ask(Time.get_ticks_msec()):
		refresh_home(Time.get_ticks_msec())
		home_requested.emit()


## `quiet` skips the `closed` signal's chime when another sound already marks the moment
## (the trip home plays the arrival sound instead).
var quiet_close := false


func close(quiet := false) -> void:
	if not visible:
		return
	visible = false
	settings.save_to()
	quiet_close = quiet
	closed.emit()
	quiet_close = false


func toggle() -> void:
	if visible:
		close()
	else:
		open()


func _on_sens(v: float) -> void:
	settings.mouse_sensitivity = v
	_refresh_labels()
	changed.emit(settings)


func _on_invert(on: bool) -> void:
	settings.invert_y = on
	changed.emit(settings)


func _on_fov(v: float) -> void:
	settings.field_of_view = v
	_refresh_labels()
	changed.emit(settings)


func _on_shoulder(i: int) -> void:
	settings.shoulder_right = i == 0
	changed.emit(settings)


func _on_volume(v: float) -> void:
	settings.master_volume = v
	_refresh_labels()
	changed.emit(settings)


func _on_graphics(i: int) -> void:
	settings.apply_quality(i)
	_sync_controls()
	changed.emit(settings)


func _on_shadows(i: int) -> void:
	settings.shadow_quality = i
	changed.emit(settings)


func _on_draw(v: float) -> void:
	settings.draw_distance = v
	_refresh_labels()
	changed.emit(settings)


func _on_reset() -> void:
	var d := ClientSettings.new()
	settings.mouse_sensitivity = d.mouse_sensitivity
	settings.invert_y = d.invert_y
	settings.master_volume = d.master_volume
	settings.shadow_quality = d.shadow_quality
	settings.draw_distance = d.draw_distance
	settings.field_of_view = d.field_of_view
	settings.shoulder_right = d.shoulder_right
	settings.graphics_quality = d.graphics_quality
	_sync_controls()
	changed.emit(settings)


func _sync_controls() -> void:
	_sens.set_value_no_signal(settings.mouse_sensitivity)
	_invert.set_pressed_no_signal(settings.invert_y)
	_volume.set_value_no_signal(settings.master_volume)
	_graphics.select(settings.graphics_quality)
	_shadows.select(settings.shadow_quality)
	_draw.set_value_no_signal(settings.draw_distance)
	_fov.set_value_no_signal(settings.field_of_view)
	_shoulder.select(0 if settings.shoulder_right else 1)
	_refresh_labels()


func _refresh_labels() -> void:
	_sens_value.text = "%.2f×" % settings.mouse_sensitivity
	_volume_value.text = "%d%%" % roundi(settings.master_volume * 100.0)
	_draw_value.text = "%d m" % roundi(settings.draw_distance)
	_fov_value.text = "%d°" % roundi(settings.field_of_view)


func _label(grid: GridContainer, text: String) -> void:
	var l := Label.new()
	l.text = text
	grid.add_child(l)


## Adds label, slider, and a value label to the grid; returns the slider.
func _slider(grid: GridContainer, text: String, lo: float, hi: float, step: float) -> HSlider:
	_label(grid, text)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.custom_minimum_size = Vector2(160, 0)
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	grid.add_child(s)
	var v := Label.new()
	v.custom_minimum_size = Vector2(56, 0)
	grid.add_child(v)
	return s
