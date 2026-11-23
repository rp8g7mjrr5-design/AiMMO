extends TestCase
## Client F1 controls overlay: every default key is installed, every listed action is bound
## and shows a real key name, rows follow the InputMap (so a rebind shows at once), and the
## window builds, opens and closes.


func test_every_listed_action_is_bound() -> void:
	ControlsOverlay.install_input()
	for action in ControlsOverlay.listed_actions():
		check(ControlsOverlay.DEFAULT_BINDS.has(action) or ControlsOverlay.DEFAULT_MOUSE.has(action), "%s has a default key or button" % action)
		check(InputMap.has_action(action), "%s is in the InputMap" % action)
		check(ControlsOverlay.key_text(action) != "?", "%s shows a key name" % action)


func test_default_key_names() -> void:
	ControlsOverlay.install_input()
	check_eq(ControlsOverlay.key_text("interact"), "E")
	check_eq(ControlsOverlay.key_text("move_forward"), "W", "first bound key wins over Up")
	check_eq(ControlsOverlay.key_text("swap_shoulder"), "V")
	check_eq(ControlsOverlay.key_text("toggle_controls"), "F1")
	check_eq(ControlsOverlay.key_text("free_look"), "Alt")
	check_eq(ControlsOverlay.key_text("=Mouse"), "Mouse", "fixed entries show as written")
	check_eq(ControlsOverlay.key_text("no_such_action"), "?", "a missing action shows, not vanishes")


func test_rows_cover_every_key_the_game_uses() -> void:
	ControlsOverlay.install_input()
	var rows := ControlsOverlay.rows()
	var whats: Array = []
	for r in rows:
		check(str(r[1]) != "", "row has a label")
		check(not (r[2] as Array).is_empty(), "%s has keys" % r[1])
		whats.append(r[1])
	for want in ["Move", "Look around", "Free look (camera only)", "Swap shoulder", "Zoom the camera", "Gather what you look at", "Use the workbench", "Chat", "This list"]:
		check(whats.has(want), "lists %s" % want)
	check_eq(rows[0][2], ["W", "A", "S", "D"], "move shows WASD in reading order")
	for a in ControlsOverlay.DEFAULT_BINDS:
		check(ControlsOverlay.listed_actions().has(a), "every bound action is in the list: %s" % a)


func test_rebind_shows_the_new_key() -> void:
	ControlsOverlay.install_input()
	var saved := InputMap.action_get_events("interact")
	InputMap.action_erase_events("interact")
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_F
	InputMap.action_add_event("interact", ev)
	check_eq(ControlsOverlay.key_text("interact"), "F", "rebound interact")
	InputMap.action_erase_events("interact")
	for e in saved:
		InputMap.action_add_event("interact", e)
	check_eq(ControlsOverlay.key_text("interact"), "E", "restored")


func test_hint_and_no_slash_help() -> void:
	ControlsOverlay.install_input()
	check_eq(ControlsOverlay.corner_hint(), "F1 controls  ·  Esc settings")
	check(not ControlsOverlay.corner_hint().contains("/help"), "no chat command in the hint")


func test_window_opens_and_closes() -> void:
	ControlsOverlay.install_input()
	var w := ControlsOverlay.new()
	w.setup(Theme.new())
	var closes := [0]
	w.closed.connect(func(): closes[0] += 1)
	check(not w.visible, "starts hidden")
	w.toggle()
	check(w.visible, "toggle opens")
	w.toggle()
	check(not w.visible, "toggle closes")
	check_eq(closes[0], 1, "closed fires once")
	w.close()
	check_eq(closes[0], 1, "closing a closed window does nothing")
	w.free()
