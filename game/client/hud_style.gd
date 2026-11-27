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

## The satchel look (owner pick, 2026-11-27): window titles in brass capitals, and the
## leather's tan thread for button edges, rules and slot rims.
const BRASS := Color(0.84, 0.70, 0.48)
const THREAD := Color(0.62, 0.48, 0.32)
## A window's leather: the pressed-in pocket of a slot, a button's darker hide.
const POCKET := Color(0.05, 0.03, 0.02, 0.45)
const HIDE := Color(0.10, 0.07, 0.05, 0.85)
const HIDE_HOVER := Color(0.16, 0.11, 0.08, 0.90)
const TITLE_SPACING := 3 ## px between title capitals


## A window title: brass capitals, a little spaced and weighted, like letters tooled into
## the flap (`size` is the old title size; capitals read bigger, so they draw 2 px smaller).
static func title(l: Label, size: int) -> Label:
	var f := FontVariation.new()
	f.base_font = ThemeDB.fallback_font
	f.spacing_glyph = TITLE_SPACING
	f.variation_embolden = 0.5
	l.add_theme_font_override("font", f)
	l.text = title_case(l.text)
	l.add_theme_font_size_override("font_size", size - 2)
	l.add_theme_color_override("font_color", BRASS)
	return l


## A title's words as the window shows them (capitals). For titles set after `title()`.
static func title_case(text: String) -> String:
	return text.to_upper()


## A pack slot's resting look: a pocket pressed into the leather. {bg, border, radius}
static func slot_look() -> Dictionary:
	return {"bg": POCKET, "border": Color(THREAD, 0.35), "radius": 4}


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


## A window's panel: stitched dark leather with an iron stud in each corner (UiSkin, one
## generated texture shared by every window). `opacity` is kept for old callers.
static func panel(_opacity: float = PANEL.a) -> StyleBox:
	return UiSkin.panel_box(6.0)


## The plain warm-grey panel (chat and anything that sits over the world all the time).
static func flat_panel(opacity: float = PANEL.a) -> StyleBoxFlat:
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


## The HUD's shared theme: warm text, dark-leather buttons with a tan thread edge, leather
## windows. `over_world` is the theme for the bits that sit on the world all the time (chat,
## top bar, dial): their panels stay the plain warm grey, so the world is never framed in leather.
static func theme(over_world := false) -> Theme:
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
		t.set_stylebox("normal", type, control_box(HIDE, Color(THREAD, 0.55)))
		t.set_stylebox("hover", type, control_box(HIDE_HOVER, Color(EMBER, 0.75)))
		t.set_stylebox("pressed", type, control_box(CONTROL_PRESSED, Color(EMBER, 0.55)))
		t.set_stylebox("disabled", type, control_box(Color(HIDE, 0.4), Color(THREAD, 0.2)))
		t.set_stylebox("focus", type, control_box(Color(0, 0, 0, 0), Color(EMBER, 0.45)))
	# A check box is its tick alone, never a button box around it.
	for st in ["normal", "hover", "pressed", "disabled", "focus", "hover_pressed"]:
		t.set_stylebox(st, "CheckBox", StyleBoxEmpty.new())
	var slider := bar_box(Color(0.04, 0.03, 0.02, 0.7))
	slider.content_margin_top = 3
	slider.content_margin_bottom = 3
	t.set_stylebox("slider", "HSlider", slider)
	t.set_stylebox("grabber_area", "HSlider", bar_box(EMBER))
	t.set_stylebox("grabber_area_highlight", "HSlider", bar_box(EMBER))
	t.set_stylebox("normal", "LineEdit", control_box(Color(0.06, 0.04, 0.03, 0.75), Color(THREAD, 0.45)))
	t.set_stylebox("focus", "LineEdit", control_box(Color(0, 0, 0, 0), Color(EMBER, 0.45)))
	t.set_color("caret_color", "LineEdit", EMBER)
	t.set_color("font_placeholder_color", "LineEdit", Color(TEXT, 0.45))
	var box := flat_panel() if over_world else panel()
	t.set_stylebox("panel", "PanelContainer", box)
	t.set_stylebox("panel", "Panel", box)
	var tip := flat_panel(0.94)
	tip.border_color = Color(THREAD, 0.6)
	tip.set_content_margin_all(8)
	t.set_stylebox("panel", "TooltipPanel", tip)
	t.set_stylebox("panel", "PopupMenu", tip)
	t.set_color("font_color", "TooltipLabel", TEXT)
	var rule := StyleBoxLine.new()
	rule.color = Color(THREAD, 0.4)
	rule.thickness = 1
	t.set_stylebox("separator", "HSeparator", rule)
	t.set_stylebox("background", "ProgressBar", bar_box(TRACK))
	t.set_stylebox("fill", "ProgressBar", bar_box(EMBER))
	return t


## HSV saturation of `c` (0..1): the art bible keeps UI colour calm, and the unit test holds
## every colour here under the neon line.
static func saturation(c: Color) -> float:
	return c.s
