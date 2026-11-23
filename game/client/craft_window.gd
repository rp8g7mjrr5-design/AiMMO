class_name CraftWindow
extends PanelContainer
## The workbench window. Stand within Crafting.BENCH_RANGE of the Spawn Meadow workbench and
## a prompt says "[E] Use Workbench"; E opens this window with every recipe, what it needs
## against what you carry ("Ash wood 2/3"), and a Craft button that lights up when you have
## it all. Owner direction 1: crafting is a window, not a chat command.
##
## The server decides everything (Crafting.check on its own copy of the pack and position).
## The window talks protocol v3 only: Craft emits `craft_requested(recipe_id)`, which the
## client sends as `net.play.c2s_craft`; the answer comes back as `craft_result` and goes to
## on_craft_result(). The pack comes from the login character and every `s2c_inventory`
## (seed_pack), so the window never sends or reads a chat line.
## All the rules are static functions so they are unit tested headless.

signal closed
## Craft was pressed for `recipe_id`: send it to the server (c2s_craft).
signal craft_requested(recipe_id: String)

const WIDTH := 600.0 ## room for a part icon before each "Ash wood 2/3"
const HEIGHT := 600.0 ## fits a 720p screen with the HUD around it
## The recipe list scrolls inside this height, so the title and Close stay on screen
## however many recipes the bench gets (six since the ember tools).
const LIST_HEIGHT := 410.0
const REPLY_TIMEOUT := 3.0 ## seconds to wait for craft_result before the buttons light again
const CLOSE_SLACK := 1.0 ## m past BENCH_RANGE before walking away closes the window
const OK_COLOR := Color(0.62, 0.92, 0.55)
const SHORT_COLOR := Color(1.0, 0.55, 0.45)
const ACCENT := GatherPrompt.ACCENT
const DIM := Color(0.85, 0.85, 0.85, 0.7)
const WORKING := "Crafting..."
const NO_ANSWER := "The bench didn't answer. Try again."

var pack := {} ## the pack as the server last sent it
var pack_known := false
var pos := Vector3.ZERO ## where you stand, for the bench check
## Your skills (skill id -> XP) once the server has sent them (skills_changed / xp_gained);
## null until then, and the level check is left to the server.
var skills: Variant = null
var status_label: Label
var list_scroll: ScrollContainer
## Where the icons come from (set by the client; without one, world's cache draws them).
var icons: IconShelf
var _rows := {} ## recipe id -> {needs: RichTextLabel, button: Button}
var _awaiting := "" ## the recipe id sent and not answered yet, or ""
var _awaiting_age := 0.0


# --- rules (static, unit tested) ---

## True when the "[E] Use Workbench" prompt shows for a player at `p`.
static func near_bench(p: Vector3) -> bool:
	return Crafting.near_bench(p)


## True once you have walked far enough from the bench that the open window closes.
static func walked_away(p: Vector3) -> bool:
	return Vector2(p.x, p.z).distance_to(Crafting.WORKBENCH_XZ) > Crafting.BENCH_RANGE + CLOSE_SLACK


## One recipe as the window shows it, for a pack, a position and (when known) your skills:
## {id, title ("Stone axe" / "Torch ×3"), parts: [{label, have, need, ok}], reason (Crafting.check,
## "" = ready), button ("Craft" / "Have it"), hint (why it's greyed out, or where it's made)}.
## A recipe above your Toolcraft level says "Needs Toolcraft 5 · 1,205 XP to go".
static func row(inv: Dictionary, id: String, p: Vector3, skills: Variant = null) -> Dictionary:
	var r: Dictionary = Crafting.RECIPES[id]
	var label := str(r.label)
	var title := label.left(1).to_upper() + label.substr(1)
	if int(r.makes) > 1:
		title += " ×%d" % int(r.makes)
	var parts: Array = []
	for item in Inventory.ITEM_ORDER:
		if r.needs.has(item):
			var need := int(r.needs[item])
			var have := Inventory.count(inv, item)
			var item_label := Inventory.label(item)
			parts.append({"item": item, "label": item_label.left(1).to_upper() + item_label.substr(1), "have": have, "need": need, "ok": have >= need})
	var reason := Crafting.check(inv, id, p, skills)
	var hint := ""
	match reason:
		"":
			hint = "Ready"
		"level":
			hint = level_hint(id, skills)
		"owned":
			hint = "In your pack; it never wears out"
		"bench":
			hint = "Needs the workbench"
		"missing":
			hint = "Need " + Crafting.needs_text(Crafting.missing(inv, id))
		"full":
			hint = "No room in your pack"
	if not bool(r.bench) and reason != "owned":
		hint += " · craft anywhere"
	return {"id": id, "title": title, "parts": parts, "reason": reason,
		"button": "Have it" if reason == "owned" else "Craft", "hint": hint}


## "Needs Toolcraft 5 · 1,205 XP to go" for a recipe above your level, "" otherwise.
static func level_hint(id: String, skills: Variant) -> String:
	var need := Crafting.required(id)
	if need.is_empty() or not skills is Dictionary or Crafting.level_ok(id, skills):
		return ""
	var skill := str(need[0])
	var to_go := maxi(0, Skills.xp_for_level(int(need[1])) - Skills.xp_of(skills, skill))
	return "Needs %s %d · %s XP to go" % [Skills.label(skill), int(need[1]), SkillsWindow._grouped(to_go)]


## "[color=#..]Ash wood 2/3[/color] · ..." for a row's parts.
static func parts_bbcode(parts: Array) -> String:
	var out := PackedStringArray()
	for p in parts:
		var c: Color = OK_COLOR if bool(p.ok) else SHORT_COLOR
		out.append("[color=#%s]%s %d/%d[/color]" % [c.to_html(false), p.label, int(p.have), int(p.need)])
	return "  ·  ".join(out)


## The toast for a craft: "Crafted: Stone axe!" / "Crafted: 3 Torches!".
static func toast_text(id: String) -> String:
	var r: Dictionary = Crafting.RECIPES[id]
	var label := str(r.label)
	label = label.left(1).to_upper() + label.substr(1)
	if int(r.makes) > 1:
		return "Crafted: %d %ses!" % [int(r.makes), label]
	return "Crafted: %s!" % label


# --- the window ---

func setup(theme_res: Theme) -> void:
	theme = theme_res
	visible = false
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 0.5
	anchor_bottom = 0.5
	offset_left = -WIDTH * 0.5
	offset_right = WIDTH * 0.5
	offset_top = -HEIGHT * 0.5
	offset_bottom = HEIGHT * 0.5
	grow_vertical = Control.GROW_DIRECTION_BOTH
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.09, 0.08, 0.07, 0.88)
	bg.border_color = Color(ACCENT, 0.6)
	bg.set_border_width_all(1)
	bg.set_corner_radius_all(6)
	add_theme_stylebox_override("panel", bg)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 18)
	add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	margin.add_child(box)
	var title := Label.new()
	title.text = "Workbench"
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", ACCENT)
	box.add_child(title)
	var sub := Label.new()
	sub.text = "Spawn Meadow · gather the parts, then craft"
	sub.modulate = DIM
	box.add_child(sub)
	list_scroll = ScrollContainer.new()
	list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	list_scroll.custom_minimum_size = Vector2(0, LIST_HEIGHT)
	list_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(list_scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 10)
	list_scroll.add_child(list)
	for id in Crafting.RECIPE_ORDER:
		list.add_child(HSeparator.new())
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 12)
		list.add_child(line)
		var product := TextureRect.new()
		product.custom_minimum_size = Vector2(IconShelf.ROW_SIZE, IconShelf.ROW_SIZE)
		product.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		product.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		product.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		product.mouse_filter = Control.MOUSE_FILTER_IGNORE
		line.add_child(product)
		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_theme_constant_override("separation", 2)
		line.add_child(col)
		var name_label := Label.new()
		name_label.add_theme_font_size_override("font_size", 18)
		col.add_child(name_label)
		var needs := RichTextLabel.new()
		needs.bbcode_enabled = true
		needs.fit_content = true
		needs.scroll_active = false
		needs.custom_minimum_size = Vector2(WIDTH - 172 - IconShelf.ROW_SIZE - 12, 0) # room for the scroll bar
		col.add_child(needs)
		var hint := Label.new()
		hint.add_theme_font_size_override("font_size", 13)
		hint.modulate = DIM
		col.add_child(hint)
		var button := Button.new()
		button.custom_minimum_size = Vector2(96, 36)
		button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		button.pressed.connect(func(): craft(id))
		line.add_child(button)
		_rows[id] = {"icon": product, "name": name_label, "needs": needs, "hint": hint, "button": button}
	box.add_child(HSeparator.new())
	status_label = Label.new()
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.custom_minimum_size = Vector2(WIDTH - 40, 0)
	box.add_child(status_label)
	var close_row := HBoxContainer.new()
	box.add_child(close_row)
	var keys := Label.new()
	keys.text = "E or Esc to close"
	keys.modulate = DIM
	keys.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	close_row.add_child(keys)
	var close_button := Button.new()
	close_button.text = "Close"
	close_button.pressed.connect(close)
	close_row.add_child(close_button)
	refresh()


func open(p: Vector3) -> void:
	pos = p
	visible = true
	if not is_waiting():
		status_label.text = "" if pack_known else "Checking your pack..."
		status_label.modulate = Color.WHITE
	refresh()


func close() -> void:
	if not visible:
		return
	visible = false
	closed.emit()


## Craft button: asks the server to make `id` (one request at a time). False when nothing
## was sent: the pack isn't known yet, an answer is still due, or `id` is no recipe.
func craft(id: String) -> bool:
	if not pack_known or is_waiting() or not Crafting.is_recipe(id):
		return false
	_awaiting = id
	_awaiting_age = 0.0
	status_label.text = WORKING
	status_label.modulate = Color.WHITE
	refresh()
	craft_requested.emit(id)
	return true


## Lights each row from the pack and where you stand.
func refresh() -> void:
	for id in _rows:
		var w: Dictionary = _rows[id]
		var r := row(pack, id, pos, skills)
		w.name.text = r.title
		(w.name as Label).modulate = DIM if r.reason == "level" else Color.WHITE
		(w.icon as TextureRect).texture = _icon(id, IconShelf.ROW_SIZE)
		_fill_needs(w.needs, r.parts)
		w.hint.text = r.hint if pack_known else ""
		var button: Button = w.button
		button.text = r.button
		button.disabled = not pack_known or r.reason != "" or _crafting()
		button.tooltip_text = r.hint


func _icon(item: String, size: int) -> Texture2D:
	return icons.texture(item, size) if icons else ItemIcons.texture(item, size)


## "[icon] Ash wood 2/3  ·  [icon] Stone 0/2", each part in green or red (same words as
## parts_bbcode, with each item's little icon in front).
func _fill_needs(needs: RichTextLabel, parts: Array) -> void:
	needs.clear()
	if not pack_known:
		needs.push_color(DIM)
		needs.add_text("...")
		needs.pop()
		return
	for i in parts.size():
		var p: Dictionary = parts[i]
		if i > 0:
			needs.add_text("  ·  ")
		needs.add_image(_icon(str(p.item), IconShelf.PART_SIZE), IconShelf.PART_SIZE, IconShelf.PART_SIZE,
			Color.WHITE, INLINE_ALIGNMENT_CENTER)
		needs.add_text(" ")
		needs.push_color(OK_COLOR if bool(p.ok) else SHORT_COLOR)
		needs.add_text("%s %d/%d" % [p.label, int(p.have), int(p.need)])
		needs.pop()


## Every frame while logged in: closes the window when you walk off, and gives up on an
## answer that never came so the buttons light again.
func tick(delta: float, p: Vector3) -> void:
	pos = p
	if _awaiting != "":
		_awaiting_age += delta
		if _awaiting_age > REPLY_TIMEOUT:
			_awaiting = ""
			status_label.text = NO_ANSWER
			status_label.modulate = SHORT_COLOR
			refresh()
	if visible and walked_away(p):
		close()


## The server's craft_result. Shows its words (a success in the ember accent, a refusal in
## red) and returns {crafted: the recipe id on a success, else "", ok}. The pack itself
## follows as s2c_inventory on the server's next tick.
func on_craft_result(recipe_id: String, ok: bool, text: String) -> Dictionary:
	if recipe_id == _awaiting:
		_awaiting = ""
	status_label.text = text
	status_label.modulate = ACCENT if ok else SHORT_COLOR
	refresh()
	return {"crafted": recipe_id if ok and Crafting.is_recipe(recipe_id) else "", "ok": ok}


## True from a Craft press until its answer (or the timeout).
func _crafting() -> bool:
	return _awaiting != ""


## The pack as the server sends it (the login character's `inventory`, then every
## s2c_inventory). Anything that isn't a Dictionary is ignored.
func seed_pack(inv: Variant) -> void:
	if typeof(inv) == TYPE_DICTIONARY:
		pack = Inventory.to_wire(Inventory.normalize(inv))
		pack_known = true
		refresh()


## skills_changed / xp_gained: your skills (skill id -> XP), so level-gated rows grey out.
func on_skills(all: Dictionary) -> void:
	skills = all.duplicate()
	refresh()


func is_waiting() -> bool:
	return _awaiting != ""


func reset() -> void:
	visible = false
	pack = {}
	pack_known = false
	skills = null
	_awaiting = ""
	_awaiting_age = 0.0
	if status_label:
		status_label.text = ""
