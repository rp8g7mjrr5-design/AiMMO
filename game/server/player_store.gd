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
