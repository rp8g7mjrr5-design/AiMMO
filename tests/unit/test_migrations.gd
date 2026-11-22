extends TestCase
## Enforces hard rule 1: migrations are numbered, sequential, and add-only.

const FORBIDDEN := ["DROP ", "RENAME ", "TRUNCATE ", "DELETE FROM", "ALTER COLUMN", "DROP\n"]


func test_numbering_is_sequential() -> void:
	var files := Migrator.list_files(Migrator.default_dir())
	check(files.size() >= 1, "at least one migration in %s" % Migrator.default_dir())
	for i in files.size():
		var want := "%04d_" % (i + 1)
		check(files[i].begins_with(want), "%s should start with %s" % [files[i], want])


func test_add_only() -> void:
	var dir := Migrator.default_dir()
	for f in Migrator.list_files(dir):
		var sql := _strip_comments(FileAccess.get_file_as_string(dir.path_join(f))).to_upper()
		for bad in FORBIDDEN:
			check(sql.find(bad) == -1, "%s contains forbidden '%s'" % [f, bad.strip_edges()])


func test_apply_twice_is_harmless() -> void:
	if not has_db():
		return
	var db := PgClient.new()
	check(db.connect_url(OS.get_environment("DATABASE_URL")), "connect: " + db.last_error)
	var m1 := Migrator.new()
	check(m1.run(db), "first run: " + m1.last_error)
	var m2 := Migrator.new()
	check(m2.run(db), "second run: " + m2.last_error)
	check_eq(m2.applied.size(), 0, "nothing re-applied")
	db.close()


func _strip_comments(sql: String) -> String:
	var out := PackedStringArray()
	for line in sql.split("\n"):
		var i := line.find("--")
		out.append(line if i == -1 else line.substr(0, i))
	return "\n".join(out)
