extends "res://tests/bot_test/bot_behaviour.gd"
## Bot behaviour (qa): fun metrics. Watches what the server tells this bot while the other
## behaviours play the real loop (walk to a node, gather, craft), and records time to first
## reward, longest dead time, rewards per minute, loops completed, and time (and seconds of
## gathering) to the first level-up (see fun_metrics.gd).
## run_bot_test.py gathers every bot's numbers into a table and fun_metrics.json, and with
## --fun-check holds them to tests/bot_test/fun_baseline.json.
##
## Every bot-test account is new, so every bot is a fresh player.

const FunMetrics := preload("res://tests/bot_test/fun_metrics.gd")

var m := FunMetrics.new()
var _last_play := -1.0 ## bot.elapsed on the last frame this bot was playing


func setup(net: Node) -> void:
	net.system_message.connect(_on_system)
	# Hooked on the send itself: on localhost the answer can arrive before the next frame.
	bot.command_sent.connect(func(_text: String): m.act(bot.elapsed))
	# Time spent gathering, for "first level-up within 90 s of gathering" (Milestone 1).
	net.gather_begun.connect(func(peer: int, _node: int, _secs: float):
		if peer == bot.my_id:
			m.gather_begun(bot.elapsed))
	net.gather_ended.connect(func(peer: int, _node: int, _reason: String):
		if peer == bot.my_id:
			m.gather_ended(bot.elapsed))


func on_login(_reconnect: bool, _character: Dictionary) -> void:
	if _last_play >= 0.0:
		m.stop_play(_last_play)
	m.start_play(bot.elapsed)
	_last_play = bot.elapsed


func on_play(_delta: float) -> void:
	_last_play = bot.elapsed


func _on_system(text: String) -> void:
	if FunMetrics.is_notice(text):
		return
	var t: float = bot.elapsed
	if FunMetrics.is_level_up(text):
		m.level_up(t)
		return
	var items := FunMetrics.items_in(text)
	if text.begins_with("You craft"):
		m.crafted(t, items)
	elif items > 0:
		m.reward(t, items)
	else:
		m.feedback(t)


func on_finish() -> void:
	if _last_play >= 0.0:
		m.stop_play(_last_play)
	var r := m.result()
	for k in r:
		stat(k, r[k])
