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

## Integrator, 2026-11-22 19:00 UTC
- Merged #29 (qa: save-compat test that builds each fixture's own old schema, inserts it, upgrades through every later migration with the real `PgStore`, and checks every character still loads and saves). Test-only, qa-owned paths; its one cross-stream edit is a "Requests from other streams" entry in gameplay's backlog. It drops only its own throwaway `aimmo_compat_*` databases, never the shared test DB.
- The branch was one commit behind (#28); merged main in (clean) and the Test check re-ran green before merging. No `max channels: 0` flake again.
- Folded `qa-save-compat-all-fixtures` into the Week 00 changelog next to the other "Behind the scenes" notes, worded for players.
- playtest.md still has no reports. Every stream backlog has 8+ open items, so no refill needed.

## Integrator, 2026-11-22 21:00 UTC
- Merged #33 (client compass strip), #35 (world lanterns and night glow) and #34 (gameplay `/gather`), oldest first by CI readiness. #34 was still testing when the run began, so #35 went in before it.
- All three stayed in their owned paths. #34's only cross-stream edit is a "Requests from other streams" entry in the client backlog. No migrations, no protocol bump, no imported assets, no secrets; each added unit tests and a bot behaviour.
- #35 and #34 were behind main after the earlier merges; merged main into each (clean, including the shared `docs/workstreams/client.md`) and each re-ran green before merging.
- Folded `client-compass`, `gameplay-gathering`, `world-lamps-night-glow`, and the leftover `gameplay-inventory` fragment into the Week 00 changelog. Dropped the inventory note's "empty for now" line since gathering now fills the pack.
- playtest.md still has no reports. Every stream backlog has 8+ open items, so no refill needed.

## 2026-11-22 (evening) — integrator

Merged #37 (qa save-compat checks packs), #38 (director: how gathering feels), #39 (client: press E to gather), #40 (director: owner directions), #41 (world: birches, mossy boulders, wildflowers) and #42 (gameplay: crafting rules and tools). #40 also edited `CLAUDE.md`, which is integrator-only, so I took that line out of the director's branch and added the same pointer to "Owner directions" here in the integrate PR. Resolved backlog conflicts in `docs/workstreams/client.md` and `gameplay.md` by keeping the more recent, more specific items (the shipped stopgap gather prompt; crafting done plus the `c2s_craft` follow-up). Note for gameplay: the planned `--dev-commands` gate will stop the client's E key (it sends `/gather` as chat) on the live server, so ship the gate only after `c2s_gather_start` is wired in the client.

## Integrator, 2026-11-22 23:30 UTC
- Merged #44 (world: node glow and gather hit reactions, `NodeFx`) and #45 (qa: protocol-mismatch test for old clients), oldest first. Both were behind main; merged main in (clean) and each re-ran green before merging.
- Both stayed in their owned paths. Cross-stream edits are only "Requests from other streams" entries (client and gameplay backlogs). No migrations, no protocol bump, no imported assets (NodeFx is all code), no secrets; each added unit tests and #44 a bot behaviour.
- The world glow and hit effects are not visible to players until the client calls `NodeProps.set_highlight` / `play_hit`, so I worded that changelog line as "switches on with the next client update" instead of claiming it is live.
- #45 found that adding `c2s_gather_start` to `net.gd` as planned would hang v1/v2 clients at login (Godot numbers RPCs by sorted name). Gameplay has the fix options in its backlog; CI now fails if it happens. Per qa's note, added a line to `docs/workstreams.md`: from v4 on, a protocol-bump PR may add the frozen `tests/protocol/net_v<old>.gd` even though it is a qa path.
- playtest.md still has no reports. Every stream backlog has 11+ open items, so no refill needed.

## Integrator, 2026-11-23 05:30 UTC
- Reviewed #67 (client: the game updates itself at launch) and #69 (world: camera clearance shapes for decorative props), both merged by auto-merge with a green Test check.
- #67 also edited `.github/workflows/ci.yml` and `.gitignore` (qa) and `README.md`. The PR says so and was an owner request from a project thread; the CI change only adds the release-job steps the updater needs (build id, game packs, `update.json` uploaded last). Accepted without a revert. Main's run for it was green, Railway redeployed and the release job succeeded.
- #69 stayed in world paths; its only cross-stream edit is a "Requests from other streams" entry in the client backlog. Worded its changelog line as "switches on as soon as the camera picks it up" since the client wiring is still pending.
- #70 (qa: Docker image test) is open with auto-merge on. Its first run failed in the new image test with `ERROR: Failed to send ID to newly connected peer.` Likely the test's own raw WebSocket handshake probe closing before Godot sends the peer ID, but it could be a real server log; qa should check next run. Auto-merge waits on a green Test, so nothing to do here.
- Folded `client-auto-update` and `world-deco-solids` into the Week 00 changelog.

## Integrator, 2026-11-23 06:30 UTC
- Reviewed everything merged since the 05:30 run, oldest first: #73 (client: camera clears decoration, bench glow, craft-window race fix), #76 (client: F1 controls overlay) and #75 (gameplay: protocol v3, real gathering messages on `Net/Play`, `ack_seq` in snapshots). All merged by auto-merge on a green Test check; all stayed in their owned paths (cross-stream edits are only "Requests from other streams" entries), no migrations, no imported assets, no secrets, unit tests and bot behaviours added. #75's "Why it's more fun" holds: its second commit removed the 1.5 s cooldown between timed gathers after CI's fun check caught rewards/min down 34%. `net_v2.gd` was already frozen, so the bump touched no qa path.
- #72, #74, #77 and #78 edited integrator/director files (`CLAUDE.md`, `docs/workstreams.md`, design and art bibles). They are owner-requested project PRs, not worker runs; accepted.
- #79 (world: level-up burst, `LevelUpFx`) was open with auto-merge on but conflicted with main in the client and world backlogs. Merged main in: kept both client requests (world's `LevelUpFx.play` and gameplay's v3 API), and in the world backlog kept the director's new Emberlight items on top and replaced the director's unticked level-up item with world's ticked one plus its follow-up. Code passes review (procedural only, world paths). Auto-merge lands it once Test re-runs green.
- Folded five fragments into Week 00 (first run after midnight Chicago). Reworded the v3 fragment's "grab the latest client from the Releases page": since #67 the game updates itself on launch.
- Health: main was green at #76 and Railway deployed it. #75's main CI and deploy were still running when I opened this PR. playtest.md has no reports; every backlog has 15+ open items, so no refill.

## Integrator, 2026-11-23 07:30 UTC
- Health: `main` went red once, on #81's push run (`aaa7318f`): qa's new run-wide check `no two players ever gathered one node at the same time` failed with `shared_node_max=1`. The PR run had passed and the next main runs (#82, #83, #79, #85) were all green, so it is a chance-based check, not a regression. No revert; filed a request in the qa backlog to make it deterministic. Railway kept serving `3c41edd9` while main was red, then deployed #83 (`a97fdfdb`) and #85 (`68e9aa94`), both `success`. The Week 00 release re-published after each green main run.
- Reviewed what merged since the 06:30 run, oldest first: #81 (qa: gather ledger in CI), #82 (world: Emberlight shader), #83 (client: timed gather bar, haul sounds, emptied nodes), #79 (world: `LevelUpFx`), #85 (gameplay: skills and XP). All green on Test, all in owned paths (cross-stream edits only "Requests from other streams" entries), procedural only, no secrets. #85 adds `0003_character_skills.sql`: a new table, next number, nothing dropped or renamed; characters without rows load as level 1, saves upsert with `GREATEST` so XP never goes down, and it adds a `week01_skills` fixture. Accepted. Its "Why it's more fun" (first level in about a minute, +25% together) is backed by the bot behaviour.
- #79 had conflicted with #82 in the world devlog and #84 (qa: render budget) with #81 in the qa devlog; GitHub runs no PR checks while a PR conflicts, so #84 had never been tested. Merged `main` into both (kept both entries). #79 then landed. #84's next run failed only on a 403 downloading Godot inside `docker build` (infrastructure), so I re-ran the failed job, which passed; it then conflicted again with #79's client-backlog request, merged `main` in once more. Auto-merge is on; it should land this hour.
- Folded five fragments into Week 00 (6 waiting counting #84's). The level-up line keeps world's "about to" wording: the client doesn't call `LevelUpFx` yet.
- playtest.md has no reports. Every backlog has 16+ open items, so no refill.

## Integrator, 2026-11-23 09:30 UTC
- Health: every `main` run since the 07:30 run is green (#84 `16e4abd`, #88 `3f4f078`, #87 `483698d`, #90 `7ff4619`). Railway deployed `7ff4619` (`success`); #91 (`dbeecd6`) and #89 (`0eeda9d`) were still in CI and their deploys waiting on it when I opened this PR.
- Reviewed what merged since the 07:30 run, oldest first: #84 (qa: render budget in the client smoke test), #88 (world: ember veins on gatherables), #87 (qa: skills and XP in CI, time to first level-up), #90 (client: avatars turn and swing while gathering), #91 (client: Graphics quality and F3 frame stats), #89 (gameplay: protocol v4, skills and XP on `Net/Play`). All landed by auto-merge on a green Test check. Every edit stayed in owned paths; the cross-stream edits are only "Requests from other streams" entries. No migrations, no imported assets, no secrets. #87's `fun_baseline.json` change only adds the `first_level_up_gather_s_worst` limit (90 s); the existing limits are unchanged. #89 freezes `tests/protocol/net_v3.gd` and `net_play_v3.gd`, the qa paths a bump PR is allowed, adds its RPCs on `Net/Play` only, and keeps the level-up chat line for clients that don't show the banner yet. Its "Why it's more fun" is plumbing for the client's XP pops and banner; acceptable for a protocol PR, and the client request is filed. All accepted.
- Folded six fragments into Week 00 (6 waiting, which meets the fold threshold). The level-up burst line keeps "about to": the client still doesn't call `LevelUpFx`.
- No open `ws/*` PRs left. playtest.md has no reports. Every backlog has 15+ open items, so no refill.
