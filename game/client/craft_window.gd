class_name CraftWindow
extends PanelContainer
## The workbench window. Stand within Crafting.BENCH_RANGE of the Spawn Meadow workbench and
## a prompt says "[E] Use Workbench"; E opens this window with every recipe, what it needs
## against what you carry ("Ash wood 2/3"), and a Craft button that lights up when you have
## it all. Owner direction 1: crafting is a window, not a chat command.
##
## The server decides everything (Crafting.check on its own copy of the pack and position).
## Until protocol v3/v4 brings c2s_craft and s2c_inventory, the window talks through the same
## hidden chat commands the bots use: opening it sends "/bag" and Craft sends "/craft <id>",
## and their replies are shown here instead of in chat. The client keeps a mirror of the pack
## from those replies and from gather lines ("(6 in your pack)"), only to light the buttons.
## All the rules are static functions so they are unit tested headless.

signal closed

const WIDTH := 600.0 ## room for a part icon before each "Ash wood 2/3"
const REPLY_TIMEOUT := 1.5 ## seconds to wait for an answer (the chat cooldown drops lines silently)
const SEND_GAP := GameConfig.CHAT_COOLDOWN + 0.1 ## never send faster than the server listens
const CLOSE_SLACK := 1.0 ## m past BENCH_RANGE before walking away closes the window
const OK_COLOR := Color(0.62, 0.92, 0.55)
const SHORT_COLOR := Color(1.0, 0.55, 0.45)
const ACCENT := GatherPrompt.ACCENT
const DIM := Color(0.85, 0.85, 0.85, 0.7)

var pack := {} ## the client's mirror of the pack
var pack_known := false
var pos := Vector3.ZERO ## where you stand, for the bench check
var status_label: Label
## Where the icons come from (set by the client; without one, world's cache draws them).
var icons: IconShelf
var _rows := {} ## recipe id -> {needs: RichTextLabel, button: Button}
var _awaiting := "" ## "bag", "craft:<id>" or ""
var _awaiting_age := 0.0
var _since_send := INF
var _queue: Array = [] ## lines to send, oldest first
var _last_crafted := ""


# --- rules (static, unit tested) ---

## True when the "[E] Use Workbench" prompt shows for a player at `p`.
static func near_bench(p: Vector3) -> bool:
	return Crafting.near_bench(p)


## True once you have walked far enough from the bench that the open window closes.
static func walked_away(p: Vector3) -> bool:
	return Vector2(p.x, p.z).distance_to(Crafting.WORKBENCH_XZ) > Crafting.BENCH_RANGE + CLOSE_SLACK


## "Your pack: 4 ash wood, 2 stone." -> {"ash_wood": 4, "stone": 2}; "Your pack is empty..."
## -> {}; any other line -> null. Unknown labels are kept by their words, like Inventory does.
static func parse_pack(text: String) -> Variant:
	if text.begins_with("Your pack is empty"):
		return {}
	if not text.begins_with("Your pack: "):
		return null
	var body := text.substr("Your pack: ".length()).strip_edges()
	if body.ends_with("."):
		body = body.left(body.length() - 1)
	var out := {}
	var re := RegEx.create_from_string("^(\\d+) (.+)$")
	for part in body.split(", ", false):
		var m := re.search(part.strip_edges())
		if m == null:
			return null
		out[item_for_label(m.get_string(2))] = m.get_string(1).to_int()
	return out


## Item id for a label as the server writes it ("ash wood" -> "ash_wood").
static func item_for_label(label: String) -> String:
	for id in Inventory.ITEMS:
		if Inventory.label(id).to_lower() == label.to_lower():
			return id
	return label.to_lower().replace(" ", "_")


## The pack after a server line, or null if the line says nothing about the pack.
## Knows "Your pack: ...", gather successes ("(6 in your pack)") and, when `crafted` names the
## recipe just sent, "You craft ..." (ingredients used up, product added).
static func apply_line(inv: Dictionary, text: String, crafted: String = "") -> Variant:
	var listed: Variant = parse_pack(text)
	if listed != null:
		return listed
	var gain := GatherPrompt.parse_gain(text)
	if not gain.is_empty() and str(gain.item) != "":
		var out := inv.duplicate()
		out[str(gain.item)] = int(gain.in_pack)
		return out
	if text.begins_with("You craft") and Crafting.is_recipe(crafted):
		var r: Dictionary = Crafting.RECIPES[crafted]
		var out := inv.duplicate()
		for item in r.needs:
			out[item] = maxi(0, Inventory.count(out, item) - int(r.needs[item]))
		var m := RegEx.create_from_string("\\((\\d+) in your pack\\)").search(text)
		out[crafted] = m.get_string(1).to_int() if m else mini(Inventory.MAX_STACK, Inventory.count(out, crafted) + int(r.makes))
		return out
	return null


## One recipe as the window shows it, for a pack and a position:
## {id, title ("Stone axe" / "Torch ×3"), parts: [{label, have, need, ok}], reason (Crafting.check,
## "" = ready), button ("Craft" / "Have it"), hint (why it's greyed out, or where it's made)}.
static func row(inv: Dictionary, id: String, p: Vector3) -> Dictionary:
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
	var reason := Crafting.check(inv, id, p)
	var hint := ""
	match reason:
		"":
			hint = "Ready"
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


## "[color=#..]Ash wood 2/3[/color] · ..." for a row's parts.
static func parts_bbcode(parts: Array) -> String:
	var out := PackedStringArray()
	for p in parts:
		var c: Color = OK_COLOR if bool(p.ok) else SHORT_COLOR
		out.append("[color=#%s]%s %d/%d[/color]" % [c.to_html(false), p.label, int(p.have), int(p.need)])
	return "  ·  ".join(out)


## What the window says about a server line it was waiting for: {text, ok}, or {} if the
## line isn't an answer to `awaiting` ("craft:<id>"). Refusals and successes both count.
static func craft_reply(text: String, awaiting: String) -> Dictionary:
	if not awaiting.begins_with("craft:"):
		return {}
	if text.begins_with("You craft"):
		return {"text": text, "ok": true}
	for p in ["You need", "You already carry", "No room in your pack", "Unknown recipe", "Craft what?"]:
		if text.begins_with(p):
			return {"text": text, "ok": false}
	var id := awaiting.substr(6)
	if Crafting.is_recipe(id) and text.begins_with("A %s needs the workbench" % Crafting.RECIPES[id].label):
		return {"text": text, "ok": false}
	return {}


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
	offset_top = -250
	offset_bottom = 250
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
	for id in Crafting.RECIPE_ORDER:
		box.add_child(HSeparator.new())
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 12)
		box.add_child(line)
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
		needs.custom_minimum_size = Vector2(WIDTH - 160 - IconShelf.ROW_SIZE - 12, 0)
		col.add_child(needs)
		var hint := Label.new()
		hint.add_theme_font_size_override("font_size", 13)
		hint.modulate = DIM
		col.add_child(hint)
		var button := Button.new()
		button.custom_minimum_size = Vector2(96, 36)
		button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		button.pressed.connect(craft.bind(id))
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
	status_label.text = "" if pack_known else "Checking your pack..."
	_send("/bag", "bag")
	refresh()


func close() -> void:
	if not visible:
		return
	visible = false
	closed.emit()


## Craft button: asks the server to make `id`.
func craft(id: String) -> void:
	if _awaiting.begins_with("craft:") or not _queue.is_empty():
		return
	_last_crafted = id
	status_label.text = "Crafting..."
	status_label.modulate = Color.WHITE
	_send("/craft %s" % id, "craft:" + id)
	refresh()


func _send(line: String, what: String) -> void:
	_queue.append([line, what])


## Lights each row from the mirrored pack and where you stand.
func refresh() -> void:
	for id in _rows:
		var w: Dictionary = _rows[id]
		var r := row(pack, id, pos)
		w.name.text = r.title
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


## Every frame while logged in. Returns the chat line to send now, or "".
func tick(delta: float, p: Vector3) -> String:
	pos = p
	_since_send += delta
	if _awaiting != "":
		_awaiting_age += delta
		if _awaiting_age > REPLY_TIMEOUT:
			# The line was dropped (chat cooldown) or the reply got lost: ask again once.
			var what := _awaiting
			_awaiting = ""
			if what == "bag" and visible:
				_send("/bag", "bag")
			elif what.begins_with("craft:"):
				status_label.text = "The bench didn't answer. Try again."
				refresh()
	if visible and walked_away(p):
		close()
	if _awaiting == "" and not _queue.is_empty() and _since_send >= SEND_GAP:
		var next: Array = _queue.pop_front()
		_awaiting = str(next[1])
		_awaiting_age = 0.0
		_since_send = 0.0
		refresh()
		return str(next[0])
	return ""


## A server line. Returns {consumed: bool (keep it out of chat), crafted: id or "", ok}.
func on_system(text: String) -> Dictionary:
	var crafted := _awaiting.substr(6) if _awaiting.begins_with("craft:") else ""
	var next: Variant = apply_line(pack, text, crafted)
	var out := {"consumed": false, "crafted": "", "ok": false}
	if next != null:
		pack = next
		if parse_pack(text) != null:
			pack_known = true
			if _awaiting == "bag":
				_awaiting = ""
				out.consumed = true
				if status_label.text == "Checking your pack...":
					status_label.text = ""
	var reply := craft_reply(text, _awaiting)
	if not reply.is_empty():
		_awaiting = ""
		out.consumed = true
		out.ok = bool(reply.ok)
		status_label.text = str(reply.text)
		status_label.modulate = ACCENT if reply.ok else SHORT_COLOR
		if reply.ok:
			out.crafted = crafted
		elif text.begins_with("You need"):
			_send("/bag", "bag") # the mirror was stale; look again
	refresh()
	return out


## True from a Craft press until its answer (or the timeout).
func _crafting() -> bool:
	if _awaiting.begins_with("craft:"):
		return true
	for q in _queue:
		if str(q[1]).begins_with("craft:"):
			return true
	return false


## The pack the server sent with the login character: the mirror's starting point.
func seed_pack(inv: Variant) -> void:
	if typeof(inv) == TYPE_DICTIONARY:
		pack = Inventory.to_wire(Inventory.normalize(inv))
		pack_known = true
		refresh()


func is_waiting() -> bool:
	return _awaiting != "" or not _queue.is_empty()


func reset() -> void:
	visible = false
	pack = {}
	pack_known = false
	_awaiting = ""
	_queue.clear()
	_since_send = INF
