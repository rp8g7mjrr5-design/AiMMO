extends TestCase
## Client chat polish: in-game timestamps, safe BBCode, the idle fade, and the line cap.

const D := WorldClock.DAY_SECONDS


func _seconds_at(frac: float, day: int = 1) -> float:
	return (day - 1) * D + (frac - WorldClock.START_FRACTION) * D


func test_timestamps_follow_the_world_clock() -> void:
	check_eq(ChatFeed.timestamp(_seconds_at(0.5, 3)), "12:00", "noon")
	check_eq(ChatFeed.timestamp(_seconds_at(0.25)), "06:00", "sunrise of day 1 (world second 0)")
	check_eq(ChatFeed.timestamp(_seconds_at(0.0, 4) - 0.001), "23:59", "never 24:00 before midnight")
	check_eq(ChatFeed.timestamp(_seconds_at(0.0, 4)), "00:00", "midnight")
	check_eq(ChatFeed.timestamp(NAN), "--:--", "broken clock")
	# Same hour and minute as the time dial at every quarter hour of a day.
	for i in 96:
		var s := _seconds_at(i / 96.0 + 0.0001, 2)
		check(TimeDial.state(s).text.contains(ChatFeed.timestamp(s)), "matches the dial at step %d" % i)


func test_lines_escape_bbcode() -> void:
	check_eq(ChatFeed.escape("a[b]c"), "a[lb]b[rb]c", "brackets escaped")
	check_eq(ChatFeed.escape("[color=red]x[/color]"), "[lb]color=red[rb]x[lb]/color[rb]", "tags neutralised")
	check_eq(ChatFeed.escape("plain"), "plain", "plain text unchanged")
	var line := ChatFeed.chat_line(_seconds_at(0.5), "Ash", "[img]res://icon.svg[/img] hi")
	check(not line.contains("[img]"), "no live img tag: %s" % line)
	check(line.contains("12:00"), "timestamp in chat line")
	check(line.contains("Ash"), "name in chat line")
	var sys := ChatFeed.system_line(_seconds_at(0.5), "3 online: Ash, Bryn, Cole.")
	check(sys.contains("[i]3 online: Ash, Bryn, Cole.[/i]"), "system line italic: %s" % sys)
	# What the label shows is exactly the player's text, brackets and all.
	var label := RichTextLabel.new()
	label.bbcode_enabled = true
	label.append_text(ChatFeed.chat_line(_seconds_at(0.5), "Ash", "[b]x[/b]"))
	check_eq(label.get_parsed_text(), "12:00 Ash: [b]x[/b]", "rendered text")
	label.free()


func test_fade_holds_then_eases_out() -> void:
	check_eq(ChatFeed.alpha(0.0, false), ChatFeed.FULL_ALPHA, "fresh chat fully visible")
	check_eq(ChatFeed.alpha(ChatFeed.IDLE_HOLD, false), ChatFeed.FULL_ALPHA, "still visible at the hold")
	var mid := ChatFeed.alpha(ChatFeed.IDLE_HOLD + ChatFeed.FADE_TIME * 0.5, false)
	check(mid < ChatFeed.FULL_ALPHA and mid > ChatFeed.MIN_ALPHA, "half-way through the fade: %f" % mid)
	check_near(ChatFeed.alpha(ChatFeed.IDLE_HOLD + ChatFeed.FADE_TIME, false), ChatFeed.MIN_ALPHA, 0.0001, "faded")
	check_near(ChatFeed.alpha(1e9, false), ChatFeed.MIN_ALPHA, 0.0001, "stays faded")
	check_eq(ChatFeed.alpha(1e9, true), ChatFeed.FULL_ALPHA, "awake beats idle")
	var prev := 2.0
	for i in 40:
		var a := ChatFeed.alpha(i * 0.5, false)
		check(a <= prev + 0.00001, "never brightens on its own (t=%.1f)" % (i * 0.5))
		prev = a


func test_feed_wakes_on_new_lines_and_typing() -> void:
	var f := ChatFeed.new()
	var a := 1.0
	for i in 30:
		a = f.step(1.0, false)
	check_near(a, ChatFeed.MIN_ALPHA, 0.0001, "faded after 30 quiet seconds")
	f.wake()
	check_eq(f.step(0.016, false), ChatFeed.FULL_ALPHA, "a new line brings it back")
	for i in 30:
		f.step(1.0, false)
	check_eq(f.step(0.016, true), ChatFeed.FULL_ALPHA, "typing brings it back")
	check_near(f.idle, 0.0, 0.0001, "typing resets the idle timer")
	f.step(-5.0, false)
	check(f.idle >= 0.0, "negative delta ignored")


func test_log_keeps_the_last_lines() -> void:
	check_eq(ChatFeed.lines_to_trim(ChatFeed.MAX_LINES), 0, "at the cap")
	check_eq(ChatFeed.lines_to_trim(ChatFeed.MAX_LINES + 1), 1, "one over")
	var f := ChatFeed.new()
	var label := RichTextLabel.new()
	label.bbcode_enabled = true
	for i in ChatFeed.MAX_LINES + 25:
		f.append(label, ChatFeed.chat_line(0.0, "Bot", "line %d" % i))
	check_eq(f.line_count, ChatFeed.MAX_LINES, "count capped")
	var text := label.get_parsed_text()
	check(not text.contains("line 24\n"), "oldest lines dropped")
	check(text.contains("line 25\n"), "first kept line present")
	check(text.contains("line %d" % (ChatFeed.MAX_LINES + 24)), "newest line present")
	f.clear(label)
	check_eq(f.line_count, 0, "cleared")
	label.free()


func test_client_chat_handlers_use_the_feed() -> void:
	var c = load("res://client/client.gd").new()
	c.chat_log = RichTextLabel.new()
	c.chat_log.bbcode_enabled = true
	c.chat_feed.idle = 99.0
	c._on_system("Bryn joined.")
	var text: String = c.chat_log.get_parsed_text()
	check(text.contains("Bryn joined."), "system line shown: %s" % text)
	check_eq(c.chat_feed.line_count, 1, "line counted")
	check_near(c.chat_feed.idle, 0.0, 0.0001, "a new line wakes the chat")
	c.chat_log.free()
	c.free()
