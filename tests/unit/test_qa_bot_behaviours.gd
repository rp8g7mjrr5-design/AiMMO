extends TestCase
## The bot-test behaviour hook: every behaviour loads, bad ones are reported, and the
## qa snapshot-flow behaviour catches a stalled snapshot stream.

const BotBehaviour := preload("res://tests/bot_test/bot_behaviour.gd")


class FakeBot extends Node:
	var phase := "playing_1"
	var elapsed := 0.0
	var failures: PackedStringArray = []

	func _fail(msg: String) -> void:
		failures.append(msg)


func test_every_shipped_behaviour_loads() -> void:
	var loaded: Array = BotBehaviour.load_all()
	check_eq(loaded[1].size(), 0, "load errors %s" % [loaded[1]])
	var names := []
	for b in loaded[0]:
		names.append(b.name)
		check(BotBehaviour._extends(b.get_script(), BotBehaviour), "%s extends the base" % b.name)
	check(names.has("qa_snapshot_flow"), "qa_snapshot_flow is loaded, got %s" % [names])
	var sorted := names.duplicate()
	sorted.sort()
	check_eq(names, sorted, "behaviours load in file-name order")


func test_missing_dir_is_empty() -> void:
	var loaded: Array = BotBehaviour.load_all("res://tests/bot_test/no_such_dir")
	check_eq(loaded[0].size(), 0)
	check_eq(loaded[1].size(), 0)


func test_bad_behaviour_is_reported() -> void:
	var dir := "user://qa_behaviour_test"
	DirAccess.make_dir_recursive_absolute(dir)
	var good := FileAccess.open(dir.path_join("a_good.gd"), FileAccess.WRITE)
	good.store_string('extends "res://tests/bot_test/bot_behaviour.gd"\n')
	good.close()
	var bad := FileAccess.open(dir.path_join("b_bad.gd"), FileAccess.WRITE)
	bad.store_string("extends RefCounted\n")
	bad.close()
	var loaded: Array = BotBehaviour.load_all(dir)
	check_eq(loaded[0].size(), 1, "only the good behaviour loads")
	check_eq(loaded[1].size(), 1, "the bad one is an error")
	if loaded[1].size() == 1:
		check(loaded[1][0].find("b_bad.gd") != -1, "error names the file")
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	DirAccess.remove_absolute(dir)


func _run_flow(snapshot_every: float, play_s: float) -> Array:
	var script: Script = load("res://tests/bot_test/behaviours/qa_snapshot_flow.gd")
	var b = script.new()
	var bot := FakeBot.new()
	b.bot = bot
	b.name = "qa_snapshot_flow"
	b.on_login(false, {})
	var dt := 0.05
	var since := 0.0
	var tick := 0
	while bot.elapsed < play_s:
		bot.elapsed += dt
		since += dt
		b.on_play(dt)
		if since >= snapshot_every - 0.0001:
			since = 0.0
			tick += 1
			b.on_snapshot(tick, [])
	b.on_finish()
	var out := [bot.failures, b.stats]
	bot.free()
	return out


func test_snapshot_flow_passes_at_tick_rate() -> void:
	var r := _run_flow(GameConfig.TICK_DT, 30.0)
	check_eq(r[0].size(), 0, "healthy stream has no failures: %s" % [r[0]])
	check_near(r[1].snapshot_rate, GameConfig.TICK_RATE, 1.5, "rate")


func test_snapshot_flow_catches_a_stall() -> void:
	var r := _run_flow(8.0, 30.0)
	check(r[0].size() >= 1, "a stream with 8s gaps fails")
	check(r[1].max_gap_s >= 7.9, "max gap recorded, got %s" % r[1].max_gap_s)
