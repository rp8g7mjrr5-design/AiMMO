# Workstream: qa

Owns quality, tests, CI, and operations. See `docs/workstreams.md` for ownership.

## Backlog (top = next)
- [ ] **Top priority (director, owner request 2026-11-22): cover real gathering in CI** once gameplay's protocol v3 lands. Bot test: at least 4 of the 8 bots gather through `c2s_gather_start` (not `/gather`), including one cancel by walking away, two bots on one node, and a node emptied and respawned; assert inventories match the server's count and nothing desyncs across reconnect. Pair it with the protocol-mismatch test below, since v3 locks out old clients.
- [ ] **Second (owner direction 1, 2026-11-22): chat is for talking, in CI.** Start the bot-test server with `--dev-commands` once gameplay gates commands behind it, and add a bot behaviour against a server *without* the flag: a bot types `/gather`, `/bag` and `/who` and the test asserts nothing changed (no items, no node charge used), the line was not broadcast, and the "Chat is for talking" hint came back. Also a unit or lint check that `CHANGELOG.md` and `changelog.d/` never tell players to type a slash command.
- [x] **Third (owner direction 2): camera smoke shots.** Client smoke screenshots from the new over-the-shoulder camera (reticle visible, character left of centre), plus one with the camera backed against a hill to prove it never clips into terrain. (this PR, `ws/qa/camera-smoke-shots`: `tests/client_smoke/camera_shots.gd` drives the real client, walks to the steepest slope near spawn, asserts on the rendered Camera3D; `camera.png` and `camera-hill.png` in the CI artifact)
- [ ] Camera shots follow-up: once client's look-to-interact and gather bar land on v3, a third camera shot aimed at a node with the prompt and highlight visible (and assert `reticle.active`)
- [ ] Camera shots follow-up: a shot with the camera backed against a tree or rock (prop pull-in), not only terrain
- [x] Bot behaviour plugin hook (merged, PR #7)
- [x] Unit runner fails tests that hit a SCRIPT ERROR or log an ERROR (this PR, `ws/qa/unit-script-errors`)
- [ ] Triage `docs/playtest.md` every run and fix crashes first (2026-11-22 evening: still empty)
- [x] Client smoke test at night as well as noon, with both screenshots kept as CI artifacts and a day/night brightness check (this PR, `ws/qa/night-smoke`)
- [x] Railway restarts a hung server: watchdog in `docker/entrypoint.sh` probes a WebSocket handshake, asks a frozen server to save, kills it if it can't, exits 70 so `ON_FAILURE` restarts it; `tests/ops/run_watchdog_test.py` in CI (this PR, `ws/qa/hung-server-watchdog`)
- [ ] Watchdog follow-up: build the Docker image in CI (`docker build` + run the watchdog test inside the image) so a broken Dockerfile or a missing tool in the slim image fails before Railway does
- [ ] Watchdog follow-up: once the live server has run with it for a day, check Railway's logs for any `[watchdog] no answer` lines on a healthy server (long autosaves or GC pauses) and tune `AIMMO_WATCHDOG_*`
- [x] Save-compatibility test: load every file in `tests/fixtures/` with the current `CharacterData` and the current migrations on Postgres; must stay green when gameplay adds inventory (Week 02) (this PR, `ws/qa/save-compat-all-fixtures`)
- [x] Save-compat follow-up: once gameplay's inventory lands, check that every loaded character's items survive too (extend `_check_account` to compare `inventory_items` rows before/after), and retire the shared-DB `test_save_compat.gd` once the new test covers its password check (this PR, `ws/qa/save-compat-items`)
- [ ] Server performance check in the bot test: tick time, memory, and bandwidth per player logged and asserted under a budget
- [x] Protocol-mismatch test: an old-protocol client gets a clear "please update" message, not a hang (this PR, `ws/qa/protocol-mismatch`: frozen `tests/protocol/net_v1.gd`/`net_v2.gd`, live `run_protocol_test.py` in CI, unit `test_qa_protocol_compat.gd`; found that v3's `c2s_gather_start` would hang every v1/v2 client, request filed with gameplay)
- [ ] Protocol test follow-up: after v3 lands, confirm `net_v3.gd` is frozen when v4 bumps, and add a client-side check that the real login screen shows the "out of date" text (needs the client smoke harness to point at a server)
- [ ] Bot-test option `--only-behaviour=<name>` to run one behaviour quickly while developing it
- [ ] Load test: optional 50-bot run (manual workflow_dispatch input)
- [ ] Unit runner: stream child output and kill a hung test after a timeout (`OS.execute_with_pipe`)
- [ ] Client smoke: also a dusk shot (0.76) once world tunes dusk colours, and an HTML/markdown contact sheet of all screenshots in the CI artifact

## Requests from other streams
- **From integrator (2026-11-22):** flaky bot-test failure `server: ERROR: Unable to send packet on channel 0, max channels: 0` on the push run of PR #19 (passed on the PR run and on rerun of the same commit). Looks like the server sending to an ENet peer that is not fully connected or already gone. Please find and guard that send. *Fixed in `ws/qa/no-peer-relay` (qa crash-fix exception): it was SceneMultiplayer's server relay, see devlog. Bot behaviour `qa_no_peer_relay` keeps it off.*
- **From client:** `tests/unit/run_all.gd` reports a test as `ok` even when a `SCRIPT ERROR` aborts it partway. Please make the runner (or CI) fail a test that logged a script error. *Done in `ws/qa/unit-script-errors`: tests that mean to log an engine error call `expect_error("part of message")`.*
- **From gameplay / world:** behaviour hook for `tests/bot_test/behaviours/*.gd`. *Director: done in PR #7; its interface is the standard and gameplay ports its clock behaviour to it.*
- **From world:** a night screenshot in the client smoke test via `AIMMO_TIME_OF_DAY`. *Done in `ws/qa/night-smoke`: `world.png` is pinned to noon, `world-night.png` to midnight, and the run fails unless night is clearly darker than day but not black.*
