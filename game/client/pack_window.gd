class_name PackWindow
extends PanelContainer
## The pack window (I, or the "Pack" button top right): your pack as a grid (PackGrid, owner
## direction 2026-11-27: "an inventory that works like Tarkov or ARC Raiders", in our own
## Satchel look). Every stack takes room by its shape (a log 1x2, an axe 1x3, a spear 1x4),
## so the pack fills up and what you carry is a choice.
##
## - Drag a stack to arrange it; R turns it while you hold it. A green-edged ghost fits, a red
##   one doesn't (the stack snaps back).
## - Drag it out of the grid and let go to drop it (it is gone).
## - Hover a stack: what it is, how many, what it's for.
## - What doesn't fit (an old save's 999 logs) waits under the grid, never lost, until there's room.
##
## The counts and the layout come only from the server (s2c_inventory, s2c_pack). A move
## shows at once (the same PackGrid rules the server checks) and the server's s2c_pack has
## the last word. A stack whose item went up glows gold for a beat and shows "+N".
##
## The texts and the layout are static functions over the pack Dictionary, so unit tests and
## the bot test check them without building a window.

signal closed
signal move_requested(item: String, index: int, x: int, y: int, turned: bool)
signal drop_requested(item: String, index: int)

const CELL := 50.0 ## one grid cell in px
const ICON := IconShelf.SLOT_SIZE
const GRID_W := PackGrid.COLS * CELL
const GRID_H := PackGrid.ROWS * CELL
const WIDTH := GRID_W + 36.0 + 12.0 ## the grid, the margins and the leather's own rim
const ACCENT := HudStyle.EMBER
const GOLD := HudStyle.GLOW ## the "you just got this" glow
const DIM := HudStyle.TEXT_DIM
const FLASH_SECONDS := 1.4 ## how long a stack that grew glows
const HINT := "Drag to arrange  ·  R turns  ·  drag out to drop"

var pack := {} ## item id -> count, as the server last sent it
var places: Array = [] ## PackGrid places, as the server last sent them (or our move, until it answers)
var pack_known := false
var icons: IconShelf ## the client's pre-drawn icons; null falls back to ItemIcons
var _laid := {"placed": [], "over": []}
var _flash := {} ## item id -> seconds of glow left
var _gain := {} ## item id -> how many just arrived (the "+N")
var _total_label: Label
var _empty_label: Label
var _over_label: Label
var _grid: Control
var _drag := {} ## the stack in hand: {item, index, n, turned, grab: Vector2 (cells)}
var _mouse := Vector2.ZERO ## in grid coordinates


## Every held item in display order: [{item, count, label, full}] (counts per item, not per
## stack; the header and the bot test add them up). Uses Inventory.held, so the order never
## shuffles between updates.
static func slots(inv: Dictionary) -> Array:
	var out: Array = []
	for item in Inventory.held(inv):
		var n := Inventory.count(inv, item)
		out.append({"item": item, "count": n, "label": Inventory.label(item).capitalize(),
			"full": n >= Inventory.MAX_STACK})
	return out


## "23 items" / "1 item" / "Empty" for the header.
static func total_text(inv: Dictionary) -> String:
	var n := 0
	for item in Inventory.held(inv):
		n += Inventory.count(inv, item)
	if n == 0:
		return "Empty"
	return "%d item%s" % [n, "" if n == 1 else "s"]


## The line under an empty grid, naming the gather key as it is bound right now.
static func empty_text() -> String:
	return "Nothing yet. Walk up to a tree or stone and press %s." % ControlsOverlay.key_text("interact")


## The line under the grid for stacks with no room: "No room for 960 ash wood, 4 stone.
## Use or drop something to make space." or "".
static func over_text(laid: Dictionary) -> String:
	var sums := {}
	var order: Array = []
	for o in laid.over:
		if not sums.has(o.item):
			order.append(str(o.item))
		sums[o.item] = int(sums.get(o.item, 0)) + int(o.n)
	if order.is_empty():
		return ""
	var parts := PackedStringArray()
	for item in order:
		parts.append("%d %s" % [int(sums[item]), Inventory.label(item)])
	return "No room for %s. Use or drop something to make space." % ", ".join(parts)


## Recipe labels that use `item` up, in RECIPE_ORDER ("stone axe", "campfire").
static func used_in(item: String) -> Array:
	var out: Array = []
	for id in Crafting.RECIPE_ORDER:
		if (Crafting.RECIPES[id].needs as Dictionary).has(item):
			out.append(str(Crafting.RECIPES[id].label))
	return out


## The hover text: name, count out of a full stack, and what it is good for.
## "Ash wood\n12 of 999\nUsed in: stone axe, campfire"
static func tooltip_text(item: String, n: int) -> String:
	var lines := PackedStringArray([Inventory.label(item).capitalize()])
	lines.append("%d of %d%s" % [n, Inventory.MAX_STACK, " (full)" if n >= Inventory.MAX_STACK else ""])
	var uses := used_in(item)
	if not uses.is_empty():
		lines.append("Used in: " + ", ".join(uses))
	elif Weapons.exists(item):
		lines.append("A weapon: you swing the best one you carry")
	elif Crafting.makes_tool(item):
		lines.append("A tool: you gather faster with it in your pack")
	if item == Vitals.BANDAGE_ITEM:
		lines.append("Press H to put one on when you're hurt")
	return "\n".join(lines)


## A stack's hover text: the item's, with this stack's own count and its size.
static func stack_tooltip(item: String, n: int, total: int) -> String:
	var s := PackGrid.shape(item)
	var head := tooltip_text(item, total)
	var cap := PackGrid.stack_size(item)
	var line := "This stack: %d of %d  ·  %dx%d" % [n, cap, s.x, s.y] if cap > 1 else "Takes %dx%d" % [s.x, s.y]
	return head + "\n" + line


## What went up from `old` to `new`: item id -> how many more (only rises, never falls).
static func gained(old: Dictionary, new: Dictionary) -> Dictionary:
	var out := {}
	for item in new:
		var d := Inventory.count(new, item) - Inventory.count(old, item)
		if d > 0:
			out[str(item)] = d
	return out


## The cell a stack held by its `grab` point lands on when the mouse is at `mouse` (grid px).
static func drop_cell(mouse: Vector2, grab: Vector2) -> Vector2i:
	var c := mouse / CELL - grab
	return Vector2i(int(round(c.x)), int(round(c.y)))


## Whether a release at `mouse` (grid px) is outside the grid: a drop.
static func is_outside(mouse: Vector2) -> bool:
	return mouse.x < -CELL * 0.5 or mouse.y < -CELL * 0.5 or mouse.x > GRID_W + CELL * 0.5 or mouse.y > GRID_H + CELL * 0.5


func setup(theme_res: Theme) -> void:
	theme = theme_res
	visible = false
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 0.5
	anchor_bottom = 0.5
	offset_left = -WIDTH * 0.5
	offset_right = WIDTH * 0.5
	offset_top = -200
	offset_bottom = 200
	grow_vertical = Control.GROW_DIRECTION_BOTH
	add_theme_stylebox_override("panel", HudStyle.panel()) # the satchel leather every window shares (art bible section 9)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 18)
	add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	margin.add_child(box)
	var head := HBoxContainer.new()
	box.add_child(head)
	var title := Label.new()
	title.text = "Pack"
	HudStyle.title(title, 21)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	_total_label = Label.new()
	_total_label.modulate = DIM
	_total_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_total_label)
	_grid = Control.new()
	_grid.custom_minimum_size = Vector2(GRID_W, GRID_H)
	_grid.mouse_filter = Control.MOUSE_FILTER_STOP
	_grid.draw.connect(_draw_grid)
	_grid.gui_input.connect(_grid_input)
	box.add_child(_grid)
	_empty_label = Label.new()
	_empty_label.modulate = DIM
	_empty_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_empty_label.custom_minimum_size = Vector2(GRID_W, 0)
	box.add_child(_empty_label)
	_over_label = Label.new()
	_over_label.add_theme_color_override("font_color", HudStyle.SHORT)
	_over_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_over_label.custom_minimum_size = Vector2(GRID_W, 0)
	box.add_child(_over_label)
	var foot := HBoxContainer.new()
	box.add_child(foot)
	var note := Label.new()
	note.text = HINT
	note.modulate = DIM
	note.add_theme_font_size_override("font_size", 14)
	note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	note.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	foot.add_child(note)
	var done := Button.new()
	done.text = "Close"
	done.focus_mode = Control.FOCUS_NONE
	done.pressed.connect(close)
	foot.add_child(done)
	refresh()


func _icon(item: String) -> Texture2D:
	return icons.texture(item, ICON) if icons else ItemIcons.texture(item, ICON)


## Lays the pack out again from `pack` and `places` (only on a change or open).
func refresh() -> void:
	_laid = PackGrid.layout(pack, places)
	if _grid == null:
		return
	_total_label.text = total_text(pack) if pack_known else ""
	_empty_label.text = empty_text() if pack_known and pack.is_empty() else ""
	_empty_label.visible = _empty_label.text != ""
	_over_label.text = over_text(_laid) if pack_known else ""
	_over_label.visible = _over_label.text != ""
	_grid.queue_redraw()


## The pack as the server sends it (the login character's `inventory`, then every
## s2c_inventory). The first one only fills the grid; later ones light the stacks that grew.
## Anything that isn't a Dictionary is ignored.
func seed_pack(inv: Variant) -> void:
	if typeof(inv) != TYPE_DICTIONARY:
		return
	var fresh := Inventory.to_wire(Inventory.normalize(inv))
	if pack_known:
		var up := gained(pack, fresh)
		for item in up:
			# A second haul while the first still glows adds to its "+N" instead of replacing it.
			_gain[item] = int(_gain.get(item, 0)) + int(up[item]) if _flash.has(item) else int(up[item])
			_flash[item] = FLASH_SECONDS
	pack = fresh
	pack_known = true
	refresh()


## The layout as the server sends it (the login character's `pack`, then every s2c_pack).
func seed_places(p: Variant) -> void:
	places = PackGrid.normalize(p)
	refresh()


## Every frame: fades the glow on stacks that just grew.
func step(delta: float) -> void:
	if _flash.is_empty():
		return
	for item in _flash.keys():
		_flash[item] = float(_flash[item]) - delta
		if float(_flash[item]) <= 0.0:
			_flash.erase(item)
			_gain.erase(item)
	if visible and _grid:
		_grid.queue_redraw()


## How bright an item's glow is right now (0 to 1), for tests and the bot.
func flash_of(item: String) -> float:
	return clampf(float(_flash.get(item, 0.0)) / FLASH_SECONDS, 0.0, 1.0)


## The item id of each laid-out stack, in layout order (tests).
func shown() -> Array:
	var out: Array = []
	for p in _laid.placed:
		out.append(str(p.item))
	return out


## The laid-out pack (tests): {placed, over} as PackGrid.layout gives it.
func laid() -> Dictionary:
	return _laid


## How many of `item` the window shows across its stacks, as text ("" when none).
func count_shown(item: String) -> String:
	var n := 0
	for p in (_laid.placed as Array) + (_laid.over as Array):
		if str(p.item) == item:
			n += int(p.n)
	return str(n) if n > 0 else ""


# --- dragging ---

func _stack_under(pos: Vector2) -> Dictionary:
	var c := Vector2i(int(floor(pos.x / CELL)), int(floor(pos.y / CELL)))
	var at := PackGrid.stack_at(_laid, c.x, c.y)
	if at.is_empty():
		return {}
	for p in _laid.placed:
		if str(p.item) == at.item and int(p.index) == int(at.index):
			return p
	return {}


func _grid_input(ev: InputEvent) -> void:
	if ev is InputEventMouseMotion:
		_mouse = (ev as InputEventMouseMotion).position
		if _drag.is_empty():
			var p := _stack_under(_mouse)
			_grid.tooltip_text = stack_tooltip(str(p.item), int(p.n), Inventory.count(pack, str(p.item))) if not p.is_empty() else ""
		else:
			_grid.queue_redraw()
	elif ev is InputEventMouseButton and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var mb := ev as InputEventMouseButton
		_mouse = mb.position
		if mb.pressed:
			pick_up_at(_mouse)
		elif not _drag.is_empty():
			put_down_at(_mouse)
		_grid.accept_event()


## Picks up the stack under `pos` (grid px). Returns whether one was picked up.
func pick_up_at(pos: Vector2) -> bool:
	var p := _stack_under(pos)
	if p.is_empty():
		return false
	_drag = {"item": str(p.item), "index": int(p.index), "n": int(p.n), "turned": bool(p.turned),
		"grab": pos / CELL - Vector2(int(p.x), int(p.y))}
	_grid.tooltip_text = ""
	_grid.queue_redraw()
	return true


## R while holding a stack: turn it, keeping the grab point on the same end of it.
func turn_held() -> void:
	if _drag.is_empty():
		return
	_drag.turned = not bool(_drag.turned)
	var g: Vector2 = _drag.grab
	_drag.grab = Vector2(g.y, g.x)
	_grid.queue_redraw()


## Lets go of the held stack at `pos` (grid px): a move where it fits, a drop outside the
## grid, else it snaps back. Returns "moved", "dropped" or "back".
func put_down_at(pos: Vector2) -> String:
	var d := _drag
	_drag = {}
	_grid.queue_redraw()
	if d.is_empty():
		return "back"
	if is_outside(pos):
		drop_requested.emit(str(d.item), int(d.index))
		return "dropped"
	var c := drop_cell(pos, d.grab)
	var moved := PackGrid.move(pack, places, str(d.item), int(d.index), c.x, c.y, bool(d.turned))
	if moved.is_empty():
		return "back"
	places = moved # shown at once; the server's s2c_pack has the last word
	refresh()
	move_requested.emit(str(d.item), int(d.index), c.x, c.y, bool(d.turned))
	return "moved"


func holding() -> bool:
	return not _drag.is_empty()


func _input(ev: InputEvent) -> void:
	if not visible or _drag.is_empty():
		return
	if ev is InputEventKey and (ev as InputEventKey).pressed and not (ev as InputEventKey).echo and (ev as InputEventKey).physical_keycode == KEY_R:
		turn_held()
		get_viewport().set_input_as_handled()


# --- drawing ---

func _draw_grid() -> void:
	var pocket := HudStyle.slot_look()
	# the pockets
	for y in PackGrid.ROWS:
		for x in PackGrid.COLS:
			var r := Rect2(Vector2(x, y) * CELL + Vector2(1, 1), Vector2(CELL - 2, CELL - 2))
			_grid.draw_rect(r, pocket.bg as Color)
			_grid.draw_rect(r, Color(pocket.border as Color, 0.5), false, 1.0)
	# the stacks
	var font := ThemeDB.fallback_font
	for p in _laid.placed:
		var held := not _drag.is_empty() and str(_drag.item) == str(p.item) and int(_drag.index) == int(p.index)
		var r := Rect2(Vector2(int(p.x), int(p.y)) * CELL + Vector2(2, 2), Vector2(int(p.w), int(p.h)) * CELL - Vector2(4, 4))
		var t := flash_of(str(p.item))
		_grid.draw_rect(r, HudStyle.HIDE.lerp(Color(GOLD, 0.30), t * t) if not held else Color(HudStyle.HIDE, 0.35))
		_grid.draw_rect(r, Color(HudStyle.THREAD, 0.55).lerp(GOLD, t), false, 1.0 + t * 2.0)
		if held:
			continue
		_draw_stack_face(r, str(p.item), int(p.n), bool(p.turned), font, t)
	# the stack in hand
	if not _drag.is_empty():
		var sz := PackGrid.shape(str(_drag.item))
		if bool(_drag.turned):
			sz = Vector2i(sz.y, sz.x)
		var c := drop_cell(_mouse, _drag.grab)
		var r := Rect2(Vector2(c) * CELL + Vector2(2, 2), Vector2(sz) * CELL - Vector2(4, 4))
		var outside := is_outside(_mouse)
		var fits := not outside and not PackGrid.move(pack, places, str(_drag.item), int(_drag.index), c.x, c.y, bool(_drag.turned)).is_empty()
		var edge: Color = HudStyle.OK if fits else HudStyle.SHORT
		if outside:
			r = Rect2(_mouse - (_drag.grab as Vector2) * CELL, Vector2(sz) * CELL - Vector2(4, 4))
		_grid.draw_rect(r, Color(HudStyle.HIDE_HOVER, 0.85))
		_grid.draw_rect(r, edge, false, 2.0)
		_draw_stack_face(r, str(_drag.item), int(_drag.n), bool(_drag.turned), font, 0.0)
		if outside:
			_grid.draw_string(font, r.position + Vector2(4, -6), "Drop", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, HudStyle.SHORT)


func _draw_stack_face(r: Rect2, item: String, n: int, _turned: bool, font: Font, glow: float) -> void:
	var side := minf(minf(r.size.x, r.size.y) - 4.0, CELL * 1.6)
	var icon_rect := Rect2(r.get_center() - Vector2(side, side) * 0.5, Vector2(side, side))
	_grid.draw_texture_rect(_icon(item), icon_rect, false)
	if PackGrid.stack_size(item) > 1:
		var txt := str(n)
		var w := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		var at := r.end - Vector2(w + 4.0, 5.0)
		_grid.draw_string(font, at + Vector2(1, 1), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, HudStyle.SHADOW)
		var col: Color = HudStyle.TEXT
		_grid.draw_string(font, at, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, col)
	if glow > 0.0 and _gain.has(item):
		_grid.draw_string(font, r.position + Vector2(4, 15), "+%d" % int(_gain[item]), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, GOLD)


func open() -> void:
	refresh()
	visible = true


func close() -> void:
	if not visible:
		return
	_drag = {}
	visible = false
	closed.emit()


func toggle() -> void:
	if visible:
		close()
	else:
		open()


## On disconnect: shut, forget the old character's pack.
func reset() -> void:
	visible = false
	pack = {}
	places = []
	pack_known = false
	_drag = {}
	_flash.clear()
	_gain.clear()
	refresh()
