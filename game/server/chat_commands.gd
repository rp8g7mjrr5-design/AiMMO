class_name ChatCommands
## Slash commands typed into chat. A chat line that starts with "/" is a command: the server
## answers only the sender with a system message and never broadcasts the line itself.
## Pure functions, so they are unit tested without a running server.
##
## Commands: /help, /time, /who, /bag, /gather, /craft. /gather and /craft change the world
## or a pack, so the server handles them itself (see is_gather, is_craft); everything else
## is answered by run(). /craft is a debug and bot command only (owner direction: chat is
## for talking): it is never listed in HELP or patch notes. Players craft from a window at
## the workbench once c2s_craft exists. Names are case-insensitive; extra words are ignored.

## /gather is not listed (owner direction "How gathering feels"): players press E at a node
## since protocol v3; /gather stays as a hidden debug and bot command.
const HELP := "Commands: /bag (what you carry), /time (time of day in Ashgrove), /who (who is online), /help."
const GATHER_NAMES := ["gather", "g", "harvest", "chop", "mine"]
const CRAFT_NAMES := ["craft", "make", "build", "recipes"]
## Sent to a player whose line came inside GameConfig.CHAT_COOLDOWN of their last one (talk
## and commands count separately), so nothing they type vanishes without a word.
const TOO_FAST := "Slow down a moment: that line wasn't sent. Try again."
## The only answer a player gets for a "/" line on a server without dev commands: the
## controls live on keys and windows, and F1 lists them.
const NOT_FOR_CHAT := "Chat is for talking. Press F1 for controls."
## Railway sets these on every deploy; the public server is the only place players play.
const RAILWAY_VARS := ["RAILWAY_ENVIRONMENT", "RAILWAY_ENVIRONMENT_NAME", "RAILWAY_ENVIRONMENT_ID",
	"RAILWAY_PROJECT_ID", "RAILWAY_SERVICE_ID", "RAILWAY_DEPLOYMENT_ID"]
const WHO_MAX_NAMES := 20 ## cap the /who list so one line stays readable


static func is_command(text: String) -> bool:
	return text.begins_with("/")


## The command's name, lower case ("help" for a bare "/").
static func name_of(text: String) -> String:
	var words := text.substr(1).strip_edges().split(" ", false)
	return words[0].to_lower() if words.size() > 0 else "help"


## Everything after the command's name, trimmed ("" if nothing).
static func argument(text: String) -> String:
	var words := text.substr(1).strip_edges().split(" ", false)
	return " ".join(words.slice(1)) if words.size() > 1 else ""


## True for /gather and its aliases, which the server runs against its world state.
static func is_gather(text: String) -> bool:
	return is_command(text) and name_of(text) in GATHER_NAMES


## True for /craft and its aliases, which the server runs against the sender's pack.
static func is_craft(text: String) -> bool:
	return is_command(text) and name_of(text) in CRAFT_NAMES


## Whether this server runs slash commands. `--dev-commands` (or `--dev-commands=0/1`) wins,
## then AIMMO_DEV_COMMANDS (1/true/on or 0/false/off). With neither, commands are off on the
## public server (any of RAILWAY_VARS set) and on everywhere else, so local runs and today's
## bot test keep their dev tools until qa passes the flag (qa backlog, "chat is for talking,
## in CI"); then this default can become plain "off". env is a name -> value lookup.
## Returns [on, why] for the start-up log line.
static func dev_commands_on(args: Dictionary, env: Callable = Callable(OS, "get_environment")) -> Array:
	if args.has("dev-commands"):
		var v = args["dev-commands"]
		var on := true if typeof(v) == TYPE_BOOL else _truthy(str(v))
		return [on, "--dev-commands"]
	var e := str(env.call("AIMMO_DEV_COMMANDS")).strip_edges()
	if e != "":
		return [_truthy(e), "AIMMO_DEV_COMMANDS"]
	for name in RAILWAY_VARS:
		if str(env.call(name)) != "":
			return [false, "public server (%s)" % name]
	return [true, "local default"]


static func _truthy(v: String) -> bool:
	return not (v.strip_edges().to_lower() in ["0", "false", "off", "no", ""])


## Returns the reply for a command line (already cleaned by Validation.clean_chat).
## ctx keys: "world_seconds" (float), "online" (Array of character names),
## "inventory" (the sender's Inventory Dictionary) and "skills" (the sender's Skills XP).
## /skills is a hidden dev and bot command, never listed in HELP or patch notes.
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
		"bag", "pack", "inventory", "inv", "i":
			return Inventory.describe(Inventory.normalize(ctx.get("inventory", {})))
		"skills", "xp", "levels":
			# Hidden dev/bot command (owner direction 1): players get a skills window.
			return Skills.describe(Skills.normalize(ctx.get("skills", {})))
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
