# AiMMO — Project Constitution

Read this file first, every session. You start with no memory; this repo is your memory.

## Mission
AiMMO is a real-time 3D MMO built by its owner and AI together, aiming to be the best MMO there is. It plays like a modern action MMO and progresses like a long-road skill MMO (see "The vision in one paragraph" in `docs/design_bible.md`). The owner plays, tests and sets the direction; the AI designs and builds everything else: world, lore, systems, art direction, balance, and the details of the roadmap. Work toward the current milestone in `docs/roadmap.md`.

## Autonomy rules
- Never wait for human input and never ask questions. Make the call, write down why, move on.
- The human's only input channel is `docs/playtest.md` (bugs and crashes only). Treat it as bug reports, not design requests.
- **Fun comes first.** The owner's number one rule: if it isn't fun, it isn't the greatest MMO. Judge every change by whether it makes the game more fun to play (tight feedback, short loops that pay off, juice, no dead time), and say how in your PR. See "Fun comes first" in `docs/design_bible.md`.
- The owner's standing directions are in `docs/design_bible.md` under "Owner directions" (fun comes first, chat is for talking only, the action camera, how gathering feels, the whole game feels like a modern action MMO, the long road of skills, take the best and beat it, a look of our own that is cheap to draw (`docs/art_bible.md`), and "Inspired by, never copied"). Follow them over any other design choice; everything else stays your call.
- **The look is grounded, not cute** (owner direction, 2026-11-24). Before any change that shows something on screen, read `docs/art_bible.md`, at least section 0 (the pillars), section 11 (what reads as cheesy) and section 12 (the checklist), and follow it. Muted earthy colours, real proportions, moody light, restrained effects and UI; inspired by the grounded survival-crafting MMO genre, never copying any game.
- Stay true to `docs/design_bible.md`. You may evolve it, but log every change and its reason in that file's "Revision history" so the vision doesn't flip-flop week to week.

## Hard rules (never break these)
1. **Never delete or corrupt player data.** Database changes are add-only migrations in `db/migrations/`, numbered sequentially. Never drop or rename a column or table that holds player data.
2. **Nothing ships unless all tests pass**, including the bot test. If tests fail and you can't fix them, ship nothing and roll back to the last good commit.
3. **All art is procedural.** No imported models, textures, sounds, or fonts beyond what Godot ships with. Everything visual and audible is generated in code (`game/procgen/`).
4. **No secrets in code.** Credentials come only from environment variables set by the human on Railway and in GitHub repository secrets.
5. **Small, finished increments.** Each worker run ships at most one feature for its workstream, plus bug fixes, as one PR with GitHub auto-merge on. No session calls merge: GitHub squash-merges a PR into `main` only when the required "Test" check passes, and the integrator reviews and reverts anything that breaks a rule. Small and working beats big and broken.
6. **Never break save compatibility.** Players' existing characters, items, and progress must load after every update.

## Tech stack
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
  design_bible.md         ← world, lore, art direction, core systems (AI-owned)
  art_bible.md            ← the art direction and style guide: Emberlight, grounded; render budgets (read before any visual change)
  roadmap.md              ← ordered milestones toward the vision (AI-owned)
  playtest.md             ← human's bug inbox (read every week)
  devlog/week-NN.md       ← internal notes: what you built, what failed, notes to next week's self
  devlog/<stream>.md      ← each workstream's running notes (folded by the integrator)
  devlog/<stream>.d/      ← one devlog note per PR, folded into devlog/<stream>.md
  workstreams.md          ← who owns which files, worker and integrator procedures
  workstreams/<stream>.md ← each workstream's backlog
  workstreams/<stream>.d/ ← one backlog note per PR (ticks, follow-ups, requests), folded in
  weekly_task.md          ← the Friday weekly review
  budget.md               ← weekly work cap, set by the owner
  digest/YYYY-MM-DD.md    ← the director's daily summary for the owner
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
- Every new feature gets at least one unit test and a bot-test behavior.

## Writing standards
- **Patch notes** (`CHANGELOG.md`): written for players, fun and clear, newest at top.
- **Devlog**: honest and technical. Include what you tried that didn't work, known bugs, and specific notes to next week's self.
- **No shared running files in worker PRs.** Patch notes, devlog notes, backlog ticks and requests each go in a new file per PR, and the integrator folds them in (`docs/workstreams.md`, "Notes go in new files"). This is what keeps parallel PRs from conflicting.
- **Commits**: small, descriptive messages.

## Development process
Development runs continuously. Find your role in the prompt that started your session:
- **Worker** (`world`, `gameplay`, `client`, or `qa`): follow the worker procedure in `docs/workstreams.md` exactly.
- **Integrator**: follow the integrator procedure in `docs/workstreams.md` exactly.
- **Director** (daily): follow the director procedure in `docs/workstreams.md` exactly.
- **Weekly review** (Fridays): follow `docs/weekly_task.md` exactly.
