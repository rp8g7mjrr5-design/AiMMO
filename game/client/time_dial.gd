class_name TimeDial
extends Control
## A small sun/moon dial above the chat: a half-sky with the sun (by day) or the moon (by
## night) riding its rim, and a readout like "Day 3 · 14:05 · Dusk".
##
## It reads the time from DayNight, which the client feeds with the server's clock
## (s2c_world_time), so the dial, the sky, and every other player agree on the hour.
## All the maths is in the static `state()` so it can be unit-tested headless.

const RADIUS := 20.0 ## px, the dial disk
const BODY_RADIUS := 5.5 ## px, the sun or moon on the rim
const UPDATE_INTERVAL := 0.5 ## seconds between redraws; one in-game minute is ~1.7 s
const PHASE_NAMES := {"dawn": "Dawn", "day": "Day", "dusk": "Dusk", "night": "Night"}

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
	}


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
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	label = Label.new()
	label.theme = theme
	label.position = Vector2(RADIUS * 2.0 + 14.0, RADIUS - 14.0)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	label.add_theme_constant_override("outline_size", 6)
	add_child(label)
	refresh()


func refresh() -> void:
	_state = state(current_seconds())
	label.text = _state.text
	queue_redraw()


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
