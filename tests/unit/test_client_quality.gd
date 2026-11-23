extends TestCase
## Graphics quality (Low/Medium/High): presets, how Settings applies them, the saved value,
## and the F3 overlay's text.


func test_medium_is_default_and_matches_todays_look() -> void:
	var s := ClientSettings.from_config(ConfigFile.new())
	check_eq(s.graphics_quality, Quality.MEDIUM, "new installs get Medium (art bible)")
	var p := Quality.preset(Quality.MEDIUM)
	check_eq(int(p.shadow_quality), s.shadow_quality, "Medium's shadows are the default shadows")
	check_near(float(p.draw_distance), s.draw_distance, 0.0001, "Medium's view distance is the default")
	check_near(Quality.flora_density(Quality.MEDIUM), 1.0, 0.0001, "Medium draws all flora")


func test_presets_scale_up() -> void:
	var lo := Quality.preset(Quality.LOW)
	var md := Quality.preset(Quality.MEDIUM)
	var hi := Quality.preset(Quality.HIGH)
	check(float(lo.draw_distance) < float(md.draw_distance), "Low sees less far")
	check(float(md.draw_distance) <= float(hi.draw_distance), "High sees at least as far")
	check(int(lo.shadow_quality) > 0, "the look holds on Low: the sun still casts shadows")
	check(int(hi.shadow_quality) > int(md.shadow_quality), "High has the longer shadows")
	check(int(lo.shadow_atlas) < int(md.shadow_atlas), "Low uses a smaller shadow map")
	check(Quality.flora_density(Quality.LOW) < Quality.flora_density(Quality.MEDIUM), "Low thins flora")
	check(Quality.motes_scale(Quality.LOW) < Quality.motes_scale(Quality.HIGH), "motes scale with quality")
	for p in Quality.PRESETS:
		check(float(p.draw_distance) >= ClientSettings.DRAW_MIN and float(p.draw_distance) <= ClientSettings.DRAW_MAX, "preset distance is a legal setting")
		check(ClientSettings.SHADOW_NAMES.size() > int(p.shadow_quality), "preset shadows are a legal setting")
	check_near(float(hi.draw_distance) * 0.006, 3.6, 0.01, "600 m is where the 0.006 haze is ~97% solid")


func test_apply_quality_sets_shadows_and_distance() -> void:
	var s := ClientSettings.new()
	s.apply_quality(Quality.LOW)
	check_eq(s.graphics_quality, Quality.LOW)
	check_eq(s.shadow_quality, 1)
	check_near(s.draw_distance, 400.0, 0.0001, "Low is 400 m")
	s.apply_quality(Quality.HIGH)
	check_eq(s.shadow_quality, 2)
	check_near(s.shadow_distance(), 120.0, 0.0001, "High is 120 m shadows")
	check_near(s.draw_distance, 600.0, 0.0001)
	s.apply_quality(9)
	check_eq(s.graphics_quality, Quality.HIGH, "out of range clamps")


func test_saved_and_old_files() -> void:
	var path := "user://test_client_quality.cfg"
	var s := ClientSettings.new()
	s.apply_quality(Quality.LOW)
	s.draw_distance = 350.0 # fine-tuned after picking Low
	check_eq(s.save_to(path), OK)
	var t := ClientSettings.load_from(path)
	check_eq(t.graphics_quality, Quality.LOW, "the level is saved")
	check_near(t.draw_distance, 350.0, 0.0001, "loading doesn't re-apply the preset over a tweak")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	# A file from before this setting: no key, own values kept.
	var cfg := ConfigFile.new()
	cfg.set_value("settings", "shadow_quality", 2)
	cfg.set_value("settings", "draw_distance", 250.0)
	var old := ClientSettings.from_config(cfg)
	check_eq(old.graphics_quality, Quality.MEDIUM, "old files read as Medium")
	check_eq(old.shadow_quality, 2, "old shadows kept")
	check_near(old.draw_distance, 250.0, 0.0001, "old distance kept")
	var bad := ConfigFile.new()
	bad.set_value("settings", "graphics_quality", "ultra")
	check_eq(ClientSettings.from_config(bad).graphics_quality, Quality.MEDIUM, "garbage falls back")
	bad.set_value("settings", "graphics_quality", -3)
	check_eq(ClientSettings.from_config(bad).graphics_quality, Quality.LOW, "negative clamps")


func test_saved_level_is_in_force_before_the_world_builds() -> void:
	# qa's request: a saved Low must thin flora when the world is first built, not only after a
	# Settings change. Quality.use is what client.start() calls before WorldBuilder.build().
	Quality.use(Quality.LOW)
	check_eq(Quality.level, Quality.LOW)
	check_near(Flora.quality_density(), Quality.flora_density(Quality.LOW), 0.0001, "flora reads the saved level")
	var flora := Flora.build()
	check_near(float(flora.get_meta("density", -1.0)), Quality.flora_density(Quality.LOW), 0.0001, "the first build is already thinned")
	flora.free()
	Quality.use(99)
	check_eq(Quality.level, Quality.HIGH, "out of range clamps")
	Quality.use(Quality.MEDIUM) # the rest of the suite runs on Medium
	check_eq(Quality.level, Quality.MEDIUM)
	# client.gd puts the saved level in force before it builds the world.
	var src := FileAccess.get_file_as_string("res://client/client.gd")
	var use_at := src.find("Quality.use(settings.graphics_quality)")
	var build_at := src.find("WorldBuilder.build()")
	check(use_at > 0 and build_at > 0 and use_at < build_at, "Quality.use runs before WorldBuilder.build() in start()")


func test_level_names() -> void:
	check_eq(Quality.level_name(Quality.LOW), "Low")
	check_eq(Quality.level_name(Quality.HIGH), "High")
	check_eq(Quality.level_name(42), "High")
	check_eq(Quality.level, Quality.MEDIUM, "headless runs stay on Medium")


func test_perf_text() -> void:
	check_eq(PerfOverlay.count_text(850), "850")
	check_eq(PerfOverlay.count_text(12340), "12.3k")
	check_eq(PerfOverlay.count_text(1998157), "2.00M")
	var t := PerfOverlay.text_for(60, 16.66, 212, 1200000, "Medium")
	check_eq(t, "60 fps · 16.7 ms\n212 draws · 1.20M tris\nGraphics: Medium")


func test_perf_overlay_refreshes_only_when_visible() -> void:
	var o := PerfOverlay.new()
	o.setup(Theme.new())
	check(not o.step(1.0), "hidden: no work")
	o.toggle()
	check(o.visible, "F3 shows it")
	check(o.mouse_filter == Control.MOUSE_FILTER_IGNORE, "never eats clicks")
	var redrew := false
	for i in 20:
		redrew = o.step(1.0 / 60.0) or redrew
	check(redrew, "redraws within a quarter second")
	check(o.text().begins_with("60 fps") or o.text().begins_with("59 fps") or o.text().begins_with("61 fps"), "fps from the frames it saw: %s" % o.text())
	check(o.text().contains("Graphics: Medium"), "names the level")
	o.toggle()
	check(not o.visible, "F3 again hides it")
	o.free()


func test_f3_is_listed() -> void:
	check(ControlsOverlay.DEFAULT_BINDS.has("toggle_perf"), "F3 has a default key")
	check(ControlsOverlay.listed_actions().has("toggle_perf"), "F3 is in the F1 list")
