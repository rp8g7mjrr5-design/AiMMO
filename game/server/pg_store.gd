class_name PgStore
extends PlayerStore
## PostgreSQL storage. Runs pending migrations on open().

var url := ""
var migrations_dir := ""
var _db: PgClient


func open() -> bool:
	_db = PgClient.new()
	if not _db.connect_url(url):
		last_error = "database connect failed: " + _db.last_error
		return false
	var m := Migrator.new()
	if not m.run(_db, migrations_dir):
		last_error = "migrations failed: " + m.last_error
		return false
	return true


func close() -> void:
	if _db != null:
		_db.close()


func _q(sql: String, params: Array = []) -> Variant:
	if _db == null:
		last_error = "store not open"
		return null
	if not _db.is_connected_to_db():
		# One reconnect attempt. Railway can recycle idle connections.
		_db = PgClient.new()
		if not _db.connect_url(url):
			last_error = "database reconnect failed: " + _db.last_error
			return null
	var r: Variant = _db.query(sql, params)
	if r == null:
		last_error = _db.last_error
	return r


func find_account(username_lc: String) -> Dictionary:
	var rows: Variant = _q("SELECT id, username, username_lc, password_hash FROM accounts WHERE username_lc = $1", [username_lc])
	if rows == null or rows.is_empty():
		return {}
	return _account(rows[0])


func create_account(username: String, username_lc: String, password_hash: String) -> Dictionary:
	var rows: Variant = _q(
		"INSERT INTO accounts (username, username_lc, password_hash) VALUES ($1, $2, $3) ON CONFLICT (username_lc) DO NOTHING RETURNING id, username, username_lc, password_hash",
		[username, username_lc, password_hash])
	if rows == null or rows.is_empty():
		return {}
	return _account(rows[0])


func touch_login(account_id: int) -> void:
	_q("UPDATE accounts SET last_login_at = now() WHERE id = $1", [account_id])


func load_or_create_character(account: Dictionary) -> Dictionary:
	var rows: Variant = _q("SELECT * FROM characters WHERE account_id = $1 ORDER BY id LIMIT 1", [account.id])
	if rows == null:
		return {}
	if not rows.is_empty():
		return CharacterData.from_pg_row(rows[0])
	var ch := CharacterData.new_for(account)
	var ins: Variant = _q(
		"INSERT INTO characters (account_id, name, pos_x, pos_y, pos_z, yaw, appearance_seed) VALUES ($1, $2, $3, $4, $5, $6, $7) RETURNING *",
		[ch.account_id, ch.name, ch.x, ch.y, ch.z, ch.yaw, ch.appearance_seed])
	if ins == null or ins.is_empty():
		return {}
	return CharacterData.from_pg_row(ins[0])


func save_character(ch: Dictionary) -> bool:
	var r: Variant = _q(
		"UPDATE characters SET pos_x = $2, pos_y = $3, pos_z = $4, yaw = $5, updated_at = now() WHERE id = $1",
		[ch.id, ch.x, ch.y, ch.z, ch.yaw])
	return r != null


func find_character_by_name(char_name: String) -> Dictionary:
	var rows: Variant = _q("SELECT * FROM characters WHERE lower(name) = lower($1) ORDER BY id LIMIT 1", [char_name])
	if rows == null or rows.is_empty():
		return {}
	return CharacterData.from_pg_row(rows[0])


func _account(row: Dictionary) -> Dictionary:
	return {"id": int(row.id), "username": row.username, "username_lc": row.username_lc, "password_hash": row.password_hash}
