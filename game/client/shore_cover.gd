class_name ShoreCover
extends CanvasLayer
## "Washing ashore": a plain dark screen over the few seconds the client builds a big world
## (an island server's s2c_world, about 6 s for 3 km), so joining never looks like a freeze or
## a crash. Drawn once before the build starts (RenderingServer.force_draw: the build holds the
## main thread), then fades out over the first moments on the new ground.
## Grounded and quiet (art bible 0, 11): no spinner, no tip text, one line in the HUD's colours.

const TEXT := "Washing ashore"
const FADE := 0.6 ## seconds to fade out once the world is built

var _bg: ColorRect
var _label: Label
var _fading := 0.0


func _init() -> void:
	layer = 50
	name = "ShoreCover"
	_bg = ColorRect.new()
	_bg.color = Color(0.06, 0.07, 0.08) # the sea at night, nearly black
	_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_bg)
	_label = HudStyle.quiet_label(Label.new(), 22, HudStyle.TEXT_DIM)
	_label.text = TEXT
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg.add_child(_label)
	visible = false


## Shows the cover and draws one frame now, before a long build on the main thread.
func show_now() -> void:
	_fading = 0.0
	_bg.modulate.a = 1.0
	visible = true
	if DisplayServer.get_name() != "headless":
		RenderingServer.force_draw(true, 0.0)


## Starts the fade out.
func done() -> void:
	if visible:
		_fading = FADE


func _process(delta: float) -> void:
	if _fading <= 0.0:
		return
	_fading = maxf(0.0, _fading - delta)
	_bg.modulate.a = _fading / FADE
	if _fading <= 0.0:
		visible = false


func is_covering() -> bool:
	return visible
