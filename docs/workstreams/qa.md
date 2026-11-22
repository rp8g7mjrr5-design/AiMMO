# Workstream: qa

Owns quality, tests, CI, and operations. See `docs/workstreams.md` for ownership.

## Backlog (top = next)
- [x] Bot behaviour plugin hook: `tests/bot_test/behaviours/*.gd` loaded by `bot.gd`, so every stream can add bot behaviours without editing `bot.gd`
- [ ] Follow-up: bot-test option `--only-behaviour=<name>` to run one behaviour quickly while developing it
- [ ] Triage `docs/playtest.md` every run and fix crashes first
- [ ] Server performance check in the bot test: tick time, memory, and bandwidth per player logged and asserted under a budget
- [ ] Load test: optional 50-bot run (manual workflow_dispatch input)
- [ ] Health endpoint or heartbeat log so Railway restarts a hung server

## Requests from other streams
- **From client:** `tests/unit/run_all.gd` reports a test as `ok` even when a `SCRIPT ERROR` aborts it partway (seen while writing `test_client_settings.gd`: a runtime error in the code under test printed SCRIPT ERROR, the remaining checks never ran, and the test still passed). Please make the runner fail a test that logged a script error, e.g. by having CI grep the unit test output for `SCRIPT ERROR` the way the client smoke test does.
