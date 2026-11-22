class_name ChatCommands
## Slash commands typed into chat. A chat line that starts with "/" is a command: the server
## answers only the sender with a system message and never broadcasts the line itself.
## Pure functions, so they are unit tested without a running server.
##
## Commands: /help, /time, /who. Names are case-insensitive; extra words are ignored.

const HELP := "Commands: /time (time of day in Ashgrove), /who (who is online), /help."
const WHO_MAX_NAMES := 20 ## cap the /who list so one line stays readable


static func is_command(text: String) -> bool:
	return text.begins_with("/")


## Returns the reply for a command line (already cleaned by Validation.clean_chat).
## ctx keys: "world_seconds" (float) and "online" (Array of character names).
static func run(text: String, ctx: Dictionary) -> String:
	var words := text.substr(1).strip_edges().split(" ", false)
	var cmd := words[0].to_lower() if words.size() > 0 else "help"
	match cmd:
		"help", "?", "commands":
			return HELP
		"time", "clock":
			return time_reply(float(ctx.get("world_seconds", 0.0)))
		"who", "online", "players":
			return who_reply(ctx.get("online", []))
	return "Unknown command /%s. Try /help." % cmd.substr(0, 20)


## "It is Day 3, 14:05 (day). Dusk comes in about 9 minutes."
static func time_reply(world_seconds: float) -> String:
	var secs := WorldClock.seconds_until_next_phase(world_seconds)
	var mins := roundi(secs / 60.0)
	var when := "about %d minutes" % mins
	if secs < 60.0:
		when = "less than a minute"
	elif mins <= 1:
		when = "about a minute"
	return "It is %s. %s comes in %s." % [
		WorldClock.describe(world_seconds), WorldClock.next_phase(world_seconds).capitalize(), when]


## "3 online: Ash, Bryn, Cole." Names sorted case-insensitively.
static func who_reply(online: Array) -> String:
	var names: Array = online.duplicate()
	names.sort_custom(func(a, b): return str(a).to_lower() < str(b).to_lower())
	if names.is_empty():
		return "Nobody is online."
	var shown := names.slice(0, WHO_MAX_NAMES)
	var line := ", ".join(PackedStringArray(shown))
	if names.size() > shown.size():
		line += " and %d more" % (names.size() - shown.size())
	return "%d online: %s." % [names.size(), line]
