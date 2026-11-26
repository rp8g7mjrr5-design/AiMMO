class_name JsonStore
extends PlayerStore
## Local development storage in a single JSON file. Not for production: no concurrency,
## whole-file rewrites. Writes go to a temp file first and are then renamed, so a crash
## mid-write never corrupts the existing file.

var path := ""
var _data := {"accounts": [], "characters": [], "next_id": 1, "worlds": [], "wipe_archive": []}


func open() -> bool:
	if FileAccess.file_exists(path):
		var txt := FileAccess.get_file_as_string(path)
		var json := JSON.new()
		var parsed: Variant = json.data if json.parse(txt) == OK else null
		if typeof(parsed) != TYPE_DICTIONARY:
			last_error = "could not parse %s; refusing to overwrite it" % path
			return false
		_data.merge(parsed, true)
	return true


func _flush() -> bool:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		last_error = "could not write %s" % tmp
		return false
	f.store_string(JSON.stringify(_data, "  "))
	f.close()
	return DirAccess.rename_absolute(tmp, path) == OK


func _next_id() -> int:
	var id := int(_data.next_id)
	_data.next_id = id + 1
	return id


func find_account(username_lc: String) -> Dictionary:
	for a in _data.accounts:
		if a.username_lc == username_lc:
			var out: Dictionary = a.duplicate()
			out.id = int(out.id)
			return out
	return {}


func create_account(username: String, username_lc: String, password_hash: String) -> Dictionary:
	if not find_account(username_lc).is_empty():
		return {}
	var a := {"id": _next_id(), "username": username, "username_lc": username_lc, "password_hash": password_hash}
	_data.accounts.append(a)
	if not _flush():
		return {}
	return a.duplicate()


func load_or_create_character(account: Dictionary) -> Dictionary:
	for c in _data.characters:
		if int(c.account_id) == int(account.id):
			return CharacterData.normalize(c)
	var ch := CharacterData.new_for(account)
	ch.id = _next_id()
	_data.characters.append(ch.duplicate())
	if not _flush():
		return {}
	return ch


func save_character(ch: Dictionary) -> bool:
	for i in _data.characters.size():
		if int(_data.characters[i].id) == int(ch.id):
			var merged: Dictionary = _data.characters[i].duplicate()
			merged.merge(ch, true)
			_data.characters[i] = merged
			return _flush()
	return false


func find_character_by_name(char_name: String) -> Dictionary:
	for c in _data.characters:
		if str(c.name).to_lower() == char_name.to_lower():
			return CharacterData.normalize(c)
	return {}


func current_world() -> Dictionary:
	if _data.worlds.is_empty():
		return {}
	return _world(_data.worlds[_data.worlds.size() - 1])


func begin_world(cfg: Dictionary, wipes_at: int) -> Dictionary:
	var now := int(Time.get_unix_time_from_system())
	if not _data.worlds.is_empty():
		_data.worlds[_data.worlds.size() - 1].wiped_at = now
	var w := {"id": _next_id(), "seed": int(cfg.get("seed", 0)), "gen_version": int(cfg.get("gen_version", 0)),
		"size_m": float(cfg.get("size_m", 0.0)), "wipes_at": wipes_at, "started_at": now, "wiped_at": 0}
	_data.worlds.append(w)
	if not _flush():
		return {}
	return _world(w)


func archive_wipe(ch: Dictionary, world_id: int) -> bool:
	_data.wipe_archive.append({"character_id": int(ch.id), "world_id": world_id, "x": ch.x, "y": ch.y, "z": ch.z,
		"inventory": Inventory.normalize(ch.get("inventory", {})), "archived_at": int(Time.get_unix_time_from_system())})
	return _flush()


func wipe_archive(character_id: int) -> Array:
	var out: Array = []
	for a in _data.wipe_archive:
		if int(a.character_id) == character_id:
			out.append({"world_id": int(a.world_id), "x": float(a.x), "y": float(a.y), "z": float(a.z), "inventory": Inventory.normalize(a.inventory)})
	return out


func _world(w: Dictionary) -> Dictionary:
	return {"id": int(w.id), "seed": int(w.seed), "gen_version": int(w.gen_version), "size_m": float(w.size_m), "wipes_at": int(w.wipes_at)}
