extends "res://tests/bot_test/bot_behaviour.gd"
## Client: system notices centre screen on a real server (chat is for talking). Each bot
## runs the client's NoticeLine on every s2c_system it gets, in the client's order (the
## level-up banner and the gather prompt's echoes first), and pairs it with its own
## s2c_gather_end refusals as the client does. It checks what the player would see:
## - join and leave lines stay in chat, and nothing else does except long dev answers;
## - every other line shows centre screen with a headline, or is dropped only because the
##   gather prompt's refusal toast said the same thing a moment before;
## - nothing stays on screen past its hold (counted from the last notice shown).

const NoticeScript := preload("res://client/notice_line.gd")
const PromptScript := preload("res://client/gather_prompt.gd")

var _n: Control
var lines := 0
var to_chat := 0
var centre := 0
var dropped := 0
var refusals := 0
var _shown_for := 0.0


func setup(net: Node) -> void:
	_n = NoticeScript.new()
	_n.setup(Theme.new())
	net.system_message.connect(_on_system)
	net.gather_ended.connect(_on_ended)


func on_login(_reconnect: bool, _character: Dictionary) -> void:
	_n.hide_all()
	_shown_for = 0.0


func on_play(delta: float) -> void:
	_n.step(delta)
	_shown_for = _shown_for + delta if _n.visible else 0.0
	if _shown_for > NoticeScript.HOLD_MAX + 0.5:
		fail("a notice stayed up %.1f s: %s" % [_shown_for, _n.text_now()])
		_shown_for = 0.0


func _on_ended(peer: int, node_id: int, reason: String) -> void:
	if peer != int(bot.my_id):
		return
	if PromptScript.notice_for(reason, node_id) != "":
		refusals += 1
		_n.note_refusal(reason)


func _on_system(text: String) -> void:
	if text.contains(" is now level "):
		return # the level-up banner's line (client_level_up checks that one)
	if PromptScript.is_echo(text):
		return # the gather bar and toast's line (client_gather_prompt checks those)
	lines += 1
	var paired: String = _n.paired_reason()
	var where: String = _n.on_system(text)
	match where:
		"chat":
			to_chat += 1
			if not NoticeScript.is_presence(text) and text.length() <= NoticeScript.MAX_CHARS and not text.contains("\n"):
				fail("'%s' went to chat (chat is for talking)" % text)
		"notice":
			centre += 1
			_shown_for = 0.0 # a new notice (or a repeat) restarts its hold
			if not _n.visible or _n.headline_label.text == "":
				fail("notice '%s' isn't showing" % text)
			elif not text.begins_with(_n.headline_label.text):
				fail("notice headline '%s' isn't the start of '%s'" % [_n.headline_label.text, text])
		"drop":
			dropped += 1
			if text.strip_edges() != "" and (paired == "" or not NoticeScript.SAID_BY_TOAST.has(paired)):
				fail("'%s' was dropped without a toast saying it (paired '%s')" % [text, paired])
		_:
			fail("unknown route %s" % where)


func on_finish() -> void:
	stat("system_lines", lines)
	stat("to_chat", to_chat)
	stat("centre", centre)
	stat("dropped", dropped)
	stat("gather_refusals", refusals)
	if is_instance_valid(_n):
		_n.free() # a Control nobody added to the tree: free it, or its labels leak at exit
