extends "res://tests/bot_test/bot_behaviour.gd"
## Bot behaviour (qa): fun metrics. Watches what the server tells this bot while the other
## behaviours play the real loop (walk to a node, gather, craft), and records time to first
## reward, longest dead time, rewards per minute, loops completed and seconds of gathering
## (see fun_metrics.gd).
## run_bot_test.py gathers every bot's numbers into a table and fun_metrics.json, and with
## --fun-check holds them to tests/bot_test/fun_baseline.json.
##
## Every bot-test account is new, so every bot is a fresh player. Numbers come from the
## protocol v3/v5/v7/v8/v9 messages (gather bar, haul, craft result, Return to Spawn Meadow,
## swings, kills, the saved-look echo, a campfire set down)
## and from the text answers to dev commands; see fun_metrics.gd for how the two are kept from double counting.

const FunMetrics := preload("res://tests/bot_test/fun_metrics.gd")

var m := FunMetrics.new()
var _last_play := -1.0 ## bot.elapsed on the last frame this bot was playing


func setup(net: Node) -> void:
	net.system_message.connect(_on_system)
	# Hooked on the send itself: on localhost the answer can arrive before the next frame.
	bot.command_sent.connect(func(text: String): m.act(bot.elapsed, text))
	# Pressing E, walking a cancel, pressing Craft (protocol v3) are actions too.
	bot.play_sent.connect(func(method: String, _args: Array): m.act(bot.elapsed, method))
	# Our gather bar starting or stopping is the game answering; also times the gathering.
	net.gather_begun.connect(func(peer: int, _node: int, _secs: float):
		if peer == bot.my_id:
			m.feedback(bot.elapsed)
			m.gather_begun(bot.elapsed))
	net.gather_ended.connect(func(peer: int, _node: int, _reason: String):
		if peer == bot.my_id:
			m.feedback(bot.elapsed)
			m.gather_ended(bot.elapsed))
	net.gather_result.connect(_on_gather_result)
	net.craft_result.connect(_on_craft_result)
	# Return to Spawn Meadow (protocol v5): its answer is the game responding to the press.
	net.unstuck_result.connect(func(_ok: bool, _text: String, _wait: float): m.feedback(bot.elapsed))
	# Saving a look (protocol v8) is answered by s2c_look naming us; setting a campfire down
	# (protocol v9) by s2c_place_result. Both are the game answering the press. Until
	# 2026-11-26 the XP and level lines of the bots' long gathering covered these by chance;
	# with levels gone the bots stop sooner and a look saved after the gathering looked like
	# a press nobody answered (CI on c810000: 31 s).
	net.look_changed.connect(func(peer: int, _look: Dictionary):
		if peer == bot.my_id:
			m.feedback(bot.elapsed))
	net.place_result.connect(func(_item: String, _ok: bool, _reason: String, _text: String): m.feedback(bot.elapsed))
	# Arranging the grid pack (protocol v13): the server answers every c2s_pack_move with
	# s2c_pack, moved or snapped back. Without this a drag looked like a press nobody
	# answered (red main on 13ae8d1: every bot's longest wait followed c2s_pack_move).
	net.pack_layout_changed.connect(func(_places: Array): m.feedback(bot.elapsed))
	# Combat (protocol v7): a swing beginning, refused, or its blow landing (the swinger
	# always hears back, hit or miss) answers the press; a kill is counted from its drops.
	net.swing_begun.connect(func(peer: int, _weapon: String, _kind: String, _secs: float):
		if peer == bot.my_id:
			m.swing(bot.elapsed))
	net.attack_refused.connect(func(_kind: String, _reason: String): m.swing_refused(bot.elapsed))
	net.swing_landed.connect(func(peer: int, _kind: String, ids: Array):
		if peer == bot.my_id:
			m.swing_landed(bot.elapsed, not ids.is_empty()))


func on_login(_reconnect: bool, _character: Dictionary) -> void:
	if _last_play >= 0.0:
		m.stop_play(_last_play)
	m.start_play(bot.elapsed)
	_last_play = bot.elapsed


func on_play(_delta: float) -> void:
	_last_play = bot.elapsed


func _on_gather_result(item: String, count: int) -> void:
	if FunMetrics.is_kill_drop(item):
		m.kill(bot.elapsed)
	m.reward(bot.elapsed, count)
	m.expect_echo("gather", bot.elapsed, count)


## Answer to a Craft press in the window (c2s_craft): no text line follows it.
func _on_craft_result(_recipe: String, ok: bool, text: String) -> void:
	if ok:
		m.crafted(bot.elapsed, FunMetrics.items_in(text))
	else:
		m.feedback(bot.elapsed)


func _on_system(text: String) -> void:
	if FunMetrics.is_notice(text):
		return
	var t: float = bot.elapsed
	var items := FunMetrics.items_in(text)
	if text.begins_with("You craft"):
		m.crafted(t, items)
	elif items > 0:
		if not m.echo("gather", t, items):
			m.reward(t, items)
	else:
		m.feedback(t)


func on_finish() -> void:
	if _last_play >= 0.0:
		m.stop_play(_last_play)
	var r := m.result()
	for k in r:
		stat(k, r[k])
