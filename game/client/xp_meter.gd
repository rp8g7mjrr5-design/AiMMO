class_name XpMeter
extends Control
## XP you can see (roadmap Milestone 1, part 1). Every s2c_xp pops a small "+12 Felling" that
## floats up beside the haul toast, and a thin bar for that skill ("Felling 3 · 395 XP to 4")
## slides from where it was to where it is now, then fades a few seconds later. Gains land in
## the same frame as the gather result (gameplay sends s2c_xp right after it), so the haul and
## the XP read as one moment.
##
## The bar keeps a running total per skill: s2c_skills at login seeds it, each s2c_xp carries
## the new total. A gain that crosses a level runs the bar up to full, holds it there, brighter,
## for LEVEL_HOLD while the level-up banner pops (part 2, s2c_level_up), then empties and slides
## into the new level, so the full bar and the banner read as one payoff.
##
## Pure static helpers (texts, bar value, fades) are unit tested; the node only draws them.

const WIDTH := 300.0
const HEIGHT := 46.0
const GOLD := HudStyle.XP ## XP: the ember accent a step calmer, so it sits beside the haul toast
const LABEL := HudStyle.TEXT
const FLOAT_SECONDS := 1.6 ## the "+12 Felling" rises and fades over this
const FLOAT_RISE := 22.0 ## px it rises
const FILL_SECONDS := 0.55 ## the bar slides from old to new progress over this
const HOLD_SECONDS := 3.0 ## the bar stays this long after the last gain...
const FADE_SECONDS := 0.8 ## ...then fades out over this
const LEVEL_HOLD := 0.6 ## a gain that crosses a level holds the bar full this long...
const WRAP_SECONDS := 0.35 ## ...then slides from empty into the new level over this
const FULL_GLOW := Color(1.25, 1.18, 1.08) ## the bar's brightening while it holds full
const BAR_W := 200.0
const BAR_H := 5.0

var gain_label: Label
var level_label: Label
var bar: ProgressBar
## skill id -> total XP, as the server last told us.
var skills := {}
var _skill := ""
var _from := 0.0 ## bar progress before the last gain
var _to := 0.0 ## bar progress after it
var _levels := 0 ## levels the last gain crossed
var _age := INF ## seconds since the last gain


## "+12 Felling"
static func gain_text(skill: String, gained: int) -> String:
	return "+%d %s" % [gained, Skills.label(skill)]


## "Felling 3 · 395 XP to 4", or "Felling 100 · max" at the cap.
static func level_text(skill: String, xp: int) -> String:
	var l := Skills.level_for(xp)
	if l >= Skills.CAP:
		return "%s %d · max" % [Skills.label(skill), l]
	return "%s %d · %d XP to %d" % [Skills.label(skill), l, Skills.xp_to_next(xp), l + 1]


## What a gain of `gained` up to `total` does to the bar: {from, to, levels}. `before` is
## the total we knew (-1 if none; then total - gained is assumed).
static func gain_motion(before: int, gained: int, total: int) -> Dictionary:
	var b := before if before >= 0 else maxi(0, total - gained)
	b = mini(b, total)
	return {
		"from": Skills.progress(b),
		"to": Skills.progress(total),
		"levels": Skills.level_for(total) - Skills.level_for(b),
	}


## Seconds from a gain until the bar rests at its new value: FILL_SECONDS within a level; a
## level-up adds the full-bar hold and the slide into the new level.
static func settle_seconds(levels: int) -> float:
	return FILL_SECONDS if levels <= 0 else FILL_SECONDS + LEVEL_HOLD + WRAP_SECONDS


## The bar's value `age` seconds into a gain's slide: eases from `from` to `to`. A gain that
## crossed a level eases up to full, holds full for LEVEL_HOLD, then eases from empty to `to`.
static func bar_value(from: float, to: float, levels: int, age: float) -> float:
	if levels <= 0:
		return lerpf(from, to, _ease(age / FILL_SECONDS))
	if age < FILL_SECONDS:
		return lerpf(from, 1.0, _ease(age / FILL_SECONDS))
	var after := age - FILL_SECONDS - LEVEL_HOLD
	if after < 0.0:
		return 1.0
	return lerpf(0.0, to, _ease(after / WRAP_SECONDS))


## True while a level-crossing gain holds the bar full (it brightens then).
static func holding_full(levels: int, age: float) -> bool:
	return levels > 0 and age >= FILL_SECONDS and age < FILL_SECONDS + LEVEL_HOLD


## Ease out: quick start, soft landing. t is clamped to 0..1.
static func _ease(t: float) -> float:
	var c := clampf(t, 0.0, 1.0)
	return 1.0 - pow(1.0 - c, 3.0)


## Alpha of the "+12 Felling" floater `age` seconds after the gain.
static func float_alpha(age: float) -> float:
	if age >= FLOAT_SECONDS:
		return 0.0
	var fade_from := FLOAT_SECONDS * 0.5
	return 1.0 if age <= fade_from else 1.0 - (age - fade_from) / (FLOAT_SECONDS - fade_from)


## Alpha of the bar and its label `age` seconds after the last gain.
static func bar_alpha(age: float) -> float:
	if age <= HOLD_SECONDS:
		return 1.0
	return clampf(1.0 - (age - HOLD_SECONDS) / FADE_SECONDS, 0.0, 1.0)


func setup(theme: Theme) -> void:
	self.theme = theme
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(WIDTH, HEIGHT)
	gain_label = _make_label(14, GOLD)
	gain_label.position = Vector2(0, 0)
	level_label = _make_label(12, LABEL)
	level_label.position = Vector2(0, 20)
	bar = ProgressBar.new()
	bar.show_percentage = false
	bar.min_value = 0.0
	bar.max_value = 1.0
	bar.step = 0.0 # smooth slide; the default 0.01 steps would snap it
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.position = Vector2((WIDTH - BAR_W) * 0.5, 39)
	bar.size = Vector2(BAR_W, BAR_H)
	var fill := StyleBoxFlat.new()
	fill.bg_color = GOLD
	fill.set_corner_radius_all(2)
	bar.add_theme_stylebox_override("fill", fill)
	var bg := StyleBoxFlat.new()
	bg.bg_color = HudStyle.TRACK
	bg.set_corner_radius_all(2)
	bar.add_theme_stylebox_override("background", bg)
	add_child(bar)
	_apply_alpha()


func _make_label(font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.size = Vector2(WIDTH, 20)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	HudStyle.quiet_label(l, font_size, color)
	add_child(l)
	return l


## s2c_skills (login): every skill's total XP. Nothing shows; the next gain starts from here.
func on_skills(all: Dictionary) -> void:
	skills = Skills.normalize(all)


## s2c_xp: show "+gained Skill" and slide that skill's bar to `total`. Returns the motion
## ({from, to, levels}) for tests and bots.
func on_gain(skill: String, gained: int, total: int) -> Dictionary:
	var before := int(skills[skill]) if skills.has(skill) else -1
	var m := gain_motion(before, gained, total)
	skills[skill] = total
	_skill = skill
	_from = float(m.from)
	_to = float(m.to)
	_levels = int(m.levels)
	_age = 0.0
	gain_label.text = gain_text(skill, gained)
	level_label.text = level_text(skill, total)
	_apply_alpha()
	return m


## Every frame while playing.
func step(delta: float) -> void:
	if _age == INF:
		return
	_age += delta
	_apply_alpha()


func _apply_alpha() -> void:
	if gain_label == null:
		return
	gain_label.modulate.a = float_alpha(_age)
	gain_label.position.y = -FLOAT_RISE * clampf(_age / FLOAT_SECONDS, 0.0, 1.0)
	var a := bar_alpha(_age)
	level_label.modulate.a = a
	bar.modulate.a = a
	bar.value = bar_value(_from, _to, _levels, _age) if _age != INF else 0.0
	bar.self_modulate = FULL_GLOW if holding_full(_levels, _age) else Color.WHITE


## Is anything on screen right now?
func showing() -> bool:
	return _age != INF and bar_alpha(_age) > 0.0


## Has the last gain's bar come to rest (slide, and any level-up hold, done)?
func settled() -> bool:
	return _age == INF or _age >= settle_seconds(_levels)


## Levels the last gain crossed (0 within a level).
func levels_crossed() -> int:
	return _levels


func current_skill() -> String:
	return _skill


func hide_all() -> void:
	skills = {}
	_skill = ""
	_age = INF
	_apply_alpha()
