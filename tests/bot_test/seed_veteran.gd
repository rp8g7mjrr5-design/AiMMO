extends SceneTree
## Seeds the level-gate veteran before the bot-test server starts (run_bot_test.py): an
## account and character named --name with password --password, standing a few metres short
## of tier-2 node --node, with exactly the level that node needs in its skill and nothing
## else. Opens storage the same way the server does (Postgres from $DATABASE_URL, else the
## JSON store in $AIMMO_DATA_DIR), so it goes through the real save path and the server loads
## it like any returning player. Prints one "seed: ..." line; exits 1 on any problem.
##
## Usage: godot --headless --path game -s tests/bot_test/seed_veteran.gd -- --name=x --password=y [--node=397]
## The last line is "seed: node=<id>", which run_bot_test.py reads.

const LevelGate := preload("res://tests/bot_test/level_gate.gd")


func _init() -> void:
	var args := CliArgs.parse(OS.get_cmdline_user_args())
	var name := str(args.get("name", ""))
	# No --node: the tier-2 node nearest spawn (LevelGate.gate_node), the one the gate check uses.
	var node_id := int(args["node"]) if args.has("node") else LevelGate.gate_node({}, GameConfig.SPAWN_POINT)
	if name == "" or ResourceNodes.get_by_id(node_id).is_empty():
		printerr("seed: need --name and a real --node (got %s, %d)" % [name, node_id])
		quit(1)
		return
	var store := PlayerStore.create_from_env(OS.get_environment("AIMMO_DATA_DIR"))
	if store is PgStore:
		(store as PgStore).migrations_dir = Migrator.default_dir()
	if not store.open():
		printerr("seed: could not open storage: ", store.last_error)
		quit(1)
		return
	var lc := name.to_lower()
	var account := store.find_account(lc)
	if account.is_empty():
		account = store.create_account(name, lc, CryptoUtil.hash_password(str(args.get("password", ""))))
	if account.is_empty():
		printerr("seed: could not create account %s: %s" % [name, store.last_error])
		store.close()
		quit(1)
		return
	var ch := store.load_or_create_character(account)
	if ch.is_empty():
		printerr("seed: could not create character %s: %s" % [name, store.last_error])
		store.close()
		quit(1)
		return
	var spot := LevelGate.veteran_spot(node_id, GameConfig.SPAWN_POINT)
	ch.x = spot.x
	ch.y = spot.y
	ch.z = spot.z
	ch.skills = LevelGate.veteran_skills(node_id)
	if not store.save_character(ch):
		printerr("seed: could not save %s: %s" % [name, store.last_error])
		store.close()
		quit(1)
		return
	var back := store.find_character_by_name(name)
	store.close()
	if Skills.normalize(back.get("skills", {})) != Skills.normalize(ch.skills):
		printerr("seed: %s saved skills %s, wanted %s" % [name, back.get("skills", {}), ch.skills])
		quit(1)
		return
	print("seed: %s at %s next to node %d with %s" % [name, spot, node_id, ch.skills])
	print("seed: node=%d" % node_id)
	quit(0)
