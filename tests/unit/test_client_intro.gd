extends TestCase
## The Budda Games intro: plays on a normal desktop launch, never in automated or headless
## runs, skips on any key, click or pad button, the video ships in the client only, and the
## engine's boot splash is off with the video's background colour.


func test_plays_on_a_normal_launch() -> void:
	check(Intro.should_play({}, "x11"), "a plain client launch shows the intro")
	check(Intro.should_play({"address": "1.2.3.4:7777"}, "windows"), "a picked server still shows it")


func test_automated_and_relaunched_runs_skip_it() -> void:
	check(not Intro.should_play({}, "headless"), "headless never plays video")
	for flag in ["no-intro", "updated", "screenshot", "autoconnect", "bot", "server"]:
		check(not Intro.should_play({flag: true}, "x11"), "--%s starts straight in" % flag)
	check(Intro.should_play({"intro": true, "screenshot": "x.png"}, "x11"), "--intro forces it for tests")


func test_skip_events() -> void:
	var key := InputEventKey.new()
	key.pressed = true
	check(Intro.is_skip_event(key), "a key press skips")
	key.echo = true
	check(not Intro.is_skip_event(key), "key repeat does not count twice")
	var up := InputEventKey.new()
	check(not Intro.is_skip_event(up), "a key release does not skip")
	var click := InputEventMouseButton.new()
	click.pressed = true
	check(Intro.is_skip_event(click), "a click skips")
	var pad := InputEventJoypadButton.new()
	pad.pressed = true
	check(Intro.is_skip_event(pad), "a pad button skips")
	check(not Intro.is_skip_event(InputEventMouseMotion.new()), "moving the mouse does not skip")


func test_video_is_a_small_theora_stream() -> void:
	check(ResourceLoader.exists(Intro.VIDEO_PATH), "intro video is in the project")
	check(load(Intro.VIDEO_PATH) is VideoStreamTheora, "intro loads as Theora")
	var f := FileAccess.open(Intro.VIDEO_PATH, FileAccess.READ)
	check(f != null and f.get_length() < 2 * 1024 * 1024, "intro stays under 2 MB for the auto-updater")


func test_ships_in_clients_not_the_server() -> void:
	var cfg := ConfigFile.new()
	check_eq(cfg.load("res://export_presets.cfg"), OK, "export presets load")
	for i in 4:
		var sec := "preset.%d" % i
		var inc := str(cfg.get_value(sec, "include_filter", ""))
		if bool(cfg.get_value(sec, "dedicated_server", false)):
			check("client/*" in str(cfg.get_value(sec, "exclude_filter", "")), "server build leaves the client (and intro) out")
		else:
			check("client/intro/*.ogv" in inc, "%s packs the intro" % cfg.get_value(sec, "name"))


func test_boot_splash_is_off() -> void:
	check_eq(ProjectSettings.get_setting("application/boot_splash/show_image"), false, "no engine logo at launch")
	var bg: Color = ProjectSettings.get_setting("application/boot_splash/bg_color")
	check(bg.is_equal_approx(Color(Intro.BG, 1.0)), "splash background matches the intro's first frame")
