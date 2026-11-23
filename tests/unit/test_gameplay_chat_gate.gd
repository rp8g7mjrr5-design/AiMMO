extends TestCase
## Chat is for talking (owner direction 1): slash commands run only on a server with dev
## commands on (ChatCommands.dev_commands_on). Off, any "/" line gets the NOT_FOR_CHAT hint,
## runs nothing, changes nothing and is never broadcast.

const ServerScript := preload("res://server/server.gd")


func _server(dev: bool) -> Node:
	var srv: Node = ServerScript.new()
	srv.test_now = 100.0
	srv.dev_commands = dev
	var n: Dictionary = ResourceNodes.all()[0]
	for id in [2, 3]:
		var ch := CharacterData.normalize({"name": "P%d" % id})
		ch.x = n.pos.x + 0.5
		ch.y = n.pos.y
		ch.z = n.pos.z
		srv.sessions[id] = {"logged_in": true, "character": ch, "move": Vector2.ZERO, "yaw": 0.0, "seq": -1,
			"last_chat": -1000.0, "last_command": -1000.0, "last_too_fast": -1000.0, "last_gather": -1000.0,
			"channel": {}, "login_attempts": 0, "inv_dirty": false}
	return srv


func _env(values: Dictionary) -> Callable:
	return func(name: String) -> String: return str(values.get(name, ""))


func _sent(srv: Node, method: String) -> Array:
	var out: Array = []
	for m in srv.test_outbox:
		if m[1] == method:
			out.append([m[0], m[2]])
	return out


func test_slash_lines_only_get_the_hint_when_off() -> void:
	var srv := _server(false)
	var inv_before: Dictionary = srv.sessions[2].character.inventory.duplicate(true)
	var gathering_before: Dictionary = srv.gathering.duplicate(true)
	for line in ["/help", "/gather", "/bag", "/craft torch", "/who", "/time", "/skills", "/"]:
		srv.test_outbox.clear()
		srv.test_now += GameConfig.CHAT_COOLDOWN + 0.01
		srv._on_chat(2, line)
		check_eq(_sent(srv, "s2c_system"), [[2, [ChatCommands.NOT_FOR_CHAT]]], "%s: one hint, to the sender only" % line)
		check_eq(_sent(srv, "s2c_chat").size(), 0, "%s is never broadcast" % line)
		check_eq(srv.test_outbox.size(), 1, "%s sends nothing else (no gather, no inventory)" % line)
	check_eq(srv.sessions[2].character.inventory, inv_before, "no item moved")
	check_eq(srv.gathering, gathering_before, "no node charge used")
	check(not GatherChannel.is_active(srv.sessions[2].channel), "no gather started")
	srv.free()


func test_talk_still_flows_when_off() -> void:
	var srv := _server(false)
	srv._on_chat(2, "hello /gather is not a command mid-line")
	check_eq(_sent(srv, "s2c_chat").size(), 2, "talk reaches both players")
	check_eq(_sent(srv, "s2c_system").size(), 0, "and earns no hint")
	srv.free()


func test_hint_respects_the_command_cooldown() -> void:
	var srv := _server(false)
	srv._on_chat(2, "/help")
	srv.test_outbox.clear()
	for i in 5:
		srv._on_chat(2, "/help")
	check_eq(_sent(srv, "s2c_system"), [[2, [ChatCommands.TOO_FAST]]], "spamming slashes gets one notice, not five hints")
	srv.free()


func test_commands_run_when_on() -> void:
	var srv := _server(true)
	srv._on_chat(2, "/time")
	var sys := _sent(srv, "s2c_system")
	check_eq(sys.size(), 1)
	check(str(sys[0][1][0]).begins_with("It is Day "), "dev server answers /time: %s" % sys)
	srv.free()


func test_hint_points_at_the_controls() -> void:
	check(ChatCommands.NOT_FOR_CHAT.contains("F1"), "names the F1 controls overlay")
	check(not ChatCommands.NOT_FOR_CHAT.contains("/"), "never teaches a slash command")


func test_dev_commands_switch() -> void:
	var none := _env({})
	check_eq(ChatCommands.dev_commands_on({"dev-commands": true}, none)[0], true, "--dev-commands")
	check_eq(ChatCommands.dev_commands_on({"dev-commands": "0"}, none)[0], false, "--dev-commands=0")
	check_eq(ChatCommands.dev_commands_on({}, _env({"AIMMO_DEV_COMMANDS": "1"}))[0], true, "env 1")
	check_eq(ChatCommands.dev_commands_on({}, _env({"AIMMO_DEV_COMMANDS": "off"}))[0], false, "env off")
	check_eq(ChatCommands.dev_commands_on({}, none), [true, "local default"], "local runs keep dev tools")
	check_eq(ChatCommands.dev_commands_on({}, _env({"RAILWAY_PROJECT_ID": "abc"}))[0], false, "public server: off")
	check_eq(ChatCommands.dev_commands_on({}, _env({"RAILWAY_ENVIRONMENT_NAME": "production"}))[0], false, "any Railway var")
	check_eq(ChatCommands.dev_commands_on({"dev-commands": true}, _env({"RAILWAY_PROJECT_ID": "abc"}))[0], true, "the flag wins")
	check_eq(ChatCommands.dev_commands_on({}, _env({"AIMMO_DEV_COMMANDS": "1", "RAILWAY_PROJECT_ID": "abc"}))[0], true, "the env switch wins over the default")
	check_eq(ChatCommands.dev_commands_on({}, _env({"AIMMO_DEV_COMMANDS": "0"}))[1], "AIMMO_DEV_COMMANDS", "says why")
