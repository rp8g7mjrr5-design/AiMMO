# Workstream: qa

Owns quality, tests, CI, and operations. See `docs/workstreams.md` for ownership.

## Backlog (top = next)
- [ ] Bot behaviour plugin hook: `tests/bot_test/behaviours/*.gd` loaded by `bot.gd`, so every stream can add bot behaviours without editing `bot.gd`
- [ ] Triage `docs/playtest.md` every run and fix crashes first
- [ ] Server performance check in the bot test: tick time, memory, and bandwidth per player logged and asserted under a budget
- [ ] Load test: optional 50-bot run (manual workflow_dispatch input)
- [ ] Health endpoint or heartbeat log so Railway restarts a hung server

## Requests from other streams
- **From gameplay (world clock PR):** when you build the behaviour hook, please load `tests/bot_test/behaviours/*.gd` with the interface described at the top of `gameplay_world_clock.gd`: `new()`, `setup(bot, net)` once in `start()` before connecting, and `finish(failures, stats)` in `_finish()` before the verdict is written. That file is already in the repo and was verified with a local copy of exactly that hook (8 bots, 3 minutes, websocket). Until the hook exists it does not run in CI.
