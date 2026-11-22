extends SceneTree
## Opens storage the same way the server does and checks each bot's saved position
## matches what the bot last saw. Run by run_bot_test.py after the server has stopped.


func _init() -> void:
	var args := CliArgs.parse(OS.get_cmdline_user_args())
	var expected: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(str(args.get("expected", ""))))
	var store := PlayerStore.create_from_env(OS.get_environment("AIMMO_DATA_DIR"))
	if store is PgStore:
		(store as PgStore).migrations_dir = Migrator.default_dir()
	if not store.open():
		printerr("verify: could not open storage: ", store.last_error)
		quit(1)
		return
	var bad := 0
	for bot_name in expected:
		var e: Array = expected[bot_name]
		var ch := store.find_character_by_name(bot_name)
		if ch.is_empty():
			printerr("verify: %s has no saved character" % bot_name)
			bad += 1
			continue
		var got := Vector3(ch.x, ch.y, ch.z)
		var want := Vector3(e[0], e[1], e[2])
		if got.distance_to(want) > 0.05:
			printerr("verify: %s saved at %s but was last at %s" % [bot_name, got, want])
			bad += 1
	store.close()
	print("verify: %d/%d characters persisted correctly" % [expected.size() - bad, expected.size()])
	quit(0 if bad == 0 else 1)
