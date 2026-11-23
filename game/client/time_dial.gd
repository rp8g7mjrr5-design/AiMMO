class_name TimeDial
extends Control
## A small sun/moon dial above the chat: a half-sky with the sun (by day) or the moon (by
## night) riding its rim, and a readout like "Day 3 · 14:05 · Dusk". In the last
## SOON_SECONDS of a phase the readout adds what comes next ("· Night soon"), and hovering the
## dial (cursor free: chat open or a window up) shows a tooltip with the exact time and how
## long until the next two phases ("Dusk in about 9 minutes"). That replaces /time.
##
## It reads the time from DayNight, which the client feeds with the server's clock
## (s2c_world_time), so the dial, the sky, and every other player agree on the hour.
## All the maths is in the static `state()` so it can be unit-tested headless.

const RADIUS := 20.0 ## px, the dial disk
const BODY_RADIUS := 5.5 ## px, the sun or moon on the rim
const UPDATE_INTERVAL := 0.5 ## seconds between redraws; one in-game minute is ~1.7 s
const PHASE_NAMES := {"dawn": "Dawn", "day": "Day", "dusk": "Dusk", "night": "Night"}
const SOON_SECONDS := 90.0 ## real seconds before a phase change when the readout warns of it

## Colours: warm sun from the late-afternoon palette, a pale moon, and a sky band per phase.
const SUN_COLOR := Color(1.0, 0.78, 0.38)
const MOON_COLOR := Color(0.86, 0.88, 0.95)
const SKY_COLORS := {
	"dawn": Color(0.93, 0.62, 0.45),
	"day": Color(0.45, 0.65, 0.9),
	"dusk": Color(0.85, 0.45, 0.35),
	"night": Color(0.12, 0.15, 0.3),
}
const GROUND_COLOR := Color(0.16, 0.13, 0.11, 0.9)

var label: Label
var _state := {}
var _timer := 0.0


## Everything the dial shows for a moment in world time.
## angle: radians round the dial, 0 = left horizon (sunrise), PI/2 = top (noon or midnight).
## body: "sun" or "moon", whichever is above the horizon. offset: the body's position from
## the dial centre for a dial of radius 1 (y down, Godot's 2D convention).
static func state(world_seconds: float) -> Dictionary:
	var frac := WorldClock.day_fraction(world_seconds)
	var phase := WorldClock.phase(world_seconds)
	var sun_angle := (frac - 0.25) * TAU # 0 at sunrise, PI/2 at noon, PI at sunset
	var is_sun := WorldClock.sun_elevation(world_seconds) >= 0.0
	var angle := fposmod(sun_angle if is_sun else sun_angle - PI, TAU)
	var h := WorldClock.hour(world_seconds)
	var hh := int(floor(h)) % 24
	var mm := clampi(int(floor((h - floor(h)) * 60.0)), 0, 59)
	return {
		"fraction": frac,
		"phase": phase,
		"body": "sun" if is_sun else "moon",
		"angle": angle,
		"offset": Vector2(-cos(angle), -sin(angle)),
		"day": WorldClock.day_number(world_seconds),
		"text": "Day %d · %02d:%02d · %s" % [WorldClock.day_number(world_seconds), hh, mm, PHASE_NAMES.get(phase, phase)],
		"soon": soon_text(world_seconds),
	}


## The readout's warning in the last SOON_SECONDS of a phase, e.g. "Night soon", else "".
static func soon_text(world_seconds: float) -> String:
	if WorldClock.seconds_until_next_phase(world_seconds) > SOON_SECONDS:
		return ""
	var nxt := WorldClock.next_phase(world_seconds)
	return "%s soon" % PHASE_NAMES.get(nxt, nxt)


## The label under the dial: the readout plus the warning when there is one.
static func label_text(st: Dictionary) -> String:
	var soon: String = st.get("soon", "")
	return st.text if soon.is_empty() else "%s · %s" % [st.text, soon]


## "in less than a minute", "in about a minute", "in about 9 minutes" for real seconds.
static func until_text(seconds: float) -> String:
	if seconds < 60.0:
		return "in less than a minute"
	var m := int(round(seconds / 60.0))
	return "in about a minute" if m <= 1 else "in about %d minutes" % m


## The hover tooltip, e.g.
##   Day 3, 14:05
##   Dusk in about 9 minutes
##   Then night in about 13 minutes
##   A day in Ashgrove lasts 40 minutes
static func tooltip_text_at(world_seconds: float) -> String:
	var h := WorldClock.hour(world_seconds)
	var hh := int(floor(h)) % 24
	var mm := clampi(int(floor((h - floor(h)) * 60.0)), 0, 59)
	var first := WorldClock.seconds_until_next_phase(world_seconds)
	var next1 := WorldClock.next_phase(world_seconds)
	# The phase after that starts when next1 ends; step just past the boundary to read it.
	var at_next := world_seconds + first + 0.01
	var second := first + WorldClock.seconds_until_next_phase(at_next)
	var next2 := WorldClock.next_phase(at_next)
	var lines := PackedStringArray([
		"Day %d, %02d:%02d" % [WorldClock.day_number(world_seconds), hh, mm],
		"%s %s" % [PHASE_NAMES.get(next1, next1), until_text(first)],
		"Then %s %s" % [String(PHASE_NAMES.get(next2, next2)).to_lower(), until_text(second)],
		"A day in Ashgrove lasts %d minutes" % int(round(WorldClock.DAY_SECONDS / 60.0)),
	])
	return "\n".join(lines)


## World seconds the dial should show: the sky's clock, or, when the sky is pinned to a
## time of day (AIMMO_TIME_OF_DAY, screenshots), that time on today's date so the dial and
## the sky always agree.
static func current_seconds() -> float:
	var secs := DayNight.now_world_seconds()
	if DayNight.pinned_fraction < 0.0:
		return secs
	var day_start := (WorldClock.day_number(secs) - 1) * WorldClock.DAY_SECONDS - WorldClock.START_FRACTION * WorldClock.DAY_SECONDS
	return day_start + fposmod(DayNight.pinned_fraction, 1.0) * WorldClock.DAY_SECONDS


func setup(theme: Theme) -> void:
	custom_minimum_size = Vector2(RADIUS * 2.0 + 8.0, RADIUS + 10.0)
	# PASS so the hover tooltip shows when the cursor is free; _has_point keeps the hover
	# area to the disk and the readout, not the whole strip above the chat.
	mouse_filter = Control.MOUSE_FILTER_PASS
	tooltip_text = "time" # any text: the real one comes from _get_tooltip when it opens
	label = Label.new()
	label.theme = theme
	label.position = Vector2(RADIUS * 2.0 + 14.0, RADIUS - 14.0)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	label.add_theme_constant_override("outline_size", 6)
	add_child(label)
	refresh()


func refresh() -> void:
	_state = state(current_seconds())
	label.text = label_text(_state)
	queue_redraw()


func _get_tooltip(_at_position: Vector2) -> String:
	return tooltip_text_at(current_seconds())


## Only the dial disk and the readout answer the mouse.
func _has_point(point: Vector2) -> bool:
	if Rect2(Vector2.ZERO, Vector2(RADIUS * 2.0 + 8.0, RADIUS * 2.0 + 8.0)).has_point(point):
		return true
	return label != null and Rect2(label.position, label.size).has_point(point)


## The tooltip as a dark panel with the HUD's outlined text, not the engine's grey box.
func _make_custom_tooltip(for_text: String) -> Object:
	var panel := PanelContainer.new()
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.06, 0.05, 0.05, 0.88)
	box.border_color = Color(SKY_COLORS.get(_state.get("phase", "day"), SKY_COLORS.day), 0.9)
	box.set_border_width_all(1)
	box.set_corner_radius_all(4)
	box.set_content_margin_all(8)
	panel.add_theme_stylebox_override("panel", box)
	var text := Label.new()
	text.text = for_text
	if label:
		text.theme = label.theme
	text.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	text.add_theme_constant_override("outline_size", 4)
	panel.add_child(text)
	return panel


func _process(delta: float) -> void:
	if not visible:
		return
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = UPDATE_INTERVAL
	refresh()


func _draw() -> void:
	if _state.is_empty():
		return
	var c := Vector2(RADIUS + 4.0, RADIUS + 4.0)
	var sky: Color = SKY_COLORS.get(_state.phase, SKY_COLORS.day)
	# Upper half: the sky in this phase's colour. Lower half: dark ground below the horizon.
	draw_circle(c, RADIUS + 2.0, Color(0, 0, 0, 0.55))
	draw_arc(c, RADIUS * 0.5, PI, TAU, 24, sky, RADIUS, true)
	draw_arc(c, RADIUS * 0.5, 0.0, PI, 24, GROUND_COLOR, RADIUS, true)
	draw_line(c - Vector2(RADIUS, 0), c + Vector2(RADIUS, 0), Color(1, 1, 1, 0.35), 1.0, true)
	var p: Vector2 = c + _state.offset * (RADIUS - BODY_RADIUS - 1.0)
	if _state.body == "sun":
		draw_circle(p, BODY_RADIUS + 2.0, Color(SUN_COLOR, 0.3))
		draw_circle(p, BODY_RADIUS, SUN_COLOR)
	else:
		# A crescent: the pale disk with a sky-coloured bite out of one side.
		draw_circle(p, BODY_RADIUS, MOON_COLOR)
		draw_circle(p + Vector2(BODY_RADIUS * 0.55, -BODY_RADIUS * 0.25), BODY_RADIUS * 0.85, sky)
