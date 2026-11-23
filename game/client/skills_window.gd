class_name SkillsWindow
extends PanelContainer
## The skills window (K, or the "Skills" button top right) and the next-goal line under the
## compass (Milestone 1, part 3). The window lists every skill with its badge, level, XP bar,
## the XP to the next level and the next named unlock, with your total level across all skills
## at the top. Opening it frees the cursor like any other window; K, Esc or Close shut it.
## The goal line always names the unlock you are closest to ("Next: Felling 5 unlocks Old ember
## ash (240 XP)"), so there is always a reason for the next gather.
##
## Everything it shows comes from the server's s2c_skills (login) and s2c_xp (each gain), kept
## in `skills` (skill id -> total XP). The texts are static functions over that Dictionary, so
## unit tests and the bot test check them without building a window.

signal closed

const WIDTH := 520.0
const ACCENT := Color(1.0, 0.56, 0.24) ## ember orange, as the workbench window and F1 list
const GOLD := Color(1.0, 0.84, 0.42) ## XP gold, as the XP meter
const DIM := Color(1, 1, 1, 0.6)
const BADGE_SIZE := 40
const BAR_H := 8.0
const GOAL_FLASH_SECONDS := 1.2 ## the goal line glows gold this long when it moves on to a new goal
const GOAL_COLOUR := Color(1.0, 0.95, 0.86, 0.85) ## the goal line at rest: warm white, quiet

var skills := {}
var _total_label: Label
var _rows_box: VBoxContainer
var _rows := {} ## skill -> {level: Label, bar: ProgressBar, xp: Label, next: Label}


## Your total level: every skill's level added up (4 for a brand-new character).
static func total_level(all: Dictionary) -> int:
	var t := 0
	for s in Skills.ORDER:
		t += Skills.level_of(all, s)
	return t


static func total_xp(all: Dictionary) -> int:
	var t := 0
	for s in Skills.ORDER:
		t += Skills.xp_of(all, s)
	return t


static func total_text(all: Dictionary) -> String:
	return "Total level %d  ·  %s XP" % [total_level(all), _grouped(total_xp(all))]


## "Felling 3"
static func level_text(all: Dictionary, skill: String) -> String:
	return "%s %d" % [Skills.label(skill), Skills.level_of(all, skill)]


## "1,240 XP to level 4", or "Max level" at the cap.
static func xp_text(all: Dictionary, skill: String) -> String:
	var xp := Skills.xp_of(all, skill)
	if Skills.level_for(xp) >= Skills.CAP:
		return "Max level"
	return "%s XP to level %d" % [_grouped(Skills.xp_to_next(xp)), Skills.level_for(xp) + 1]


## "Level 5: Old ember ash, work the old ember ashes past the meadow", with "(coming soon)"
## for an unlock that is named but not built yet, or "" when nothing named is left.
static func next_text(all: Dictionary, skill: String) -> String:
	var u = Skills.next_unlock(skill, Skills.level_of(all, skill))
	if u == null:
		return ""
	var line := "Level %d: %s, %s" % [int(u.level), str(u.name), str(u.text)]
	if u.get("soon", false):
		line += " (coming soon)"
	return line


## The named unlock you are closest to, across every skill, by XP still needed:
## {skill, level, name, need}. Unlocks marked `soon` are skipped (they aren't in the world
## yet, so they make a poor goal). Ties go to the skill listed first. Empty when none is left.
## The goal follows what you do: only skills you have earned XP in compete. A brand-new
## character (no XP anywhere) is pointed at the first skill in Skills.ORDER, where the game
## starts (chop a tree), not at a cheap Toolcraft unlock it has no materials for yet. If every
## skill you have trained is past its last unlock, the untrained ones compete after all.
static func next_goal(all: Dictionary) -> Dictionary:
	var trained: Array = []
	for s in Skills.ORDER:
		if Skills.xp_of(all, s) > 0:
			trained.append(s)
	if trained.is_empty():
		trained = [Skills.ORDER[0]]
	var best := _closest(all, trained)
	if best.is_empty():
		best = _closest(all, Skills.ORDER)
	return best


static func _closest(all: Dictionary, skills: Array) -> Dictionary:
	var best := {}
	for s in skills:
		var xp := Skills.xp_of(all, s)
		var lv := Skills.level_for(xp)
		var u = Skills.next_unlock(s, lv)
		while u != null and u.get("soon", false):
			u = Skills.next_unlock(s, int(u.level))
		if u == null:
			continue
		var need := Skills.xp_for_level(int(u.level)) - xp
		if best.is_empty() or need < int(best.need):
			best = {"skill": s, "level": int(u.level), "name": str(u.name), "need": need}
	return best


## "Next: Felling 5 unlocks Old ember ash (240 XP)", or "" when there is no goal left.
static func goal_text(all: Dictionary) -> String:
	var g := next_goal(all)
	if g.is_empty():
		return ""
	return "Next: %s %d unlocks %s (%s XP)" % [Skills.label(str(g.skill)), int(g.level), str(g.name), _grouped(int(g.need))]


## Which unlock the goal names ("felling:5"), "" for none: the client flashes the line when
## this changes after a gain (you just reached the old goal).
static func goal_key(all: Dictionary) -> String:
	var g := next_goal(all)
	return "" if g.is_empty() else "%s:%d" % [g.skill, int(g.level)]


## The goal line's colour: GOLD at `flash` 1, easing back to GOAL_COLOUR at 0.
static func goal_colour(flash: float) -> Color:
	return GOAL_COLOUR.lerp(GOLD, clampf(flash, 0.0, 1.0) ** 2)


## 12345 -> "12,345"
static func _grouped(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out


func setup(theme_res: Theme) -> void:
	theme = theme_res
	visible = false
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 0.5
	anchor_bottom = 0.5
	offset_left = -WIDTH * 0.5
	offset_right = WIDTH * 0.5
	offset_top = -190
	offset_bottom = 190
	grow_vertical = Control.GROW_DIRECTION_BOTH
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.09, 0.08, 0.07, 0.9)
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
	var head := HBoxContainer.new()
	box.add_child(head)
	var title := Label.new()
	title.text = "Skills"
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", ACCENT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	_total_label = Label.new()
	_total_label.add_theme_color_override("font_color", GOLD)
	_total_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_total_label)
	_rows_box = VBoxContainer.new()
	_rows_box.add_theme_constant_override("separation", 12)
	box.add_child(_rows_box)
	for s in Skills.ORDER:
		_rows_box.add_child(_make_row(s))
	var foot := HBoxContainer.new()
	box.add_child(foot)
	var note := Label.new()
	note.text = "Every level makes that skill a little quicker."
	note.modulate = DIM
	note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(note)
	var done := Button.new()
	done.text = "Close"
	done.focus_mode = Control.FOCUS_NONE
	done.pressed.connect(close)
	foot.add_child(done)
	refresh()


func _make_row(skill: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var badge := TextureRect.new()
	badge.texture = SkillIcons.texture(skill, BADGE_SIZE)
	badge.custom_minimum_size = Vector2(BADGE_SIZE, BADGE_SIZE)
	badge.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(badge)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(col)
	var top := HBoxContainer.new()
	col.add_child(top)
	var lv := Label.new()
	lv.add_theme_font_size_override("font_size", 18)
	lv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(lv)
	var xp := Label.new()
	xp.modulate = DIM
	top.add_child(xp)
	var bar := ProgressBar.new()
	bar.min_value = 0.0
	bar.max_value = 1.0
	bar.step = 0.0
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, BAR_H)
	var fill := StyleBoxFlat.new()
	fill.bg_color = GOLD
	fill.set_corner_radius_all(3)
	var back := StyleBoxFlat.new()
	back.bg_color = Color(1, 1, 1, 0.12)
	back.set_corner_radius_all(3)
	bar.add_theme_stylebox_override("fill", fill)
	bar.add_theme_stylebox_override("background", back)
	col.add_child(bar)
	var nxt := Label.new()
	nxt.add_theme_font_size_override("font_size", 13)
	nxt.add_theme_color_override("font_color", Color(ACCENT, 0.9))
	nxt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(nxt)
	_rows[skill] = {"level": lv, "bar": bar, "xp": xp, "next": nxt}
	return row


## s2c_skills (login): every skill's total XP.
func on_skills(all: Dictionary) -> void:
	skills = Skills.normalize(all)
	refresh()


## s2c_xp: one skill's new total.
func on_gain(skill: String, total: int) -> void:
	if not Skills.is_skill(skill):
		return
	skills[skill] = total
	refresh()


## Rewrites every text and bar from `skills` (cheap: four rows, only on a change or open).
func refresh() -> void:
	if _total_label == null:
		return
	_total_label.text = total_text(skills)
	for s in _rows:
		var r: Dictionary = _rows[s]
		r.level.text = level_text(skills, s)
		r.xp.text = xp_text(skills, s)
		r.bar.value = Skills.progress(Skills.xp_of(skills, s))
		r.next.text = next_text(skills, s)
		r.next.visible = r.next.text != ""


func row_texts(skill: String) -> Dictionary:
	var r: Dictionary = _rows.get(skill, {})
	if r.is_empty():
		return {}
	return {"level": r.level.text, "xp": r.xp.text, "bar": r.bar.value, "next": r.next.text}


func total_shown() -> String:
	return _total_label.text if _total_label != null else ""


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


## On disconnect: shut, forget the old character.
func reset() -> void:
	visible = false
	skills = {}
	refresh()
