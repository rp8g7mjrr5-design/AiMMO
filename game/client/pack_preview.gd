class_name PackPreview
extends SubViewportContainer
## Your traveller in the pack window (I), turned to face you (owner, 2026-11-28: "see our
## character in this menu looking back at us so we can see our gear"). The same carved figure
## everyone sees in the world (Carved.skinned on your saved look), standing in a quiet lantern-lit
## pocket of its own, breathing on the idle clip and holding what you would swing: your best
## weapon, else your best tool, else a torch (held_for). Craft a stone maul in the next column
## and it is in your hand here before you close the pack. Drag across it to turn them round.
##
## Its own small World3D (own_world_3d): one figure, one key light, one fill, no shadows,
## nothing from the island drawn twice. The viewport only renders while the pack is open
## (UPDATE_DISABLED otherwise), so it costs nothing in play (art bible section 7).
##
## held_for() and turn_for() are static, so tests check them without a renderer.

const SIZE := Vector2i(200, 330)
const DRAG_TURN := 0.012 ## radians per pixel dragged
const FACE_YAW := 0.32 ## turned a little off square, so the figure reads in three quarters
## Tools in the order the hand reaches for them when there is no weapon: best last.
const TOOL_ORDER := ["torch", "wooden_pickaxe", "wooden_axe", "stone_pickaxe", "stone_axe"]

var look := {}
var appearance_seed := 0
var display_name := ""
var yaw := FACE_YAW
var _vp: SubViewport
var _stage: Node3D
var _skel: Skeleton3D
var _anim := AvatarAnimator.new()
var _held := ""
var _built_key := ""


## What the figure holds for a pack: the weapon you swing (Weapons.ORDER, best last), else
## your best tool, else "" (empty hands).
static func held_for(inv: Dictionary) -> String:
	for i in range(Weapons.ORDER.size() - 1, -1, -1):
		if Inventory.count(inv, Weapons.ORDER[i]) > 0:
			return str(Weapons.ORDER[i])
	for i in range(TOOL_ORDER.size() - 1, -1, -1):
		if Inventory.count(inv, TOOL_ORDER[i]) > 0:
			return str(TOOL_ORDER[i])
	return ""


## The figure's yaw after dragging `dx` pixels from `from`.
static func turn_for(from: float, dx: float) -> float:
	return wrapf(from + dx * DRAG_TURN, -PI, PI)


func setup() -> void:
	stretch = true
	custom_minimum_size = Vector2(SIZE)
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_DRAG
	tooltip_text = "Drag to turn"
	_vp = SubViewport.new()
	_vp.own_world_3d = true
	_vp.transparent_bg = true
	_vp.msaa_3d = Viewport.MSAA_4X
	_vp.size = SIZE
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_vp)
	_stage = Node3D.new()
	_vp.add_child(_stage)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_CLEAR_COLOR
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Palette.LINEN.lerp(Color(0.55, 0.6, 0.7), 0.5)
	e.ambient_light_energy = 0.55
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	_vp.add_child(env)
	var key := DirectionalLight3D.new()
	key.light_color = Color(1.0, 0.9, 0.78) # warm, like the lantern on the satchel's flap
	key.light_energy = 1.25
	key.rotation_degrees = Vector3(-28, 35, 0)
	_vp.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.light_color = Color(0.62, 0.70, 0.86) # cool from the other side (warm light, cool shade)
	fill.light_energy = 0.35
	fill.rotation_degrees = Vector3(-10, -140, 0)
	_vp.add_child(fill)
	var cam := Camera3D.new()
	cam.fov = 30.0
	cam.transform = Transform3D.IDENTITY.looking_at(Vector3(0, 0.92, 0) - Vector3(0, 1.05, 3.9), Vector3.UP).translated(Vector3(0, 1.05, 3.9))
	_vp.add_child(cam)
	gui_input.connect(_on_input)


## Builds (or rebuilds, only when the look changed) the figure, and puts `inv`'s best kit in
## its hand.
func show_traveller(name_text: String, seed_value: int, look_in: Dictionary, inv: Dictionary) -> void:
	display_name = name_text
	appearance_seed = seed_value
	look = look_in
	var key := "%s|%d|%s" % [name_text, seed_value, JSON.stringify(look_in)]
	if key != _built_key or _skel == null:
		_built_key = key
		for c in _stage.get_children():
			_drop(c)
		_skel = Carved.skinned(seed_value, look_in) # the figure without its name tag
		_skel.name = "Skeleton"
		_stage.add_child(_skel)
		_held = "~" # force the hand to be filled again
	set_kit(inv)


## Puts `inv`'s best weapon or tool in the figure's hand (a no-op when it is the same).
func set_kit(inv: Dictionary) -> void:
	var want := held_for(inv)
	if want == _held or _skel == null:
		return
	_held = want
	HeldItems.attach(_skel, want)


## What the figure holds now ("" for empty hands), for tests and the bot.
func holding() -> String:
	return "" if _held == "~" else _held


## Every frame while the pack is open: breathe, and render.
func step(delta: float) -> void:
	if _skel == null:
		return
	_stage.rotation.y = yaw
	_anim.step(delta, {"pos": Vector3.ZERO, "yaw": 0.0, "gather": {}})
	_anim.apply(_skel)


func set_live(on: bool) -> void:
	if _vp:
		_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_DISABLED


func _on_input(ev: InputEvent) -> void:
	if ev is InputEventMouseMotion and ((ev as InputEventMouseMotion).button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
		yaw = turn_for(yaw, (ev as InputEventMouseMotion).relative.x)
		accept_event()


## Frees `c` (off the stage): queued while drawn, at once when the window was never in a tree.
func _drop(c: Node) -> void:
	_stage.remove_child(c)
	if is_inside_tree():
		c.queue_free()
	else:
		c.free()


func reset() -> void:
	yaw = FACE_YAW
	_built_key = ""
	_held = ""
	if _stage:
		for c in _stage.get_children():
			_drop(c)
	_skel = null
