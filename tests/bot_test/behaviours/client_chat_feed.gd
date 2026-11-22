extends "res://tests/bot_test/bot_behaviour.gd"
## Client: chat polish on the real chat stream. Each bot runs the client's ChatFeed on every
## chat and system line it receives, rendering into a real RichTextLabel, and checks that
## each line shows exactly "HH:MM name: text" with a valid in-game time from the server's
## clock, that a new line wakes a faded chat, and that the log never grows past its cap.

const ChatFeedScript := preload("res://client/chat_feed.gd")

var _feed: RefCounted
var _label: RichTextLabel
var _clock := NAN ## last server world_seconds
var _clock_at := 0.0 ## bot.elapsed when it arrived
var _lines := 0
var _woken := 0


func setup(net: Node) -> void:
	_feed = ChatFeedScript.new()
	_label = RichTextLabel.new()
	_label.bbcode_enabled = true
	net.world_time.connect(_on_world_time)
	net.chat_message.connect(func(from_name: String, text: String): _show(ChatFeedScript.chat_line(_now(), from_name, text), "%s: %s" % [from_name, text]))
	net.system_message.connect(func(text: String): _show(ChatFeedScript.system_line(_now(), text), text))


func _on_world_time(world_seconds: float) -> void:
	_clock = world_seconds
	_clock_at = bot.elapsed


func _now() -> float:
	return _clock + (bot.elapsed - _clock_at) if is_finite(_clock) else NAN


func on_play(delta: float) -> void:
	_feed.step(delta, false)


func _show(bbcode: String, want: String) -> void:
	if not is_finite(_clock):
		return # no clock yet (lines before the first sync); the client would show --:--
	var faded: bool = _feed.idle > ChatFeedScript.IDLE_HOLD + ChatFeedScript.FADE_TIME
	var before := _label.get_parsed_text()
	_feed.append(_label, bbcode)
	_lines += 1
	if faded:
		_woken += 1
		if _feed.step(0.0, false) != ChatFeedScript.FULL_ALPHA:
			fail("a new line did not wake the faded chat")
	if _feed.line_count > ChatFeedScript.MAX_LINES:
		fail("chat log grew to %d lines" % _feed.line_count)
	var stamp: String = ChatFeedScript.timestamp(_now())
	var shown := _label.get_parsed_text()
	var expect := "%s %s\n" % [stamp, want]
	if _feed.line_count < ChatFeedScript.MAX_LINES and shown != before + expect:
		fail("line rendered as %s, wanted %s" % [JSON.stringify(shown.substr(before.length())), JSON.stringify(expect)])
	if not shown.ends_with(expect):
		fail("last line is not %s" % JSON.stringify(expect))
	var hh := int(stamp.substr(0, 2))
	var mm := int(stamp.substr(3, 2))
	if stamp.length() != 5 or hh < 0 or hh > 23 or mm < 0 or mm > 59:
		fail("bad timestamp %s" % stamp)


func on_finish() -> void:
	stat("lines", _lines)
	stat("woken_from_fade", _woken)
	stat("kept", _feed.line_count)
	if bot.stats.get("logins", 0) > 0 and _lines == 0:
		fail("never rendered a chat line")
	_label.free()
