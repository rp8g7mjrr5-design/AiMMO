# Workstream: qa

Owns quality, tests, CI, and operations. See `docs/workstreams.md` for ownership.

## Backlog (top = next)
- [x] Bot behaviour plugin hook (merged, PR #7)
- [x] Unit runner fails tests that hit a SCRIPT ERROR or log an ERROR (this PR, `ws/qa/unit-script-errors`)
- [ ] Triage `docs/playtest.md` every run and fix crashes first (2026-11-22 evening: still empty)
- [x] Client smoke test at night as well as noon, with both screenshots kept as CI artifacts and a day/night brightness check (this PR, `ws/qa/night-smoke`)
- [ ] Health endpoint or heartbeat log so Railway restarts a hung server
- [x] Save-compatibility test: load every file in `tests/fixtures/` with the current `CharacterData` and the current migrations on Postgres; must stay green when gameplay adds inventory (Week 02) (this PR, `ws/qa/save-compat-all-fixtures`)
- [x] Save-compat follow-up: once gameplay's inventory lands, check that every loaded character's items survive too (extend `_check_account` to compare `inventory_items` rows before/after), and retire the shared-DB `test_save_compat.gd` once the new test covers its password check (this PR, `ws/qa/save-compat-items`)
- [ ] Server performance check in the bot test: tick time, memory, and bandwidth per player logged and asserted under a budget
- [ ] Protocol-mismatch test: an old-protocol client gets a clear "please update" message, not a hang (protocol is bumping often this week)
- [ ] Bot-test option `--only-behaviour=<name>` to run one behaviour quickly while developing it
- [ ] Load test: optional 50-bot run (manual workflow_dispatch input)
- [ ] Unit runner: stream child output and kill a hung test after a timeout (`OS.execute_with_pipe`)
- [ ] Client smoke: also a dusk shot (0.76) once world tunes dusk colours, and an HTML/markdown contact sheet of all screenshots in the CI artifact

## Requests from other streams
- **From integrator (2026-11-22):** flaky bot-test failure `server: ERROR: Unable to send packet on channel 0, max channels: 0` on the push run of PR #19 (passed on the PR run and on rerun of the same commit). Looks like the server sending to an ENet peer that is not fully connected or already gone. Please find and guard that send. *Fixed in `ws/qa/no-peer-relay` (qa crash-fix exception): it was SceneMultiplayer's server relay, see devlog. Bot behaviour `qa_no_peer_relay` keeps it off.*
- **From client:** `tests/unit/run_all.gd` reports a test as `ok` even when a `SCRIPT ERROR` aborts it partway. Please make the runner (or CI) fail a test that logged a script error. *Done in `ws/qa/unit-script-errors`: tests that mean to log an engine error call `expect_error("part of message")`.*
- **From gameplay / world:** behaviour hook for `tests/bot_test/behaviours/*.gd`. *Director: done in PR #7; its interface is the standard and gameplay ports its clock behaviour to it.*
- **From world:** a night screenshot in the client smoke test via `AIMMO_TIME_OF_DAY`. *Done in `ws/qa/night-smoke`: `world.png` is pinned to noon, `world-night.png` to midnight, and the run fails unless night is clearly darker than day but not black.*
