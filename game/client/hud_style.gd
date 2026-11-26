class_name HudStyle
extends RefCounted
## The HUD's one quiet look (owner direction, 2026-11-24: "grounded, not cute"; art bible
## section 9, "UI tone"). The HUD is the frame, not the picture: small calm type with a soft
## shadow instead of a thick black outline, muted warm-grey panels about 80% opaque, and one
## accent, `Palette.EMBER`, used sparingly for what is ready, earned or yours. Every window,
## toast, floater and banner takes its colours and its label look from here, so the whole HUD
## changes together and nothing drifts back to bold outlined yellow.
##
## Everything is static and unit tested (`tests/unit/test_client_hud_style.gd`): no colour
## here may be neon, and no label may carry the old thick outline.

## The one accent: a title, a ready button, a progress fill, your own row. Never decoration.
const EMBER := Palette.EMBER
## "You just got this": the accent's hue, a step calmer, so a glow and the haul toast don't
## shout over each other.
const GLOW := Color(0.90, 0.70, 0.40)
## Body text: warm parchment white, never paper white.
const TEXT := Color(0.91, 0.88, 0.82)
const TEXT_DIM := Color(0.91, 0.88, 0.82, 0.62)
## A refusal or a notice: warm and soft, not alarming.
const NOTE := Color(0.93, 0.82, 0.68)
## "You have enough" and "you don't" in a recipe: sage and dull brick, read at a glance
## without traffic-light green and red.
const OK := Color(0.64, 0.76, 0.52)
const SHORT := Color(0.86, 0.50, 0.40)
## Panels: dark warm grey, about 80% opaque, with a faint warm edge (not an ember frame).
const PANEL := Color(0.13, 0.12, 0.11, 0.82)
const PANEL_EDGE := Color(0.62, 0.55, 0.46, 0.30)
## A small control (button, field) on a panel, and its hover and pressed tints.
const CONTROL := Color(0.22, 0.20, 0.18, 0.85)
const CONTROL_HOVER := Color(0.28, 0.25, 0.22, 0.90)
const CONTROL_PRESSED := Color(0.18, 0.16, 0.14, 0.95)
## A bar's empty track.
const TRACK := Color(0.08, 0.07, 0.06, 0.55)
## The soft shadow behind HUD text over the world: enough to read on a noon sky, no outline.
const SHADOW := Color(0.05, 0.04, 0.03, 0.62)
const EDGE_SIZE := 2 ## a thin, soft warm-dark edge (the old outlines were 5 to 8 px of black)
## The shadow stays a plain 1 px offset: a soft `shadow_outline_size` breaks canvas batching
## and cost about 200 draw calls on the HUD in the smoke shots (render budget, art bible 7).
const SHADOW_SIZE := 0
const CORNER := 3
const FONT_SIZE := 16 ## the theme's default body size (windows are laid out for it)


## A label that sits over the world (toast, floater, banner, notice): `font_size`, `colour`,
## a thin soft edge and a 1 px shadow instead of the old thick black outline.
static func quiet_label(l: Label, font_size: int, colour: Color) -> Label:
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", colour)
	l.add_theme_constant_override("outline_size", EDGE_SIZE)
	l.add_theme_color_override("font_outline_color", Color(SHADOW, 0.6))
	l.add_theme_color_override("font_shadow_color", SHADOW)
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 1)
	l.add_theme_constant_override("shadow_outline_size", SHADOW_SIZE)
	return l


## A window's panel: dark warm grey with a faint warm edge.
static func panel(opacity: float = PANEL.a) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(PANEL, opacity)
	s.border_color = PANEL_EDGE
	s.set_border_width_all(1)
	s.set_corner_radius_all(CORNER)
	return s


## A small control's box (buttons, fields, the top-bar buttons).
static func control_box(colour: Color, edge: Color = Color(PANEL_EDGE, 0.0)) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = colour
	s.border_color = edge
	s.set_border_width_all(1 if edge.a > 0.0 else 0)
	s.set_corner_radius_all(CORNER)
	s.content_margin_left = 10
	s.content_margin_right = 10
	s.content_margin_top = 4
	s.content_margin_bottom = 4
	return s


## A thin bar's fill or track.
static func bar_box(colour: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = colour
	s.set_corner_radius_all(2)
	return s


## The HUD's shared theme: warm text, warm-grey buttons, panels and fields in place of
## Godot's default blue-grey, so every window and button reads as one set.
static func theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = FONT_SIZE
	for type in ["Label", "Button", "LineEdit", "CheckBox", "OptionButton", "RichTextLabel"]:
		t.set_color("font_color", type, TEXT)
	t.set_color("default_color", "RichTextLabel", TEXT)
	for type in ["Button", "OptionButton"]:
		t.set_color("font_hover_color", type, Color(1.0, 0.96, 0.90))
		t.set_color("font_pressed_color", type, EMBER)
		t.set_color("font_focus_color", type, TEXT)
		t.set_color("font_disabled_color", type, Color(TEXT, 0.38))
		t.set_stylebox("normal", type, control_box(CONTROL))
		t.set_stylebox("hover", type, control_box(CONTROL_HOVER, PANEL_EDGE))
		t.set_stylebox("pressed", type, control_box(CONTROL_PRESSED, Color(EMBER, 0.55)))
		t.set_stylebox("disabled", type, control_box(Color(CONTROL, 0.4)))
		t.set_stylebox("focus", type, control_box(Color(0, 0, 0, 0), Color(EMBER, 0.45)))
	t.set_stylebox("normal", "LineEdit", control_box(Color(0.08, 0.07, 0.06, 0.7), PANEL_EDGE))
	t.set_stylebox("focus", "LineEdit", control_box(Color(0, 0, 0, 0), Color(EMBER, 0.45)))
	t.set_color("caret_color", "LineEdit", EMBER)
	t.set_color("font_placeholder_color", "LineEdit", Color(TEXT, 0.45))
	t.set_stylebox("panel", "PanelContainer", panel())
	t.set_stylebox("panel", "Panel", panel())
	t.set_stylebox("panel", "TooltipPanel", panel(0.92))
	t.set_color("font_color", "TooltipLabel", TEXT)
	var rule := StyleBoxLine.new()
	rule.color = Color(PANEL_EDGE, 0.5)
	rule.thickness = 1
	t.set_stylebox("separator", "HSeparator", rule)
	t.set_stylebox("background", "ProgressBar", bar_box(TRACK))
	t.set_stylebox("fill", "ProgressBar", bar_box(EMBER))
	return t


## HSV saturation of `c` (0..1): the art bible keeps UI colour calm, and the unit test holds
## every colour here under the neon line.
static func saturation(c: Color) -> float:
	return c.s
