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
| `qa` | `tests/` (except `tests/fixtures/`), `.github/`, `Dockerfile`, `docker/`, `railway.json`, `tools/`, `docs/playtest.md` | Bugs from playtest.md, crash fixes anywhere (see below), bot-test coverage, performance, CI, ops |

**Every worker owns:** `docs/workstreams/<its stream>.md`, `docs/devlog/<its stream>.md`, and
new files it creates in `changelog.d/`. Every worker adds unit tests for its own code under
`tests/unit/test_<stream>_*.gd` and bot behaviours in `tests/bot_test/behaviours/<stream>_*.gd`
when the test harness supports them (qa builds that hook if it doesn't exist yet).

**QA exception:** `qa` may make the smallest possible fix in any file to resolve a crash,
data-loss bug, or red `main`. It must say so in the PR description.

**Integrator only:** `CHANGELOG.md`, `CLAUDE.md`, `docs/workstreams.md`, `docs/weekly_task.md`,
`docs/devlog/week-NN.md`.

**Director:** `docs/roadmap.md`, `docs/design_bible.md`, `docs/art_bible.md`, `docs/digest/`, and the "Backlog"
sections of every `docs/workstreams/<stream>.md` (workers still tick their own items and add
follow-ups).

**Protocol changes** (`game/shared/net.gd`, `GameConfig.PROTOCOL_VERSION`) belong to
`gameplay`. Installed games update themselves on launch and when the server turns them away
(PR #67), so there is no daily limit: bump when a feature needs it, as soon as it is ready.
Keep at most one bump PR open at a time and put every protocol change that is ready into it,
and note the bump in the changelog fragment. From v4 on, the bump PR also adds a frozen copy of the old `net.gd` as
`tests/protocol/net_v<old>.gd`; that one qa path is allowed in a gameplay PR (see
`tests/protocol/README.md`).

## One run per stream at a time (claims)

Workers run every hour, and a run can take longer than that. Two runs of one stream at once
build the same item twice, so every worker run (and the integrator, as stream `integrator`)
holds a **claim** while it works: a branch `claim/<stream>` that `tools/ws_claim.sh` creates
atomically. It needs no clone, so take it before doing anything expensive:

```sh
CLAIM() { bash <(gh api repos/rp8g7mjrr5-design/AiMMO/contents/tools/ws_claim.sh -H "Accept: application/vnd.github.raw") "$@"; }
CLAIM take <stream> "starting"        # exit 3 = another run of this stream is working: stop now, one line
CLAIM note <stream> "<item you picked>"   # once you've picked, and every ~45 min of a long run
CLAIM release <stream> "<PR link or why>" # last thing you do, whether you shipped or not
```

A claim nobody refreshed for 150 minutes belongs to a run that died and the next run takes it
over. Never take or release another stream's claim.

**Older scheduled prompts.** The scheduled tasks that start the workers and the integrator
can't be edited, and some still say "keep at most one open PR" or "squash-merge". The owner
replaced those rules on 2026-11-23: this file wins. Take your claim as soon as you've read
this, if you didn't take it before cloning.

## Worker procedure (each run)

0. **Budget check first.** Follow `docs/budget.md`. If your stream has hit its weekly cap and
   has no open PR to fix, stop immediately. Then **take your claim** (above); if it's busy,
   stop with one line. From here on, release the claim before you stop, on every path.
1. Attach and clone the repo. Read `CLAUDE.md`, this file, `docs/design_bible.md`
   (especially the North star), `docs/art_bible.md` (if your change shows anything on screen), `docs/roadmap.md`, your backlog `docs/workstreams/<stream>.md`,
   and the tail of `docs/devlog/<stream>.md`.
2. **Look after your open PRs, then keep going.** List your open `ws/<stream>/` PRs. For each:
   - Checks green or still running, auto-merge on, no conflict, no unanswered review comment:
     nothing to do. GitHub lands it on its own. Carry on to step 3.
   - Red CI, a merge conflict, or a review comment: fix it first (merge `main` in, don't
     rebase), push, make sure auto-merge is on, then carry on to step 3 if this run still has
     room for a small item.
   - Auto-merge off and no comment saying why: turn it on.
   A worker has at most **two** open PRs: one landing, one new. If you already have two, fix
   what needs fixing and stop. Never start a new item on top of an unmerged PR's branch; the
   new item branches from `main` and must not need the open PR's code. If the top item does,
   take the next one that doesn't.
3. Pick the top unblocked item from your backlog (requests from other streams and bugs
   first), skipping any item already in one of your open PRs (its tick is in that PR, not on
   `main` yet). If the top items are blocked on another stream, take the next unblocked one,
   then a follow-up, a bug, a test or a polish item from your own area: a run that ships
   nothing is the last resort, for when your stream truly has no work it can do alone. Write
   the reason in your devlog, and add the missing items to your backlog's follow-ups so the
   next run has something. Size it so it is built and fully tested in this run. Small and working beats big
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
   (or `gh pr merge <n> --auto --squash` where GraphQL is available). Never call merge
   yourself; GitHub merges the PR when the required "Test" check is green. Don't wait for CI:
   if it goes red, auto-merge waits, and the next run fixes it (step 2).
8. Release your claim with the PR link, and stop.
9. Never ask questions; make the call and write down why.

**CI is the second test run, not the first.** CI tests a PR once, on its PR run (pushes to a
branch without a PR run nothing). Docs-only PRs (`docs/`, `changelog.d/`, root `*.md`) run
only the unit tests, so director, digest and changelog PRs land in about two minutes. Pushing
the branch before opening the PR is fine; open the PR as soon as the branch is ready.

## Integrator procedure (each run)

0. **Cheap exit first.** Before cloning, check for open `ws/*` PRs, PRs merged since the last
   `integrate/` PR or integrator devlog note, and the latest `main` CI result. If there is
   nothing open, nothing new merged, and `main` is green, stop with one line. Otherwise take
   the `integrator` claim (see "Claims"); if it's busy, stop with one line.
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
4. **Fold the changelog a few times a day, not every hour.** The release notes already show
   unfolded `changelog.d/*.md` fragments on top of the week's entry, so players see new notes
   as soon as a PR lands. Fold only when the last `integrate/` PR merged 6 or more hours ago,
   or 6 or more fragments are waiting, or it's the first run after 00:00 Chicago: move every
   fragment into `CHANGELOG.md` under the current week's heading (`## Week NN — <headline>`;
   create it if this is the first merge of the week, with a provisional headline), then
   delete the fragments. Put it on a branch `integrate/YYYY-MM-DD-HH`, open a PR, and turn on
   auto-merge (squash); it's docs-only, so CI takes about two minutes and the server doesn't
   restart. Never push to `main` directly. At most one PR of your own per run.
5. Confirm CI passes, the server redeploys, and the `Week NN` release updates. Railway
   deploys the server itself from `main` when server files change (`railway.json`
   `watchPatterns`), and waits for that commit's CI to pass first ("Wait for CI" is on in
   Railway, set by the owner 2026-11-23); CI no longer deploys a second time. A red `main`
   therefore never reaches players, but fix or revert it at once: nothing else deploys
   until `main` is green again. If the deploy breaks, revert and
   confirm the previous version is live.
6. Triage `docs/playtest.md`: tag new reports and add them to the right stream's backlog.
7. If a stream's backlog has fewer than 3 items, add the next ones from the roadmap.
8. Release the `integrator` claim and end with your two or three lines.

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
