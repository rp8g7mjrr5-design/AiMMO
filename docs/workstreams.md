# Continuous development: workstreams

AiMMO is developed around the clock by several AI sessions working in parallel. Each
**worker** owns one area of the game and ships one small, tested improvement per run as a
pull request. The **integrator** is the only session that merges to `main`. The **weekly
review** (Fridays) steps back, rebalances the plan, and names the week's release.

Every session still follows CLAUDE.md first. Nothing here relaxes a hard rule.

## Workstreams and file ownership

Ownership keeps parallel PRs from colliding. A worker may only edit the paths it owns, plus
its own files listed under "Every worker owns". If a change needs another stream's files,
write the request into that stream's backlog (`docs/workstreams/<stream>.md`, "Requests
from other streams") in your PR, and work around it for now.

| Stream | Owns | Focus |
|---|---|---|
| `world` | `game/procgen/` (except `sfx.gd`), `game/shared/terrain.gd` | Terrain, biomes, flora, creatures' looks, buildings, weather visuals, art direction |
| `gameplay` | `game/server/`, `game/shared/` (except `terrain.gd`), `db/migrations/`, `tests/fixtures/` | Systems: gathering, inventory, crafting, combat, NPC/creature AI, quests, economy, protocol |
| `client` | `game/client/`, `game/main.gd`, `game/main.tscn`, `game/procgen/sfx.gd`, `game/project.godot`, `game/export_presets.cfg` | UI/HUD, camera, controls, prediction and smoothing, settings, audio, onboarding |
| `qa` | `tests/` (except `tests/fixtures/`), `.github/`, `Dockerfile`, `docker/`, `railway.json`, `docs/playtest.md` | Bugs from playtest.md, crash fixes anywhere (see below), bot-test coverage, performance, CI, ops |

**Every worker owns:** `docs/workstreams/<its stream>.md`, `docs/devlog/<its stream>.md`, and
new files it creates in `changelog.d/`. Every worker adds unit tests for its own code under
`tests/unit/test_<stream>_*.gd` and bot behaviours in `tests/bot_test/behaviours/<stream>_*.gd`
when the test harness supports them (qa builds that hook if it doesn't exist yet).

**QA exception:** `qa` may make the smallest possible fix in any file to resolve a crash,
data-loss bug, or red `main`. It must say so in the PR description.

**Integrator only:** `CHANGELOG.md`, `docs/roadmap.md`, `docs/design_bible.md`, `CLAUDE.md`,
`docs/workstreams.md`, `docs/weekly_task.md`, `docs/devlog/week-NN.md`.

**Protocol changes** (`game/shared/net.gd`, `GameConfig.PROTOCOL_VERSION`) belong to
`gameplay`. A protocol bump means old clients can't connect, so do it at most once per day
and note it in the changelog fragment.

## Worker procedure (each run)

0. **Budget check first.** Follow `docs/budget.md`. If your stream has hit its weekly cap and
   has no open PR to fix, stop immediately.
1. Attach and clone the repo. Read `CLAUDE.md`, this file, `docs/design_bible.md`
   (especially the North star), `docs/roadmap.md`, your backlog `docs/workstreams/<stream>.md`,
   and the tail of `docs/devlog/<stream>.md`.
2. **Finish before starting.** If you already have an open PR (branch `ws/<stream>/...`):
   bring it up to date with `main` (merge, don't rebase), fix red CI or review comments, and
   stop there for this run. A worker has at most one open PR.
3. Pick the top unblocked item from your backlog (requests from other streams and bugs
   first). Size it so it is built and fully tested in this run. Small and working beats big
   and broken.
4. Branch `ws/<stream>/<short-slug>` from the latest `main`. Build it within your owned
   paths, following CLAUDE.md (procedural art, add-only migrations, save compatibility,
   no secrets).
5. Test: all unit tests, the full bot test (8 bots, 3 minutes), and the client smoke test
   if you touched anything the client loads. Add at least one unit test and a bot behaviour
   for anything players can do.
6. Write a changelog fragment `changelog.d/<stream>-<short-slug>.md` with 1 to 3 player-facing
   bullet lines (fun and clear). Append honest notes to `docs/devlog/<stream>.md` (what you
   built, what didn't work, notes to your next run). Update your backlog: tick the item,
   add follow-ups.
7. Open a PR titled `[<stream>] <what players get>` and stop. Do not merge.
8. Never ask questions; make the call and write down why.

## Integrator procedure (each run)

0. **Cheap exit first.** Before cloning, check for open `ws/*` PRs and the latest `main` CI
   result. If there are no open worker PRs and `main` is green, stop with one line.
1. Attach and clone. Read CLAUDE.md and this file.
2. **Health first.** Check the latest CI run on `main` and the Railway deploy. If `main` is
   red or the deploy failed, fix it or revert to the last good commit before anything else.
3. Collect open `ws/*` PRs whose CI is green. For each, oldest first:
   - Merge `main` into the branch if it's behind; resolve conflicts; push; wait for CI.
   - Review against the hard rules: ownership respected, add-only migrations, procedural
     only, no secrets, save compatibility (old fixtures still load), tests added.
   - If it passes, squash-merge it. If it breaks a rule, leave a PR comment with what to fix
     and move on (the worker fixes it next run). If a PR has been stuck for over 24 hours,
     close it with a reason and put the item back in that stream's backlog.
4. After merging, fold every `changelog.d/*.md` fragment into `CHANGELOG.md` under the
   current week's heading (`## Week NN — <headline>`; create it if this is the first merge of
   the week, with a provisional headline), then delete the fragments. Push to `main`. At most
   one push to `main` per run, so the live server restarts at most once an hour.
5. Confirm CI passes, the server redeploys, and the `Week NN` release updates. If the deploy
   breaks, revert and confirm the previous version is live.
6. Triage `docs/playtest.md`: tag new reports and add them to the right stream's backlog.
7. If a stream's backlog has fewer than 3 items, add the next ones from the roadmap.

**Week numbers:** weeks start Friday. Week 00 started 2026-11-20. Week NN is the number of
whole weeks since then.

## Weekly review (Fridays)

See `docs/weekly_task.md`.
