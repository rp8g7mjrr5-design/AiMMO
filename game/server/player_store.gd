class_name PlayerStore
extends RefCounted
## Storage interface for accounts and characters. PgStore is used whenever DATABASE_URL
## is set (production, CI). JsonStore is a local development fallback.

var last_error := ""


func open() -> bool:
	return true


func close() -> void:
	pass


## Returns {} when there is no such account.
func find_account(_username_lc: String) -> Dictionary:
	return {}


## Returns the new account, or {} on failure (e.g. the name was taken a moment ago).
func create_account(_username: String, _username_lc: String, _password_hash: String) -> Dictionary:
	return {}


func touch_login(_account_id: int) -> void:
	pass


## Returns the account's character, creating it on first login.
func load_or_create_character(_account: Dictionary) -> Dictionary:
	return {}


func save_character(_ch: Dictionary) -> bool:
	return false


## Monthly wipes (WorldWipe, migration 0005). The world this server runs now: {id, seed,
## gen_version, size_m, wipes_at}, or {} before the first one.
func current_world() -> Dictionary:
	return {}


## Records a new world (cfg as WorldGen.config gives it) ending at `wipes_at` (Unix seconds),
## marks the one before it wiped, and returns the new one, or {} on failure.
func begin_world(_cfg: Dictionary, _wipes_at: int) -> Dictionary:
	return {}


## Keeps what `ch` had on world `world_id` (position and pack) before a wipe clears it.
## Never deletes anything.
func archive_wipe(_ch: Dictionary, _world_id: int) -> bool:
	return false


## The archived rows for character `character_id`, oldest first (tests and support).
func wipe_archive(_character_id: int) -> Array:
	return []


## Returns {} if not found. Used by tests to verify persistence.
func find_character_by_name(_name: String) -> Dictionary:
	return {}


static func create_from_env(data_dir: String) -> PlayerStore:
	var url := OS.get_environment("DATABASE_URL")
	if url != "":
		var pg := PgStore.new()
		pg.url = url
		return pg
	var js := JsonStore.new()
	js.path = data_dir.path_join("aimmo_dev_store.json")
	return js
