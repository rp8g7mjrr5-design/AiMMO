extends TestCase
## Return to Spawn Meadow (Esc menu, gameplay's c2s_unstuck): the button's countdown and
## answer handling, the settings menu showing it only in game, and the camera going with you.



func test_ready_at_first() -> void:
	var r := SpawnReturn.new()
	check(r.enabled(0), "a fresh session can go home at once")
	check_eq(r.label(0), "Return to Spawn Meadow")


func test_press_waits_for_the_answer_once() -> void:
	var r := SpawnReturn.new()
	check(r.ask(1000), "first press goes out")
	check_eq(r.label(1100), SpawnReturn.ASKING_LABEL)
	check(not r.enabled(1100), "no second press while the first is in flight")
	check(not r.ask(1200), "a double click sends one ask")
	check_eq(r.asks, 1)


func test_trip_home_counts_down_the_server_cooldown() -> void:
	var r := SpawnReturn.new()
	r.ask(0)
	r.answered(true, GameConfig.UNSTUCK_COOLDOWN, 200)
	check_eq(r.homes, 1)
	check(not r.enabled(200), "cooling down after a trip home")
	check_eq(r.label(200), "Return to Spawn Meadow (60 s)")
	check_eq(r.label(200 + 17_500), "Return to Spawn Meadow (43 s)", "rounds up, never shows 0 s")
	check_eq(r.seconds_left(200 + 59_999), 1)
	check(r.enabled(200 + 60_000), "works again when the server's cooldown ends")
	check_eq(r.label(200 + 60_000), "Return to Spawn Meadow")


func test_refusals() -> void:
	var r := SpawnReturn.new()
	r.ask(0)
	r.answered(false, 0.0, 100) # "You're already in Spawn Meadow."
	check(r.enabled(100), "already home keeps the button ready (the server keeps your cooldown)")
	r.ask(200)
	r.answered(false, 12.3, 300) # reconnected inside the server's cooldown
	check_eq(r.seconds_left(300), 13)
	check(not r.enabled(300), "cooldown refusal greys the button")
	r.ask(400)
	r.answered(false, NAN, 400)
	check(r.enabled(400), "a bad wait never locks the button")
	check_eq(r.homes, 0)


func test_lost_answer_gives_the_button_back() -> void:
	var r := SpawnReturn.new()
	r.ask(0)
	check(not r.enabled(SpawnReturn.ANSWER_TIMEOUT_MS), "still waiting at the timeout")
	check(r.enabled(SpawnReturn.ANSWER_TIMEOUT_MS + 1), "no answer in 5 s: press again")


func test_reset_forgets_the_session() -> void:
	var r := SpawnReturn.new()
	r.ask(0)
	r.answered(true, 60.0, 0)
	r.reset()
	check(r.enabled(1), "a new login starts ready")


func test_settings_menu_shows_it_only_in_game() -> void:
	var m := SettingsMenu.new()
	m.setup(ClientSettings.new(), Theme.new())
	check(not m.home_button.visible, "not on the login screen")
	var asked := [0]
	m.home_requested.connect(func(): asked[0] += 1)
	m.home_button.pressed.emit()
	check_eq(asked[0], 0, "no ask before login")
	m.set_in_game(true)
	check(m.home_button.visible, "shown once you play")
	check_eq(m.home_button.text, "Return to Spawn Meadow")
	m.home_button.pressed.emit()
	m.home_button.pressed.emit()
	check_eq(asked[0], 1, "one ask per press, none while waiting")
	check(m.home_button.disabled, "greyed while waiting")
	var now := Time.get_ticks_msec()
	m.home.answered(true, 60.0, now)
	m.refresh_home(now)
	check(m.home_button.text.begins_with("Return to Spawn Meadow ("), m.home_button.text)
	m.set_in_game(false)
	check(not m.home_button.visible, "hidden again after logout")
	check(m.home.enabled(now), "and the next login starts ready")
	m.free()


func test_quiet_close_skips_the_chime_flag() -> void:
	var m := SettingsMenu.new()
	m.setup(ClientSettings.new(), Theme.new())
	m.settings = ClientSettings.new()
	var quiet := []
	m.closed.connect(func(): quiet.append(m.quiet_close))
	m.visible = true
	m.close(true)
	m.visible = true
	m.close()
	check_eq(quiet, [true, false])
	check(not m.quiet_close, "flag cleared after the signal")
	m.free()


func test_camera_jumps_with_a_teleport() -> void:
	var cam := ActionCamera.new()
	cam.place(Vector3(200, 4, -150), 1.0)
	cam.turn(Vector2(30, 10))
	var yaw := cam.yaw
	var pitch := cam.pitch
	cam.jump_to(Vector3(0, 2, 3))
	check_near(cam.pivot.distance_to(Vector3(0, 2, 3)), 0.0, 0.0001, "pivot is home at once, no fly-over")
	check_near(cam.yaw, yaw, 0.0001, "you keep looking where you looked")
	check_near(cam.pitch, pitch, 0.0001)
	var xf := cam.step(Vector3(0, 2, 3), 1.0 / 60.0, func(_x, _z): return 0.0)
	check(xf.origin.distance_to(Vector3(0, 2, 3)) < ActionCamera.DIST_MAX + 2.0, "camera is by the avatar the next frame")


func test_client_wires_it() -> void:
	var src := FileAccess.get_file_as_string("res://client/client.gd")
	check(src.contains("net.unstuck_result.connect(_on_unstuck)"), "answers are handled")
	check(src.contains("c2s_unstuck.rpc_id(1)"), "the press sends c2s_unstuck")
	check(src.contains("cam.jump_to(prediction.position)"), "the camera follows a snap")
	check(not src.contains("\"/unstuck\""), "no chat command")


func test_f1_lists_it() -> void:
	var found := false
	for r in ControlsOverlay.rows():
		if str(r[1]).contains("Return to Spawn Meadow"):
			found = true
	check(found, "F1 tells you where to find it")
