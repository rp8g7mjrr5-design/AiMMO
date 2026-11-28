class_name CraftPanel
extends VBoxContainer
## The craft column of the pack window (I): basic crafting from your pack, anywhere (owner,
## 2026-11-28: "basic crafting should be done from our inventory menu"). Every recipe with
## `bench: false` (the wooden tools and weapons, bandages, torches) is made right here, on the
## beach, the moment you have the parts. The bench recipes (the stone tier, the campfire) are
## listed under them, greyed with "At a workbench", so the next goal is always in sight; they
## light up too when you open the pack standing at a workbench.
##
## The server decides everything, as for the workbench window: Craft emits
## `craft_requested(recipe_id)`, the client sends c2s_craft, and the answer comes back to
## on_craft_result(). The rows reuse CraftWindow.row(), so the two never disagree about what
## you can make. The new item lands in the grid next to this column with its gold glow.
##
## Static helpers over a pack Dictionary, so tests check the order and the words headless.

## Craft was pressed for `recipe_id`: send it to the server (c2s_craft).
signal craft_requested(recipe_id: String)

const WIDTH := 300.0
const ICON := IconShelf.ROW_SIZE
const PART := IconShelf.PART_SIZE
const REPLY_TIMEOUT := CraftWindow.REPLY_TIMEOUT
const BENCH_HEAD := "At a workbench"

var pack := {}
var pack_known := false
var pos := Vector3.ZERO ## where you stand (the bench recipes light up at a bench)
var icons: IconShelf
var status_label: Label
var _ready_label: Label
var _rows := {} ## recipe id -> {icon, name, needs, button}
var _awaiting := ""
var _awaiting_age := 0.0


## The recipes this column lists, in order: the hand recipes first (craft anywhere), then the
## bench ones. Both in Crafting.RECIPE_ORDER, so a row never jumps when the pack changes.
static func order() -> Array:
	var hand: Array = []
	var bench: Array = []
	for id in Crafting.RECIPE_ORDER:
		(bench if bool(Crafting.RECIPES[id].bench) else hand).append(id)
	return hand + bench


## How many recipes you could craft right now (the "Craft · 2 ready" header).
static func ready_count(inv: Dictionary, p: Vector3) -> int:
	var n := 0
	for id in Crafting.RECIPE_ORDER:
		if Crafting.check(inv, id, p) == "":
			n += 1
	return n


static func head_text(inv: Dictionary, p: Vector3, known: bool) -> String:
	if not known:
		return ""
	var n := ready_count(inv, p)
	return "%d ready" % n if n > 0 else ""


## The short line under a row's parts: what stops it, in a few words ("" when it's ready).
static func short_hint(reason: String) -> String:
	match reason:
		"owned":
			return "Carried"
		"bench":
			return "At a workbench"
		"full":
			return "No room in your pack"
	return ""


func setup() -> void:
	custom_minimum_size = Vector2(WIDTH, 0)
	add_theme_constant_override("separation", 6)
	var head := HBoxContainer.new()
	add_child(head)
	var title := Label.new()
	title.text = "Craft"
	HudStyle.title(title, 18)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	_ready_label = Label.new()
	_ready_label.add_theme_color_override("font_color", HudStyle.OK)
	_ready_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_ready_label)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(WIDTH, 0)
	add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 4)
	scroll.add_child(list)
	var bench_started := false
	for id in order():
		if bool(Crafting.RECIPES[id].bench) and not bench_started:
			bench_started = true
			var sep := Label.new()
			sep.text = BENCH_HEAD
			HudStyle.quiet_label(sep, 13, HudStyle.TEXT_DIM)
			list.add_child(sep)
		list.add_child(_make_row(id))
	status_label = Label.new()
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.custom_minimum_size = Vector2(WIDTH, 0)
	status_label.add_theme_font_size_override("font_size", 14)
	add_child(status_label)
	refresh()


func _make_row(id: String) -> Control:
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 8)
	var product := TextureRect.new()
	product.custom_minimum_size = Vector2(ICON, ICON)
	product.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	product.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	product.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	product.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(product)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 0)
	line.add_child(col)
	var name_label := Label.new()
	name_label.add_theme_font_size_override("font_size", 15)
	col.add_child(name_label)
	var needs := RichTextLabel.new()
	needs.bbcode_enabled = false
	needs.fit_content = true
	needs.scroll_active = false
	needs.autowrap_mode = TextServer.AUTOWRAP_OFF
	needs.add_theme_font_size_override("normal_font_size", 13)
	needs.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(needs)
	var button := Button.new()
	button.custom_minimum_size = Vector2(64, 30)
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(func(): craft(id))
	line.add_child(button)
	_rows[id] = {"line": line, "icon": product, "name": name_label, "needs": needs, "button": button}
	return line


func _icon(item: String, size: int) -> Texture2D:
	return icons.texture(item, size) if icons else ItemIcons.texture(item, size)


## Lights each row from the pack and where you stand.
func refresh() -> void:
	if status_label == null:
		return
	_ready_label.text = head_text(pack, pos, pack_known)
	for id in _rows:
		var w: Dictionary = _rows[id]
		var r := CraftWindow.row(pack, id, pos)
		var ready := pack_known and str(r.reason) == ""
		(w.name as Label).text = str(r.title)
		(w.name as Label).modulate = HudStyle.TEXT if ready or not pack_known else HudStyle.TEXT_DIM
		(w.icon as TextureRect).texture = _icon(id, ICON)
		(w.icon as TextureRect).modulate = Color.WHITE if ready else Color(1, 1, 1, 0.55)
		_fill_needs(w.needs, r)
		var button: Button = w.button
		button.text = "Craft" if str(r.reason) != "owned" else "Have"
		button.disabled = not ready or _awaiting != ""
		button.tooltip_text = str(r.hint)
		(w.line as Control).tooltip_text = str(r.hint)


## "[icon] 2/3  [icon] 0/2", green when you have enough, red when short; for a row that is
## held back by something else (carried, the bench) a short word after the parts.
func _fill_needs(needs: RichTextLabel, r: Dictionary) -> void:
	needs.clear()
	if not pack_known:
		needs.push_color(HudStyle.TEXT_DIM)
		needs.add_text("...")
		needs.pop()
		return
	var parts: Array = r.parts if str(r.reason) != "owned" else [] # carried: the parts don't matter
	for i in parts.size():
		var p: Dictionary = parts[i]
		if i > 0:
			needs.add_text("   ")
		needs.add_image(_icon(str(p.item), PART), PART, PART, Color.WHITE, INLINE_ALIGNMENT_CENTER)
		needs.add_text(" ")
		needs.push_color(HudStyle.OK if bool(p.ok) else HudStyle.SHORT)
		needs.add_text("%d/%d" % [int(p.have), int(p.need)])
		needs.pop()
	var why := short_hint(str(r.reason))
	if why != "":
		needs.push_color(HudStyle.TEXT_DIM)
		needs.add_text(("   " if not parts.is_empty() else "") + why)
		needs.pop()


## Craft button: asks the server to make `id`. False when nothing was sent.
func craft(id: String) -> bool:
	if not pack_known or _awaiting != "" or not Crafting.is_recipe(id):
		return false
	if Crafting.check(pack, id, pos) != "":
		return false
	_awaiting = id
	_awaiting_age = 0.0
	status_label.text = CraftWindow.WORKING
	status_label.modulate = HudStyle.TEXT_DIM
	refresh()
	craft_requested.emit(id)
	return true


func is_waiting() -> bool:
	return _awaiting != ""


## The server's craft_result. A success is told by the chime, the toast and the new stack
## glowing in the grid, so the line here stays quiet; a refusal says why in red.
func on_craft_result(recipe_id: String, ok: bool, text: String) -> void:
	if recipe_id == _awaiting:
		_awaiting = ""
	status_label.text = "" if ok else text
	status_label.modulate = HudStyle.SHORT
	refresh()


## Every frame while the pack is open: where you stand, and the reply timeout.
func tick(delta: float, p: Vector3) -> void:
	var moved := p.distance_to(pos) > 0.25
	pos = p
	if _awaiting != "":
		_awaiting_age += delta
		if _awaiting_age > REPLY_TIMEOUT:
			_awaiting = ""
			status_label.text = CraftWindow.NO_ANSWER
			status_label.modulate = HudStyle.SHORT
			refresh()
			return
	if moved:
		refresh()


func seed_pack(inv: Dictionary, known: bool) -> void:
	pack = inv
	pack_known = known
	refresh()


func reset() -> void:
	pack = {}
	pack_known = false
	_awaiting = ""
	_awaiting_age = 0.0
	if status_label:
		status_label.text = ""
	refresh()
