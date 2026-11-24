extends SceneTree
## Seeds the craft-haul bot before the bot-test server starts (run_bot_test.py): an account
## and character named --name with password --password, standing at the Spawn Meadow
## workbench (CraftHaul.spot) with exactly a campfire's and a torch's inputs (CraftHaul.pack)
## and nothing else. Opens storage the same way the server does (Postgres from $DATABASE_URL,
## else the JSON store in $AIMMO_DATA_DIR), so the pack goes through the real save path and
## the server loads it like any returning player's. Prints one "seed: ..." line; exits 1 on
## any problem.
##
## Usage: godot --headless --path game -s tests/bot_test/seed_crafter.gd -- --name=x --password=y

const CraftHaul := preload("res://tests/bot_test/craft_haul.gd")


func _init() -> void:
	var args := CliArgs.parse(OS.get_cmdline_user_args())
	var name := str(args.get("name", ""))
	if name == "":
		printerr("seed: need --name")
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
	var spot := CraftHaul.spot()
	ch.x = spot.x
	ch.y = spot.y
	ch.z = spot.z
	ch.inventory = CraftHaul.pack()
	if not store.save_character(ch):
		printerr("seed: could not save %s: %s" % [name, store.last_error])
		store.close()
		quit(1)
		return
	var back := store.find_character_by_name(name)
	store.close()
	var want := Inventory.to_wire(Inventory.normalize(ch.inventory))
	if Inventory.to_wire(Inventory.normalize(back.get("inventory", {}))) != want:
		printerr("seed: %s saved pack %s, wanted %s" % [name, back.get("inventory", {}), want])
		quit(1)
		return
	print("seed: crafter %s at the workbench %s with %s" % [name, spot, want])
	quit(0)
