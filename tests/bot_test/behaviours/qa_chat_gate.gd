extends "res://tests/bot_test/bot_behaviour.gd"
## QA: chat is for talking (owner direction 1), checked against a server WITHOUT
## `--dev-commands`, the way the public server runs.
##
## Only active when the bot is started with `--chat-gate` (run_bot_test.py's chat-gate phase
## starts a second server with `--dev-commands=0` and two bots with
## `--only-behaviour=qa_chat_gate --chat-gate`). On a normal run it does nothing, because the
## bot-test server keeps its dev commands for the other behaviours.
##
## After each login the bot types /gather, /bag and /who. For every line it must get the
## "Chat is for talking" hint back, and nothing may happen: no item, no XP, no gather started,
## no node emptied, no command answer, and nobody sees the line as chat. Plain talk still goes
## through: bot.gd's "hello from" lines must reach the other bot (expect-peers).

const COMMANDS := ["/gather", "/bag", "/who"]
const FIRST_DELAY := 2.0
## A hint that hasn't come this long after its line went out is a failure.
const ANSWER_WITHIN := 4.0
const MAX_TOO_FAST := 6

var active := false
var _queue: Array = [] ## commands still to send this login
var _pending: Array = [] ## [text, sent_at] waiting for their hint, oldest first
var _next_at := 0.0
var _too_fast := 0
var _pack_seen := false
var _pack := {}
var _depleted_at_login := []
var _logins := 0

var sent := 0
var hints := 0
var leaked := 0 ## command lines that came back as chat


func setup(net: Node) -> void:
	active = bot.args.has("chat-gate")
	if not active:
		return
	net.system_message.connect(_on_system)
	net.chat_message.connect(_on_chat)
	net.inventory_changed.connect(_on_pack)
	net.gather_begun.connect(func(_p, node_id, _s): fail("a gather started on node %d with dev commands off" % node_id))
	net.gather_result.connect(func(item_id, count): fail("got %d %s with dev commands off" % [count, item_id]))
	net.node_state.connect(func(node_id, depleted): if depleted: fail("node %d was emptied with dev commands off" % node_id))
	net.nodes_depleted.connect(_on_depleted)
	bot.command_sent.connect(_on_sent)


func on_login(_reconnect: bool, _character: Dictionary) -> void:
	if not active:
		return
	_logins += 1
	_queue = COMMANDS.duplicate()
	_pending.clear()
	_next_at = bot.elapsed + FIRST_DELAY + bot.rng.randf_range(0.0, 0.5)


func on_play(_delta: float) -> void:
	if not active:
		return
	if not _pending.is_empty() and bot.elapsed - float(_pending[0][1]) > ANSWER_WITHIN:
		fail("no \"Chat is for talking\" hint for %s within %.0f s" % [_pending[0][0], ANSWER_WITHIN])
		_pending.pop_front()
	if _queue.is_empty() or bot.elapsed < _next_at:
		return
	bot.send_command(_queue.pop_front())
	_next_at = bot.elapsed + 0.1


func _on_sent(text: String) -> void:
	sent += 1
	_pending.append([text, bot.elapsed])


func _on_system(text: String) -> void:
	if text == ChatCommands.NOT_FOR_CHAT:
		hints += 1
		if _pending.is_empty():
			fail("got the \"Chat is for talking\" hint without typing a command")
		else:
			_pending.pop_front()
		return
	if text == ChatCommands.TOO_FAST:
		# The line was dropped by the cooldown before the gate: type it again.
		if not _pending.is_empty():
			var again: String = _pending.pop_front()[0]
			_too_fast += 1
			if _too_fast > MAX_TOO_FAST:
				fail("server kept saying \"too fast\" (%d times)" % _too_fast)
			else:
				_queue.push_front(again)
		return
	# Answers a command would have given. With the gate on, none of these may arrive.
	if text.contains(" online: ") or text.begins_with("Commands:") or text.begins_with("It is Day "):
		fail("a command was answered with dev commands off: %s" % text.substr(0, 60))


func _on_chat(from_name: String, text: String) -> void:
	if text.begins_with("/"):
		leaked += 1
		fail("%s's command line was broadcast as chat: %s" % [from_name, text.substr(0, 40)])


func _on_pack(items: Dictionary) -> void:
	if not _pack_seen:
		_pack_seen = true
		_pack = items.duplicate(true)
	elif items != _pack:
		fail("pack changed with dev commands off: %s -> %s" % [_pack, items])
		_pack = items.duplicate(true)


func _on_depleted(ids: Array) -> void:
	var now := ids.duplicate()
	now.sort()
	# A node may come back between logins; a node newly emptied means a command gathered.
	var fresh := now.filter(func(n): return not _depleted_at_login.has(n))
	if _logins >= 2 and not fresh.is_empty():
		fail("nodes emptied between logins with dev commands off: %s" % [fresh])
	_depleted_at_login = now


func on_finish() -> void:
	if not active:
		return
	stat("sent", sent)
	stat("hints", hints)
	stat("leaked", leaked)
	stat("too_fast", _too_fast)
	if _logins >= 2 and sent < COMMANDS.size() * 2:
		fail("typed only %d of %d command lines" % [sent, COMMANDS.size() * 2])
	if hints < sent - _too_fast:
		fail("%d command lines but only %d hints" % [sent, hints])
