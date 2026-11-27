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
		return _with_skills(_with_inventory(CharacterData.from_pg_row(rows[0])))
	var ch := CharacterData.new_for(account)
	var ins: Variant = _q(
		"INSERT INTO characters (account_id, name, pos_x, pos_y, pos_z, yaw, appearance_seed) VALUES ($1, $2, $3, $4, $5, $6, $7) RETURNING *",
		[ch.account_id, ch.name, ch.x, ch.y, ch.z, ch.yaw, ch.appearance_seed])
	if ins == null or ins.is_empty():
		return {}
	return CharacterData.from_pg_row(ins[0])


func save_character(ch: Dictionary) -> bool:
	var r: Variant = _q(
		"UPDATE characters SET pos_x = $2, pos_y = $3, pos_z = $4, yaw = $5, appearance = $6, world_id = $7, hunger = $8, pack_layout = $9, updated_at = now() WHERE id = $1",
		[ch.id, ch.x, ch.y, ch.z, ch.yaw, Appearance.to_json(ch.get("look", {})), int(ch.get("world_id", 0)), Needs.hunger_of(ch), PackGrid.to_json(ch.get("pack", []))])
	if r == null:
		return false
	if not _save_inventory(int(ch.id), Inventory.normalize(ch.get("inventory", {}))):
		return false
	return _save_skills(int(ch.id), RetiredSkills.normalize(ch.get("skills", {})))


func find_character_by_name(char_name: String) -> Dictionary:
	var rows: Variant = _q("SELECT * FROM characters WHERE lower(name) = lower($1) ORDER BY id LIMIT 1", [char_name])
	if rows == null or rows.is_empty():
		return {}
	return _with_skills(_with_inventory(CharacterData.from_pg_row(rows[0])))


## Fills ch.skills (old XP from the retired leveling system, see RetiredSkills) from
## character_skills (migration 0003). Returns {} if the query fails
## (or `ch` is already {}), so a character is never handed out, and later saved, with
## skills that failed to load.
func _with_skills(ch: Dictionary) -> Dictionary:
	if ch.is_empty():
		return {}
	var rows: Variant = _q("SELECT skill, xp FROM character_skills WHERE character_id = $1", [ch.id])
	if rows == null:
		return {}
	var skills := {}
	for r in rows:
		skills[r.skill] = r.xp
	ch.skills = RetiredSkills.normalize(skills)
	return ch


## Writes the old XP back unchanged (nothing earns XP any more). Never deletes rows, never lowers a
## stored total (GREATEST), so a stale copy of a character can't take XP away.
func _save_skills(character_id: int, skills: Dictionary) -> bool:
	if skills.is_empty():
		return true
	var values := PackedStringArray()
	var params: Array = [character_id]
	for skill in skills:
		params.append(skill)
		params.append(int(skills[skill]))
		values.append("($1, $%d, $%d, now())" % [params.size() - 1, params.size()])
	var r: Variant = _q(
		"INSERT INTO character_skills (character_id, skill, xp, updated_at) VALUES %s ON CONFLICT (character_id, skill) DO UPDATE SET xp = GREATEST(character_skills.xp, EXCLUDED.xp), updated_at = now()" % ", ".join(values),
		params)
	return r != null


## Fills ch.inventory from inventory_items. Returns {} if the query fails, so a character is
## never handed out (and later saved) with a pack that failed to load.
func _with_inventory(ch: Dictionary) -> Dictionary:
	var rows: Variant = _q("SELECT item, qty FROM inventory_items WHERE character_id = $1", [ch.id])
	if rows == null:
		return {}
	var inv := {}
	for r in rows:
		inv[r.item] = r.qty
	ch.inventory = Inventory.normalize(inv)
	Inventory.convert_retired(ch.inventory) # ember items -> grounded ones (Inventory.RETIRED)
	return ch


## Upserts every item in the pack, zeros included (see Inventory), in one statement.
## Never deletes rows.
func _save_inventory(character_id: int, inv: Dictionary) -> bool:
	if inv.is_empty():
		return true
	var values := PackedStringArray()
	var params: Array = [character_id]
	for item in inv:
		params.append(item)
		params.append(int(inv[item]))
		values.append("($1, $%d, $%d, now())" % [params.size() - 1, params.size()])
	var r: Variant = _q(
		"INSERT INTO inventory_items (character_id, item, qty, updated_at) VALUES %s ON CONFLICT (character_id, item) DO UPDATE SET qty = EXCLUDED.qty, updated_at = now()" % ", ".join(values),
		params)
	return r != null


func current_world() -> Dictionary:
	var rows: Variant = _q("SELECT id, seed, gen_version, size_m, wipes_at FROM worlds ORDER BY id DESC LIMIT 1")
	if rows == null or rows.is_empty():
		return {}
	return _world(rows[0])


func begin_world(cfg: Dictionary, wipes_at: int) -> Dictionary:
	if _q("UPDATE worlds SET wiped_at = now() WHERE wiped_at IS NULL") == null:
		return {}
	var rows: Variant = _q("INSERT INTO worlds (seed, gen_version, size_m, wipes_at) VALUES ($1, $2, $3, $4) RETURNING id, seed, gen_version, size_m, wipes_at",
		[int(cfg.get("seed", 0)), int(cfg.get("gen_version", 0)), float(cfg.get("size_m", 0.0)), wipes_at])
	if rows == null or rows.is_empty():
		return {}
	return _world(rows[0])


func archive_wipe(ch: Dictionary, world_id: int) -> bool:
	return _q("INSERT INTO wipe_archive (character_id, world_id, pos_x, pos_y, pos_z, inventory) VALUES ($1, $2, $3, $4, $5, $6)",
		[ch.id, world_id, ch.x, ch.y, ch.z, JSON.stringify(Inventory.normalize(ch.get("inventory", {})))]) != null


func wipe_archive(character_id: int) -> Array:
	var rows: Variant = _q("SELECT world_id, pos_x, pos_y, pos_z, inventory FROM wipe_archive WHERE character_id = $1 ORDER BY id", [character_id])
	if rows == null:
		return []
	var out: Array = []
	for r in rows:
		out.append({"world_id": int(r.world_id), "x": float(r.pos_x), "y": float(r.pos_y), "z": float(r.pos_z), "inventory": Inventory.normalize(JSON.parse_string(str(r.inventory)))})
	return out


func _world(row: Dictionary) -> Dictionary:
	return {"id": int(row.id), "seed": int(row.seed), "gen_version": int(row.gen_version), "size_m": float(row.size_m), "wipes_at": int(row.wipes_at)}


func _account(row: Dictionary) -> Dictionary:
	return {"id": int(row.id), "username": row.username, "username_lc": row.username_lc, "password_hash": row.password_hash}
