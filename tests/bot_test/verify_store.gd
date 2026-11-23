extends SceneTree

const GatherLedger := preload("res://tests/bot_test/gather_ledger.gd")
## Opens storage the same way the server does and checks each bot's saved position
## matches what the bot last saw. Run by run_bot_test.py after the server has stopped.
## Each expected entry is [x, y, z] (old form) or {"pos": [x, y, z], "pack": {item: n}}: then
## the saved inventory must also hold exactly the pack the bot last got in s2c_inventory.
## With "skills_floor": {skill: xp} the saved character must hold at least that XP in each
## skill (the bot can't see every gain, only logins and level-up lines, so it is a floor).


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
		var entry: Variant = expected[bot_name]
		var e: Array = entry.pos if entry is Dictionary else entry
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
			continue
		if entry is Dictionary and entry.has("pack"):
			var saved := Inventory.to_wire(Inventory.normalize(ch.get("inventory", {})))
			var seen := Inventory.to_wire(Inventory.normalize(entry.pack))
			# A gather of ours still running at the hang-up may have paid out on the server
			# after the last s2c_inventory got through (see GatherLedger.reconnect_problem).
			var running := int(entry.get("running_node", -1))
			var amount := int(entry.get("running_amount", 0))
			var why := GatherLedger.reconnect_problem(seen, saved, running, amount)
			if why == "in_flight":
				print("verify: %s's last gather paid out as it logged off (%s)" % [bot_name, GatherLedger.pack_diff(seen, saved)])
			elif why != "":
				printerr("verify: %s saved pack %s but the server last told the bot %s" % [bot_name, saved, seen])
				bad += 1
				continue
		if entry is Dictionary and entry.has("skills_floor"):
			var why := skills_problem(entry.skills_floor, ch.get("skills", {}))
			if why != "":
				printerr("verify: %s %s" % [bot_name, why])
				bad += 1
	store.close()
	print("verify: %d/%d characters persisted correctly (position, pack and skills)" % [expected.size() - bad, expected.size()])
	quit(0 if bad == 0 else 1)


## Pure: "" when `saved` holds at least `least` XP in every skill, else what is short.
static func skills_problem(least: Dictionary, saved: Variant) -> String:
	var sk := Skills.normalize(saved)
	var short := PackedStringArray()
	for id in least:
		if Skills.xp_of(sk, str(id)) < int(least[id]):
			short.append("%s %d XP (level %d), the bot knew of at least %d (level %d)" % [
				id, Skills.xp_of(sk, str(id)), Skills.level_for(Skills.xp_of(sk, str(id))),
				int(least[id]), Skills.level_for(int(least[id]))])
	return "" if short.is_empty() else "saved " + ", ".join(short)
