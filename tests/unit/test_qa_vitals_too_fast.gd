extends TestCase
## gameplay_vitals only takes a "Slow down" (ChatCommands.TOO_FAST) as its own once its line
## has gone out. Before, a TOO_FAST for another behaviour's line, arriving while the vitals
## /vitals still sat in the bot's queue, queued a second /vitals; its spare answer ("70/100,
## in combat") then landed on the HEAL step and failed the 45 s smoke run on a busy CI box
## (PR #175, qa 2026-11-24).

const Behaviour := preload("res://tests/bot_test/behaviours/gameplay_vitals.gd")
const BotScript := preload("res://tests/bot_test/bot.gd")

const HURT := "You take 30 damage. Health 70/100, stamina 100/100, in combat."
const HIT := "Health 70/100, stamina 100/100, in combat."
const HEALED := "Health 70/100, stamina 100/100, out of combat." ## held: natural healing stops at half


func _pair() -> Array:
	var bot: Node = BotScript.new()
	var b = Behaviour.new()
	b.bot = bot
	b.name = "gameplay_vitals"
	bot.phase = "playing_1"
	bot.elapsed = 20.0
	b._step = Behaviour.Step.HURT
	b._next_at = 0.0
	return [bot, b]


## One frame: the behaviour plays, then the bot sends whatever is due. Returns the line sent.
func _frame(bot: Node, b, dt: float = 0.1) -> String:
	bot.elapsed += dt
	b.on_play(dt)
	return bot._next_command()


func _queued_lines(bot: Node) -> Array:
	var out: Array = []
	for c in bot._commands:
		out.append(c[0])
	return out


func _run_until_sent(bot: Node, b, line: String) -> void:
	for i in 40:
		if _frame(bot, b) == line:
			return
	check(false, "%s never went out" % line)


func test_someone_elses_too_fast_does_not_queue_a_second_line() -> void:
	var pb := _pair()
	var bot: Node = pb[0]
	var b = pb[1]
	_run_until_sent(bot, b, "/hurt 30")
	b._on_system(HURT)
	bot._last_command_at = bot.elapsed # the next line waits out the gap in the queue
	b.on_play(0.0)
	check_eq(_queued_lines(bot), ["/vitals"], "READ queued its /vitals")
	b._on_system(ChatCommands.TOO_FAST) # another behaviour's line was dropped
	for i in 10: # well past the old 0.6 s resend
		bot.elapsed += 0.2
		b.on_play(0.2)
	check_eq(_queued_lines(bot), ["/vitals"], "still one /vitals: the TOO_FAST wasn't ours")
	_run_until_sent(bot, b, "/vitals")
	b._on_system(HIT)
	check_eq(b._step, Behaviour.Step.HEAL)
	for i in 120: # past the fight and the regen wait
		_frame(bot, b)
		if b._step != Behaviour.Step.HEAL:
			break
		if b._sent_at >= 0.0 and b._sent_at <= bot.elapsed:
			b._on_system(HEALED)
	check_eq(Array(bot.failures), [], "the check passes with one answer per line")
	check_eq(b.heals, 1)
	check_eq(b._step, Behaviour.Step.DOWN)
	bot.free()


func test_our_own_too_fast_still_resends() -> void:
	var pb := _pair()
	var bot: Node = pb[0]
	var b = pb[1]
	_run_until_sent(bot, b, "/hurt 30")
	b._on_system(ChatCommands.TOO_FAST) # ours went out and was dropped
	check_eq(b._tries, 0, "a TOO_FAST doesn't spend a try")
	_run_until_sent(bot, b, "/hurt 30")
	check_eq(Array(bot.failures), [])
	bot.free()


func test_a_replaced_send_does_not_start_the_clock() -> void:
	var pb := _pair()
	var bot: Node = pb[0]
	var b = pb[1]
	bot._last_command_at = bot.elapsed
	b.on_play(0.0) # queues /hurt 30 behind the gap
	var first: Callable = bot._commands[0][1]
	b._send("/vitals") # a later send replaces it
	var queued_at: float = b._sent_at
	first.call() # the old line goes out
	check_eq(b._sent_at, queued_at, "only the latest send's going out starts the clock")
	bot.free()
