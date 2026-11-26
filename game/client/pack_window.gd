class_name PackWindow
extends PanelContainer
## The pack window (I, or the "Pack" button top right): everything you carry as a grid of
## slots, each with world's procedural item icon and its count. It replaces typing "/bag" in
## chat (owner direction 1: chat is for talking). Opening it frees the cursor like the other
## windows; I, Esc or Close shut it.
##
## The pack comes only from the server: the login character's `inventory`, then every
## s2c_inventory (`seed_pack`). A slot whose count went up glows gold for a beat and shows
## "+N", so a haul you just made is the first thing your eye lands on. Hovering a slot says
## what the item is for ("Used in: stone axe, campfire").
##
## The texts and slot list are static functions over the pack Dictionary, so unit tests and
## the bot test check them without building a window.

signal closed

const COLUMNS := 5
const MIN_SLOTS := 10 ## two rows of slots even when the pack is nearly empty, so it reads as a pack
const SLOT := 68.0 ## slot size in px
const ICON := IconShelf.SLOT_SIZE
const WIDTH := COLUMNS * SLOT + (COLUMNS - 1) * 8.0 + 36.0
const ACCENT := HudStyle.EMBER ## ember orange, as the workbench and players windows
const GOLD := HudStyle.GLOW ## the "you just got this" glow
const FULL_COLOR := HudStyle.SHORT ## a stack at MAX_STACK: more of it won't fit
const DIM := HudStyle.TEXT_DIM
const FLASH_SECONDS := 1.4 ## how long a slot that grew glows

var pack := {} ## item id -> count, as the server last sent it
var pack_known := false
var icons: IconShelf ## the client's pre-drawn icons; null falls back to ItemIcons
var _flash := {} ## item id -> seconds of glow left
var _gain := {} ## item id -> how many just arrived (the "+N")
var _total_label: Label
var _empty_label: Label
var _grid: GridContainer
var _slots: Array = [] ## [{panel, style, icon, count, plus}] in grid order
var _shown: Array = [] ## the item id in each slot ("" for an empty slot)


## Every held stack in display order: [{item, count, label, full}]. Uses Inventory.held, so
## the order never shuffles between updates (raw materials, then tools, then anything new).
static func slots(inv: Dictionary) -> Array:
	var out: Array = []
	for item in Inventory.held(inv):
		var n := Inventory.count(inv, item)
		out.append({"item": item, "count": n, "label": Inventory.label(item).capitalize(),
			"full": n >= Inventory.MAX_STACK})
	return out


## How many slots the grid shows: every stack, at least MIN_SLOTS, rounded up to a full row.
static func slot_count(stacks: int) -> int:
	var n := maxi(stacks, MIN_SLOTS)
	return int(ceil(float(n) / COLUMNS)) * COLUMNS


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


## Recipe labels that use `item` up, in RECIPE_ORDER ("stone axe", "campfire").
static func used_in(item: String) -> Array:
	var out: Array = []
	for id in Crafting.RECIPE_ORDER:
		if (Crafting.RECIPES[id].needs as Dictionary).has(item):
			out.append(str(Crafting.RECIPES[id].label))
	return out


## The hover text: name, count out of a full stack, and what it is good for.
## "Ash wood\n12 of 99\nUsed in: stone axe, campfire"
static func tooltip_text(item: String, n: int) -> String:
	var lines := PackedStringArray([Inventory.label(item).capitalize()])
	lines.append("%d of %d%s" % [n, Inventory.MAX_STACK, " (full)" if n >= Inventory.MAX_STACK else ""])
	var uses := used_in(item)
	if not uses.is_empty():
		lines.append("Used in: " + ", ".join(uses))
	elif Crafting.makes_tool(item):
		lines.append("A tool: you gather faster with it in your pack")
	return "\n".join(lines)


## What went up from `old` to `new`: item id -> how many more (only rises, never falls).
static func gained(old: Dictionary, new: Dictionary) -> Dictionary:
	var out := {}
	for item in new:
		var d := Inventory.count(new, item) - Inventory.count(old, item)
		if d > 0:
			out[str(item)] = d
	return out


func setup(theme_res: Theme) -> void:
	theme = theme_res
	visible = false
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 0.5
	anchor_bottom = 0.5
	offset_left = -WIDTH * 0.5
	offset_right = WIDTH * 0.5
	offset_top = -150
	offset_bottom = 150
	grow_vertical = Control.GROW_DIRECTION_BOTH
	add_theme_stylebox_override("panel", HudStyle.panel(0.9)) # muted warm grey, no ember frame (art bible section 9)
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
	title.add_theme_font_size_override("font_size", 21)
	title.add_theme_color_override("font_color", ACCENT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	_total_label = Label.new()
	_total_label.modulate = DIM
	_total_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_total_label)
	_grid = GridContainer.new()
	_grid.columns = COLUMNS
	_grid.add_theme_constant_override("h_separation", 8)
	_grid.add_theme_constant_override("v_separation", 8)
	box.add_child(_grid)
	_empty_label = Label.new()
	_empty_label.modulate = DIM
	_empty_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_empty_label.custom_minimum_size = Vector2(WIDTH - 36.0, 0)
	box.add_child(_empty_label)
	var foot := HBoxContainer.new()
	box.add_child(foot)
	var note := Label.new()
	note.text = "Stacks hold up to %d." % Inventory.MAX_STACK
	note.modulate = DIM
	note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(note)
	var done := Button.new()
	done.text = "Close"
	done.focus_mode = Control.FOCUS_NONE
	done.pressed.connect(close)
	foot.add_child(done)
	refresh()


func _make_slot() -> Dictionary:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(SLOT, SLOT)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP # so the tooltip shows on hover
	var style := StyleBoxFlat.new()
	style.bg_color = Color(1, 1, 1, 0.06)
	style.border_color = Color(1, 1, 1, 0.12)
	style.set_border_width_all(1)
	style.set_corner_radius_all(5)
	panel.add_theme_stylebox_override("panel", style)
	var icon := TextureRect.new()
	icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(icon)
	var count := Label.new()
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	count.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	HudStyle.quiet_label(count, 14, HudStyle.TEXT)
	count.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(count)
	var plus := Label.new()
	plus.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	plus.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	HudStyle.quiet_label(plus, 13, GOLD)
	plus.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(plus)
	_grid.add_child(panel)
	return {"panel": panel, "style": style, "icon": icon, "count": count, "plus": plus}


func _icon(item: String) -> Texture2D:
	return icons.texture(item, ICON) if icons else ItemIcons.texture(item, ICON)


## Rebuilds every slot from `pack` (only on a change or open: a handful of slots).
func refresh() -> void:
	if _grid == null:
		return
	var stacks := slots(pack)
	var want := slot_count(stacks.size())
	while _slots.size() < want:
		_slots.append(_make_slot())
	while _slots.size() > want:
		var s: Dictionary = _slots.pop_back()
		(s.panel as Control).queue_free()
	_shown.clear()
	for i in _slots.size():
		var s: Dictionary = _slots[i]
		if i < stacks.size():
			var st: Dictionary = stacks[i]
			_shown.append(str(st.item))
			s.icon.texture = _icon(str(st.item))
			s.count.text = str(int(st.count))
			s.count.add_theme_color_override("font_color", FULL_COLOR if st.full else Color.WHITE)
			s.panel.tooltip_text = tooltip_text(str(st.item), int(st.count))
		else:
			_shown.append("")
			s.icon.texture = null
			s.count.text = ""
			s.panel.tooltip_text = ""
	_paint_flash()
	_total_label.text = total_text(pack) if pack_known else ""
	_empty_label.text = empty_text() if pack_known and stacks.is_empty() else ""
	_empty_label.visible = _empty_label.text != ""


## The pack as the server sends it (the login character's `inventory`, then every
## s2c_inventory). The first one only fills the grid; later ones light the slots that grew.
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


## Every frame: fades the glow on slots that just grew.
func step(delta: float) -> void:
	if _flash.is_empty():
		return
	for item in _flash.keys():
		_flash[item] = float(_flash[item]) - delta
		if float(_flash[item]) <= 0.0:
			_flash.erase(item)
			_gain.erase(item)
	if visible:
		_paint_flash()


func _paint_flash() -> void:
	for i in _slots.size():
		var s: Dictionary = _slots[i]
		var item: String = _shown[i] if i < _shown.size() else ""
		var t := clampf(float(_flash.get(item, 0.0)) / FLASH_SECONDS, 0.0, 1.0) if item != "" else 0.0
		var style: StyleBoxFlat = s.style
		style.border_color = Color(1, 1, 1, 0.12).lerp(GOLD, t)
		style.set_border_width_all(1 + int(round(t * 2.0)))
		style.bg_color = Color(1, 1, 1, 0.06).lerp(Color(GOLD, 0.22), t * t)
		s.plus.text = "+%d" % int(_gain[item]) if t > 0.0 and _gain.has(item) else ""


## How bright a slot's glow is right now (0 to 1), for tests and the bot.
func flash_of(item: String) -> float:
	return clampf(float(_flash.get(item, 0.0)) / FLASH_SECONDS, 0.0, 1.0)


## The item id in each slot, "" for an empty one (tests).
func shown() -> Array:
	return _shown.duplicate()


func count_shown(item: String) -> String:
	var i := _shown.find(item)
	return (_slots[i].count as Label).text if i >= 0 else ""


func open() -> void:
	refresh()
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


## On disconnect: shut, forget the old character's pack.
func reset() -> void:
	visible = false
	pack = {}
	pack_known = false
	_flash.clear()
	_gain.clear()
	refresh()
