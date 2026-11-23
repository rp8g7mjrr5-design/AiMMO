extends TestCase
## Client settings: defaults, clamping, round trip to disk, and the look maths.

const ClientScript := preload("res://client/client.gd")


func test_defaults() -> void:
	var s := ClientSettings.from_config(ConfigFile.new())
	check_near(s.mouse_sensitivity, 1.0, 0.0001, "sensitivity")
	check_eq(s.invert_y, false)
	check_near(s.master_volume, 0.8, 0.0001, "volume")
	check_eq(s.shadow_quality, 1, "new installs get 60 m sun shadows (art bible Medium)")
	check_near(s.draw_distance, 600.0, 0.0001, "draw distance")


func test_round_trip() -> void:
	var path := "user://test_client_settings.cfg"
	var s := ClientSettings.new()
	s.mouse_sensitivity = 1.75
	s.invert_y = true
	s.master_volume = 0.3
	s.shadow_quality = 1
	s.draw_distance = 250.0
	check_eq(s.save_to(path), OK)
	var t := ClientSettings.load_from(path)
	check_near(t.mouse_sensitivity, 1.75, 0.0001, "sensitivity")
	check_eq(t.invert_y, true)
	check_near(t.master_volume, 0.3, 0.0001, "volume")
	check_eq(t.shadow_quality, 1)
	check_near(t.draw_distance, 250.0, 0.0001, "draw distance")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func test_saved_high_shadows_are_kept() -> void:
	# Players who already chose High (the old default, saved) keep it after the default moved.
	var cfg := ConfigFile.new()
	cfg.set_value("settings", "shadow_quality", 2)
	var s := ClientSettings.from_config(cfg)
	check_eq(s.shadow_quality, 2, "saved High stays High")
	check_near(s.shadow_distance(), 120.0, 0.0001, "High is 120 m")


func test_missing_file_gives_defaults() -> void:
	var s := ClientSettings.load_from("user://does_not_exist_settings.cfg")
	check_near(s.mouse_sensitivity, 1.0, 0.0001, "sensitivity")


func test_garbage_is_clamped() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("settings", "mouse_sensitivity", 99.0)
	cfg.set_value("settings", "invert_y", "yes please")
	cfg.set_value("settings", "master_volume", -4)
	cfg.set_value("settings", "shadow_quality", 7)
	cfg.set_value("settings", "draw_distance", "far")
	var s := ClientSettings.from_config(cfg)
	check_near(s.mouse_sensitivity, ClientSettings.SENS_MAX, 0.0001, "sensitivity clamps high")
	check_eq(s.invert_y, false, "non-bool invert falls back to off")
	check_near(s.master_volume, 0.0, 0.0001, "volume clamps low")
	check_eq(s.shadow_quality, 2, "shadow quality clamps")
	check_near(s.draw_distance, 600.0, 0.0001, "non-number falls back to default")
	cfg.set_value("settings", "draw_distance", INF)
	check_near(ClientSettings.from_config(cfg).draw_distance, 600.0, 0.0001, "inf falls back")


func test_shadow_distance_and_volume() -> void:
	var s := ClientSettings.new()
	s.shadow_quality = 0
	check_near(s.shadow_distance(), 0.0, 0.0001, "off")
	s.shadow_quality = 2
	check_near(s.shadow_distance(), 120.0, 0.0001, "high matches the world default")
	s.master_volume = 1.0
	check_near(s.volume_db(), 0.0, 0.001, "full volume is 0 dB")
	s.master_volume = 0.0
	check(is_finite(s.volume_db()), "silent volume stays finite")


func test_look_delta() -> void:
	var s := ClientSettings.new()
	var base: Vector2 = ClientScript.look_delta(Vector2(10, 10), s)
	check_near(base.x, -0.06, 0.0001, "drag right turns left-handed yaw")
	check_near(base.y, -0.04, 0.0001, "drag down tilts down")
	s.invert_y = true
	s.mouse_sensitivity = 2.0
	var inv: Vector2 = ClientScript.look_delta(Vector2(10, 10), s)
	check_near(inv.x, -0.12, 0.0001, "sensitivity scales yaw")
	check_near(inv.y, 0.08, 0.0001, "invert flips pitch and sensitivity scales it")
