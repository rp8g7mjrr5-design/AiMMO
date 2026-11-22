extends RefCounted
## Base class for pluggable bot-test behaviours.
##
## Drop a script in tests/bot_test/behaviours/<stream>_<what>.gd that does
## `extends "res://tests/bot_test/bot_behaviour.gd"` and overrides any of the hooks
## below. Every bot in the bot test loads every behaviour in that folder, so a stream
## can make bots use its new feature without editing bot.gd.
##
## Inside a hook you can use:
##   bot            the bot node (bot.net for RPCs and signals, bot.my_pos, bot.my_id,
##                  bot.bot_name, bot.rng for deterministic randomness, bot.elapsed)
##   fail(msg)      record a failure; the bot test fails if any behaviour fails
##   stat(k, v)     record a stat, reported under stats.behaviours.<name>.<k>
##
## Keep behaviours deterministic (use bot.rng) and cheap: they run on 8+ bots at once.
## Movement belongs to bot.gd; a behaviour that needs to stand still can set
## bot.move = Vector2.ZERO inside on_play.

const DIR := "res://tests/bot_test/behaviours"

var bot: Node
var name := ""
var stats := {}


## Called once per bot after it has parsed its args, before it connects.
## `net` is the shared Net node, so this is the place to connect to its signals.
func setup(_net: Node) -> void:
	pass


## Called after every successful login. `reconnect` is true for the second login.
func on_login(_reconnect: bool, _character: Dictionary) -> void:
	pass


## Called every frame while the bot is playing (both play phases).
func on_play(_delta: float) -> void:
	pass


## Called for every new snapshot, after bot.gd has done its own checks.
func on_snapshot(_tick: int, _entries: Array) -> void:
	pass


## Called once just before the bot writes its verdict. Assert end-of-run expectations here.
func on_finish() -> void:
	pass


func fail(msg: String) -> void:
	bot.call("_fail", "[%s] %s" % [name, msg])


func stat(key: String, value: Variant) -> void:
	stats[key] = value


## Loads every behaviour script in `dir`, sorted by file name. Returns
## [behaviours: Array, errors: PackedStringArray]. A script that fails to load or does
## not extend this base is reported as an error rather than silently skipped.
static func load_all(dir: String = DIR) -> Array:
	var out: Array = []
	var errors := PackedStringArray()
	if not DirAccess.dir_exists_absolute(dir):
		return [out, errors]
	var files := PackedStringArray()
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			files.append(f)
	files.sort()
	var base: Script = load("res://tests/bot_test/bot_behaviour.gd")
	for f in files:
		var script: Script = load(dir.path_join(f))
		if script == null or not script.can_instantiate():
			errors.append("behaviour %s failed to load" % f)
			continue
		var inst = script.new()
		if not (inst is RefCounted) or not _extends(script, base):
			errors.append("behaviour %s does not extend bot_behaviour.gd" % f)
			continue
		inst.name = f.get_basename()
		out.append(inst)
	return [out, errors]


static func _extends(script: Script, base: Script) -> bool:
	var s := script
	while s != null:
		if s == base:
			return true
		s = s.get_base_script()
	return false
