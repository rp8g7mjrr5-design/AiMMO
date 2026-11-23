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
