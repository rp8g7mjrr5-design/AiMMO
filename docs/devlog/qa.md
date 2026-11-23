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

## 2026-11-22 — fixed the ENet bot-test flake (max channels: 0)

PR #21 (night smoke) was merged before this fix landed on its branch, so it ships as its own
PR on `ws/qa/no-peer-relay`.

After the integrator merged `main` into #21, both of its CI runs failed the 45s ENet bot
test with `server: ERROR: Unable to send packet on channel 0, max channels: 0` (the same
error made `main` red on #19's push run). `Server._send()` already skips peers that aren't
`STATE_CONNECTED`, so the send wasn't ours: SceneMultiplayer's `server_relay` (on by
default) makes the server tell every client about every other client's connect/disconnect,
and those ADD/DEL_PEER notices go straight to the ENet peer with no liveness check. When
bots reconnect together, a notice can hit a peer ENet has already reset (channel count 0).
Fix (qa crash-fix exception, one line in `game/server/server.gd`, gameplay-owned):
`server_relay = false` before the peer is set. Nothing uses the relay: clients only
`rpc_id(1, ...)` and learn about other players from `s2c_player_joined`. It also stops
leaking every peer id to every client. New behaviour `qa_no_peer_relay.gd` asserts a bot
only ever knows peer 1; without the fix it failed on every bot (max_known_peers=4 with 4
bots), with it max_known_peers=1. Couldn't reproduce the original error locally (fast
machine, 5 green ENet runs before the fix), so the evidence is the code path plus the
behaviour check; if the error ever comes back, it's somewhere else.

## 2026-11-22 — save-compat test for every fixture

**Built:** `tests/unit/test_qa_save_compat.gd`. For each `tests/fixtures/*.sql` it creates a
throwaway database (`aimmo_compat_<pid>_<ticks>_<fixture>`, dropped afterwards), migrates it only
to the schema the fixture was written for, inserts the fixture, snapshots the raw rows, then
opens it with the real `PgStore` (which runs every later migration, as a deploy does) and checks,
for every account: password hash unchanged, the loaded character is the stored one (same id,
name, appearance seed, yaw, position after `Terrain.clamp_to_world`), every `CharacterData`
field is present, loading created no new characters, and a save + reload round-trips. No
per-fixture code: gameplay's Week 02 inventory fixture is picked up automatically.

**Which schema a fixture is "from":** a header line `-- schema-version: NNNN` if present;
otherwise the test tries 0001, then 0001-0002, ... and uses the first schema the fixture's
INSERTs fit. I can't edit `tests/fixtures/` (gameplay owns it), so the existing week00 fixture
has no header and inference was the only way to cover it; a fixture always fails on a schema
older than the columns it uses, so the first fit is its shape. Asked gameplay (their backlog)
to add the header to new fixtures anyway.

**Why a database per fixture:** the shared `DATABASE_URL` database keeps state between runs.
While proving the test, I added a deliberately bad migration (`UPDATE characters SET
appearance_seed = 0`) via `AIMMO_MIGRATIONS_DIR`. The new test caught it ("appearance expected
1234, got 0"). The bad run then left `0002_bad` recorded in my local shared DB, and the old
`test_save_compat.gd` stayed red until I recreated the DB. The new test can't be poisoned like
that. Also noticed: the old test caught the bad migration only because the legacy row already
existed from an earlier run (its INSERT is `ON CONFLICT DO NOTHING` and runs after migrations).
On a fresh DB it would have inserted the row after the bad migration and passed. Kept the old
test (it also checks the old password still verifies); retire it once the new one covers that.
My first version applied fixtures on top of all migrations and missed the bad migration
completely, which is why it now builds the old schema first.

**Needs:** a role allowed to `CREATE DATABASE`. CI's postgres service user is the superuser; a
role without it fails the test with a clear message instead of skipping silently.

**Tests:** 116 unit tests pass with Postgres (fresh DB) and without it; bot test 8 bots x 180s WebSocket + Postgres passed in 185s.
Client smoke not run: nothing the client loads changed.

**Next run:** triage playtest.md, then the health endpoint / heartbeat for Railway (needs a
small gameplay-owned hook in `server.gd` or a log line qa can watch; look at what Railway's
healthcheck can do over TCP/WebSocket first). When inventory lands, extend `_check_account`
to compare item rows before and after.

## 2026-11-22 (evening) — save-compat now checks every saved pack

Playtest inbox still empty, no open qa PR, budget 5/40. Picked the save-compat follow-up
over the Railway health check because inventory (#30, `0002_inventory_items`) and
gathering (#34) have landed, so packs are now player data that the save-compat test didn't
look at. The health check needs a gameplay-owned hook and a look at what Railway's
healthcheck can do over a WebSocket port; it is next.

**Built** (all in `tests/unit/test_qa_save_compat.gd`):
- Before any current code runs, the test snapshots every `inventory_items` row (if the table
  exists in the fixture's schema; a 0001-era fixture gives empty packs, which is correct).
- After the current `PgStore` opens and migrates it, every character's loaded pack must equal
  its stored rows exactly: same quantities, qty-0 rows kept, unknown item ids kept, nothing new.
- The round-trip now also changes the pack (`changed_pack`: first item used up to 0, the rest
  +1 capped at `MAX_STACK`, plus a new stack of a real item), saves, reloads, and reads
  `inventory_items` directly to check the table holds exactly what was saved.
- Whole-table row count after loading and saving is never below the stored count (rows are
  never deleted).
- Password check: a fixture's plain password comes from a `-- password: X` header or the
  existing comment form `Password is "X"`, and every account in it must still verify. That
  covered the last thing the old shared-DB `test_save_compat.gd` did, so I deleted it.
  Asked gameplay (their backlog) to update the stale comment in `week00_characters.sql`
  (gameplay owns fixtures; I didn't edit it).

**Proved it catches things** (all reverted):
- Extra migration `0003_bad.sql` = `DELETE FROM inventory_items WHERE qty = 0` via
  `AIMMO_MIGRATIONS_DIR`: fails with "pack on load: 'stone' (x0) lost" (and test_add_only
  also fails on the DELETE).
- `PgStore._with_inventory` changed to skip unknown item ids: fails with "'retired_relic' (x1)
  lost". gameplay's own `test_week00_pack_loads` also caught it.
- Fixture comment changed to the wrong password: fails with "the old password no longer logs in".

**Didn't work first time:** checked table existence with `to_regclass(...) IS NOT NULL`;
PgClient returns booleans as the string "t", and comparing that to `true` is a SCRIPT ERROR
in GDScript. Switched to `count(*)` from `pg_tables`.

**Tests:** 146 unit tests pass with Postgres (fresh DB) and without; bot test 8 bots x 180s WebSocket + Postgres passed in 185s.
Client smoke not run: nothing the client loads changed.

**Next run:** triage playtest.md, then the Railway health check / heartbeat.

## 2026-11-22 (night) — old clients must be told to update, not left hanging

Playtest inbox still empty, no open qa PR, budget 6/40. The top two backlog items (real
gathering in CI, chat-is-for-talking) are blocked on gameplay's v3 and `--dev-commands`,
which haven't landed. Took the protocol-mismatch test because the backlog pairs it with v3
and v3 is due tomorrow, so it is most useful *before* that bump.

**Found a real bug-in-waiting.** Godot numbers a node's RPCs by sorted method name and sends
the number. I added the planned `c2s_gather_start` to `net.gd` locally (bumped to v3) and
connected a v2 client: its `c2s_login` landed on the server's `c2s_input`, the server logged
`Cannot convert argument 2 from String to Vector2`, and the client waited forever with no
message. A v1 client against today's v2 server is fine only by luck: v2 added
`s2c_world_time`, which sorts last. Godot's "rpc node checksum failed" ERROR is logged in
both cases but the call still goes through, so the checksum is not a guard. Filed the fix
options with gameplay (new RPCs on a child node of `Net`, or names that sort last).

**Built:**
- `tests/protocol/net_v1.gd`, `net_v2.gd`: frozen copies of `net.gd` at each protocol (v1 from
  `ca6ce1e^`). `old_client.gd`: headless client from any frozen copy, any protocol number.
- `tests/protocol/run_protocol_test.py`, new CI step before the bot test (about 3 s): each
  frozen copy plus current RPCs with N-1 and N+1 must get a reply within 8 s that refuses
  login and says to update, with no game traffic first; then a current client must still log
  in, the server must stop cleanly, and no server ERROR except the checksum notice.
- `tests/unit/test_qa_protocol_compat.gd`: fast check that `c2s_login`/`s2c_login_result`
  keep their RPC number and argument types against every frozen copy, names the RPC that
  shifted them, requires a frozen copy for every older protocol, plus a self-test that
  injects `c2s_gather_start` into the v2 copy. `KNOWN_LOCKED_OUT` exists for a deliberate,
  reasoned lockout; keep it empty.

**Proved it catches it** (reverted): with the simulated v3 change, the live test reports
"a v1 client: HANGS at login" and "a v2 client: HANGS at login", and the unit test fails
with "c2s_login is RPC #2 for old clients but #3 now (new RPCs sorting before it:
c2s_gather_start)".

**Didn't work first time:** `Script.get_rpc_config()` doesn't exist in 4.3 (SCRIPT ERROR,
and a `-s` script that errors in `_init` never quits, so it hung); the unit test parses
`@rpc` lines from the source instead. `root.multiplayer` is null in a SceneTree's
`_initialize`, so `old_client.gd` sets up on the first `_process`. My first self-test edited
today's `net.gd` and broke as soon as `net.gd` itself had the new RPC; it now builds on the
frozen v2 copy.

**Ownership note:** from v4 on, the bump PR needs `tests/protocol/net_v<old>.gd`. That is a
qa path; I told gameplay qa allows that one file in a bump PR. Integrator may want that in
`docs/workstreams.md`.

**Tests:** 165 unit tests pass with Postgres and without; protocol test passes over
WebSocket and ENet; bot test 8 bots x 180s WebSocket + Postgres passed in 185s. Client smoke not
run: nothing the client loads changed.

**Next run:** v3 gathering in CI if it has landed (and check v3 kept old clients informed),
otherwise the Railway health check.

## 2026-11-23 — Railway restarts a frozen server

Playtest inbox still empty, no open qa PR, budget 7/40. All three top items are still blocked:
real gathering in CI and chat-is-for-talking wait on gameplay's v3 (PR #49 open, not merged)
and `--dev-commands` (not started); camera smoke shots wait on client's action camera (PR #47
open). Took the next unblocked one, the hung-server restart.

**Why it mattered:** `railway.json` restarts `ON_FAILURE`, which only fires when the process
exits. A server stuck in a loop, a deadlock, or a Postgres call that never returns would sit
there accepting TCP connections and serving nobody until the owner noticed.

**Built (all in qa paths, no server code touched):**
- `docker/probe.sh`: bash `/dev/tcp` WebSocket handshake, passes on `HTTP/1.1 101`. Godot only
  answers handshakes from its main loop, so it is a real liveness check; the kernel still
  accepts the TCP connect for a frozen process, so a plain port check would not be. No new
  packages: the slim image already has bash and coreutils `timeout`.
- `docker/entrypoint.sh` (now bash): watchdog waits up to 180 s for the first answer, then
  probes every 20 s (5 s timeout). After 3 misses in a row (~1 minute) it touches the stop
  file so a slow-but-alive server can still save everyone, waits 20 s, then `kill -KILL`s it.
  Either way the entrypoint exits 70 so Railway restarts it (a clean stop after the
  watchdog fired would otherwise exit 0 and *not* be restarted). Off for ENet (it probes
  WebSocket) and with `AIMMO_WATCHDOG=off`. SIGTERM behaviour is unchanged. Timings are
  env vars, listed at the top of the script.
- `tests/ops/run_watchdog_test.py`, new CI step (~50 s): runs the real entrypoint with short
  timings. healthy (no false alarm, SIGTERM still exits 0 and stops cleanly), recovers
  (SIGSTOP, watchdog asks it to stop, SIGCONT, server saves and stops cleanly, exit 70,
  nothing killed), frozen (SIGSTOP for good, killed, exit 70 in ~16 s), enet (watchdog off),
  probe (fails fast on a closed port, honours its timeout on a silent listener).

**Proved it catches it:** with `AIMMO_PROBE=/bin/true` (a probe that always passes) the frozen
scenario fails with "entrypoint was still running 31s after the server froze"; with
`AIMMO_WATCHDOG=off` frozen and recovers both fail.

**Known costs:** each probe makes the server log a `peer N connected` / `disconnected before
logging in` pair (~3/min). Asked gameplay (optional) to quiet those. Killing a truly frozen
server loses progress since the last autosave; it was already lost while frozen.

**Didn't work:** wanted to build the image locally to run the test inside it, but Docker
Hub returned 429 on `debian:bookworm-slim`. Not verified inside the image; the scripts only
use bash, coreutils and the godot binary already there. Added a backlog item to build the
image in CI. No unit test: this is shell/ops, the live test is its test, and nothing players
do changed, so no bot behaviour either.

**Tests:** 179 unit tests pass with Postgres; protocol test passes; watchdog test passes;
bot test 8 bots x 180s WebSocket + Postgres passed in 185s. Client smoke not run: nothing the
client loads changed.

**Next run:** v3 gathering in CI if #49 has merged, otherwise camera shots if #47 has, otherwise
build the image in CI.

## 2026-11-23 — Camera smoke shots from the action camera

Playtest inbox still empty, no open qa PR, budget 8/40. Client's action camera (#47) and
gameplay's server-side gather channel (#49) both merged, but `net.gd` is still protocol v2:
there is no `c2s_gather_start` yet, so real gathering in CI is still blocked, and nobody has
started `--dev-commands`, so chat-is-for-talking is too. Took the third item, camera smoke shots.

**Built (qa paths only):**
- `tests/client_smoke/camera_shots.gd`: a SceneTree script that instantiates the real
  `main.tscn` (main.gd reads the same user args, so it is the real client logging in to the
  smoke server), then inspects the live client node instead of needing a test hook in
  client-owned code. Two shots:
  - `camera.png` after login: reticle visible and centred within 2 px, chest projected with the
    real `Camera3D.unproject_position` at least 20 px left of centre and on screen, camera above
    ground, picture not black. Measured: chest at x 555 of 1280.
  - `camera-hill.png`: searches a 2 m grid 30 m around spawn for the dry spot with the most
    ground rising within 6 m behind it, walks there with real input (`Input.action_press`
    on `move_forward` with the camera yaw aimed at it, so the server moves the character),
    turns the camera to back onto the rise, pitch to `PITCH_MAX`, zoom to `DIST_MAX`. Asserts
    the arm pulled in (otherwise the shot proves nothing), the camera and an 8-point ring of
    twice the near plane are above `Terrain.height`, character in front, picture not black.
    Measured: spot (26, 3.5, 20), ground rises 2 m behind, arm 1.30 of 6.00, camera 0.4 m
    above ground.
- `run.sh` runs it after the night shot with a separate character, `SmokeCamera`, because it
  walks away from spawn and the day/night shots must keep starting at spawn when a local run
  reuses the data folder. Adds about 20 s. The CI artifact already uploads the whole folder.
- `tests/unit/test_qa_camera_shots.gd`: the slope search still finds a dry slope with at least
  1 m of rise near spawn, and the chosen yaw is the steepest. If world flattens the meadow, this
  fails with a clear reason instead of the smoke test quietly shooting flat ground.

**Proved it catches it:** with `clear_arm` and the ground clamp removed from `ActionCamera.step`
and `SHOULDER` flipped to -0.6, the smoke test failed with all three: character not left of
centre (x 725), arm did not pull in (6.00 of 6.00), camera in the ground (y 0.81, ground 5.00).
Restored the file before committing; this PR does not touch `game/client/`.

**Didn't do / didn't work:** first version only looked up from spawn; spawn is flat, so it was
not really "against a hill". Added the walk. No pixel test of the reticle itself (the ring is
7 px at 55% alpha and software GL antialiasing makes a pixel match brittle); it checks the
Control's visibility and rect instead. No bot behaviour: nothing players do changed, and the
bot test already runs the camera maths on real positions (`client_action_camera`).

**Tests:** 205 unit tests pass with Postgres and without; client smoke passes (all five
shots); bot test 8 bots x 180s WebSocket + Postgres passed in 185s.

**Next run:** v3 gathering in CI if `c2s_gather_start` is on main, otherwise build the Docker
image in CI (watchdog follow-up).

## 2026-11-23 — Fun metrics in the bot test, and one command queue per bot

Playtest inbox still empty, no open qa PR, budget 9/40. `main` is still protocol v2 (no
`c2s_gather_start`) and nobody has added `--dev-commands`, so the first two backlog items are
still blocked. Took the client's flaky `/time` request first (requests before backlog), then
the next unblocked item, fun metrics.

**Flake fix (bot harness, qa paths):** `bot.send_command(text, on_sent)` queues slash commands
and sends one every `CHAT_COOLDOWN + 0.15` s. All six behaviours that typed commands
(`client_gather_prompt`, `gameplay_chat_commands`, `_crafting`, `_gather_channel`, `_gathering`,
`_inventory`) now go through it; I edited those files because they are under `tests/`, which qa
owns, and the change is one line each. `gameplay_crafting` judges its distance to the bench in
the `on_sent` callback, because the line can now wait up to ~1.4 s (max seen) behind others.
The queue is cleared on login (a line queued before a disconnect belongs to the old session),
and overflow (16) is a bot failure. Root cause of the flake: the server answers only one
`TOO_FAST` per cooldown window, so when two behaviours collided, the second line was dropped
with no answer at all; 4 unlucky tries in a row failed the run. Bot stats now include
`commands_sent` and `max_command_wait`.

**Fun metrics:** `tests/bot_test/fun_metrics.gd` (pure maths), behaviour `qa_fun_metrics`
(watches `system_message` and the new `bot.command_sent` signal), `tests/bot_test/fun_report.py`
(roll-up, table, limits, baseline). Every run prints a per-bot table and writes
`fun_metrics.json` into the bot-test work dir, which is now kept after a pass so the CI artifact
has it. The 180 s CI run has `--fun-check`; the 45 s ENet run only prints.

Definitions I chose, and why:
- Feedback = any system line to this bot except "X has arrived/left", plus items. Other bots'
  `hello from` chatter is not feedback: a player alone wouldn't get it, and with 8 bots it would
  make dead time ~0 forever.
- `longest_dead_s` (no feedback at all, per play stretch, offline excluded) came out 41-69 s
  median and up to 91 s worst: bots gather once per login and then wander. That's a bot-script
  artefact more than the game, so it's reported and in the JSON, not gated.
- `longest_wait_s` is the "dead time while acting" the backlog asked for: from the first
  unanswered command to the next feedback. Limited to 45 s on the worst bot, baseline median
  0.05 s. On v2 every command is answered at once, so it's ~0.01 s; it starts mattering with
  timed gathering.
- First reward: median 7.4-8.5 s over six runs, but the worst bot hit 67 s and 82 s in two runs
  (8 bots, ~14 nodes near spawn, all spent). A 90 s limit would flake, so the limit is 120 s for
  now; follow-up to tighten.
- Regression rule: a median that is >20% worse than `fun_baseline.json` **and** worse by more than
  its slack (3 s first reward, 2 s wait, 1.0 items/min) fails. The slack is there because bot
  names (and so routes) change every run.
- `loops_completed` counts crafts. It's 0 today: bots never hold 3 ash + 2 stone.

**Didn't work:** first version marked an action from `on_play` by watching `commands_sent`.
Behaviours run before the harness sends, and on localhost the reply landed before the next
frame, so the action was recorded *after* its answer and "waited" until the next feedback
(70-80 s fake waits). Fixed by emitting `command_sent` at the send itself.

**Tests:** 246 unit tests pass with Postgres (new `test_qa_fun_metrics.gd`: metric maths, the
command queue spacing/order/callback/overflow, and a lint that no behaviour calls `c2s_chat`);
7 Python tests for `fun_report.py` (new CI step); bot test 8 bots x 180 s WebSocket + Postgres
with `--fun-check` passed twice on the final code (four earlier runs used to pick the numbers);
45 s ENet bot test passed. Client smoke not run: nothing the client loads changed.

**Next run:** v3 gathering in CI if `c2s_gather_start` is on main (and fold it into
`qa_fun_metrics`), otherwise build the Docker image in CI.
