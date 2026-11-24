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
	for c in [HudStyle.XP, HudStyle.TEXT, HudStyle.NOTE, HudStyle.OK, HudStyle.SHORT, HudStyle.PANEL, HudStyle.CONTROL]:
		check(HudStyle.saturation(c) < 0.6, "no neon: %s is %.2f saturated" % [c, HudStyle.saturation(c)])
	check(HudStyle.TEXT.v < 0.95, "text is warm parchment, not paper white")
	check(HudStyle.PANEL.a >= 0.7 and HudStyle.PANEL.a <= 0.85, "panels about 70 to 85% opaque")
	check(HudStyle.PANEL.r >= HudStyle.PANEL.b, "panels lean warm, not blue-grey")
	check(HudStyle.XP.s < HudStyle.EMBER.s, "XP is a step calmer than the accent")


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
	check(button.bg_color.r >= button.bg_color.b, "buttons are warm grey, not Godot's blue-grey")
	var panel := t.get_stylebox("panel", "PanelContainer") as StyleBoxFlat
	check(panel != null and panel.bg_color.is_equal_approx(HudStyle.PANEL), "panels are the HUD's warm grey")
	check(panel.border_color.s < 0.4, "the panel edge is faint warm grey, not an ember frame")


func test_hud_pieces_are_quiet() -> void:
	var t := HudStyle.theme()
	var b := LevelUpBanner.new()
	b.setup(t)
	for l in [b.title_label, b.unlock_label, b.next_label]:
		_no_outline(l, "banner")
	check(b.title_label.get_theme_font_size("font_size") < 30, "the banner title is proud, not loud")
	b.free()
	var x := XpMeter.new()
	x.setup(t)
	_no_outline(x.gain_label, "XP floater")
	_no_outline(x.level_label, "XP bar label")
	x.free()
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
