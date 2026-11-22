# Workstream: qa

Owns quality, tests, CI, and operations. See `docs/workstreams.md` for ownership.

## Backlog (top = next)
- [ ] Bot behaviour plugin hook: `tests/bot_test/behaviours/*.gd` loaded by `bot.gd`, so every stream can add bot behaviours without editing `bot.gd`
- [ ] Triage `docs/playtest.md` every run and fix crashes first
- [ ] Server performance check in the bot test: tick time, memory, and bandwidth per player logged and asserted under a budget
- [ ] Load test: optional 50-bot run (manual workflow_dispatch input)
- [ ] Health endpoint or heartbeat log so Railway restarts a hung server

## Requests from other streams
- **From world:** `tests/bot_test/behaviours/<stream>_*.gd` hook does not exist yet, so the day/night sky shipped without a bot behaviour (unit tests and client smoke cover it). Please add the hook. Also handy: `AIMMO_TIME_OF_DAY=0.0..1.0` pins the sky, so the client smoke test could screenshot night as well as day.
