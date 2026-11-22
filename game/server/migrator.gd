class_name Migrator
extends RefCounted
## Applies numbered SQL files from db/migrations in order, once each, recording them in
## schema_migrations. Each file runs in its own transaction.

var last_error := ""
var applied: PackedStringArray = []


## Where migrations live: $AIMMO_MIGRATIONS_DIR, else <repo>/db/migrations next to game/.
static func default_dir() -> String:
	var env := OS.get_environment("AIMMO_MIGRATIONS_DIR")
	if env != "":
		return env
	return ProjectSettings.globalize_path("res://").path_join("../db/migrations").simplify_path()


static func list_files(dir: String) -> PackedStringArray:
	var out := PackedStringArray()
	var d := DirAccess.open(dir)
	if d == null:
		return out
	for f in d.get_files():
		if f.ends_with(".sql"):
			out.append(f)
	out.sort()
	return out


func run(db: PgClient, dir: String = "") -> bool:
	if dir == "":
		dir = default_dir()
	var files := list_files(dir)
	if files.is_empty():
		last_error = "no migrations found in %s" % dir
		return false
	if db.simple_query("CREATE TABLE IF NOT EXISTS schema_migrations (version TEXT PRIMARY KEY, applied_at TIMESTAMPTZ NOT NULL DEFAULT now())") == null:
		last_error = db.last_error
		return false
	var done_rows: Variant = db.query("SELECT version FROM schema_migrations")
	if done_rows == null:
		last_error = db.last_error
		return false
	var done := {}
	for r in done_rows:
		done[r.version] = true
	for f in files:
		if done.has(f):
			continue
		var sql := FileAccess.get_file_as_string(dir.path_join(f))
		if sql.strip_edges() == "":
			last_error = "migration %s is empty" % f
			return false
		var wrapped := "BEGIN;\n%s\n;INSERT INTO schema_migrations (version) VALUES ('%s');\nCOMMIT;" % [sql, f.replace("'", "''")]
		if db.simple_query(wrapped) == null:
			last_error = "%s: %s" % [f, db.last_error]
			db.simple_query("ROLLBACK")
			return false
		applied.append(f)
		print("[db] applied migration ", f)
	return true
