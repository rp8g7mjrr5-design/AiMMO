class_name PerfOverlay
extends PanelContainer
## The F3 overlay: frames per second, frame time, draw calls and triangles, refreshed four
## times a second, plus the Graphics quality in use, so the owner can see what a scene costs
## while playing (bottom-right corner). It never takes input or the cursor (it isn't a window).

const REFRESH := 0.25 ## seconds between refreshes

var _label: Label
var _t := 0.0
var _frames := 0
var _time := 0.0


func setup(theme_res: Theme) -> void:
	theme = theme_res
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Bottom-right corner: the one corner no HUD piece or the login panel uses.
	anchor_left = 1.0
	anchor_right = 1.0
	anchor_top = 1.0
	anchor_bottom = 1.0
	grow_horizontal = Control.GROW_DIRECTION_BEGIN
	grow_vertical = Control.GROW_DIRECTION_BEGIN
	offset_left = -12
	offset_right = -12
	offset_top = -12
	offset_bottom = -12
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.05, 0.06, 0.09, 0.6)
	bg.set_corner_radius_all(6)
	bg.content_margin_left = 10
	bg.content_margin_right = 10
	bg.content_margin_top = 6
	bg.content_margin_bottom = 6
	add_theme_stylebox_override("panel", bg)
	_label = Label.new()
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.add_theme_font_size_override("font_size", 14)
	_label.text = text_for(0, 0.0, 0, 0, Quality.level_name())
	add_child(_label)


func toggle() -> void:
	visible = not visible
	_t = 0.0
	_frames = 0
	_time = 0.0


## Call every frame; it samples while visible and redraws every REFRESH seconds.
## Returns true when it redrew.
func step(delta: float) -> bool:
	if not visible:
		return false
	_frames += 1
	_time += delta
	_t += delta
	if _t < REFRESH:
		return false
	_t = 0.0
	var fps := roundi(_frames / _time) if _time > 0.0 else 0
	var ms := _time * 1000.0 / maxf(1.0, _frames)
	_frames = 0
	_time = 0.0
	_label.text = text_for(fps, ms,
		int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)),
		Quality.level_name())
	return true


func text() -> String:
	return _label.text


## "60 fps · 16.7 ms" / "212 draws · 1.20M tris" / "Graphics: Medium".
static func text_for(fps: int, frame_ms: float, draws: int, tris: int, quality_name: String) -> String:
	return "%d fps · %.1f ms\n%d draws · %s tris\nGraphics: %s" % [fps, frame_ms, draws, count_text(tris), quality_name]


## 850 -> "850", 12_340 -> "12.3k", 1_998_157 -> "2.00M".
static func count_text(n: int) -> String:
	if n < 1000:
		return str(n)
	if n < 1_000_000:
		return "%.1fk" % (n / 1000.0)
	return "%.2fM" % (n / 1_000_000.0)
