class_name NeedsIcon
extends Control
## Hunger on screen (protocol v12 `s2c_needs`, Needs; the owner's survival plan, 2026-11-27):
## one small food mark left of the health bar that shows **only when it matters** (art bible
## section 9, "quiet by default"):
## - fine (Needs.LOW_AT or more): nothing on screen;
## - low: the cooked-meat icon, muted, with a thin straw fill under it showing how fed you are;
## - bad: the same in SMOULDER red, slowly pulsing, so "eat now" is felt without words.
## The key hint (F) sits under it the first time it shows each login and fades.
##
## Pure static helpers (tier, alpha, tint) are unit tested; the node only draws.

const SIZE := 32.0
const BAR_H := 3.0
const PULSE_PERIOD := 1.4
const FADE_IN := 0.35
const HINT_SECONDS := 6.0
const LOW_TINT := Color(0.86, 0.80, 0.68) ## pale straw: noticed, not alarming
const BAD_TINT := Color(0.88, 0.42, 0.30) ## SMOULDER, lifted a little so it reads on the dark HUD
const FILL := Color(0.72, 0.62, 0.40) ## straw
const FILL_BAD := Color(0.71, 0.26, 0.16)

var hunger := 100
var known := false
var _shown_for := 0.0
var _t := 0.0
var _hinted := false
var icon: TextureRect
var track: Panel
var fill: Panel
var hint: Label


## Which tier a 0..100 hunger is in, the same lines as the server's Needs.tier.
static func tier_of(value: int) -> String:
	return Needs.tier(float(value))


## Whether the mark is on screen at all.
static func visible_for(value: int) -> bool:
	return tier_of(value) != "fine"


## The icon's colour at `t` seconds: straw when low, a slow SMOULDER pulse when starving.
static func tint(value: int, t: float) -> Color:
	match tier_of(value):
		"low":
			return LOW_TINT
		"bad":
			var k := 0.5 + 0.5 * sin(TAU * t / PULSE_PERIOD)
			return BAD_TINT.lerp(BAD_TINT.lightened(0.25), k)
	return Color(1, 1, 1, 0)


func setup(p_theme: Theme) -> void:
	theme = p_theme
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(SIZE, SIZE + BAR_H + 3.0)
	icon = TextureRect.new()
	icon.texture = ItemIcons.texture("cooked_meat")
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.size = Vector2(SIZE, SIZE)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(icon)
	track = _panel(HudStyle.TRACK, Vector2(2, SIZE + 1.0), Vector2(SIZE - 4.0, BAR_H))
	fill = _panel(FILL, Vector2(2, SIZE + 1.0), Vector2(SIZE - 4.0, BAR_H))
	hint = Label.new()
	hint.position = Vector2(-6, -17.0) # above the mark: the bottom edge is close
	hint.size = Vector2(SIZE + 12.0, 16)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	HudStyle.quiet_label(hint, 11, HudStyle.TEXT)
	add_child(hint)
	_draw_mark()


func _panel(color: Color, pos: Vector2, sz: Vector2) -> Panel:
	var p := Panel.new()
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(1)
	p.add_theme_stylebox_override("panel", box)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.position = pos
	p.size = sz
	add_child(p)
	return p


## s2c_needs: {"hunger": 0..100}; other keys are later needs and are ignored here.
func on_needs(needs: Dictionary) -> void:
	if not needs.has("hunger"):
		return
	var was_visible := known and visible_for(hunger)
	hunger = clampi(int(needs.hunger), 0, 100)
	known = true
	if visible_for(hunger) and not was_visible:
		_shown_for = 0.0
	_draw_mark()


func step(delta: float) -> void:
	_t += delta
	_shown_for += delta
	_draw_mark()


## Is the mark on screen right now?
func showing() -> bool:
	return known and visible_for(hunger)


func hide_all() -> void:
	known = false
	hunger = 100
	_hinted = false
	_draw_mark()


## An action's first key, read live from the InputMap so a rebound key shows its new name.
static func key_name(action: String, fallback: String) -> String:
	if not InputMap.has_action(action):
		return fallback
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey:
			var k := ev as InputEventKey
			return OS.get_keycode_string(k.keycode if k.keycode != 0 else k.physical_keycode)
	return fallback


static func eat_key() -> String:
	return key_name("eat", "F")


func _draw_mark() -> void:
	if icon == null:
		return
	var on := showing()
	modulate.a = clampf(_shown_for / FADE_IN, 0.0, 1.0) if on else 0.0
	if not on:
		return
	icon.self_modulate = tint(hunger, _t)
	var w := track.size.x
	fill.size.x = w * clampf(float(hunger) / 100.0, 0.0, 1.0)
	var box := fill.get_theme_stylebox("panel") as StyleBoxFlat
	if box != null:
		box.bg_color = FILL_BAD if tier_of(hunger) == "bad" else FILL
	if not _hinted and _shown_for < HINT_SECONDS:
		hint.text = "[%s] Eat" % eat_key()
		hint.modulate.a = clampf((HINT_SECONDS - _shown_for) / 1.0, 0.0, 1.0)
	else:
		if _shown_for >= HINT_SECONDS:
			_hinted = true
		hint.text = ""
