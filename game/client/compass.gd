class_name CompassStrip
extends Control
## A compass strip across the top of the screen. It turns with the camera and shows:
## - the cardinal letters N, E, S, W (with small ticks every 15 degrees),
## - a dot for every other player you can see on the strip, fading with distance,
## - a chevron pinned to the strip's edge for players outside its view, so you know
##   which way to turn to find them,
## - an ember diamond for the Spawn Meadow, so new players can always find their way home.
##
## North is -Z (Godot's forward), east is +X. Headings are radians clockwise from north.
## All the maths is in static functions so it can be unit-tested headless.

const WIDTH := 480.0 ## px
const HEIGHT := 30.0 ## px
const HALF_SPAN := PI / 2.0 ## the strip shows 90 degrees either side of where you look
const NEAR_DISTANCE := 40.0 ## m; players this close are drawn fully opaque
const FAR_DISTANCE := 200.0 ## m; players at or beyond this are drawn at FAR_ALPHA
const FAR_ALPHA := 0.35
const HOME := Vector3.ZERO ## the Spawn Meadow's centre
const HOME_HIDE_DISTANCE := 12.0 ## m; standing in the meadow, the home marker would just flicker
const EDGE_FADE := 28.0 ## px over which letters and ticks fade at the strip's ends
const UPDATE_INTERVAL := 0.05 ## s between redraws (20 Hz is plenty for a strip)

const CARDINALS := [["N", 0.0], ["E", PI / 2.0], ["S", PI], ["W", PI * 1.5]]
const BG_COLOR := Color(0, 0, 0, 0.45)
const TICK_COLOR := Color(1, 1, 1, 0.45)
const LETTER_COLOR := Color(1, 1, 1, 0.9)
const NORTH_COLOR := Color(1.0, 0.62, 0.38) ## ember orange, so north stands out
const PLAYER_COLOR := Color(0.98, 0.95, 0.86)
const HOME_COLOR := Color(1.0, 0.5, 0.25)

var font: Font
## Set by the client each frame.
var cam_yaw := 0.0
var me := Vector3.ZERO
var others: Array = [] ## Array of Vector3, every other player's rendered position
var _timer := 0.0
var _marks: Array = []
var _home := {}


## The compass heading of a camera with this yaw (the client's cam_yaw: the camera looks
## along (-sin(yaw), 0, -cos(yaw))). 0 = north, PI/2 = east.
static func heading(yaw: float) -> float:
	return fposmod(-yaw, TAU)


## The compass bearing from `from` to `to` on the ground plane.
static func bearing(from: Vector3, to: Vector3) -> float:
	var d := to - from
	return fposmod(atan2(d.x, -d.z), TAU)


## Signed angle from `h` (heading) to `b` (bearing): negative is to your left.
static func relative(h: float, b: float) -> float:
	return wrapf(b - h, -PI, PI)


## Strip x (0..width) for a relative angle, and whether it had to be pinned to an edge.
static func strip_x(rel: float, width: float = WIDTH) -> Array:
	var edge := absf(rel) > HALF_SPAN
	var r := clampf(rel, -HALF_SPAN, HALF_SPAN)
	return [width * 0.5 + r / HALF_SPAN * width * 0.5, edge]


## How opaque a player dot is at this distance.
static func distance_alpha(dist: float) -> float:
	var t := clampf((dist - NEAR_DISTANCE) / (FAR_DISTANCE - NEAR_DISTANCE), 0.0, 1.0)
	return lerpf(1.0, FAR_ALPHA, t)


## One mark per other player: {x, edge, alpha, side, distance}. `side` is -1 (left),
## 0 (on the strip) or 1 (right). Players standing on top of you have no direction and
## are left out.
static func player_marks(yaw: float, my_pos: Vector3, positions: Array, width: float = WIDTH) -> Array:
	var h := heading(yaw)
	var out: Array = []
	for p in positions:
		var pos: Vector3 = p
		var flat := Vector2(pos.x - my_pos.x, pos.z - my_pos.z)
		var dist := flat.length()
		if dist < 0.5:
			continue
		var rel := relative(h, bearing(my_pos, pos))
		var sx: Array = strip_x(rel, width)
		out.append({
			"x": sx[0],
			"edge": sx[1],
			"alpha": distance_alpha(dist),
			"side": (-1 if rel < 0.0 else 1) if sx[1] else 0,
			"distance": dist,
		})
	return out


## Cardinal letters visible on the strip: [{letter, x}].
static func cardinal_marks(yaw: float, width: float = WIDTH) -> Array:
	var h := heading(yaw)
	var out: Array = []
	for c in CARDINALS:
		var rel := relative(h, c[1])
		if absf(rel) <= HALF_SPAN:
			out.append({"letter": c[0], "x": width * 0.5 + rel / HALF_SPAN * width * 0.5})
	return out


## The Spawn Meadow marker: {x, edge, distance}, or {} when you're standing in it.
static func home_mark(yaw: float, my_pos: Vector3, width: float = WIDTH) -> Dictionary:
	var dist := Vector2(HOME.x - my_pos.x, HOME.z - my_pos.z).length()
	if dist < HOME_HIDE_DISTANCE:
		return {}
	var sx: Array = strip_x(relative(heading(yaw), bearing(my_pos, HOME)), width)
	return {"x": sx[0], "edge": sx[1], "distance": dist}


## Letters and ticks fade out over the last EDGE_FADE px of the strip so they slide in
## and out smoothly instead of hanging half off the end.
static func edge_fade(x: float, width: float = WIDTH) -> float:
	return clampf(minf(x, width - x) / EDGE_FADE, 0.0, 1.0)


func setup(theme: Theme) -> void:
	custom_minimum_size = Vector2(WIDTH, HEIGHT)
	size = Vector2(WIDTH, HEIGHT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	font = theme.default_font if theme and theme.default_font else ThemeDB.fallback_font


## Feed the latest camera and positions, then redraw now.
func feed(p_cam_yaw: float, p_me: Vector3, p_others: Array) -> void:
	cam_yaw = p_cam_yaw
	me = p_me
	others = p_others
	_marks = player_marks(cam_yaw, me, others, WIDTH)
	_home = home_mark(cam_yaw, me, WIDTH)
	queue_redraw()


## True when it's time to call feed() again; keeps redraws to UPDATE_INTERVAL.
func due(delta: float) -> bool:
	_timer -= delta
	if _timer > 0.0:
		return false
	_timer = UPDATE_INTERVAL
	return true


func _draw() -> void:
	var w := WIDTH
	var mid := HEIGHT * 0.5
	draw_rect(Rect2(0, 0, w, HEIGHT), BG_COLOR)
	# Ticks every 15 degrees; taller every 45.
	var h := heading(cam_yaw)
	for i in 24:
		var a := i * TAU / 24.0
		var rel := relative(h, a)
		if absf(rel) > HALF_SPAN:
			continue
		var x := w * 0.5 + rel / HALF_SPAN * w * 0.5
		var tall := i % 3 == 0
		draw_line(Vector2(x, HEIGHT - (9.0 if tall else 5.0)), Vector2(x, HEIGHT - 1.0), Color(TICK_COLOR, TICK_COLOR.a * edge_fade(x, w)), 1.0)
	var fs := 14
	for c in cardinal_marks(cam_yaw, w):
		var s: String = c.letter
		var tw := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var lc: Color = NORTH_COLOR if s == "N" else LETTER_COLOR
		draw_string(font, Vector2(c.x - tw * 0.5, mid + 3.0), s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(lc, lc.a * edge_fade(c.x, w)))
	# Home: an ember diamond (a small chevron at the edge when it is behind you).
	if not _home.is_empty():
		var hx: float = _home.x
		if _home.edge:
			_draw_chevron(hx, mid, -1 if hx < w * 0.5 else 1, Color(HOME_COLOR, 0.9))
		else:
			var y := 5.0
			draw_colored_polygon(PackedVector2Array([Vector2(hx, y - 4), Vector2(hx + 4, y), Vector2(hx, y + 4), Vector2(hx - 4, y)]), HOME_COLOR)
	# Players: dots on the strip, chevrons at the edges for those out of view.
	for m in _marks:
		var col := Color(PLAYER_COLOR, m.alpha)
		if m.edge:
			_draw_chevron(m.x, mid, m.side, col)
		else:
			draw_circle(Vector2(m.x, HEIGHT - 6.0), 3.0, Color(0, 0, 0, 0.6 * m.alpha))
			draw_circle(Vector2(m.x, HEIGHT - 6.0), 2.2, col)
	# Where you're looking.
	draw_line(Vector2(w * 0.5, 0), Vector2(w * 0.5, 4), LETTER_COLOR, 2.0)


func _draw_chevron(x: float, y: float, side: int, col: Color) -> void:
	var inset := 6.0
	var cx := x - side * inset
	draw_colored_polygon(PackedVector2Array([
		Vector2(cx + side * 4.0, y),
		Vector2(cx - side * 2.0, y - 5.0),
		Vector2(cx - side * 2.0, y + 5.0),
	]), col)
