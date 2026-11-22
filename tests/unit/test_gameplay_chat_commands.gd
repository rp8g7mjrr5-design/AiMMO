extends TestCase
## Chat slash commands (game/server/chat_commands.gd) and the WorldClock phase helpers
## that /time uses.

const D := WorldClock.DAY_SECONDS


func test_only_slash_lines_are_commands() -> void:
	check(ChatCommands.is_command("/time"), "/time is a command")
	check(ChatCommands.is_command("/"), "a bare slash is a command (shows help)")
	check(not ChatCommands.is_command("hello /time"), "slash later in the line is just chat")
	check(not ChatCommands.is_command(""), "empty is not a command")


func test_help_and_unknown() -> void:
	check_eq(ChatCommands.run("/help", {}), ChatCommands.HELP)
	check_eq(ChatCommands.run("/", {}), ChatCommands.HELP, "bare slash shows help")
	check_eq(ChatCommands.run("/HELP please", {}), ChatCommands.HELP, "case and extra words ignored")
	var r := ChatCommands.run("/dance", {})
	check(r.begins_with("Unknown command /dance"), "unknown command named: " + r)
	check(r.contains("/help"), "unknown command points at /help")
	var long := ChatCommands.run("/" + "x".repeat(150), {})
	check(long.length() < 80, "unknown command reply stays short")


func test_time_reply_at_known_times() -> void:
	# World second 0 is sunrise (06:00), which is dawn; day starts at fraction 0.30.
	var r := ChatCommands.run("/time", {"world_seconds": 0.0})
	check(r.begins_with("It is Day 1, 06:00 (dawn)."), "sunrise reply: " + r)
	check(r.contains("Day comes in about 2 minutes"), "dawn -> day in 0.05 day = 2 min: " + r)
	var noon := D * 0.25
	r = ChatCommands.run("/Clock", {"world_seconds": noon})
	check(r.begins_with("It is Day 1, 12:00 (day)."), "noon reply: " + r)
	check(r.contains("Dusk comes in about 8 minutes"), "noon -> dusk in 0.20 day = 8 min: " + r)


func test_time_reply_tracks_server_clock() -> void:
	var ws := 123456.7
	check(ChatCommands.time_reply(ws).contains(WorldClock.describe(ws)), "uses WorldClock.describe")


func test_next_phase_cycle_and_countdown() -> void:
	for i in 480:
		var ws := D * i / 480.0 + 3.0
		var left := WorldClock.seconds_until_next_phase(ws)
		check(left > 0.0 and left <= D * 0.44 + 0.01, "countdown in range at %f: %f" % [ws, left])
		var before := WorldClock.phase(ws + left - 0.05)
		var after := WorldClock.phase(ws + left + 0.05)
		check_eq(before, WorldClock.phase(ws), "still the same phase just before the boundary")
		check_eq(after, WorldClock.next_phase(ws), "next phase starts at the boundary")
	# Night wraps past midnight: just after midnight dawn is still 0.22 day away.
	var midnight := D * 0.75
	check_eq(WorldClock.next_phase(midnight + 1.0), "dawn")
	check_near(WorldClock.seconds_until_next_phase(midnight + 1.0), D * 0.22 - 1.0, 0.01, "after midnight")
	check_near(WorldClock.seconds_until_next_phase(midnight - 1.0), D * 0.22 + 1.0, 0.01, "before midnight")


func test_who_reply() -> void:
	check_eq(ChatCommands.run("/who", {"online": []}), "Nobody is online.")
	check_eq(ChatCommands.run("/who", {"online": ["cole", "Ash", "Bryn"]}), "3 online: Ash, Bryn, cole.")
	var many: Array = []
	for i in 25:
		many.append("P%02d" % i)
	var r := ChatCommands.who_reply(many)
	check(r.begins_with("25 online: P00, P01"), "count and sorted: " + r)
	check(r.ends_with("and 5 more."), "capped list: " + r)
	check(not r.contains("P24"), "names past the cap are left out")
