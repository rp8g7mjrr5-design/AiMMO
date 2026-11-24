class_name LevelUpBanner
extends Control
## The level-up moment (roadmap Milestone 1, part 2). On s2c_level_up a banner pops in near
## the top of the screen: the skill's badge, "Felling 5" in calm ember type, what the level
## gave you ("Old ember ash: work the old ember ashes past the meadow", or "Your gathers are a
## little quicker"), and the next goal ("Next: Felling 10, Clean cuts"). It pops with a small
## overshoot, holds, and fades, all inside DURATION (under 2 s), and never takes the mouse or
## the keyboard, so you keep chopping straight through it.
##
## The client pairs it with Sfx.level_up() and world's LevelUpFx burst on your avatar, and
## drops the server's matching level-up system line from chat (chat is for talking).
##
## Pure static helpers (texts, pop scale, alpha) are unit tested; the node only draws them.

const WIDTH := 520.0
const HEIGHT := 92.0
const ICON := 40 ## badge size, px
const DURATION := 1.9 ## seconds from pop to gone
const POP_SECONDS := 0.28 ## scale POP_FROM -> 1.0 over this, easing out, no overshoot
const POP_FROM := 0.92 ## proud, not loud (art bible section 9): a settle, not a bounce
const TITLE_SIZE := 24 ## calm type; the badge and the ember colour carry the moment
const FADE_SECONDS := 0.45 ## the last part of DURATION
const GOLD := HudStyle.EMBER ## the one accent: a level is the XP bar paying out
const LABEL := HudStyle.TEXT
const DIM := HudStyle.TEXT_DIM

var icon: TextureRect
var title_label: Label
var unlock_label: Label
var next_label: Label
var _skill := ""
var _level := 0
var _age := INF
## The system line the server sends with this level-up, so the client can keep it out of chat.
var _expect_line := ""


## "Felling 5"
static func title_text(skill: String, level: int) -> String:
	return "%s %d" % [Skills.label(skill), level]


## What reaching `level` gave you: the named unlocks ("Old ember ash: work the old ember
## ashes past the meadow (coming soon)"), else the small speed gain every gathering level
## brings. Empty for a Toolcraft level with no unlock.
static func unlock_text(skill: String, unlocks: Array) -> String:
	if not unlocks.is_empty():
		var parts := PackedStringArray()
		for u in unlocks:
			if not (u is Dictionary):
				continue
			var line := "%s: %s" % [str(u.get("name", "")), str(u.get("text", ""))]
			if u.get("soon", false):
				line += " (coming soon)"
			parts.append(line)
		return "  ·  ".join(parts)
	if skill == "toolcraft" or not Skills.is_skill(skill):
		return ""
	return "Your %s are a little quicker" % str(Skills.SKILLS[skill].verb)


## "Next: Felling 10, Clean cuts", or "" when nothing named is left.
static func next_text(skill: String, level: int) -> String:
	var nxt = Skills.next_unlock(skill, level)
	if nxt == null:
		return ""
	return "Next: %s %d, %s" % [Skills.label(skill), int(nxt.level), str(nxt.name)]


## The system line the server sends with this level-up (`Skills.level_up_text`); the client
## keeps exactly that line out of chat because the banner already said it.
static func announcement(skill: String, level: int, unlocks: Array) -> String:
	return Skills.level_up_text({"skill": skill, "level": level, "unlocks": unlocks})


## The banner's scale `age` seconds in: grows from POP_FROM and settles at 1 without
## overshooting (the old 0.6 -> 1.08 bounce read as a mobile game).
static func pop_scale(age: float) -> float:
	if age <= 0.0:
		return POP_FROM
	if age >= POP_SECONDS:
		return 1.0
	var t := age / POP_SECONDS
	return lerpf(POP_FROM, 1.0, 1.0 - pow(1.0 - t, 3.0)) # ease-out cubic


## The banner's alpha `age` seconds in: in fast, holds, fades over the last FADE_SECONDS.
static func alpha(age: float) -> float:
	if age < 0.0 or age >= DURATION:
		return 0.0
	if age < 0.08:
		return age / 0.08
	var fade_from := DURATION - FADE_SECONDS
	if age <= fade_from:
		return 1.0
	return clampf(1.0 - (age - fade_from) / FADE_SECONDS, 0.0, 1.0)


func setup(theme: Theme) -> void:
	self.theme = theme
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(WIDTH, HEIGHT)
	size = Vector2(WIDTH, HEIGHT)
	pivot_offset = Vector2(WIDTH * 0.5, HEIGHT * 0.4)
	icon = TextureRect.new()
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.size = Vector2(ICON, ICON)
	icon.position = Vector2(0, 0)
	add_child(icon)
	title_label = _make_label(TITLE_SIZE, GOLD, 4.0, 34.0)
	unlock_label = _make_label(14, LABEL, 46.0, 20.0)
	next_label = _make_label(12, DIM, 68.0, 18.0)
	_apply()


func _make_label(font_size: int, color: Color, y: float, h: float) -> Label:
	var l := Label.new()
	l.position = Vector2(0, y)
	l.size = Vector2(WIDTH, h)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	HudStyle.quiet_label(l, font_size, color)
	add_child(l)
	return l


## s2c_level_up: show the banner (a second level-up restarts it with the newer one).
func on_level_up(skill: String, level: int, unlocks: Array) -> void:
	_skill = skill
	_level = level
	_age = 0.0
	title_label.text = title_text(skill, level)
	unlock_label.text = unlock_text(skill, unlocks)
	next_label.text = next_text(skill, level)
	icon.texture = SkillIcons.texture(skill, ICON) if Skills.is_skill(skill) else null
	# Sit the badge just left of the title, whatever its width.
	var title_w := title_label.get_theme_font("font").get_string_size(title_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, TITLE_SIZE).x
	icon.position = Vector2((WIDTH - title_w) * 0.5 - ICON - 10.0, 1.0)
	_expect_line = announcement(skill, level, unlocks)
	_apply()


## A system line from the server: true if it is this level-up's own announcement (the banner
## already said it, so it stays out of chat). Each level-up swallows at most one line.
func consume_system(text: String) -> bool:
	if _expect_line != "" and text == _expect_line:
		_expect_line = ""
		return true
	return false


## Every frame.
func step(delta: float) -> void:
	if _age == INF:
		return
	_age += delta
	if _age >= DURATION:
		_age = INF
	_apply()


func _apply() -> void:
	if title_label == null:
		return
	var a := alpha(_age) if _age != INF else 0.0
	modulate.a = a
	var s := pop_scale(_age) if _age != INF else 1.0
	scale = Vector2(s, s)


## The banner's alpha right now (0 when it isn't up).
func current_alpha() -> float:
	return alpha(_age) if _age != INF else 0.0


## Is the banner on screen right now?
func showing() -> bool:
	return _age != INF and alpha(_age) > 0.0


func current() -> String:
	return title_text(_skill, _level) if _skill != "" else ""


func hide_all() -> void:
	_skill = ""
	_level = 0
	_age = INF
	_expect_line = ""
	_apply()
