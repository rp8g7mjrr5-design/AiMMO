extends TestCase
## Fun metrics maths (tests/bot_test/fun_metrics.gd) and the bot harness's command queue,
## which keeps behaviours from tripping the shared command cooldown on each other.

const FunMetrics := preload("res://tests/bot_test/fun_metrics.gd")
const BotScript := preload("res://tests/bot_test/bot.gd")


func test_first_reward_counts_from_first_login() -> void:
	var m := FunMetrics.new()
	m.start_play(10.0)
	m.feedback(12.0)
	m.reward(17.5, 2)
	m.reward(20.0, 1)
	m.stop_play(70.0)
	var r := m.result()
	check_near(r.first_reward_s, 7.5, 0.001, "first reward")
	check_eq(r.rewards, 3)
	check_near(r.rewards_per_min, 3.0, 0.001, "3 items in 60 s of play")


func test_no_reward_is_minus_one() -> void:
	var m := FunMetrics.new()
	m.start_play(0.0)
	m.feedback(5.0)
	m.stop_play(30.0)
	check_near(m.result().first_reward_s, -1.0, 0.001)
	check_near(m.result().rewards_per_min, 0.0, 0.001)


func test_dead_time_is_longest_gap_and_skips_offline() -> void:
	var m := FunMetrics.new()
	m.start_play(0.0)
	m.feedback(5.0)
	m.feedback(25.0) # 20 s gap
	m.stop_play(30.0) # 5 s tail
	m.feedback(200.0) # offline: ignored
	m.start_play(100.0)
	m.feedback(112.0) # 12 s after the second login, not 82 s after the last feedback
	m.stop_play(140.0) # 28 s tail: the longest
	var r := m.result()
	check_near(r.longest_dead_s, 28.0, 0.001, "open tail counts up to the disconnect")
	check_near(r.longest_dead_from_s, 112.0, 0.001, "where it started, from first login")
	check_near(r.play_s, 70.0, 0.001, "30 s + 40 s of play")
	check_eq(r.feedback_events, 3, "the offline line is not counted")


func test_wait_runs_from_first_unanswered_action() -> void:
	var m := FunMetrics.new()
	m.start_play(0.0)
	m.act(10.0)
	m.act(12.0) # still waiting since 10
	m.feedback(13.5) # waited 3.5 s
	m.act(20.0)
	m.feedback(20.2)
	m.act(50.0) # never answered before the disconnect at 60
	m.stop_play(56.0)
	check_near(m.result().longest_wait_s, 6.0, 0.001, "unanswered action counts to the stop")
	var quiet := FunMetrics.new()
	quiet.start_play(0.0)
	quiet.stop_play(100.0)
	check_near(quiet.result().longest_wait_s, 0.0, 0.001, "wandering without acting is not waiting")
	check_near(quiet.result().longest_dead_s, 100.0, 0.001, "but it is dead time")


func test_craft_is_a_reward_and_a_loop() -> void:
	var m := FunMetrics.new()
	m.start_play(0.0)
	m.crafted(30.0, FunMetrics.items_in("You craft a stone axe. Ash and pine give more, and faster, with it in your pack."))
	m.stop_play(60.0)
	check_eq(m.result().loops_completed, 1)
	check_eq(m.result().rewards, 1)
	check_near(m.result().first_reward_s, 30.0, 0.001)


func test_server_lines() -> void:
	check_eq(FunMetrics.items_in("You gather 2 ash wood from the ember ash (6 in your pack)."), 2)
	check_eq(FunMetrics.items_in("You craft 4 planks (4 in your pack)."), 4)
	check_eq(FunMetrics.items_in("You craft a stone pickaxe. Stone gives more."), 1)
	check_eq(FunMetrics.items_in("This ember ash is spent."), 0)
	check(FunMetrics.is_notice("bot_3 has arrived."), "arrival is a notice")
	check(FunMetrics.is_notice("bot_3 has left."), "leaving is a notice")
	check(not FunMetrics.is_notice("You gather 2 stone (2 in your pack)."), "a gather is feedback")


func test_command_queue_spaces_lines_past_the_cooldown() -> void:
	var bot: Node = BotScript.new()
	var emitted: Array = []
	bot.command_sent.connect(func(text: String): emitted.append(text))
	var judged := []
	bot.send_command("/time")
	bot.send_command("/craft axe", func(): judged.append(bot.elapsed))
	bot.send_command("/bag")
	var times := []
	while bot.elapsed < 3.0:
		bot.elapsed += 0.05
		var text: String = bot._next_command()
		if text != "":
			times.append([text, bot.elapsed])
	check_eq(times.size(), 3, "all three sent: %s" % [times])
	if times.size() == 3:
		check_eq([times[0][0], times[1][0], times[2][0]], ["/time", "/craft axe", "/bag"], "in order")
		for i in range(1, 3):
			check(times[i][1] - times[i - 1][1] >= GameConfig.CHAT_COOLDOWN + 0.1, "gap %d is past the cooldown" % i)
		check_eq(judged.size(), 1, "on_sent ran once")
		if judged.size() == 1:
			check_near(judged[0], times[1][1], 0.001, "on_sent runs when the line goes out")
	check_eq(emitted, ["/time", "/craft axe", "/bag"], "command_sent for each")
	check_eq(bot.stats.commands_sent, 3)
	bot.free()


func test_gathering_seconds() -> void:
	var m := FunMetrics.new()
	m.start_play(0.0)
	m.gather_begun(10.0)
	m.gather_ended(13.0) # 3 s
	m.gather_begun(20.0)
	m.gather_begun(22.0) # restarted: 2 s counted, new one runs
	check_near(m.gather_time(25.0), 8.0, 0.001, "a running gather counts up to now")
	m.gather_ended(26.0)
	m.stop_play(60.0)
	var r := m.result()
	check_near(r.gather_s, 9.0, 0.001, "all gathering")
	for k in r:
		check(not str(k).contains("level"), "no level numbers: %s" % k)


func test_gather_stops_at_disconnect() -> void:
	var m := FunMetrics.new()
	m.start_play(0.0)
	m.gather_begun(5.0)
	m.stop_play(9.0) # hung up mid-gather: 4 s
	m.gather_ended(30.0) # offline: nothing more
	m.start_play(40.0)
	m.stop_play(50.0)
	check_near(m.result().gather_s, 4.0, 0.001)


func test_command_queue_is_bounded() -> void:
	var bot: Node = BotScript.new()
	for i in BotScript.MAX_QUEUED_COMMANDS + 2:
		bot.send_command("/time")
	check_eq(bot._commands.size(), BotScript.MAX_QUEUED_COMMANDS)
	check_eq(bot.failures.size(), 2, "overflow is a bot failure, not silent")
	bot.free()


func test_behaviours_send_commands_through_the_queue() -> void:
	var dir := "res://tests/bot_test/behaviours"
	for f in DirAccess.get_files_at(dir):
		if not f.ends_with(".gd"):
			continue
		var src := FileAccess.get_file_as_string(dir.path_join(f))
		check(not src.contains("c2s_chat"), "%s sends chat directly; use bot.send_command so the shared cooldown can't drop it" % f)


func test_behaviours_send_play_requests_through_the_bot() -> void:
	# The fun metrics time each press of E / Craft from bot.play_sent; a direct
	# net.play.<c2s>.rpc_id call would be a press nobody measures.
	var direct := RegEx.create_from_string("\\bc2s_\\w+\\.rpc")
	var dir := "res://tests/bot_test/behaviours"
	for f in DirAccess.get_files_at(dir):
		if not f.ends_with(".gd"):
			continue
		var src := FileAccess.get_file_as_string(dir.path_join(f))
		check(direct.search(src) == null, "%s calls a c2s_ RPC directly; use bot.send_play(method, args)" % f)


func test_send_play_offline_sends_nothing() -> void:
	var bot: Node = BotScript.new()
	var seen := []
	bot.play_sent.connect(func(method: String, _a: Array): seen.append(method))
	check(not bot.send_play("c2s_gather_start", [1]), "no peer, no send")
	check_eq(seen.size(), 0, "and no press is counted")
	check_eq(int(bot.stats.play_sent), 0)
	bot.free()


func test_rpc_reward_and_its_text_line_count_once() -> void:
	var m := FunMetrics.new()
	m.start_play(0.0)
	m.act(5.0) # pressed E
	m.feedback(5.05) # s2c_gather_begin
	m.reward(8.0, 2) # s2c_gather_result
	m.expect_echo("gather", 8.0, 2)
	var line := "You gather 2 ash wood from the ember ash (2 in your pack)."
	check(m.echo("gather", 8.0, FunMetrics.items_in(line)), "the text line after the RPC is its echo")
	check(not m.echo("gather", 8.0, 2), "an echo is dropped only once")
	m.stop_play(60.0)
	var r := m.result()
	check_eq(r.rewards, 2, "2 items, not 4")
	check_near(r.first_reward_s, 8.0, 0.001)
	check_near(r.longest_wait_s, 0.05, 0.001, "the press was answered by the gather bar")


func test_echo_needs_same_kind_count_and_time() -> void:
	var m := FunMetrics.new()
	m.start_play(0.0)
	m.expect_echo("gather", 10.0, 2)
	check(not m.echo("gather", 10.1, 3), "different count: a separate reward")
	check(not m.echo("craft", 10.1, 2), "different kind")
	check(not m.echo("gather", 10.0 + FunMetrics.ECHO_WINDOW + 0.1, 2), "too late: a /gather of its own")
	m.expect_echo("craft", 20.0, 1)
	check(m.echo("craft", 20.0, 1), "same kind and count")
	m.expect_echo("gather", 30.0, 1)
	m.expect_echo("gather", 31.0, 1) # the 30.0 one expires when this is added
	check(m.echo("gather", 31.2, 1), "the newer one is still there")
	check(not m.echo("gather", 31.3, 1), "each RPC drops one line")
	check(not m.echo("gather", 5.0, 1), "a line before the RPC is not its echo")


func test_dev_gather_text_alone_still_counts() -> void:
	# /gather (dev commands) answers with text only: no RPC, so nothing to echo.
	var m := FunMetrics.new()
	m.start_play(0.0)
	check(not m.echo("gather", 4.0, 1), "nothing expected")
	m.reward(4.0, 1)
	m.stop_play(60.0)
	check_eq(m.result().rewards, 1)


func test_swings_are_feedback_and_counted() -> void:
	# Protocol v7: a press of the attack button is an action (bot.play_sent); the server's
	# s2c_swing, s2c_attack_refused or s2c_swing_hits for us answers it.
	var m := FunMetrics.new()
	m.start_play(0.0)
	m.act(10.0)
	m.swing(10.05)
	m.swing_landed(10.6, false) # missed: still an answer
	m.act(20.0)
	m.swing_refused(20.1)
	m.act(30.0)
	m.swing(30.05)
	m.swing_landed(30.6, true)
	m.stop_play(40.0)
	var r := m.result()
	check_eq([r.swings, r.swings_refused, r.swings_hit, r.kills], [2, 1, 1, 0])
	check_near(r.longest_wait_s, 0.1, 0.001, "every press answered at once")
	check_eq(r.feedback_events, 5)
	m.swing(50.0) # offline
	check_eq(m.result().swings, 2, "nothing counts between stretches")


func test_kill_counts_once_and_its_drops_are_rewards() -> void:
	var m := FunMetrics.new()
	m.start_play(0.0)
	# The server sends one s2c_gather_result per drop, in Wildlife.drops order.
	for d in Wildlife.drops("grazer"):
		if FunMetrics.is_kill_drop(str(d[0])):
			m.kill(12.0)
		m.reward(12.0, int(d[1]))
	m.stop_play(60.0)
	var r := m.result()
	check_eq(r.kills, 1, "one grazer, one kill")
	check_eq(r.rewards, 3, "+1 hide, +2 raw meat")
	check_near(r.first_reward_s, 12.0, 0.001, "a kill can be the first reward")


func test_no_gather_haul_looks_like_a_kill() -> void:
	check(FunMetrics.is_kill_drop(str(Wildlife.drops("grazer")[0][0])), "the hide is a kill drop")
	check(not FunMetrics.is_kill_drop(str(Wildlife.drops("grazer")[1][0])), "the meat (second drop) is not")
	var hauls := 0
	for table in [ResourceNodes.KINDS, ResourceNodes.TIER2]:
		for kind in table:
			hauls += 1
			var item := str(table[kind].item)
			check(not FunMetrics.is_kill_drop(item), "%s is a gather haul, not a kill" % item)
	check(hauls >= 6, "read every node kind (%d)" % hauls)
