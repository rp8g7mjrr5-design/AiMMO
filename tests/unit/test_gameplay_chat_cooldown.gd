extends TestCase
## The chat cooldown (GameConfig.CHAT_COOLDOWN) in the server's _on_chat: talk lines and
## slash commands count separately, and a line the cooldown drops is never dropped silently
## (one ChatCommands.TOO_FAST notice per cooldown window, to the sender only).

const ServerScript := preload("res://server/server.gd")


func _server() -> Node:
	var srv: Node = ServerScript.new()
	srv.test_now = 100.0
	srv.dev_commands = true # these tests run commands; the gate has its own test
	for id in [2, 3]:
		srv.sessions[id] = {"logged_in": true, "character": CharacterData.normalize({"name": "P%d" % id}),
			"move": Vector2.ZERO, "yaw": 0.0, "seq": -1, "last_chat": -1000.0, "last_gather": -1000.0,
			"channel": {}, "login_attempts": 0, "inv_dirty": false}
	return srv


## [peer, args] for every message `method` sent so far, then clears the outbox.
func _take(srv: Node, method: String) -> Array:
	var out: Array = []
	for m in srv.test_outbox:
		if m[1] == method:
			out.append([m[0], m[2]])
	srv.test_outbox.clear()
	return out


func test_talk_inside_cooldown_is_refused_out_loud() -> void:
	var srv := _server()
	srv._on_chat(2, "hello")
	check_eq(_take(srv, "s2c_chat").size(), 2, "first line goes to both players")
	srv.test_now += GameConfig.CHAT_COOLDOWN * 0.5
	srv._on_chat(2, "hello again")
	var out: Array = srv.test_outbox.duplicate()
	check_eq(_take(srv, "s2c_chat").size(), 0, "second line inside the cooldown is not broadcast")
	srv.test_outbox = out
	check_eq(_take(srv, "s2c_system"), [[2, [ChatCommands.TOO_FAST]]], "only the sender is told it wasn't sent")
	srv.test_now += GameConfig.CHAT_COOLDOWN
	srv._on_chat(2, "third time")
	check_eq(_take(srv, "s2c_chat").size(), 2, "after the cooldown talk flows again")
	srv.free()


func test_commands_and_talk_have_separate_cooldowns() -> void:
	var srv := _server()
	srv._on_chat(2, "hi all")
	srv._on_chat(2, "/time")
	var sys := _take(srv, "s2c_system")
	check_eq(sys.size(), 1, "a command right after talking is answered")
	check(str(sys[0][1][0]).begins_with("It is Day "), "and it is the /time answer: %s" % sys)
	srv.free()


func test_too_fast_notice_once_per_window() -> void:
	var srv := _server()
	srv._on_chat(2, "/time")
	srv.test_outbox.clear()
	for i in 5:
		srv._on_chat(2, "/who")
	check_eq(_take(srv, "s2c_system"), [[2, [ChatCommands.TOO_FAST]]], "five dropped lines, one notice")
	srv.test_now += GameConfig.CHAT_COOLDOWN + 0.01
	srv._on_chat(2, "/who")
	var sys := _take(srv, "s2c_system")
	check_eq(sys.size(), 1, "after the window the command runs")
	check(str(sys[0][1][0]).contains(" online: "), "and /who answers: %s" % sys)
	srv.free()


func test_empty_line_is_ignored_without_notice() -> void:
	var srv := _server()
	srv._on_chat(2, "/time")
	srv.test_outbox.clear()
	srv._on_chat(2, "   ")
	check_eq(srv.test_outbox.size(), 0, "a blank line neither runs nor earns a notice")
	srv.free()
