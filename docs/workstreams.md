# Continuous development: workstreams

AiMMO is developed around the clock by several AI sessions working in parallel. Each
**worker** owns one area of the game and ships one small, tested improvement per run as a
pull request and turns on GitHub auto-merge, so GitHub squash-merges it once the required
"Test" check passes. No session calls merge directly. The **integrator** reviews what landed,
folds the changelog, and reverts anything that breaks a rule. The **weekly
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

**Integrator only:** `CHANGELOG.md`, `CLAUDE.md`, `docs/workstreams.md`, `docs/weekly_task.md`,
`docs/devlog/week-NN.md`.

**Director:** `docs/roadmap.md`, `docs/design_bible.md`, `docs/digest/`, and the "Backlog"
sections of every `docs/workstreams/<stream>.md` (workers still tick their own items and add
follow-ups).

**Protocol changes** (`game/shared/net.gd`, `GameConfig.PROTOCOL_VERSION`) belong to
`gameplay`. A protocol bump means old clients can't connect, so do it at most once per day
and note it in the changelog fragment. From v4 on, the bump PR also adds a frozen copy of the old `net.gd` as
`tests/protocol/net_v<old>.gd`; that one qa path is allowed in a gameplay PR (see
`tests/protocol/README.md`).

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
   and broken. **Fun comes first** (design bible, "Fun comes first"): before you build,
   write down in one sentence what a player will feel that they didn't before. If you can't,
   pick a smaller slice that does, or add the feedback (sound, motion, toast) that makes it
   land. Plumbing is fine when it names the fun it unblocks.
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
7. Open a PR titled `[<stream>] <what players get>`. The PR body starts with a
   **Why it's more fun** line: one or two sentences on what a player will feel (faster
   feedback, a shorter loop, a new payoff, less dead time), or which upcoming fun this
   plumbing unblocks. Then turn on auto-merge with the squash
   method: `gh api -X PUT repos/<owner>/<repo>/pulls/<n>/ccr/auto_merge -f merge_method=squash`
   (or `gh pr merge <n> --auto --squash` where GraphQL is available). Then stop. Never call
   merge yourself; GitHub merges the PR when the required "Test" check is green. If CI goes
   red, auto-merge waits, and you fix it next run (step 2).
8. Never ask questions; make the call and write down why.

## Integrator procedure (each run)

0. **Cheap exit first.** Before cloning, check for open `ws/*` PRs and the latest `main` CI
   result. If there are no open worker PRs and `main` is green, stop with one line.
1. Attach and clone. Read CLAUDE.md and this file.
2. **Health first.** Check the latest CI run on `main` and the Railway deploy. If `main` is
   red or the deploy failed, fix it or revert to the last good commit before anything else.
3. **Review, don't merge.** GitHub auto-merge does the merging; the integrator never calls
   the merge API. Look at every `ws/*` PR merged since your last run and every one still open,
   oldest first:
   - Review against the hard rules: ownership respected, add-only migrations, procedural
     only, no secrets, save compatibility (old fixtures still load), tests added.
   - Review for fun (design bible, "Fun comes first"): the PR has a "Why it's more fun"
     line that is true, and it doesn't make the game slower, duller or noisier for players
     (the bot test's fun metrics didn't get worse). A PR missing the line gets a comment
     asking for it; one that makes the game less fun is treated like a rule break.
   - **Open PR that breaks a rule:** turn its auto-merge off
     (`gh api -X DELETE repos/<owner>/<repo>/pulls/<n>/ccr/auto_merge`) and leave a PR comment
     with what to fix. The worker fixes it next run and turns auto-merge back on.
   - **Open PR with no auto-merge** (a worker forgot): if it passes review, turn auto-merge on.
   - **Open PR with a merge conflict:** merge `main` into the branch, resolve, push, and let
     auto-merge finish it after CI.
   - **Merged PR that breaks a rule:** open a revert PR with auto-merge on and add the item
     back to that stream's backlog with a note.
   - If a PR has been stuck for over 24 hours, close it with a reason and put the item back in
     that stream's backlog.
4. After merging, fold every `changelog.d/*.md` fragment into `CHANGELOG.md` under the
   current week's heading (`## Week NN — <headline>`; create it if this is the first merge of
   the week, with a provisional headline), then delete the fragments. `main` is protected and
   only accepts merged PRs with a green "Test" check, so put this on a branch
   `integrate/YYYY-MM-DD-HH`, open a PR, and turn on auto-merge (squash). Never push to `main`
   directly. Worker PRs now deploy as they land, so the server may restart more than once an
   hour; keep your own changes to one PR per run.
5. Confirm CI passes, the server redeploys, and the `Week NN` release updates. If the deploy
   breaks, revert and confirm the previous version is live.
6. Triage `docs/playtest.md`: tag new reports and add them to the right stream's backlog.
7. If a stream's backlog has fewer than 3 items, add the next ones from the roadmap.

**Week numbers:** weeks start Friday. Week 00 started 2026-11-20. Week NN is the number of
whole weeks since then.

## Director procedure (daily)

The director keeps the four streams pointed at the North star and makes sure they never run
dry. It does not write game code.

1. Read CLAUDE.md, this file, the design bible, the roadmap, every stream's backlog and the
   last day of `docs/devlog/<stream>.md`, the PRs merged and opened in the last 24 hours, and
   `docs/playtest.md`.
2. Judge the last day honestly: is the game more fun than yesterday? Check the bot test's
   fun metrics trend (time to first reward, longest dead time, rewards per minute) and
   each merged PR's "Why it's more fun" line. Are streams
   duplicating work, blocked on each other, or drifting from the design bible?
3. Refill and reorder every backlog so each stream has 8 to 12 well-sized items, ordered by
   how much fun they add for players soonest, cross-stream
   dependencies come in the right order (e.g. gameplay adds the data before client shows it),
   and requests between streams are answered. Items for the current milestone in `docs/roadmap.md` come before anything else that is not a bug or an owner-direction item. Keep the roadmap's milestones current.
4. Write `docs/digest/YYYY-MM-DD.md`: a short plain-language summary for the owner of what
   changed in the game yesterday, what got more fun (with the fun metrics), what's coming today, anything stuck, and budget use so far.
5. Commit on a branch `ws/director/YYYY-MM-DD`, open a PR (docs only), and turn on
   auto-merge (squash) like any other worker PR.
6. End the run with the digest's text so the owner can read it in the thread.

## Weekly review (Fridays)

See `docs/weekly_task.md`. Like everyone else, it changes `main` only through a PR with
auto-merge on, which lands once the "Test" check is green.
