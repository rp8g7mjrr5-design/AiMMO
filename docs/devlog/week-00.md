# Week 00 devlog: First Steps

## Plan
Week 0 is the foundation every later week builds on. The headline feature is "a shared world you can walk around in", which needs every layer to exist and be tested:

1. Godot 4 project with one entry point and three roles (server, client, bot).
2. Authoritative dedicated server: login, movement, chat, snapshots at 20 Hz.
3. Postgres persistence with add-only migrations, plus a JSON fallback for local dev.
4. A procedural world: terrain, water, trees, rocks, sky, character avatars, sounds.
5. Desktop client: login screen with patch notes, third-person camera, chat.
6. Unit tests and the bot test (8 bots, 3 minutes, disconnect and reconnect, data-loss check).
7. CI: test on every push and PR; on `main`, deploy to Railway and publish client builds as a GitHub Release.
8. Docs: design bible, roadmap, playtest inbox, this devlog, changelog.

## What shipped
All of the above. Key decisions and why:

- **Postgres driver written in GDScript** (`game/server/pg_client.gd`). Godot has no Postgres client and I did not want a sidecar process. It speaks the v3 wire protocol with SCRAM-SHA-256 (Railway's default), MD5, and cleartext auth; uses the extended protocol with bound parameters for anything containing player input. Tested against Postgres 16 locally and in CI.
- **Migrations run on server start** from `db/migrations/`, each in a transaction, recorded in `schema_migrations`. A unit test fails the build if a migration contains DROP, RENAME, TRUNCATE, DELETE FROM, or ALTER COLUMN, or if numbering is not sequential.
- **Save compatibility** lives in one place: `CharacterData.normalize()` gives every field a default and repairs bad values. `tests/fixtures/week00_characters.sql` is a character stored the Week 00 way; `test_save_compat` loads it every run. When a later week changes the schema, add a fixture for the old shape.
- **Transport: WebSocket in production, ENet otherwise.** CLAUDE.md names ENet, but as far as I know Railway's public networking only proxies TCP, and ENet is UDP. Godot's `WebSocketMultiplayerPeer` is a drop-in for the same high-level multiplayer API, so all game code is transport-agnostic. The Docker image sets `AIMMO_TRANSPORT=websocket`; the client picks WebSocket when the address starts with `ws://`. The bot test runs over WebSocket (the production path) for the full 3 minutes and over ENet for a shorter smoke run. If Railway adds UDP, switching back is one environment variable.
- **The server runs from source in Docker** (`godot --headless --path game`) rather than from an exported binary. This avoids downloading ~1 GB of export templates on every Railway build. The `server` export preset still exists for anyone who wants a single binary.
- **Graceful shutdown.** Godot does not handle SIGTERM, so `docker/entrypoint.sh` traps it and drops a stop file; the server polls for it, saves everyone, and exits. Autosave every 30 s caps any loss if that fails.
- **Passwords** are PBKDF2-SHA256, 20,000 iterations, 16-byte salt, implemented on Godot's native HMAC. Unit-tested against known vectors.

## What didn't work / what I changed
- TLS to Postgres: Godot's `TLSOptions.client_unsafe()` still failed the handshake against a self-signed certificate in my local test. Railway's private network URL does not use TLS, so `sslmode` now defaults to `disable`; `prefer` falls back to plain on failure; `require` is supported but untested against Railway's public proxy.
- First pass let `-s tests/unit/run_all.gd` resolve outside `res://`. Godot resolves `-s` paths inside the project, so `game/tests` is a symlink to the top-level `tests/` folder (same for `game/CHANGELOG.md`). This keeps the layout from CLAUDE.md and the test command working unchanged.

## Known bugs and limitations
- No client-side prediction: your own character moves when the server says so. On high latency it feels floaty. Scheduled for Week 01.
- Database calls are synchronous on the server's main thread. Fine at this scale (a save is one small UPDATE), but logins briefly stall the tick. Backlog item.
- Snapshots include every player. Fine below ~100 players; interest management is in the backlog.
- One global chat channel, no moderation tools yet.
- macOS builds are ad-hoc signed only; macOS will warn on first launch (right-click → Open).

## Setup the owner needs to do (one time)
See the PR description for Week 00. In short: a Railway project with Postgres and a service built from this repo's Dockerfile, a TCP proxy on the server port, and the `RAILWAY_TOKEN` secret plus `RAILWAY_SERVICE` and `AIMMO_PUBLIC_SERVER` variables in GitHub.

### Setup status (end of Week 00)
The owner created the Railway project, Postgres, the `AiMMO-Server` service, and a TCP proxy at `hopper.proxy.rlwy.net:29419` (public game address `ws://hopper.proxy.rlwy.net:29419`, baked into client builds via the `AIMMO_PUBLIC_SERVER` variable). `RAILWAY_TOKEN` was added as a repository secret. If a later deploy job skips or fails on auth, the token is the first thing to check.

## Notes to next week's self
- Check `docs/playtest.md` first. Nobody has played yet, so the first real reports will come after Week 00 deploys.
- Week 01 is Day and night. Keep the clock on the server and send only the time offset at login plus a periodic correction; the sky is pure procgen on the client.
- Add client-side prediction in Week 01 too: run `Movement.step` locally on input and reconcile with snapshots using the input `seq` the server already tracks (add an acked seq to snapshots, which is a protocol change: bump `PROTOCOL_VERSION`).
- If the Railway deploy job is skipped in CI, it means the `RAILWAY_TOKEN` secret is not set yet. That is the owner's step, not a bug.
- Godot version is pinned to 4.3-stable in CI, Docker, and the release job. Upgrade all three together or not at all.

## Integrator, 2026-11-22 11:00 UTC

Merged #6 (client settings), #7 (qa bot-behaviour hook), #8 (gameplay world clock, protocol v2), #9 (world day/night sky) and #10 (director backlogs) in that order, oldest first.

- #7 and #8 collided at runtime: qa's `BotBehaviour.load_all()` fails any behaviour that doesn't extend `bot_behaviour.gd`, and gameplay's `gameplay_world_clock.gd` extended `RefCounted`. #7 merged first, so I ported the gameplay behaviour to the qa interface while merging main into #8 (same checks; verified locally with 54 unit tests and an 8-bot 45 s WebSocket bot test). Director had already ruled qa's interface the standard.
- Backlog files (`docs/workstreams/*.md`) conflicted on every merge. For #9 I kept both sides; for #10 I took the director's sections as its PR asked, then marked #6 to #9 merged and ticked the ported-behaviour item.
- Each worker merge triggered a main CI run, so the server redeployed more than once this run. Next run: merge everything first and let a single integrate/ PR be the last push, where the order allows.
- Known: two clocks still exist (`SkyClock` on Unix time, `WorldClock` on the 2026-11-20 Chicago epoch). World and client have backlog items to unify them; noted as a known issue in the changelog.

## Integrator, 2026-11-22 12:00 UTC
- Merged #11 (client walk animation) and #13 (world shared-clock sky). Both stayed in their owned paths; their only cross-stream edits were "Requests from other streams" entries, which the procedure allows. No migrations, no assets, no secrets; each added unit tests and a bot behaviour.
- #13 conflicted with #11 in `docs/workstreams/world.md` (both touched the requests list). Kept both entries; CI re-ran green on the merged branch before merging.
- Changelog: #13's fragment said the server decides the sky, but the client doesn't call `DayNight.set_world_seconds` yet, so players still compute the shared schedule from their own clock. I worded the patch note and known issue to match what players actually get.

## Integrator, 2026-11-22 16:00 UTC
- Merged #21 (qa night smoke screenshot + day/night brightness check). Test-only, qa-owned paths, unit tests added. Merged main into the branch first (clean).
- Both CI runs on the merged branch failed on the bot-test flake `server: ERROR: Unable to send packet on channel 0, max channels: 0` (the same one logged for qa on PR #19). It passed on a rerun of the same commit, so I merged; the PR doesn't touch the server or bot test. The flake is getting more frequent (2 of 2 runs this time), so the qa request to guard that send should be qa's next item.
- Folded `qa-night-smoke` into the Week 00 changelog.

## Integrator, 2026-11-22 17:00 UTC
- Merged #24 (qa: turn off SceneMultiplayer `server_relay`, qa crash-fix exception in `game/server/server.gd`) and #22 (gameplay: `ResourceNodes`, 397 deterministic gathering nodes, data only).
- Out of oldest-first order on purpose: after merging main into #22, its push-event CI run failed on the `Unable to send packet on channel 0, max channels: 0` flake again while its PR-event run passed. #24 is the fix for exactly that, so it went first; #22 then re-ran green on top of it. If this error shows up again after #24, the relay was not the (only) cause: send it back to qa with the failing run link.
- Folded `gameplay-resource-nodes` and `qa-no-peer-relay` into the Week 00 changelog. Players can't interact with nodes yet, and the patch note says so.
- playtest.md still has no reports. Every stream backlog has 8+ items, so no refill needed.

## Integrator, 2026-11-22 18:00 UTC
- Merged #25 (client chat polish: in-game timestamps, idle fade, 150-line cap) and #27 (world resource-node props: visible ash, pine, stone and ember-sap nodes with depleted looks), oldest first.
- Both stayed in their owned paths. #27's only cross-stream edit is a "Requests from other streams" entry in the client backlog, which the procedure allows. No migrations, no imported assets, no secrets; each added unit tests and a bot behaviour.
- Merged main into each branch before merging (both clean, including the shared `docs/workstreams/client.md`), and each re-ran green. No sign of the `max channels: 0` flake this run, so #24 looks like it fixed it.
- Folded `client-chat-polish` and `world-resource-node-props` into the Week 00 changelog. Merged the 2 fragments' bullets into 3 notes; the props note says gathering isn't live yet.
- playtest.md still has no reports. Every stream backlog has 8+ items, so no refill needed.
