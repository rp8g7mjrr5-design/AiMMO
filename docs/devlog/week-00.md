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

## Integrator, 2026-11-23 14:30 UTC
- Health: `main` went red at #109 (`b603fb2`, flaky dead-time gate: 50.75 s vs baseline 35) and again at #102 (`bb48678`): `test_client_skills_window::test_goal_skips_unlocks_not_in_the_world_yet` used Toolcraft 5 as its "coming soon" example, and #110 built it. #110's own main run was cancelled by #102's push. qa's #114 (`b4e15d7`) fixed the test, steadied the dead-time gate (baseline 40 s, slack 15 s, re-based on nine CI runs) and the craft-window bot race; its main run is green. No revert needed: Railway kept serving #107 (`b6e38e5`) while main was red, which is what "Wait for CI" is for.
- Reviewed what merged since the 12:30 fold, oldest first: #104 (gameplay: tier-2 nodes), #101 (client: workbench over `c2s_craft`), #106 (qa: skills baseline), #108 (world: heartwood and veinstone icons), #109 (client: skills window on K, next-goal line), #107 (qa: daily fun trend), #110 (gameplay: Toolcraft 5 ember tools), #102 (client: level-up banner and chord), #114 (qa: steady main). All have a true "Why it's more fun" line, stay procedural, add no migrations or secrets, and add unit tests and bot behaviours. #104 edited three world test files (tier-aware asserts) and says so; minimal, and filed as a world request, so accepted. #114 used the qa red-main exception only in `tests/` (its own paths) and says so.
- Open PRs #111 (client: Budda Games intro), #112 (world: ember tool icons), #113 (gameplay: chat commands become a nudge to F1) were all red only from main's breakage (the skills-window test and the dead-time gate). Merged `main` into all three. #111 conflicted with #114 in `tests/bot_test/behaviours/client_craft_window.gd` (both fixed the same `/gather` race); kept main's version so `test_qa_craft_window_race.gd` matches. Auto-merge stays on for all three.
- #111 adds an imported video (`game/client/intro/budda_games_intro.ogv`, 1.15 MB) and edits `docs/design_bible.md`. Checked: the owner asked for it in their own project thread ("this should be the intro of the game instead of the godot thing") with the clip attached, and the design bible now records it as the single owner-approved exception to hard rule 3, client builds only. Accepted; it does not license any other imported asset.
- #113's dev-commands default is off on Railway, on elsewhere, so bots keep their `/gather` lines until qa passes the flag; a reasonable bridge for owner direction 1, accepted.
- Folded nine fragments into Week 00 (9 waiting, over the threshold of 6).
- playtest.md has no reports. Backlogs: world 29, gameplay 16, client 46, qa 31 open items, so no refill.

## Integrator, 2026-11-23 16:30 UTC
- Health: `main` green through #119 (`ae7fed3`). Railway's last finished deploy is #116 (`bcfb4a0`, `success`); #120 (`962aa99`) and #121 (`fb01d0e`) were in CI with their deploys waiting on it when I opened this PR.
- Reviewed what merged since the 14:30 run, oldest first: #112 (world: ember tool icons), #111 (client: Budda Games intro), #113 (gameplay: chat nudge), all three reviewed open last run; #117 (client: level walls), #116 (world: Emberlight 2b), #119 (qa: chat gate in CI, changelog lint), #120 (client: pack window on I), #121 (world: chunked node props). All landed on a green Test check, each has a true "Why it's more fun" line, stay in owned paths (cross-stream edits are "Requests from other streams" entries), add unit tests and bot behaviours, no migrations, no imported assets, no secrets. #116 and #121 edit qa's `tests/client_smoke/render_baseline.json` only to lower ceilings (materials 20 -> 12, primitives 650k -> 500k) and reset the baseline, which that file's own rule allows world to do; accepted.
- Open: #118 (gameplay: full pack still pays XP) conflicted with main in the client and qa backlogs' "Requests from other streams". Merged `main` in, kept both sides (gameplay's new requests plus main's done-marked ones). #122 (qa: E and Craft timed in the fun metrics) touches other streams' bot behaviours only to route RPCs through `bot.send_play`, and tightens `first_reward_s_worst` 120 -> 90 s; both in qa's paths, accepted. #118 and #122 both edit `gameplay_gather_v3.gd` in different lines; whichever lands second may need a `main` merge next run. Auto-merge on for both.
- Folded eight fragments into Week 00 (8 waiting, over the threshold). Also reworded the six old Week 00 lines that still sent players to type commands (now **E**, **I**, the time dial, join notices; dropped the "nearest tree" pointer line, which has no key yet) and emptied `tools/changelog_lint_allow.json`, as the lint's notes ask.
- playtest.md has no reports. Backlogs: world 30, gameplay 17, client 49, qa 32 open items, so no refill.

## Integrator, 2026-11-23 18:30 UTC
- Health: `main` green through #128 (`4f184b3`), and Railway deployed it (`success`). #130's main run (`88361db`) was cancelled by #127's push a few minutes later, so its Railway deploy shows `failure` (it waited on a cancelled CI); expected, and #127's run (`1a83df1`) carries both changes. That run and its deploy were still in progress when I opened this PR.
- Reviewed what merged since the 16:30 run, oldest first: #118 (gameplay: full pack still pays XP, first-session pace held in CI), #129 (client: players panel on O), #128 (gameplay: ember tools next to stone tools in the pack), #130 (client: time dial tooltip), #127 (world: Emberlight part 4, golden hour, blue nights, ember motes). All landed on a green Test check, each stays in its stream's files (other streams' backlogs touched only under "Requests from other streams"), no migrations, nothing imported, no secrets, and each has a true "Why it's more fun" line. No reverts.
- Open: #126 (qa: style check) was red only from the roster bot-behaviour breakage that #125 fixed on main (`test_qa_fun_metrics::test_behaviours_send_play_requests_through_the_bot`); updated the branch from `main`, CI re-running, auto-merge on. #131 (gameplay: health and stamina rules, pure `Vitals` functions, nothing wired yet) conflicted with main in `docs/devlog/gameplay.md`; merged `main` in, kept both entries (main's #128 entry first), CI re-running, auto-merge on. Both pass review.
- Folded seven fragments into Week 00 (7 waiting, over the threshold of 6). `python3 tools/changelog_lint.py` passes.
- playtest.md has no reports. Backlogs: world 31, gameplay 20, client 55, qa 33 open items, so no refill.

## Integrator, 2026-11-23 23:30 UTC
- Health: `main` green through #145 (`03a9d26`). Railway deployed #148 (`8ba4bd6`, `success`); #145's deploy was in progress after its CI passed when I opened this PR. #139's main run (`318e94b`) was cancelled by #148's push, so its deploy shows `failure` (waited on a cancelled CI); expected, and #148's green run carries it. The Week 00 release updated at 23:27 UTC.
- Reviewed what merged since the 20:00 fold (#142), oldest first: #143 (client: left-click gather), #144 (client: next goal follows training, quiet full-pack toast), #146 (world: level-up checks moved to unit tests; removes its own `world_level_up_fx` bot behaviour, world's path), #147 (qa: image test passes `AIMMO_DEV_COMMANDS` to its bots), #149 (world: far beam), #150 (client: prediction), #139 (gameplay: dev commands off by default, unblocked by #147), #148 (qa: F1, haul toast and Low smoke shots), #145 (gameplay: server-side grazers). All landed on a green Test check, stay in owned paths (other streams' backlogs touched only under "Requests from other streams"), no migrations, nothing imported, no secrets, each with a true "Why it's more fun" line. #145 ships no bot behaviour because grazers aren't on the wire yet; the stalk-and-spook behaviour is a follow-up tied to the bump, accepted as build-ahead.
- Open: #151 (qa: Low proven cheaper) conflicted with main in world's "Requests from other streams" (gameplay's grazer note vs qa's Low note); merged `main` in, kept both. #152 (gameplay: ember lantern, 999 stacks) conflicted in `docs/devlog/gameplay.md`; merged `main` in, kept both entries (#145's first). `MAX_STACK` 99 -> 999 only raises a cap and `ember_lantern` is a new text item id, so old saves load unchanged. #153 (world: night beam ember) is in CI. All three pass review, auto-merge on.
- Folded eight fragments (11 lines) into Week 00 (8 waiting, over the threshold of 6). `python3 tools/changelog_lint.py` passes.
- playtest.md has no reports. Backlogs: world 32, gameplay 19, client 63, qa 39 open items, so no refill.

## Integrator, 2026-11-24 01:30 UTC
- Health: `main` green through #159 (`155eae6`). Railway deployed #158 (`7d97f26`, protocol v6, `success`); #159 is tests-only, so Railway skipped it (`inactive`) and #158's build is what's live. The Week 00 release updated at 01:26 UTC.
- Reviewed what merged since the 23:30 run, oldest first: #153 (world: night beam ember), #151 (qa: Low proven cheaper) and #152 (gameplay: ember lantern, 999 stacks), all three reviewed open last run; #155 (client: level-up reads clean, saved Low starts Low), #156 (client: Return to Spawn Meadow in the Esc menu), #157 (world: motes only over gatherable nodes), #158 (gameplay: protocol v6, wildlife on the wire, with frozen `tests/protocol/net_v5.gd` and `net_play_v5.gd` as the bump rule asks), #159 (qa: three players on one node). All landed on a green Test check, stay in owned paths (other streams' backlogs touched only under "Requests from other streams"), no migrations, nothing imported, no secrets, each with a true "Why it's more fun" line. #157 has unit tests only, in line with world moving its visual checks out of the bot test (#146). No reverts.
- Open, all in CI with auto-merge on, no conflicts, all pass review: #160 (world: grazer models, procgen only), #161 (client: grazers on screen with a placeholder figure until world's model lands; edits `sfx.gd`, client-owned; night draw calls 292 of a 300 ceiling, worth watching when #160's model is swapped in), #162 (qa: bots prove a craft succeeds; edits client bot behaviours, which sit in qa's `tests/` paths).
- Folded eight fragments (13 lines) into Week 00 (8 waiting, over the threshold of 6). `python3 tools/changelog_lint.py` passes.
- playtest.md has no reports. Backlogs: world 32, gameplay 20, client 64, qa 39 open items, so no refill.

## Integrator, 2026-11-24 03:30 UTC
- Health: `main` green through #170 (`82ad0db`); #164 (`bbc5309`) landed during this run and its main CI is running. #162's main run (`d9927b3`) went red at 01:57 on the levelled fun gate; #166 (`f7e6e9f`) was green again and #168 made that gate steadier. Railway: #166's deploy `success` (02:35). #168 and #160's main runs were cancelled by the next push, so their deploys show `failure` (waited on a cancelled CI), expected. #167's deploy (`caddc07f`) shows `failure` at 02:42 while its CI was still queued (it only started at 02:43); #170's deploy (`82ad0db`) carries #167's server change too and was still `in_progress` when I opened this PR, about 12 minutes after its CI passed. Next run: confirm it finished `success`, and if Railway is stuck, the live server is still #166's build (protocol v6, same as main).
- Reviewed what merged since the 01:30 run, oldest first: #161 (client: grazers on screen), #162 (qa: craft haul proven every release), #166 (client: intro trimmed and sharp), #160 (world: grazer models), #168 (qa: steady levelled gate, fun trend verdict), #167 (gameplay: spear and maul rules, pure functions), #170 (client: footsteps), #164 (gameplay: health and stamina on the server, not saved, `s2c_vitals` waits for the next bump). All landed on a green Test check, stay in owned paths (other streams' backlogs touched only under "Requests from other streams"), no migrations, no secrets, each with a true "Why it's more fun" line. #166 replaces the intro video and adds a 720p encode of the same owner-supplied clip (`budda_games_intro_720.ogv`); that is the owner's studio-intro exception (design bible, "Studio intro"), asked for by the owner in the project thread, so accepted, but it is now two files of one clip, not one: nothing else may use the exception. No reverts.
- Open: #172 (client: grazers' real model) and #173 (world: lantern flicker) both went red on the bot test from flakes unrelated to their diffs: #172 on `gameplay_wildlife` ("grazer 3 bolted but no herd-mate went with it"; #172 only touches client drawing code), #173 on the levelled fun gate (5 of 6 bots; #173 only touches lamp visuals). Re-ran both failed jobs; auto-merge is on for both and both pass review. If either flake repeats, gameplay owns the wildlife bolt check and qa owns the levelled gate. #164 merged during the run.
- Folded eight fragments (13 lines) into Week 00 (8 waiting, over the threshold of 6). `python3 tools/changelog_lint.py` passes.
- playtest.md has no reports. Backlogs all well over 3 items, so no refill.
