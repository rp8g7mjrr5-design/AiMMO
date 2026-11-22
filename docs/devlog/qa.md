# Devlog: qa workstream

Newest entries at the bottom. Each run appends what it built, what didn't work, and notes to its next run.

## 2026-11-22 — bot behaviour plugin hook

**Built:** `tests/bot_test/bot_behaviour.gd`, a base class with hooks `setup(net)`,
`on_login(reconnect, character)`, `on_play(delta)`, `on_snapshot(tick, entries)` and
`on_finish()`, plus `fail(msg)` and `stat(k, v)`. `bot.gd` loads every `*.gd` in
`tests/bot_test/behaviours/` (sorted by file name) and calls the hooks; behaviour stats land in
the result JSON under `stats.behaviours.<name>` and are printed in the bot-test summary.
First behaviour: `qa_snapshot_flow.gd` asserts snapshots keep arriving while playing
(average at least 25% of TICK_RATE, no gap over 5s). Unit test `test_qa_bot_behaviours.gd`
checks every shipped behaviour loads and extends the base, that a bad script is reported
(not silently skipped), and that the snapshot-flow logic passes a healthy stream and fails a
stalled one.

**Decisions:** behaviours `extends "res://tests/bot_test/bot_behaviour.gd"` by path instead of
a `class_name`, so test-only code doesn't register global classes in the game project.
Thresholds in `qa_snapshot_flow` are loose on purpose (CI runs 9 Godot processes on a small
runner); locally all 8 bots measured 20.0 snapshots/s with a max gap of 0.17s. A behaviour
that fails to load fails the bot (and the unit test) instead of being skipped, so a broken
behaviour from another stream can't quietly turn off its coverage.

**Tests:** 38 unit tests pass (with Postgres); bot test 8 bots x 180s WebSocket + Postgres
passed in 185s; 8 bots x 45s ENet passed; client smoke passed.

**Next run:** the performance check (tick time, memory, bandwidth per player) can be built
as a server-side log plus a behaviour or a run_bot_test.py assertion. Movement is still
owned by bot.gd; if a stream needs bots to walk to a target (e.g. a resource node), add a
small `bot.steer_to(pos)` helper rather than letting behaviours fight over `move`.

## 2026-11-22 — unit runner fails tests that hit a SCRIPT ERROR

**Built:** `tests/unit/run_all.gd` now re-runs itself as a child process
(`-- --unit-child`) that prints `[unit] begin/end <test>` markers around each test, and the
parent reads the child's combined stdout+stderr with `tests/unit/unit_log.gd`. A test fails if
it has a failed check, logs a `SCRIPT ERROR`/`ERROR` line, or begins and never ends (child
crashed). Errors outside any test (e.g. a parse error while loading a file) also fail the run,
as does a non-zero child exit code or zero tests run. `TestCase.expect_error("part")` lets a
test that deliberately triggers a `push_error` say so; an expected error that never shows up
fails the test. `--dir=<path>` runs another folder of tests. The CI/CLAUDE.md command is
unchanged. New `test_qa_unit_runner.gd`: parser cases plus an end-to-end run of the real
runner on a temp folder whose test dies halfway (must exit 1 and name the line).

**Decisions:** Godot 4.3 has no in-process hook for script errors (the `Logger` API only
arrived in 4.5), and a script error just makes the called function return, so the only
reliable signal is the log. A child process was chosen over a CI grep so the documented
command does the right thing locally too, and so each error is pinned to its test. I made
`ERROR:` lines fail too, not just `SCRIPT ERROR:`, because the whole suite (73 tests, with
Postgres) logs none today; `WARNING:` lines are ignored. Checked ordering of stdout vs stderr
through `OS.execute` empirically: lines stay in order (debug builds flush stdout on print).

**Didn't do / known gaps:** `OS.execute` is blocking, so output appears only when the child
finishes, and a hung test hangs the run until the CI job timeout (30 min). Program output is
printed first, then the ok/FAIL list, so output is no longer interleaved with test names.
If another stream's open PR has a test that logs an `ERROR`, it will go red after this merges:
the fix is `expect_error(...)` in that test, or fixing the error.

**Tests:** 73 unit tests pass with Postgres (fresh DB); a test with a deliberate script error
injected into `test_misc.gd` turned the run red with the file and line; bot test 8 bots x 180s
WebSocket + Postgres passed in 185s. Client smoke not run: nothing the client loads changed.

**Next run:** triage `docs/playtest.md` (still empty), then the night client smoke test
(world's request). Consider `OS.execute_with_pipe` plus a per-run timeout if a hung test ever
bites.

## 2026-11-22 — night screenshot in the client smoke test

**Built:** `tests/client_smoke/run.sh` now takes three client shots: `login.png`,
`world.png` pinned to noon (`AIMMO_TIME_OF_DAY=0.5`) and a new `world-night.png` pinned to
midnight (`AIMMO_TIME_OF_DAY=0.0`). Both world shots land in the existing CI artifact
(`build/client-smoke/`). New `tests/client_smoke/image_stats.gd` (run with `godot --headless
-s`) measures mean Rec. 709 luminance of each and fails the smoke test if the day shot is
near-black (< 0.15, world didn't render), the night shot is pure black (< 0.01), or night is
not clearly darker than day (> 80% of day). Its output goes to `brightness.log`, so the
existing SCRIPT ERROR grep covers it. The run now also requires two logins (the night client
logs in again as the same character, so it doubles as a reconnect/"Welcome back" check).
Unit test `test_qa_smoke_brightness.gd` covers the luminance maths and each failure case.

**Decisions:** used the client-side pin (`AIMMO_TIME_OF_DAY`, read by
`DayNight.pin_from_env()`) rather than restarting the server with `--clock-offset`, because
one server serves both shots and the pin also drives the time dial, so the HUD reads
"12:00 · Day" / "00:00 · Night". Pinning the day shot to noon makes it deterministic; before,
it showed whatever the wall clock said, so a CI run at the wrong hour gave a night picture
labelled "world". Brightness check in Godot rather than Python so CI needs no PIL. Thresholds
are loose on purpose: measured day 0.735, night 0.081 under xvfb + Mesa llvmpipe.

**Didn't do:** no dusk shot yet (colours are still being tuned by world), no pixel-diff
against a golden image (procedural art changes every day, so it would be red constantly).

**Tests:** 92 unit tests pass with Postgres; bot test 8 bots x 180s WebSocket + Postgres
passed in 185s; client smoke passed three times locally.

**Next run:** triage playtest.md, then the health endpoint / heartbeat for Railway, or the
save-compat test before gameplay's Week 02 inventory lands.
