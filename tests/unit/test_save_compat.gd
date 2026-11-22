extends TestCase
## Loads characters exactly as older versions stored them (fixtures in tests/fixtures).
## Each week that changes the schema adds a fixture for the previous shape.


func test_week00_rows_load() -> void:
	if not has_db():
		return
	var store := PgStore.new()
	store.url = OS.get_environment("DATABASE_URL")
	store.migrations_dir = Migrator.default_dir()
	check(store.open(), "open: " + store.last_error)
	var db := PgClient.new()
	db.connect_url(store.url)
	var sql := FileAccess.get_file_as_string("res://tests/fixtures/week00_characters.sql")
	check(db.simple_query(sql) != null, "fixture applied: " + db.last_error)
	db.close()
	var acct := store.find_account("legacy_wanderer")
	check(not acct.is_empty(), "legacy account found")
	var ch := store.load_or_create_character(acct)
	check_eq(ch.name, "Legacy_Wanderer")
	check_near(ch.x, 42.5, 0.0001, "position kept")
	check_near(ch.z, -17.25, 0.0001, "position kept")
	check_eq(ch.appearance_seed, 1234, "appearance kept")
	check(CryptoUtil.verify_password("oldpassword", acct.password_hash), "old password still works")
	store.close()
