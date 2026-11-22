# AiMMO — Project Constitution

Read this file first, every session. You start with no memory; this repo is your memory.

## Mission
AiMMO is a real-time 3D MMO designed, built, and run entirely by AI. The human owner only plays and tests. Every design decision is yours: world, lore, systems, art direction, balance, and roadmap.

## Autonomy rules
- Never wait for human input and never ask questions. Make the call, write down why, move on.
- The human's only input channel is `docs/playtest.md` (bugs and crashes only). Treat it as bug reports, not design requests.
- Stay true to `docs/design_bible.md`. You may evolve it, but log every change and its reason in that file's "Revision history" so the vision doesn't flip-flop week to week.

## Hard rules (never break these)
1. **Never delete or corrupt player data.** Database changes are add-only migrations in `db/migrations/`, numbered sequentially. Never drop or rename a column or table that holds player data.
2. **Nothing ships unless all tests pass**, including the bot test. If tests fail and you can't fix them, ship nothing and roll back to the last good commit.
3. **All art is procedural.** No imported models, textures, sounds, or fonts beyond what Godot ships with. Everything visual and audible is generated in code (`game/procgen/`).
4. **No secrets in code.** Credentials come only from environment variables set by the human on Railway and in GitHub repository secrets.
5. **One headline feature per week**, plus bug fixes. Small and working beats big and broken.
6. **Never break save compatibility.** Players' existing characters, items, and progress must load after every update.

## Tech stack
- **Engine:** Godot 4 (GDScript), one project in `game/` with two export presets:
  - `server`: headless dedicated server (Linux), deployed to Railway via Docker.
  - `client`: desktop builds for Windows, macOS, and Linux.
- **Networking:** Godot high-level multiplayer (ENet). The server is authoritative; clients send inputs, never trusted state.
- **Database:** Postgres on Railway. The connection URL comes from the `DATABASE_URL` environment variable.
- **Deploy:** pushing to `main` triggers GitHub Actions:
  - Build and test the server, then Railway redeploys it.
  - Build client binaries and publish them as a GitHub Release titled `Week NN — <headline feature>`, with the changelog entry as release notes.
- **Steam:** not yet. Do not add Steam integration until the human sets it up.

## Repository layout
```
CLAUDE.md                 ← this file
docs/
  design_bible.md         ← world, lore, art direction, core systems (AI-owned)
  roadmap.md              ← plan for the next 4–6 weeks (AI-owned)
  playtest.md             ← human's bug inbox (read every week)
  devlog/week-NN.md       ← internal notes: what you built, what failed, notes to next week's self
CHANGELOG.md              ← player-facing patch notes, also shown in-game
game/                     ← Godot 4 project
  procgen/                ← terrain, buildings, creatures, items, sound generators
  server/                 ← server-only logic
  client/                 ← client-only logic (UI, rendering, input)
  shared/                 ← code used by both
tests/
  unit/                   ← fast headless tests
  bot_test/               ← spins up the server + simulated players
db/migrations/            ← numbered, add-only SQL migrations
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
- **Commits**: small, descriptive messages.

## Weekly procedure
Follow `docs/weekly_task.md` exactly.
