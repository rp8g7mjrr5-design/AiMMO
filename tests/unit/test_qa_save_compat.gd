extends TestCase
## Save compatibility for every fixture (hard rules 1 and 6), with no per-fixture code.
##
## For each tests/fixtures/*.sql this builds a brand-new database, brings it to the schema
## the fixture was written for, inserts the fixture, runs every remaining migration the way
## the live server would on deploy, and then checks through the real PgStore that every
## stored character still loads with its own id, name, look and position, that loading
## creates nobody new, and that saving and loading again keeps everything.
##
## A fixture names the schema it was written against with a header line
##   -- schema-version: 0001
## meaning "migrations up to and including 0001 existed". Without the line the test uses the
## oldest schema the fixture's SQL fits (tries 0001, then 0001-0002, ...), which is right for
## any fixture that uses a column the moment it is added; set the header to be explicit.
##
## Needs DATABASE_URL and a role that may CREATE DATABASE (CI's is the superuser). Each
## fixture gets its own throwaway database, dropped afterwards, so it never touches the
## shared test database other tests use.

const FIXTURES_DIR := "res://tests/fixtures"
const HEADER := "schema-version:"


## Pure: the schema version a fixture declares, or "" when it has no header.
static func schema_version_of(sql: String) -> String:
	for line in sql.split("\n"):
		var l := line.strip_edges()
		if not l.begins_with("--"):
			continue
		l = l.substr(2).strip_edges()
		if l.begins_with(HEADER):
			return l.substr(HEADER.length()).strip_edges()
	return ""


## Pure: the migration files that existed at `version` ("0001" keeps 0001_*.sql and older).
## An empty version means all of them.
static func migrations_up_to(files: PackedStringArray, version: String) -> PackedStringArray:
	if version == "":
		return files
	var out := PackedStringArray()
	for f in files:
		if f.substr(0, 4) <= version.substr(0, 4):
			out.append(f)
	return out


## Pure: the same server and credentials as `url`, pointed at database `db`.
static func url_with_database(url: String, db: String) -> String:
	var p := PgClient.parse_url(url)
	return "postgres://%s:%s@%s:%d/%s?sslmode=%s" % [
		str(p.user).uri_encode(), str(p.password).uri_encode(), p.host, p.port, db, p.sslmode]


static func fixture_files() -> PackedStringArray:
	var out := PackedStringArray()
	for f in DirAccess.get_files_at(FIXTURES_DIR):
		if f.ends_with(".sql"):
			out.append(f)
	out.sort()
	return out


func test_header_parsing() -> void:
	check_eq(schema_version_of("-- hi\n-- schema-version: 0003\nINSERT ..."), "0003")
	check_eq(schema_version_of("--   schema-version:   0001  \n"), "0001", "spaces trimmed")
	check_eq(schema_version_of("INSERT INTO x VALUES (1);"), "", "no header")
	var files := PackedStringArray(["0001_a.sql", "0002_b.sql", "0003_c.sql"])
	check_eq(migrations_up_to(files, "0002"), PackedStringArray(["0001_a.sql", "0002_b.sql"]))
	check_eq(migrations_up_to(files, ""), files, "no version means all")
	check_eq(migrations_up_to(files, "0009"), files, "version newer than all")
	check_eq(candidate_versions("0002", files), PackedStringArray(["0002"]), "header wins")
	check_eq(candidate_versions("", files), PackedStringArray(["0001", "0002", "0003"]), "oldest first")


func test_url_with_database() -> void:
	var u := url_with_database("postgres://bob:p%40ss@db.internal:6543/main?sslmode=require", "other")
	var p := PgClient.parse_url(u)
	check_eq(p.user, "bob")
	check_eq(p.password, "p@ss", "password round-trips through encoding")
	check_eq(p.host, "db.internal")
	check_eq(p.port, 6543)
	check_eq(p.database, "other")
	check_eq(p.sslmode, "require")
	check_eq(_ident("Week-02 inv.v2"), "week_02_inv_v2", "database name piece")


func test_there_are_fixtures() -> void:
	check(fixture_files().size() >= 1, "at least one fixture in %s" % FIXTURES_DIR)
	var all := Migrator.list_files(Migrator.default_dir())
	for f in fixture_files():
		var v := schema_version_of(FileAccess.get_file_as_string(FIXTURES_DIR.path_join(f)))
		if v == "":
			continue
		check(v.length() == 4 and v.is_valid_int(), "%s: schema-version '%s' should be 4 digits" % [f, v])
		check(migrations_up_to(all, v).size() >= 1, "%s: schema-version %s matches no migration" % [f, v])


func test_every_fixture_loads_after_all_migrations() -> void:
	if not has_db():
		return
	var base := OS.get_environment("DATABASE_URL")
	var admin := PgClient.new()
	check(admin.connect_url(base), "connect: " + admin.last_error)
	if failures.size() > 0:
		return
	var tag := "%d_%d" % [OS.get_process_id(), Time.get_ticks_usec() % 1000000]
	for f in fixture_files():
		_check_fixture(admin, base, f, "aimmo_compat_%s_%s" % [tag, _ident(f.get_basename())])
		if failures.size() > 0:
			break  # one broken fixture is enough to read; the rest would repeat it
	admin.close()


## Pure: a safe unquoted Postgres identifier piece (letters, digits, underscore).
static func _ident(s: String) -> String:
	var out := ""
	for c in s.to_lower():
		out += c if (c >= "a" and c <= "z") or (c >= "0" and c <= "9") else "_"
	return out


## Candidate schemas for a fixture: its header's version, or else every migration prefix
## from oldest to newest (the first one the fixture's INSERTs fit is the shape it was written
## for, so old fixtures without a header still go through every later migration).
static func candidate_versions(version: String, all: PackedStringArray) -> PackedStringArray:
	if version != "":
		return PackedStringArray([version])
	var out := PackedStringArray()
	for f in all:
		out.append(f.substr(0, 4))
	return out


func _check_fixture(admin: PgClient, base: String, fixture: String, db_name: String) -> void:
	var sql := FileAccess.get_file_as_string(FIXTURES_DIR.path_join(fixture))
	var mig_dir := Migrator.default_dir()
	var all := Migrator.list_files(mig_dir)
	var url := url_with_database(base, db_name)
	var before: Variant = null
	var tried := PackedStringArray()

	# 1 and 2. The schema as it was when the fixture was written, the old data, and a raw
	# snapshot of it taken before any current code touches it.
	for version in candidate_versions(schema_version_of(sql), all):
		admin.simple_query("DROP DATABASE IF EXISTS %s" % db_name)
		if admin.simple_query("CREATE DATABASE %s" % db_name) == null:
			check(false, "%s: CREATE DATABASE failed (the test role needs CREATEDB): %s" % [fixture, admin.last_error])
			return
		var tmp := _copy_migrations(mig_dir, migrations_up_to(all, version), fixture)
		var db := PgClient.new()
		if not db.connect_url(url):
			check(false, "%s: connect: %s" % [fixture, db.last_error])
			return
		var m := Migrator.new()
		var ok := m.run(db, tmp)
		_remove_dir(tmp)
		if not ok:
			check(false, "%s: migrations up to %s: %s" % [fixture, version, m.last_error])
			db.close()
			break
		if db.simple_query(sql) == null:
			tried.append("%s (%s)" % [version, db.last_error])
			db.close()
			continue
		before = db.query(
			"SELECT a.id AS acct_id, a.username_lc, a.password_hash, c.* FROM accounts a " +
			"LEFT JOIN LATERAL (SELECT * FROM characters WHERE account_id = a.id ORDER BY id LIMIT 1) c ON true " +
			"ORDER BY a.id")
		if before == null:
			check(false, "%s: snapshot: %s" % [fixture, db.last_error])
		db.close()
		print("[qa] save-compat: %s written for schema %s, upgrading through %d later migration(s)" % [
			fixture, version, all.size() - migrations_up_to(all, version).size()])
		break
	if before == null:
		check(false, "%s fits no schema: %s" % [fixture, ", ".join(tried)])
		admin.simple_query("DROP DATABASE IF EXISTS %s" % db_name)
		return
	check(before.size() >= 1, "%s inserts no accounts" % fixture)
	_check_upgraded(fixture, url, mig_dir, before)
	if admin.simple_query("DROP DATABASE IF EXISTS %s" % db_name) == null:
		check(false, "%s: could not drop %s: %s" % [fixture, db_name, admin.last_error])


func _check_upgraded(fixture: String, url: String, mig_dir: String, before: Array) -> void:
	# 3. Today's server opens it: runs the remaining migrations, then loads every character.
	var store := PgStore.new()
	store.url = url
	store.migrations_dir = mig_dir
	if not store.open():
		check(false, "%s: current server can't open it: %s" % [fixture, store.last_error])
		store.close()
		return
	var count_before := _character_count(store)
	for row in before:
		_check_account(fixture, store, row)
	check_eq(_character_count(store), count_before, "%s: loading created characters" % fixture)
	store.close()


func _check_account(fixture: String, store: PgStore, row: Dictionary) -> void:
	var who := "%s/%s" % [fixture, row.username_lc]
	var acct := store.find_account(row.username_lc)
	check(not acct.is_empty(), who + ": account not found")
	if acct.is_empty():
		return
	check_eq(acct.password_hash, row.password_hash, who + ": password hash changed")
	if row.get("id") == null:
		return  # account that never made a character: creating one now is fine
	var ch := store.load_or_create_character(acct)
	check(not ch.is_empty(), who + ": character did not load: " + store.last_error)
	if ch.is_empty():
		return
	for k in CharacterData.DEFAULTS:
		check(ch.has(k), "%s: loaded character lacks '%s'" % [who, k])
	check_eq(ch.id, int(row.id), who + ": got a different character")
	check_eq(ch.name, str(row.name), who + ": name")
	check_eq(ch.appearance_seed, int(row.appearance_seed), who + ": appearance")
	var want := Terrain.clamp_to_world(Vector3(float(row.pos_x), float(row.pos_y), float(row.pos_z)))
	check(CharacterData.position(ch).distance_to(want) < 0.001,
		"%s: position %s, stored %s" % [who, CharacterData.position(ch), want])
	check_near(ch.yaw, float(row.yaw), 0.0001, who + ": yaw")

	# Save and load again: what the server writes back must read back the same.
	# (normalize, because the store snaps a moved character back onto the terrain)
	ch.x += 1.0
	ch.yaw = 0.5
	ch = CharacterData.normalize(ch)
	check(store.save_character(ch), who + ": save failed: " + store.last_error)
	var again := store.load_or_create_character(acct)
	for k in CharacterData.DEFAULTS:
		var a: Variant = again.get(k)
		var b: Variant = ch.get(k)
		if typeof(b) == TYPE_FLOAT:
			check(absf(float(a) - b) < 0.0001, "%s: '%s' after save: %s vs %s" % [who, k, a, b])
		else:
			check_eq(a, b, "%s: '%s' after save" % [who, k])


func _character_count(store: PgStore) -> int:
	var r: Variant = store._q("SELECT count(*) AS n FROM characters")
	return -1 if r == null or r.is_empty() else int(r[0].n)


func _copy_migrations(src: String, files: PackedStringArray, fixture: String) -> String:
	var dir := OS.get_user_data_dir().path_join("qa_compat_%s_%d" % [fixture.get_basename(), OS.get_process_id()])
	DirAccess.make_dir_recursive_absolute(dir)
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	for f in files:
		DirAccess.copy_absolute(src.path_join(f), dir.path_join(f))
	return dir


func _remove_dir(dir: String) -> void:
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	DirAccess.remove_absolute(dir)
