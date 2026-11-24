extends TestCase
## The game is called ZombAi, but a few old "AiMMO" names must never change, because friends
## already have the game installed (docs/vision.md, "Rename"). Renaming any of them would move
## their settings and downloaded updates out of reach, or stop the installed game finding its
## update pack.


func test_user_data_folder_keeps_its_name() -> void:
	check(ProjectSettings.get_setting("application/config/name") == "AiMMO",
		"config/name names app_userdata/AiMMO, where players' settings and updates live")


func test_window_title_says_zombai() -> void:
	var main: GDScript = load("res://main.gd")
	check(main.get_script_constant_map().get("GAME_TITLE") == "ZombAi", "the window shows ZombAi")


func test_build_file_names_stay() -> void:
	var cfg := ConfigFile.new()
	check(cfg.load("res://export_presets.cfg") == OK, "export presets load")
	var paths := []
	for section in cfg.get_sections():
		if cfg.has_section_key(section, "export_path"):
			paths.append(str(cfg.get_value(section, "export_path")))
	for want in ["AiMMO.x86_64", "AiMMO.exe", "AiMMO.zip"]:
		var found := false
		for p in paths:
			if p.ends_with("/" + want):
				found = true
		check(found, "the client still exports as %s, which installed games load packs for" % want)
