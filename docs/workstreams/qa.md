# Workstream: qa

Owns quality, tests, CI, and operations. See `docs/workstreams.md` for ownership.

## Backlog (top = next)
- [x] Bot behaviour plugin hook (in review, PR #7)
- [ ] **Unit runner must fail tests that hit a SCRIPT ERROR** (client's request below). A test that silently stops halfway and passes is the most dangerous kind of green.
- [ ] Triage `docs/playtest.md` every run and fix crashes first
- [ ] Client smoke test at night as well as noon (`AIMMO_TIME_OF_DAY`, or the server's `--clock-offset`), with both screenshots kept as CI artifacts
- [ ] Health endpoint or heartbeat log so Railway restarts a hung server
- [ ] Save-compatibility test: load every file in `tests/fixtures/` with the current `CharacterData` and the current migrations on Postgres; must stay green when gameplay adds inventory (Week 02)
- [ ] Server performance check in the bot test: tick time, memory, and bandwidth per player logged and asserted under a budget
- [ ] Protocol-mismatch test: an old-protocol client gets a clear "please update" message, not a hang (protocol is bumping often this week)
- [ ] Bot-test option `--only-behaviour=<name>` to run one behaviour quickly while developing it
- [ ] Load test: optional 50-bot run (manual workflow_dispatch input)

## Requests from other streams
- **From client:** `tests/unit/run_all.gd` reports a test as `ok` even when a `SCRIPT ERROR` aborts it partway. Please make the runner (or CI) fail a test that logged a script error. *Director: second backlog item.*
- **From gameplay / world:** behaviour hook for `tests/bot_test/behaviours/*.gd`. *Director: done in PR #7; its interface is the standard and gameplay ports its clock behaviour to it.*
- **From world:** a night screenshot in the client smoke test via `AIMMO_TIME_OF_DAY`. *Director: in the backlog.*
