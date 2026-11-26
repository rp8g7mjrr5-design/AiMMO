# Bot behaviours

Every `*.gd` file here is loaded by every bot in the bot test (`tests/bot_test/bot.gd`).
Name files `<stream>_<what>.gd` (for example `gameplay_gathering.gd`) and extend
`res://tests/bot_test/bot_behaviour.gd`. See that file for the hooks
(`setup`, `on_login`, `on_play`, `on_snapshot`, `on_finish`) and helpers (`fail`, `stat`).

Send slash commands with `bot.send_command("/bag")` (optionally with a callback that runs the
moment the line goes out), never `bot.net.c2s_chat` directly. The harness spaces every bot's
commands past the server's shared command cooldown, so one behaviour's line can't make the
server drop another's. A unit test fails any behaviour that calls `c2s_chat`.

`qa_fun_metrics.gd` watches every bot and reports the fun metrics (time to first reward,
dead time, wait after acting, rewards per minute, loops). See `../fun_report.py`.

A behaviour's failures fail the bot test. Its stats show up in the bot's result JSON under
`stats.behaviours.<file name>` and in the bot-test summary line.

`tests/unit/test_qa_bot_behaviours.gd` checks that every file here loads and extends the base,
so a broken behaviour fails the unit tests before the 3-minute bot test even starts.

`qa_gather_ledger.gd` checks real gathering never loses or invents items (pack across a
reconnect, final pack against the save) and that every client agrees which nodes are empty.
After long runs the harness starts one extra bot with `--only-behaviour=qa_gather_ledger
--gather-probe=<node>` to watch an emptied node respawn and gather it (see
`../gather_report.py`). `--only-behaviour=a,b` works for any behaviour while developing it.

`qa_chat_gate.gd` only acts on bots started with `--chat-gate`. After the main run the harness
boots a second server with `--dev-commands=0` (how the public server runs) and two such bots
type /gather, /bag and /who: chat is for talking, so each line must get the hint and change
nothing. The main bot-test server runs with `--dev-commands`, so other behaviours may type
commands.

`qa_player_cap.gd` only acts on bots started with `--player-cap=N` (owner direction 8, a world
for 2 to 8 friends). After a long run the harness boots a third server with `--max-players=8`
(the Railway image's `MAX_PLAYERS`), fills it with eight `--single-login` bots and sends a ninth
with `--retry-when-full`: it must read exactly "The world is full (8 / 8). Try again soon.",
keep knocking, and get in only after one of the eight leaves; no bot may ever see more than 8
players, and nobody inside is dropped. See `run_bot_test.run_player_cap`.

`qa_night_walkers.gd` only acts on bots started with `--night-walkers` (basics 2, zombie
survival). After a long run the harness boots a fourth server with `--gloam=1` and a
`--clock-offset` that puts it at midnight, and four such bots walk out to their own posts past
Spawn Meadow, call walkers in with loud swings, let the first one of each login grab them, and
fight the walkers that rise on their own bare-handed. Each bot must see walkers rise; the group
must be grabbed and put walkers down. See `run_bot_test.run_night`.

`qa_tool_gate.gd` only acts on bots started with `--tool-gate=fresh|veteran` (tier-2 nodes
refuse bare hands; there are no levels since 2026-11-26). Before a long run's server starts,
`../seed_veteran.gd` saves a character carrying the tool the tier-2 node nearest spawn needs,
plus old XP from the retired skills; next to the pair check, a fresh bot walks there and must
be refused ("tool" and the "You need an axe ..." line, nothing paid), then the veteran works
the node empty with every charge paid, and both reconnect (still refused; the veteran keeps its
tool, and its old XP is still in the save, untouched). See `../tool_gate.gd`.

`client_craft_window.gd` with `--craft-haul` is the craft-haul check: after a long run's main
bots, `../seed_crafter.gd` saves a character at the workbench holding exactly a campfire's
and a torch's inputs, and one bot with only this behaviour presses Craft on the real client
window. It must make both and end with exactly the goods (also
checked in the save). See `../craft_haul.gd`; skip it with `--no-craft-haul`.
