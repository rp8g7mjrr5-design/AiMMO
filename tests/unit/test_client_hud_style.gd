extends TestCase
## The quiet HUD (owner direction 2026-11-24, art bible section 9): one ember accent, calm
## warm colours, soft-shadowed type with no thick black outline, warm-grey panels, and every
## HUD piece that sits over the world built that way.


func _no_outline(l: Label, what: String) -> void:
	check(l.get_theme_constant("outline_size") <= 2, "%s: no thick outline" % what)
	check(l.get_theme_color("font_outline_color").a <= 0.65, "%s: the edge is soft, not black" % what)
	check_eq(l.get_theme_constant("shadow_outline_size"), 0, "%s: no blurred shadow (it breaks batching: +200 draw calls)" % what)
	check(l.get_theme_font_size("font_size") <= 24, "%s: calm type (%d px)" % [what, l.get_theme_font_size("font_size")])


func test_one_calm_accent() -> void:
	check(HudStyle.EMBER.is_equal_approx(Palette.EMBER), "the accent is the palette's ember")
	for c in [HudStyle.GLOW, HudStyle.TEXT, HudStyle.NOTE, HudStyle.OK, HudStyle.SHORT, HudStyle.PANEL, HudStyle.CONTROL]:
		check(HudStyle.saturation(c) < 0.6, "no neon: %s is %.2f saturated" % [c, HudStyle.saturation(c)])
	check(HudStyle.TEXT.v < 0.95, "text is warm parchment, not paper white")
	check(HudStyle.PANEL.a >= 0.7 and HudStyle.PANEL.a <= 0.85, "panels about 70 to 85% opaque")
	check(HudStyle.PANEL.r >= HudStyle.PANEL.b, "panels lean warm, not blue-grey")
	check(HudStyle.GLOW.s < HudStyle.EMBER.s, "the glow is a step calmer than the accent")


func test_quiet_label() -> void:
	var l := HudStyle.quiet_label(Label.new(), 15, HudStyle.TEXT)
	_no_outline(l, "quiet_label")
	check_eq(l.get_theme_color("font_color"), HudStyle.TEXT)
	check(l.get_theme_color("font_shadow_color").a > 0.4, "the shadow still lets it read on a noon sky")
	l.free()


func test_theme_is_warm() -> void:
	var t := HudStyle.theme()
	var button := t.get_stylebox("normal", "Button") as StyleBoxFlat
	check(button != null, "buttons have our own box")
	check(button.bg_color.r >= button.bg_color.b, "buttons are dark leather, not Godot's blue-grey")
	check(button.border_color.s < 0.6, "the button edge is tan thread, not neon")
	var panel := t.get_stylebox("panel", "PanelContainer") as StyleBoxTexture
	check(panel != null and panel.texture == UiSkin.panel_texture(), "windows are the shared satchel leather")
	var world := HudStyle.theme(true).get_stylebox("panel", "PanelContainer") as StyleBoxFlat
	check(world != null and world.bg_color.is_equal_approx(HudStyle.PANEL), "panels over the world stay the quiet warm grey")
	check(world.border_color.s < 0.4, "the over-world edge is faint warm grey, not an ember frame")
	check(t.get_stylebox("normal", "CheckBox") is StyleBoxEmpty, "a check box is its tick, with no button box round it")


func test_satchel_titles() -> void:
	var l := Label.new()
	l.text = "Pack"
	HudStyle.title(l, 21)
	check_eq(l.text, "PACK", "titles are capitals, tooled into the flap")
	check(l.get_theme_color("font_color").is_equal_approx(HudStyle.BRASS), "titles are brass")
	check(HudStyle.saturation(HudStyle.BRASS) < 0.45, "brass is a muted natural, not gold leaf")
	check(l.get_theme_font_size("font_size") <= 24, "calm type")
	check_eq(HudStyle.title_case("Make your traveller"), "MAKE YOUR TRAVELLER")
	l.free()


func test_slot_is_a_pocket() -> void:
	var look := HudStyle.slot_look()
	check((look.bg as Color).v < 0.15, "a slot is a dark pocket pressed into the leather")
	check(HudStyle.saturation(look.border) < 0.6, "its rim is the calm thread colour")


func test_hud_pieces_are_quiet() -> void:
	var t := HudStyle.theme()
	var g := GatherPrompt.new()
	g.setup(t)
	_no_outline(g.toast_label, "haul toast")
	_no_outline(g.prompt_label, "gather prompt")
	check(g.toast_label.get_theme_font_size("font_size") <= 16, "the toast is small")
	g.free()
	var n := NoticeLine.new()
	n.setup(t)
	_no_outline(n.headline_label, "notice")
	n.free()
