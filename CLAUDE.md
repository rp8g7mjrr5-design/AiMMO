# ZombAi Project Constitution

Read this file first, every session. You start with no memory; this repo is your memory.

## Mission
**ZombAi** (the repo was renamed from AiMMO on 2026-11-24; the game's internal data folder and `AIMMO_*` settings keep the old name on purpose, see `docs/vision.md`) is a real-time 3D **third-person open-world zombie survival sandbox** built by its owner and AI together (owner direction, 2026-11-24 and 2026-11-25): a fallen medieval kingdom on generated maps full of risk-graded ruins, the Zombai (our own undead), building and surviving on **servers of up to about 100 players** under rules each server sets, sold as a one-time buy. **It is not an MMO** (owner, 2026-11-25). Today's official always-on Railway world is one such server, capped at 8 until load tests prove more; never break it. **Read `docs/vision.md` every session** (automated runs read its summary in `docs/worker_brief.md` instead); it is the design, and its "Never" list binds every stream. The owner plays, tests and sets the direction; the AI designs and builds everything else: world, lore, systems, art direction, balance, and the details of the roadmap. Work toward the current phase in `docs/roadmap.md`.

## Autonomy rules
- Never wait for human input and never ask questions. Make the call, write down why, move on.
- The human's only input channel is `docs/playtest.md` (bugs and crashes only). Treat it as bug reports, not design requests.
- **Fun comes first.** The owner's number one rule: if it isn't fun, it isn't worth shipping. Judge every change by whether it makes the game more fun to play (tight feedback, short loops that pay off, juice, no dead time), and say how in your PR. See "Fun comes first" in `docs/design_bible.md`.
- The owner's standing directions are in `docs/design_bible.md` under "Owner directions" (fun comes first, chat is for talking only, the action camera, how gathering feels, the whole game feels like a modern action game, progress through tools and gear with no levels (2026-11-26), take the best and beat it, a look of our own that is cheap to draw (`docs/art_bible.md`), the ZombAi survival sandbox on servers of up to 100 (`docs/vision.md`), the basics first, a clean fight with no words on screen and no running backwards, and "Inspired by, never copied"). Follow them over any other design choice; everything else stays your call.
- **The look is grounded, not cute** (owner direction, 2026-11-24). Before any change that shows something on screen, read `docs/art_bible.md`, at least section 0 (the pillars), section 11 (what reads as cheesy) and section 12 (the checklist), and follow it. Muted earthy colours, real proportions, clear sunny days and moody nights, restrained effects and UI; inspired by grounded survival-crafting games, never copying any game. The one exception is the characters: survivors and the Zombai are goofy cartoon folk in the same muted colours (owner direction, 2026-11-26; art bible section 3).
- Stay true to `docs/design_bible.md`. You may evolve it, but log every change and its reason in that file's "Revision history" so the vision doesn't flip-flop week to week.

## Hard rules (never break these)
1. **Never delete or corrupt player data.** Database changes are add-only migrations in `db/migrations/`, numbered sequentially. Never drop or rename a column or table that holds player data.
2. **Nothing ships unless all tests pass**, including the bot test. If tests fail and you can't fix them, ship nothing and roll back to the last good commit.
3. **All art is procedural.** No imported models, textures, sounds, or fonts beyond what Godot ships with. Everything visual and audible is generated in code (`game/procgen/`).
4. **No secrets in code.** Credentials come only from environment variables set by the human on Railway and in GitHub repository secrets.
5. **Small, finished increments.** Each worker run ships at most one feature for its workstream, plus bug fixes, as one PR with GitHub auto-merge on. No session calls merge: GitHub squash-merges a PR into `main` only when the required "Test" check passes, and the integrator reviews and reverts anything that breaks a rule. Small and working beats big and broken.
6. **Never break save compatibility.** Players' existing characters, items, worlds and progress must load after every update, including worlds saved by hosts on their own machines.

## Tech stack
- **Repository:** `rp8g7mjrr5-design/ZombAi` (renamed from AiMMO). Use the new name in every `gh api` path and `add_repo` call: the API answers the old name with a redirect the session proxy refuses. Never create a new repository named AiMMO, because installed games follow GitHub's redirect from the old name to find updates.
- **Engine:** Godot 4 (GDScript), one project in `game/` with two export presets:
  - `server`: headless dedicated server (Linux), deployed to Railway via Docker.
  - `client`: desktop builds for Windows, macOS, and Linux.
- **Networking:** Godot high-level multiplayer (ENet locally; WebSocket in production, because Railway only proxies TCP). The server is authoritative; clients send inputs, never trusted state.
- **Database:** Postgres on Railway. The connection URL comes from the `DATABASE_URL` environment variable.
- **Deploy:** pushing to `main` triggers GitHub Actions:
  - Test the server; Railway redeploys it from `main` once that commit's CI passes, and only when server files changed.
  - Build client binaries and publish them as a GitHub Release titled `Week NN — <headline feature>`, with the changelog entry as release notes. Later pushes in the same week update that week's release.
- **Steam:** not yet. Do not add Steam integration until the human sets it up.

## Repository layout
```
CLAUDE.md                 ← this file
docs/
  vision.md               ← the game: ZombAi, a fallen kingdom, ruins, the Zombai (owner direction)
  research/               ← design studies behind the vision
  design_bible.md         ← world, lore, art direction, core systems (AI-owned)
  art_bible.md            ← the art direction and style guide: Emberlight, grounded; render budgets (read before any visual change)
  roadmap.md              ← ordered phases toward the vision (AI-owned)
  playtest.md             ← human's bug inbox (read every week)
  devlog/week-NN.md       ← internal notes: what you built, what failed, notes to next week's self
  devlog/<stream>.md      ← each workstream's running notes (folded by the integrator)
  devlog/<stream>.d/      ← one devlog note per PR, folded into devlog/<stream>.md
  workstreams.md          ← builder and integrator procedures, the owner's own work
  worker_brief.md         ← one-page summary of the bibles that every automated run reads
  workstreams/<stream>.md ← each workstream's backlog
  workstreams/<stream>.d/ ← one backlog note per PR (ticks, follow-ups, requests), folded in
  weekly_task.md          ← the Friday weekly review
  budget.md               ← weekly work cap, set by the owner
  digest/YYYY-MM-DD.md    ← the integrator's daily summary for the owner
CHANGELOG.md              ← player-facing patch notes, also shown in-game (integrator only)
changelog.d/              ← one fragment per PR, folded into CHANGELOG.md by the integrator
game/                     ← Godot 4 project
  procgen/                ← terrain, buildings, creatures, items, sound generators
  server/                 ← server-only logic
  client/                 ← client-only logic (UI, rendering, input)
  shared/                 ← code used by both
tests/
  unit/                   ← fast headless tests
  bot_test/               ← spins up the server + simulated players
db/migrations/            ← numbered, add-only SQL migrations
tools/ws_claim.sh         ← "one run per stream at a time" claims (see docs/workstreams.md)
.github/workflows/        ← CI: test, build, deploy, release
Dockerfile                ← server container for Railway
```

## Testing standard
- Unit tests run headless: `godot --headless --path game -s tests/unit/run_all.gd`
- **Bot test:** start the dedicated server, connect at least 8 simulated players who log in, move, chat, use this week's new feature, disconnect, and reconnect. It runs for at least 3 minutes. Any crash, error log, desync, or data loss is a failure.
- **Load test:** before the live world's player cap goes up, a load test with as many bots as the new cap passes on `main` (`docs/vision.md`, "Getting to 100").
- Every new feature gets at least one unit test and a bot-test behavior.

## Writing standards
- **Patch notes** (`CHANGELOG.md`): written for players, fun and clear, newest at top.
- **Devlog**: honest and technical. Include what you tried that didn't work, known bugs, and specific notes to next week's self.
- **No shared running files in worker PRs.** Patch notes, devlog notes, backlog ticks and requests each go in a new file per PR, and the integrator folds them in (`docs/workstreams.md`, "Notes go in new files"). This is what keeps parallel PRs from conflicting.
- **Commits**: small, descriptive messages.

## Development process
Development runs continuously. Find your role in the prompt that started your session:
- **Builder** (the one worker, a few times a day): follow the builder procedure in `docs/workstreams.md` exactly.
- **Integrator** (daily; also does the old qa checks and the director's digest): follow the integrator procedure in `docs/workstreams.md` exactly.
- Automated runs read lean: this file, `docs/worker_brief.md`, and only the bible sections their item names (owner, 2026-11-25, to save usage). The owner also builds on the side: never touch their branches or PRs (`docs/workstreams.md`, "The owner's own work").
- **Weekly review** (Fridays): follow `docs/weekly_task.md` exactly.
