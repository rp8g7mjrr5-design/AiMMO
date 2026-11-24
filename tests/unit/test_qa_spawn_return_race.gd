extends TestCase
## client_spawn_return notes the "Return to Spawn Meadow" ask the moment it goes out
## (bot.play_sent), so an answer that arrives before the behaviour's next on_play still
## closes it. Before, it watched gameplay_roster_v5's meta on its next frame: a fast answer
## was handled first, the ask was noted after it, and 5 s later the bot failed with "no answer
## within 5000 ms" although the server had answered (bot test, qa 2026-11-24).

const Behaviour := preload("res://tests/bot_test/behaviours/client_spawn_return.gd")
const BotScript := preload("res://tests/bot_test/bot.gd")


func _pair() -> Array:
	var bot: Node = BotScript.new()
	var b = Behaviour.new()
	b.bot = bot
	b.name = "client_spawn_return"
	bot.play_sent.connect(b._on_play_sent)
	bot.phase = "playing_1"
	bot.elapsed = 20.0
	return [bot, b]


func test_answer_before_the_next_frame_closes_the_ask() -> void:
	var pb := _pair()
	var bot: Node = pb[0]
	var b = pb[1]
	bot.play_sent.emit("c2s_unstuck", [])
	b._on_unstuck(true, "Back in Spawn Meadow.", GameConfig.UNSTUCK_COOLDOWN) # same frame
	for i in 10:
		bot.elapsed += 1.0
		b.on_play(1.0)
	check_eq(Array(bot.failures), [], "a fast answer is still an answer")
	check_eq(b._answers, 1)
	check_eq(b._ret.asks, 1)
	bot.free()


func test_a_real_silence_still_fails() -> void:
	var pb := _pair()
	var bot: Node = pb[0]
	var b = pb[1]
	bot.play_sent.emit("c2s_unstuck", [])
	for i in 7:
		bot.elapsed += 1.0
		b.on_play(1.0)
	check_eq(bot.failures.size(), 1, "an ask nobody answers fails once")
	bot.free()


func test_other_presses_are_not_asks() -> void:
	var pb := _pair()
	var bot: Node = pb[0]
	var b = pb[1]
	bot.play_sent.emit("c2s_craft", ["torch"])
	bot.play_sent.emit("c2s_gather_start", [3])
	check_eq(b._ret.asks, 0)
	bot.free()
