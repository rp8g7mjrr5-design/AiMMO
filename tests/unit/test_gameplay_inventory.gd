extends TestCase
## Inventory (game/shared/inventory.gd), its place in CharacterData, the /bag command,
## and that both stores keep a character's pack across save and reload.


func test_add_stacks_and_caps() -> void:
	var inv := {}
	check_eq(Inventory.add(inv, "ash_wood", 3), 3, "added 3")
	check_eq(Inventory.add(inv, "ash_wood", 2), 2, "stacks")
	check_eq(Inventory.count(inv, "ash_wood"), 5)
	check_eq(Inventory.add(inv, "ash_wood", Inventory.MAX_STACK * 2), Inventory.MAX_STACK - 5, "stops at the cap")
	check_eq(Inventory.count(inv, "ash_wood"), Inventory.MAX_STACK)
	check_eq(Inventory.add(inv, "ash_wood", 1), 0, "full stack takes nothing")
	check_eq(Inventory.add(inv, "dragon_egg", 1), 0, "unknown item refused")
	check_eq(Inventory.add(inv, "stone", 0), 0, "zero refused")
	check_eq(Inventory.add(inv, "stone", -4), 0, "negative refused")
	check(not inv.has("dragon_egg") and not inv.has("stone"), "refusals leave no entries")


func test_stack_cap_is_999() -> void:
	# Raised from 99 (2026-11-23): both wood stacks filled in one long session. At 999 a
	# long first session (a few hundred wood over two kinds) never fills one.
	check_eq(Inventory.MAX_STACK, 999)
	var inv := {"pine_wood": 99}
	check_eq(Inventory.add(inv, "pine_wood", 5), 5, "a 99 stack keeps filling")


func test_remove_is_all_or_nothing() -> void:
	var inv := {"stone": 3}
	check(not Inventory.remove(inv, "stone", 4), "can't take more than you have")
	check_eq(Inventory.count(inv, "stone"), 3, "nothing taken")
	check(not Inventory.remove(inv, "stone", 0), "zero is not a removal")
	check(not Inventory.remove(inv, "stone", -1), "negative is not a removal")
	check(Inventory.remove(inv, "stone", 3), "takes exactly what you have")
	check_eq(Inventory.count(inv, "stone"), 0)
	check(inv.has("stone"), "kept at 0 so the next save writes the 0")
	check(not Inventory.has(inv, "stone"), "0 is not having it")
	check(Inventory.held(inv).is_empty(), "nothing held")


func test_normalize_repairs_and_keeps_unknown_items() -> void:
	var inv := Inventory.normalize({"ash_wood": "4", "stone": 2.0, "plant_fibre": -3, "pine_wood": NAN, "old_relic": 1, "": 5, 7: 2})
	check_eq(inv.ash_wood, 4, "text quantity from Postgres")
	check_eq(inv.stone, 2, "float from JSON")
	check_eq(inv.plant_fibre, 0, "negative floored")
	check_eq(inv.pine_wood, 0, "NaN floored")
	check_eq(inv.old_relic, 1, "unknown (retired) item kept, never silently lost")
	check(not inv.has(""), "blank id dropped")
	check_eq(inv.get("7", -1), 2, "keys become strings")
	check_eq(Inventory.normalize(null), {}, "null")
	check_eq(Inventory.normalize("junk"), {}, "not a Dictionary")
	check_eq(Inventory.held(inv), ["ash_wood", "stone", "7", "old_relic"], "known items first, then unknown sorted")


func test_items_match_resource_nodes() -> void:
	for kind in ResourceNodes.KINDS:
		var item: String = ResourceNodes.KINDS[kind].item
		check(Inventory.is_item(item), "%s gives a real item (%s)" % [kind, item])
	check_eq(Inventory.ITEM_ORDER.size(), Inventory.ITEMS.size(), "every item has an order")


func test_character_data_inventory() -> void:
	var old := CharacterData.normalize({"id": 1, "name": "Old"})
	check_eq(old.inventory, {}, "characters from before inventory have an empty pack")
	var other := CharacterData.normalize({"id": 2, "name": "Other"})
	Inventory.add(old.inventory, "stone", 1)
	check_eq(other.inventory, {}, "packs are never shared through the default")
	check_eq(CharacterData.DEFAULTS.inventory, {}, "default untouched")
	var bad := CharacterData.normalize({"id": 3, "inventory": "garbage"})
	check_eq(bad.inventory, {}, "a corrupt pack loads empty instead of crashing")
	var fresh := CharacterData.new_for({"id": 4, "username": "Moss", "username_lc": "moss"})
	check_eq(fresh.inventory, {}, "new characters start empty")


func test_bag_command() -> void:
	check(ChatCommands.HELP.contains("/bag"), "help lists /bag")
	var empty := ChatCommands.run("/bag", {})
	check(empty.begins_with("Your pack is empty."), "empty pack: " + empty)
	var r := ChatCommands.run("/inventory", {"inventory": {"stone": 2, "ash_wood": 4, "pine_wood": 0}})
	check_eq(r, "Your pack: 4 ash wood, 2 stone.", "lists held items in order")
	check_eq(ChatCommands.run("/i", {"inventory": {"plant_fibre": 1}}), "Your pack: 1 plant fibre.", "alias /i")


func test_json_store_keeps_pack() -> void:
	var path := OS.get_user_data_dir().path_join("unit_test_inv_%d.json" % Time.get_ticks_usec())
	var s := JsonStore.new()
	s.path = path
	check(s.open(), "opens")
	var ch := s.load_or_create_character(s.create_account("Bram", "bram", "h"))
	check_eq(ch.inventory, {}, "starts empty")
	Inventory.add(ch.inventory, "pine_wood", 6)
	Inventory.add(ch.inventory, "stone", 1)
	Inventory.remove(ch.inventory, "stone", 1)
	check(s.save_character(ch), "saved")
	var s2 := JsonStore.new()
	s2.path = path
	check(s2.open(), "reopens")
	var back := s2.load_or_create_character(s2.find_account("bram"))
	check_eq(Inventory.count(back.inventory, "pine_wood"), 6, "pine kept")
	check_eq(Inventory.count(back.inventory, "stone"), 0, "used-up stone stays used up")
	DirAccess.remove_absolute(path)


func test_pg_store_keeps_pack() -> void:
	if not has_db():
		return
	var s := PgStore.new()
	s.url = OS.get_environment("DATABASE_URL")
	s.migrations_dir = Migrator.default_dir()
	check(s.open(), "open: " + s.last_error)
	var uname := "invtest%d" % (Time.get_ticks_usec() % 100000000)
	var acct := s.create_account(uname, uname, "h")
	check(not acct.is_empty(), "account: " + s.last_error)
	var ch := s.load_or_create_character(acct)
	check_eq(ch.inventory, {}, "new character, empty pack")
	check(s.save_character(ch), "saving an empty pack is fine: " + s.last_error)
	Inventory.add(ch.inventory, "ash_wood", 4)
	Inventory.add(ch.inventory, "plant_fibre", 1)
	check(s.save_character(ch), "save: " + s.last_error)
	var back := s.load_or_create_character(acct)
	check_eq(Inventory.count(back.inventory, "ash_wood"), 4, "ash kept")
	check_eq(Inventory.count(back.inventory, "plant_fibre"), 1, "fibre kept")
	check(Inventory.remove(back.inventory, "ash_wood", 4), "use it all")
	Inventory.add(back.inventory, "plant_fibre", 2)
	check(s.save_character(back), "save again: " + s.last_error)
	var again := s.find_character_by_name(uname)
	check_eq(Inventory.count(again.inventory, "ash_wood"), 0, "used-up wood stays used up")
	check_eq(Inventory.count(again.inventory, "plant_fibre"), 3, "fibre stacked")
	check_eq(Inventory.held(again.inventory), ["plant_fibre"], "only fibre held")
	s.close()


func test_week00_pack_loads() -> void:
	if not has_db():
		return
	var store := PgStore.new()
	store.url = OS.get_environment("DATABASE_URL")
	store.migrations_dir = Migrator.default_dir()
	check(store.open(), "open: " + store.last_error)
	var db := PgClient.new()
	db.connect_url(store.url)
	var sql := FileAccess.get_file_as_string("res://tests/fixtures/week00_inventory.sql")
	check(db.simple_query(sql) != null, "fixture applied: " + db.last_error)
	db.close()
	var acct := store.find_account("pack_carrier")
	check(not acct.is_empty(), "account found")
	var ch := store.load_or_create_character(acct)
	check_eq(ch.name, "Pack_Carrier")
	check_eq(Inventory.count(ch.inventory, "ash_wood"), 7, "ash wood kept")
	check_eq(Inventory.count(ch.inventory, "plant_fibre"), 2, "old ember sap is plant fibre now")
	check_eq(Inventory.count(ch.inventory, "stone"), 0, "used-up stone stays used up")
	check_eq(Inventory.count(ch.inventory, "retired_relic"), 1, "unknown item not lost")
	check(store.save_character(ch), "saves back: " + store.last_error)
	var back := store.load_or_create_character(acct)
	check_eq(back.inventory, ch.inventory, "save + reload round-trips the pack")
	# The week 00 character, which has no inventory rows, loads with an empty pack.
	var legacy := store.find_account("legacy_wanderer")
	if not legacy.is_empty():
		check_eq(store.load_or_create_character(legacy).inventory, {}, "pre-inventory character has an empty pack")
	store.close()
