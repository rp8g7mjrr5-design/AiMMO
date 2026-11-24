class_name PlayersPanel
extends PanelContainer
## The players panel (O, or the "Players" button top right): who is in the valley right now,
## each with their total level (every skill's level added up), you marked in ember orange.
## It replaces typing "/who" in chat (owner direction 1: chat is for talking). Opening it
## frees the cursor like any other window; O, Esc or Close shut it.
##
## Fed only by the server's s2c_roster (`on_roster`), which comes right after login and again
## whenever anyone joins, leaves or levels up. A row for someone who just arrived glows gold
## and says "just arrived"; a row whose total level went up glows gold with "+N", so a burst
## across the meadow can be put to a name. The very first roster after login never glows.
## The "Players" button carries the live count ("Players 5"), so the valley's size reads at a
## glance without opening anything.
##
## The texts are static functions over the roster Array, so unit tests and the bot test check
## them without building a window.

signal closed

const WIDTH := 380.0
const LIST_HEIGHT := 330.0 ## about eleven rows; more scroll
const ROW_HEIGHT := 30.0 ## one row plus its gap, for sizing the list to the roster
const HALF_HEIGHT := 90.0 ## the panel's resting half-height; it grows to fit its rows
const ACCENT := HudStyle.EMBER ## ember orange, as the other windows: your own row
const GOLD := HudStyle.XP ## the "this just changed" glow, the XP meter's gold
const DIM := HudStyle.TEXT_DIM
const FLASH_SECONDS := 1.6 ## how long a row that just changed glows
const ARRIVED_TEXT := "just arrived"

var my_id := 0
var entries: Array = [] ## the last roster, cleaned by `rows`
var _known := false ## false until the first roster after login (that one never glows)
var _flash := {} ## peer id -> seconds of glow left
var _note := {} ## peer id -> "+N" or ARRIVED_TEXT while it glows
var _header: Label
var _list: VBoxContainer
var _scroll: ScrollContainer
var _row_nodes := {} ## peer id -> {name: Label, level: Label, note: Label}


## The server's roster as rows: [{id, name, level, you}], in the server's order (sorted by
## name). Anything malformed or a second row for one id is skipped, so a bad entry never
## breaks the panel; a missing level shows as 0.
static func rows(roster: Array, me: int) -> Array:
	var out: Array = []
	var seen := {}
	for e in roster:
		if not (e is Dictionary) or not e.has("id"):
			continue
		var id := int(e.id)
		if seen.has(id):
			continue
		seen[id] = true
		out.append({"id": id, "name": str(e.get("name", "?")), "level": int(e.get("level", 0)), "you": id == me})
	return out


## "Just you in the valley", "2 in the valley".
static func header_text(count: int) -> String:
	if count <= 1:
		return "Just you in the valley"
	return "%d in the valley" % count


## "Players 5" on the button (just "Players" before the first roster).
static func button_text(count: int) -> String:
	return "Players" if count <= 0 else "Players %d" % count


## "Total level 12"
static func level_text(level: int) -> String:
	return "Total level %d" % level


## What changed between two rosters (both from `rows`): {joined: [ids], levelled: {id: +N}}.
## Someone who left is simply gone; a level that went down (never on the server) is ignored.
static func changes(old_rows: Array, new_rows: Array) -> Dictionary:
	var before := {}
	for r in old_rows:
		before[int(r.id)] = int(r.level)
	var joined: Array = []
	var levelled := {}
	for r in new_rows:
		var id := int(r.id)
		if not before.has(id):
			joined.append(id)
		elif int(r.level) > int(before[id]):
			levelled[id] = int(r.level) - int(before[id])
	return {"joined": joined, "levelled": levelled}


func setup(theme_res: Theme) -> void:
	theme = theme_res
	visible = false
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 0.5
	anchor_bottom = 0.5
	offset_left = -WIDTH * 0.5
	offset_right = WIDTH * 0.5
	offset_top = -HALF_HEIGHT
	offset_bottom = HALF_HEIGHT
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
	title.text = "Players"
	title.add_theme_font_size_override("font_size", 21)
	title.add_theme_color_override("font_color", ACCENT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	_header = Label.new()
	_header.add_theme_color_override("font_color", GOLD)
	_header.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_header)
	_scroll = ScrollContainer.new()
	var scroll := _scroll
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 6)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)
	var foot := HBoxContainer.new()
	box.add_child(foot)
	var hint := Label.new()
	hint.text = "Total level is every skill's level added up."
	hint.add_theme_font_size_override("font_size", 13)
	hint.modulate = DIM
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(hint)
	var done := Button.new()
	done.text = "Close"
	done.focus_mode = Control.FOCUS_NONE
	done.pressed.connect(close)
	foot.add_child(done)
	_rebuild()


## Who "you" is (login): marks your row, even if the roster beat the login answer here.
func set_me(id: int) -> void:
	my_id = id
	for r in entries:
		r.you = int(r.id) == my_id
	_rebuild()


## s2c_roster: everyone online. Rows that joined or levelled since the last roster glow.
func on_roster(roster: Array) -> void:
	var fresh := rows(roster, my_id)
	if _known:
		var ch := changes(entries, fresh)
		for id in ch.joined:
			if int(id) == my_id:
				continue
			_flash[int(id)] = FLASH_SECONDS
			_note[int(id)] = ARRIVED_TEXT
		for id in ch.levelled:
			# A second level-up while the first still glows adds to its "+N".
			var prev := 0
			if _flash.has(int(id)) and str(_note.get(int(id), "")).begins_with("+"):
				prev = str(_note[int(id)]).substr(1).to_int()
			_flash[int(id)] = FLASH_SECONDS
			_note[int(id)] = "+%d" % (prev + int(ch.levelled[id]))
	for id in _flash.keys():
		var still := false
		for r in fresh:
			if int(r.id) == int(id):
				still = true
		if not still:
			_flash.erase(id)
			_note.erase(id)
	entries = fresh
	_known = true
	_rebuild()


func _rebuild() -> void:
	if _list == null:
		return
	_header.text = header_text(entries.size())
	# The list is as tall as its rows (up to LIST_HEIGHT, then it scrolls), and the panel
	# shrinks back around it, so three players don't sit in a mostly empty box.
	_scroll.custom_minimum_size = Vector2(0, clampf(entries.size() * ROW_HEIGHT, ROW_HEIGHT, LIST_HEIGHT))
	offset_top = -HALF_HEIGHT
	offset_bottom = HALF_HEIGHT
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	_row_nodes = {}
	for r in entries:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var nm := Label.new()
		nm.text = str(r.name) + ("  (you)" if r.you else "")
		nm.add_theme_font_size_override("font_size", 17)
		nm.clip_text = true
		nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(nm)
		var note := Label.new()
		note.add_theme_font_size_override("font_size", 13)
		note.add_theme_color_override("font_color", GOLD)
		note.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(note)
		var lv := Label.new()
		lv.text = level_text(int(r.level))
		lv.modulate = DIM
		lv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(lv)
		_list.add_child(row)
		_row_nodes[int(r.id)] = {"name": nm, "level": lv, "note": note, "you": bool(r.you)}
	_paint()


## Every frame: fades the glow on rows that just changed.
func step(delta: float) -> void:
	if _flash.is_empty():
		return
	for id in _flash.keys():
		_flash[id] = float(_flash[id]) - delta
		if float(_flash[id]) <= 0.0:
			_flash.erase(id)
			_note.erase(id)
	_paint()


func _paint() -> void:
	for id in _row_nodes:
		var n: Dictionary = _row_nodes[id]
		var base: Color = ACCENT if n.you else HudStyle.TEXT
		var f := flash_of(int(id))
		n.name.add_theme_color_override("font_color", base.lerp(GOLD, f * f))
		n.note.text = str(_note.get(int(id), "")) if f > 0.0 else ""
		n.note.modulate.a = clampf(f * 1.5, 0.0, 1.0)


## How bright a row's glow is right now (0 to 1), for tests.
func flash_of(id: int) -> float:
	return clampf(float(_flash.get(id, 0.0)) / FLASH_SECONDS, 0.0, 1.0)


## The note a row shows right now ("+1", "just arrived" or ""), for tests.
func note_of(id: int) -> String:
	var n: Dictionary = _row_nodes.get(id, {})
	return str(n.note.text) if not n.is_empty() else ""


## The rows on screen as "Name  (you)|Total level 9", for tests.
func shown() -> Array:
	var out: Array = []
	for r in entries:
		var n: Dictionary = _row_nodes.get(int(r.id), {})
		if not n.is_empty():
			out.append("%s|%s" % [n.name.text, n.level.text])
	return out


func header_shown() -> String:
	return _header.text if _header != null else ""


func open() -> void:
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


## On disconnect: shut and forget everyone, so the next login's first roster doesn't glow.
func reset() -> void:
	visible = false
	entries = []
	_known = false
	_flash = {}
	_note = {}
	my_id = 0
	_rebuild()
