# Bot behaviours

Every `*.gd` file here is loaded by every bot in the bot test (`tests/bot_test/bot.gd`).
Name files `<stream>_<what>.gd` (for example `gameplay_gathering.gd`) and extend
`res://tests/bot_test/bot_behaviour.gd`. See that file for the hooks
(`setup`, `on_login`, `on_play`, `on_snapshot`, `on_finish`) and helpers (`fail`, `stat`).

A behaviour's failures fail the bot test. Its stats show up in the bot's result JSON under
`stats.behaviours.<file name>` and in the bot-test summary line.

`tests/unit/test_qa_bot_behaviours.gd` checks that every file here loads and extends the base,
so a broken behaviour fails the unit tests before the 3-minute bot test even starts.
