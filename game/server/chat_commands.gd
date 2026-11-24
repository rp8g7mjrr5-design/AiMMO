class_name ChatCommands
## Slash commands typed into chat. A chat line that starts with "/" is a command: the server
## answers only the sender with a system message and never broadcasts the line itself.
## Pure functions, so they are unit tested without a running server.
##
## Commands: /help, /time, /who, /bag, /gather, /craft (and hidden /skills, /hurt, /vitals, /lure). /gather and /craft change the world
## or a pack, so the server handles them itself (see is_gather, is_craft); everything else
## is answered by run(). /craft is a debug and bot command only (owner direction: chat is
## for talking): it is never listed in HELP or patch notes. Players craft from a window at
## the workbench once c2s_craft exists. Names are case-insensitive; extra words are ignored.

## /gather is not listed (owner direction "How gathering feels"): players press E at a node
## since protocol v3; /gather stays as a hidden debug and bot command.
const HELP := "Commands: /bag (what you carry), /time (time of day in Ashgrove), /who (who is online), /help."
const GATHER_NAMES := ["gather", "g", "harvest", "chop", "mine"]
const CRAFT_NAMES := ["craft", "make", "build", "recipes"]
## The retired timed-gather dev command. It no longer runs ("Unknown command"), but the
## classifier stays so bot checks that hold a press after a pack-changing line still compile.
const CHANNEL_NAMES := ["channel"]
## Sent to a player whose line came inside GameConfig.CHAT_COOLDOWN of their last one (talk
## and commands count separately), so nothing they type vanishes without a word.
const TOO_FAST := "Slow down a moment: that line wasn't sent. Try again."
## The only answer a player gets for a "/" line on a server without dev commands: the
## controls live on keys and windows, and F1 lists them.
const NOT_FOR_CHAT := "Chat is for talking. Press F1 for controls."
## Railway sets these on every deploy; only used to say "public server" in the start-up line.
const RAILWAY_VARS := ["RAILWAY_ENVIRONMENT", "RAILWAY_ENVIRONMENT_NAME", "RAILWAY_ENVIRONMENT_ID",
	"RAILWAY_PROJECT_ID", "RAILWAY_SERVICE_ID", "RAILWAY_DEPLOYMENT_ID"]
const WHO_MAX_NAMES := 20 ## cap the /who list so one line stays readable
## Hidden dev and bot commands for health (Vitals), never listed in HELP: /hurt N hits you
## for N, /vitals reads your bars. The server runs them (Server.vitals_command).
const HURT_NAMES := ["hurt"]
const VITALS_NAMES := ["vitals", "hp", "health"]
## Hidden bot command for the first hunt: /lure lays the nearest grazer down in front of you
## (Server.lure_command, Wildlife.lure).
const LURE_NAMES := ["lure"]
const HURT_MAX := 1000
const HURT_DEFAULT := 10


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


## True for the retired /channel line (see CHANNEL_NAMES). Nothing runs it any more.
static func is_channel(text: String) -> bool:
	return is_command(text) and name_of(text) in CHANNEL_NAMES


## True for the hidden /hurt dev command.
static func is_hurt(text: String) -> bool:
	return is_command(text) and name_of(text) in HURT_NAMES


## True for the hidden /vitals dev command and its aliases.
static func is_vitals(text: String) -> bool:
	return is_command(text) and name_of(text) in VITALS_NAMES


## The damage a /hurt line asks for: HURT_DEFAULT with no number, 0 for anything that is
## not a whole number from 1 to HURT_MAX.
static func hurt_amount(text: String) -> int:
	var arg := argument(text)
	if arg == "":
		return HURT_DEFAULT
	var word := arg.split(" ", false)[0]
	if not word.is_valid_int():
		return 0
	var n := word.to_int()
	return n if n >= 1 and n <= HURT_MAX else 0


## True for the hidden /lure bot command.
static func is_lure(text: String) -> bool:
	return is_command(text) and name_of(text) in LURE_NAMES


## True for /craft and its aliases, which the server runs against the sender's pack.
static func is_craft(text: String) -> bool:
	return is_command(text) and name_of(text) in CRAFT_NAMES


## Whether this server runs slash commands. `--dev-commands` (or `--dev-commands=0/1`) wins,
## then AIMMO_DEV_COMMANDS (1/true/on or 0/false/off). With neither, commands are off: every
## server is a player server unless someone asks for dev tools (the bot test passes
## `--dev-commands`; for a local run add `-- --server --dev-commands`). On Railway the reason
## names the Railway variable it saw, so the start-up line still says "public server".
## env is a name -> value lookup. Returns [on, why] for the start-up log line.
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
	return [false, "default"]


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
