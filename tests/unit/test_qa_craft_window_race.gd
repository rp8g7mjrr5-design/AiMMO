extends TestCase
## The client_craft_window bot behaviour waits for a quiet pack before it presses Craft.
## An instant "/gather" from another behaviour paid a pine wood between the window's last
## s2c_inventory and the press, so the window predicted "1 pine wood and 1 ember sap" while
## the server said "1 ember sap" (flaky PR #111, 2026-11-23). These pin the guard down.

const Behaviour := preload("res://tests/bot_test/behaviours/client_craft_window.gd")
const BotScript := preload("res://tests/bot_test/bot.gd")


func test_pack_changing_lines() -> void:
	for line in ["/gather", "/gather pine", "/craft axe", "/craft ember axe", "/channel", "/channel stop"]:
		check(Behaviour.changes_pack(line), "%s can change the pack" % line)
	for line in ["/time", "/bag", "/who", "/skills", "/help", "hello there", "gather some wood"]:
		check(not Behaviour.changes_pack(line), "%s leaves the pack alone" % line)


func test_no_press_right_after_a_gather_line() -> void:
	var bot: Node = BotScript.new()
	var b = Behaviour.new()
	b.bot = bot
	bot.command_sent.connect(b._on_command_sent)
	bot.phase = "playing_2"
	bot.duration = 180.0
	bot.elapsed = 50.0
	check(b._quiet(), "quiet with nothing sent")
	bot.send_command("/gather pine")
	bot.elapsed += 1.0
	check_eq(bot._next_command(), "/gather pine")
	check(not b._quiet(), "not quiet just after /gather went out")
	bot.elapsed += 1.0
	check(not b._quiet(), "still not quiet 1 s later")
	bot.elapsed += Behaviour.QUIET_AFTER_GATHER
	check(b._quiet(), "quiet again once the pay has landed")
	bot.send_command("/bag")
	bot.elapsed += 1.0
	check_eq(bot._next_command(), "/bag")
	check(b._quiet(), "/bag does not hold a press back")
	bot.free()
