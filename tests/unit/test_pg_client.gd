extends TestCase


func test_parse_url() -> void:
	var c := PgClient.parse_url("postgresql://us%40er:p%3Ass@db.example.com:6543/game?sslmode=require")
	check_eq(c.user, "us@er")
	check_eq(c.password, "p:ss")
	check_eq(c.host, "db.example.com")
	check_eq(c.port, 6543)
	check_eq(c.database, "game")
	check_eq(c.sslmode, "require")
	var d := PgClient.parse_url("postgres://u:p@h/db")
	check_eq(d.port, 5432, "default port")
	check_eq(d.sslmode, "disable", "default sslmode")


func test_queries() -> void:
	if not has_db():
		return
	var db := PgClient.new()
	check(db.connect_url(OS.get_environment("DATABASE_URL")), "connect: " + db.last_error)
	var rows: Variant = db.query("SELECT $1::int + 1 AS n, $2::text AS s, NULL AS z", [41, "héllo"])
	check(rows != null, "query ran: " + db.last_error)
	if rows != null:
		check_eq(rows[0].n, "42")
		check_eq(rows[0].s, "héllo", "utf8 roundtrip")
		check_eq(rows[0].z, null, "null")
	var evil: Variant = db.query("SELECT $1::text AS s", ["'); DROP TABLE accounts; --"])
	check(evil != null and evil[0].s == "'); DROP TABLE accounts; --", "params are not SQL")
	check(db.query("SELECT * FROM no_such_table") == null, "errors reported")
	check(db.last_error.find("42P01") != -1, "error code kept: " + db.last_error)
	var after: Variant = db.query("SELECT 1 AS one")
	check(after != null and after[0].one == "1", "connection usable after an error")
	db.close()
