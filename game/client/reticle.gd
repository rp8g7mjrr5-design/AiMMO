class_name Reticle
extends Control
## The small centre reticle for the action camera: a thin ring with a dot, drawn in code in the
## ember palette. It brightens when the thing in front of you can be gathered (look-to-interact).

const RADIUS := 7.0
const DOT := 1.6
const IDLE := Color(1.0, 0.95, 0.88, 0.55)
const ACTIVE := Color(HudStyle.EMBER, 0.95) ## the one accent, as the gather prompt
const OUTLINE := Color(0, 0, 0, 0.35)

var active := false:
	set(v):
		if v != active:
			active = v
			queue_redraw()


func setup() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_CENTER)
	custom_minimum_size = Vector2(RADIUS * 2.0 + 4.0, RADIUS * 2.0 + 4.0)
	offset_left = -RADIUS - 2.0
	offset_top = -RADIUS - 2.0
	offset_right = RADIUS + 2.0
	offset_bottom = RADIUS + 2.0


## The colour the reticle draws in.
static func color_for(is_active: bool) -> Color:
	return ACTIVE if is_active else IDLE


func _draw() -> void:
	var c := size * 0.5
	var col := color_for(active)
	var r := RADIUS * (1.15 if active else 1.0)
	draw_arc(c, r, 0.0, TAU, 32, OUTLINE, 3.0, true)
	draw_arc(c, r, 0.0, TAU, 32, col, 1.4, true)
	draw_circle(c, DOT + 0.8, OUTLINE)
	draw_circle(c, DOT, col)
