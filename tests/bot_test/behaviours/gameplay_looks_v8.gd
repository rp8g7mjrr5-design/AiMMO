extends "res://tests/bot_test/bot_behaviour.gd"
## Bot behaviour (gameplay): protocol v8, character customization. Every bot wears a random
## look of its own, as a player who just made their traveller would.
##
## - A couple of seconds after the first login it saves a random look (c2s_set_look). The
##   server must echo it back (s2c_look for our own id) unchanged within 4 s.
## - Late in the first play phase it changes its look once more (the Esc menu's "Change
##   appearance"), with the same check.
## - Every other player who joins while we're online must come with an s2c_look, and every
##   look anyone sends must pass Appearance.check or be {} (never chosen).
## - After the reconnect, the login answer's character must carry the last look we saved:
##   a look survives logout and the save (the bot test's data-loss rule).

const FIRST_AFTER := 2.0
const CHANGE_AT := 0.3 ## of the bot's duration: the second look, well before the disconnect
const ECHO_TIMEOUT := 4.0

var _logins := 0
var _login_at := 0.0
var _saved: Dictionary = {}
var _sent_at := -1.0
var _pending: Dictionary = {}
var _changed := false
var _first_done := false
var _joined := {} ## peer id -> true when its s2c_player_joined came, cleared by its s2c_look
var echoes := 0
var looks_seen := 0


func setup(net: Node) -> void:
	net.look_changed.connect(_on_look)
	net.player_joined.connect(func(id: int, _n: String, _s: int): _joined[id] = bot.elapsed)
	net.player_left.connect(func(id: int): _joined.erase(id))


func on_login(reconnect: bool, character: Dictionary) -> void:
	_logins += 1
	_login_at = bot.elapsed
	_sent_at = -1.0
	_joined.clear()
	if reconnect and not _saved.is_empty():
		var got := Appearance.normalize(character.get("look", {}))
		if got != _saved:
			fail("after reconnecting our look is %s, we saved %s" % [got, _saved])


func _send_new_look() -> void:
	_pending = Appearance.random(bot.rng)
	_sent_at = bot.elapsed
	bot.send_play("c2s_set_look", [_pending])


func _on_look(peer_id: int, look: Dictionary) -> void:
	looks_seen += 1
	if not look.is_empty() and Appearance.check(look) != "":
		fail("s2c_look for %d is not a valid look: %s (%s)" % [peer_id, look, Appearance.check(look)])
	_joined.erase(peer_id)
	if peer_id == bot.my_id and _sent_at >= 0.0:
		if Appearance.normalize(look) != _pending:
			fail("our look came back as %s, we sent %s" % [look, _pending])
		_saved = _pending
		_sent_at = -1.0
		echoes += 1


func on_play(_delta: float) -> void:
	if _sent_at >= 0.0 and bot.elapsed - _sent_at > ECHO_TIMEOUT:
		fail("c2s_set_look never echoed back")
		_sent_at = -1.0
	for id in _joined.keys():
		if bot.elapsed - float(_joined[id]) > ECHO_TIMEOUT:
			fail("peer %d joined but its look never came" % id)
			_joined.erase(id)
	if _logins == 1 and not _first_done and bot.elapsed - _login_at >= FIRST_AFTER:
		_first_done = true
		_send_new_look()
	elif _logins == 1 and _first_done and not _changed and _sent_at < 0.0 \
			and bot.elapsed >= float(bot.duration) * CHANGE_AT:
		_changed = true
		_send_new_look()


func on_finish() -> void:
	stat("echoes", echoes)
	stat("looks_seen", looks_seen)
	if _logins > 0 and echoes == 0:
		fail("never saw our own look saved")
	if int(bot.expect_peers) > 0 and looks_seen <= echoes:
		fail("never got another player's look")
