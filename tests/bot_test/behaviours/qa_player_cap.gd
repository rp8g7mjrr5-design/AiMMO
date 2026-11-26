extends "res://tests/bot_test/bot_behaviour.gd"
## QA: the player cap (owner direction 8: a world for 2 to 8 friends), checked live.
##
## Only active when the bot is started with `--player-cap=N` (run_bot_test.py's player-cap
## phase boots a server with `--max-players=N`, fills it with N bots and then sends one more,
## see run_bot_test.run_player_cap). On a normal run it does nothing: the main bot-test server
## has no cap, so its 8 bots plus the probe, pair, tool-gate and haul bots all get in.
##
## Every bot checks it never shares the world with more than N players, counting itself (a
## snapshot with N or more others means the cap let one too many in). A bot turned away must
## read exactly the server's polite text, "The world is full (N / N). Try again soon.", the
## one the login screen shows. The harness checks the rest from the results and the server
## log: the extra bot was refused at least once, got in only after one of the N left, and
## nobody inside was ever disconnected (bot.gd fails a bot the server drops).

var cap := 0
var refusals := 0
var max_players_seen := 0 ## the most players (this bot included) one snapshot showed


func setup(net: Node) -> void:
	cap = int(bot.args.get("player-cap", "0"))
	if cap <= 0:
		return
	net.login_result.connect(_on_login_result)


## The text a player turned away by a full world of `n` reads (server.gd world_full_text()).
static func full_text(n: int) -> String:
	return "The world is full (%d / %d). Try again soon." % [n, n]


func _on_login_result(ok: bool, message: String, _id: int, _character: Dictionary) -> void:
	if ok:
		return
	refusals += 1
	if message != full_text(cap):
		fail("turned away with %s, expected %s" % [JSON.stringify(message), JSON.stringify(full_text(cap))])


func on_snapshot(_tick: int, entries: Array) -> void:
	if cap <= 0:
		return
	var players := 0
	var i := 0
	while i + 4 < entries.size():
		players += 1
		i += 5
	if players > max_players_seen:
		max_players_seen = players
		if players > cap:
			fail("%d players in a world capped at %d" % [players, cap])


func on_finish() -> void:
	if cap <= 0:
		return
	stat("refusals", refusals)
	stat("max_players_seen", max_players_seen)
