# Continuous development: workstreams

ZombAi (repo renamed from AiMMO) is developed around the clock by several AI sessions working in parallel. Each
**worker** owns one area of the game and ships one small, tested improvement per run as a
pull request and turns on GitHub auto-merge, so GitHub squash-merges it once the required
"Test" check passes. No session calls merge directly. The **integrator** reviews what landed,
folds the changelog, and reverts anything that breaks a rule. The **weekly
review** (Fridays) steps back, rebalances the plan, and names the week's release.

Every session still follows CLAUDE.md first. Nothing here relaxes a hard rule.

## Workstreams and file ownership

Ownership keeps parallel PRs from colliding. A worker may only edit the paths it owns, plus
its own files listed under "Every worker owns". If a change needs another stream's files,
write the request as a backlog note in that stream's notes folder (see "Notes go in new
files" below) in your PR, and work around it for now.

| Stream | Owns | Focus |
|---|---|---|
| `world` | `game/procgen/` (except `sfx.gd`), `game/shared/terrain.gd`, `game/shared/worldgen.gd` | Terrain, biomes, flora, creatures' looks, buildings, weather visuals, art direction |
| `gameplay` | `game/server/`, `game/shared/` (except `terrain.gd` and `worldgen.gd`), `db/migrations/`, `tests/fixtures/` | Systems: gathering, inventory, crafting, combat, NPC/creature AI, quests, economy, protocol |
| `client` | `game/client/`, `game/main.gd`, `game/main.tscn`, `game/procgen/sfx.gd`, `game/project.godot`, `game/export_presets.cfg` | UI/HUD, camera, controls, prediction and smoothing, settings, audio, onboarding |
| `qa` | `tests/` (except `tests/fixtures/`), `.github/`, `Dockerfile`, `docker/`, `railway.json`, `tools/`, `docs/playtest.md` | Bugs from playtest.md, crash fixes anywhere (see below), bot-test coverage, performance, CI, ops |

**Every worker owns:** the new files it creates in `changelog.d/`, `docs/devlog/<its stream>.d/`
and `docs/workstreams/<any stream>.d/` (see "Notes go in new files"). Workers no longer edit
`docs/devlog/<stream>.md` or `docs/workstreams/<stream>.md` themselves. Every worker adds unit tests for its own code under
`tests/unit/test_<stream>_*.gd` and bot behaviours in `tests/bot_test/behaviours/<stream>_*.gd`
when the test harness supports them (qa builds that hook if it doesn't exist yet).

**QA exception:** `qa` may make the smallest possible fix in any file to resolve a crash,
data-loss bug, or red `main`. It must say so in the PR description.

**Integrator only:** `CHANGELOG.md`, `CLAUDE.md`, `docs/workstreams.md`, `docs/weekly_task.md`,
`docs/devlog/week-NN.md`, the running devlogs `docs/devlog/<stream>.md`, and the ticks,
follow-ups and "Requests from other streams" of every `docs/workstreams/<stream>.md`. It
changes them only by folding notes (integrator procedure, step 4).

**Director:** `docs/vision.md`, `docs/research/`, `docs/roadmap.md`, `docs/design_bible.md`, `docs/art_bible.md`, `docs/digest/`, and the "Backlog"
sections of every `docs/workstreams/<stream>.md` (workers tick their own items and add
follow-ups through backlog notes, which the integrator folds in).

## Notes go in new files (no shared running files)

Almost every merge conflict between workers came from two PRs editing the same running file:
a stream's backlog (ticking an item, adding follow-ups, another stream adding a request) and
its devlog (appending notes). So no worker PR edits a running file. Each PR adds new files
instead, and the integrator folds them in, the same way `changelog.d/` works:

| What | New file in your PR | Folded into |
|---|---|---|
| Player-facing patch note | `changelog.d/<stream>-<slug>.md` | `CHANGELOG.md` |
| Devlog notes for your next run | `docs/devlog/<stream>.d/YYYY-MM-DD-<slug>.md` | `docs/devlog/<stream>.md` |
| Tick, follow-ups for your own backlog | `docs/workstreams/<stream>.d/<stream>-<slug>.md` | `docs/workstreams/<stream>.md` |
| Request to another stream | `docs/workstreams/<other>.d/from-<stream>-<slug>.md` | that stream's "Requests from other streams" |

Use the date in America/Chicago and your branch slug, so two PRs never pick the same name.
A **backlog note** is short and uses these headings (leave out any you don't need):

```md
Done: <the item, quoted closely enough to find it> (ws/<stream>/<slug>)
One line on what shipped. Details belong in the devlog note, not here.

Follow-ups:
- [ ] <new item>

Request (from <stream>, YYYY-MM-DD): <what you need and why>
```

**Reading:** a stream's backlog is `docs/workstreams/<stream>.md` plus every unfolded note in
`docs/workstreams/<stream>.d/` on `main`. An item a note marks Done is done; follow-ups and
requests in notes are live items. Your devlog is the tail of `docs/devlog/<stream>.md` plus
the newest notes in `docs/devlog/<stream>.d/`.

**Fixing a note:** a later PR may edit or delete a note file that its own stream's earlier PR
added and that is still unfolded (for example to untick an item that turned out unfinished).
Never edit another stream's note.

Code files can still collide inside one stream (its landing PR and its new PR both touching
`client.gd`, say). Step 2 of the worker procedure already covers that: merge `main` in and
fix it.

**Protocol changes** (`game/shared/net.gd`, `GameConfig.PROTOCOL_VERSION`) belong to
`gameplay`. Installed games update themselves on launch and when the server turns them away
(PR #67), so there is no daily limit: bump when a feature needs it, as soon as it is ready.
Keep at most one bump PR open at a time and put every protocol change that is ready into it,
and note the bump in the changelog fragment. From v4 on, the bump PR also adds a frozen copy of the old `net.gd` as
`tests/protocol/net_v<old>.gd`; that one qa path is allowed in a gameplay PR (see
`tests/protocol/README.md`).

## One run per stream at a time (claims)

Workers run on a schedule (every worker every 4 hours, the integrator every 8; see "Schedule"), and a run can take longer than that. Two runs of one stream at once
build the same item twice, so every worker run (and the integrator, as stream `integrator`)
holds a **claim** while it works: a branch `claim/<stream>` that `tools/ws_claim.sh` creates
atomically. It needs no clone, so take it before doing anything expensive:

```sh
CLAIM() { bash <(gh api repos/rp8g7mjrr5-design/ZombAi/contents/tools/ws_claim.sh -H "Accept: application/vnd.github.raw") "$@"; }
CLAIM take <stream> "starting"        # exit 3 = another run of this stream is working: stop now, one line
CLAIM note <stream> "<item you picked>"   # once you've picked, and every ~45 min of a long run
CLAIM release <stream> "<PR link or why>" # last thing you do, whether you shipped or not
```

A claim nobody refreshed for 150 minutes belongs to a run that died and the next run takes it
over. Never take or release another stream's claim.

**No private follow-up runs.** Never schedule a reminder, wake-up or one-off task to finish
your stream's work later (for example "open the PR after midnight"). Leave the branch pushed
and a note at the top of your devlog; the next scheduled run of your stream picks it up. A
reminder runs outside the claim and builds the same thing as the next scheduled run (that
is how protocol v3 was built twice on 2026-11-23). If some session does run stream work
outside the schedule, it takes that stream's claim first like any worker run.

**Older scheduled prompts.** The scheduled tasks that start the workers and the integrator
can't be edited, and some still say "keep at most one open PR", "squash-merge", "one hourly
run", or "write down why in docs/devlog/<stream>.md". The owner replaced those rules on
2026-11-23 and 2026-11-24: this file wins. "Write it in your devlog" now means a devlog
note in `docs/devlog/<stream>.d/`.

## Schedule

Set by the owner on 2026-11-25 (every worker every 4 hours, to save usage; the owner turns the
schedules on and off themselves). All times America/Chicago, every day, overnight included:

| Session | Runs at |
|---|---|
| world | every 4 hours at :07 (00:07, 04:07, 08:07, 12:07, 16:07, 20:07) |
| gameplay | every 4 hours at :27 (01:27, 05:27, 09:27, 13:27, 17:27, 21:27) |
| client | every 4 hours at :47 (02:47, 06:47, 10:47, 14:47, 18:47, 22:47) |
| qa | every 4 hours at :43 (03:43, 07:43, 11:43, 15:43, 19:43, 23:43) |
| integrator | every 8 hours, at :56 (02:56, 10:56, 18:56) |
| director | daily at 04:47 |
| weekly review | Fridays at 11:42 |

GitHub auto-merge lands green PRs between integrator runs, so a slower integrator only means
the changelog and notes are folded less often. Take your claim as soon as you've read
this, if you didn't take it before cloning.

## Worker procedure (each run)

0. **Budget check first.** Follow `docs/budget.md`. If your stream has hit its weekly cap and
   has no open PR to fix, stop immediately. **qa only, cheap exit:** if no PR merged into `main`
   since qa's last PR was opened, `main` is green, qa has no open PR to fix and
   `docs/playtest.md` has no untagged report, stop with one line before cloning. Then **take your claim** (above); if it's busy,
   stop with one line. From here on, release the claim before you stop, on every path.
1. Attach and clone the repo (shallow: `--depth 50`). **Read lean** (owner, 2026-11-25: runs
   cost usage, and the running devlogs and the Done lists are over 100 KB). Read `CLAUDE.md`,
   this file's worker procedure, the design bible's "Fun comes first" and owner direction 9 ("The
   basics first"), the vision's "Never" list, the **Backlog** and **Requests from other streams**
   sections of `docs/workstreams/<stream>.md` (skip "Done"), the unfolded notes in
   `docs/workstreams/<stream>.d/`, the **last 80 lines** of `docs/devlog/<stream>.md` and the newest
   notes in `docs/devlog/<stream>.d/`. If your change shows anything on screen, also read the art
   bible's sections 0, 11 and 12 (and section 3 for characters). Open the rest of the vision,
   roadmap or bibles only for the section your item names.
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
   first, including those in unfolded notes), skipping any item a note on `main` marks Done
   and any item already in one of your open PRs (its tick is in that PR, not on
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
   bullet lines (fun and clear). Write honest notes in a new devlog note
   `docs/devlog/<stream>.d/YYYY-MM-DD-<short-slug>.md` (what you built, what didn't work,
   notes to your next run). Tick the item and add follow-ups in a new backlog note
   `docs/workstreams/<stream>.d/<stream>-<short-slug>.md`, and put any request to another
   stream in `docs/workstreams/<other>.d/from-<stream>-<short-slug>.md` (see "Notes go in new
   files"). Don't edit `docs/devlog/<stream>.md` or any `docs/workstreams/<stream>.md`.
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
4. **Fold the changelog and the notes a few times a day, not every run.** The release notes already show
   unfolded `changelog.d/*.md` fragments on top of the week's entry, so players see new notes
   as soon as a PR lands, and workers read unfolded notes as part of their backlog and devlog.
   Fold only when the last `integrate/` PR merged 6 or more hours ago,
   or 6 or more changelog fragments or 12 or more notes are waiting, or it's the first run after 00:00 Chicago. In one PR:
   - move every changelog fragment into `CHANGELOG.md` under the current week's heading (`## Week NN — <headline>`;
     create it if this is the first merge of the week, with a provisional headline);
   - append every devlog note in `docs/devlog/<stream>.d/` to the end of `docs/devlog/<stream>.md`,
     oldest first, each under a `## YYYY-MM-DD — <slug>` heading;
   - apply every backlog note in `docs/workstreams/<stream>.d/`: tick the Done item (with the
     note's one line and branch, kept short), add its follow-ups under the Backlog, and add its
     requests under "Requests from other streams". If an item can't be found, add the note's
     line under the Backlog as done so nothing is lost;
   - delete every note and fragment you folded (keep `changelog.d/README.md` and each folder's `.gitkeep`).
   Skip folding backlog notes while a `ws/director/` PR is open (the director is reordering
   those files); fold them next run. Put it on a branch `integrate/YYYY-MM-DD-HH`, open a PR, and turn on
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
7. If a stream's backlog has fewer than 3 items, add the next ones from the roadmap, basics
   first (design bible, owner direction 9).
8. Release the `integrator` claim and end with your two or three lines.

**Week numbers:** weeks start Friday. Week 00 started 2026-11-20. Week NN is the number of
whole weeks since then.

## Director procedure (daily)

The director keeps the four streams pointed at the North star and makes sure they never run
dry. It does not write game code.

0. **Cheap exit:** if no PR merged in the last 24 hours, no `docs/playtest.md` report is
   untagged and every stream's Backlog has at least 4 open items, stop with one line before
   cloning.
1. Read CLAUDE.md, this file, the design bible's owner directions, the roadmap's current phase,
   the **Backlog** and **Requests** sections of every stream's backlog (skip "Done"; with its
   unfolded notes in `docs/workstreams/<stream>.d/`) and the last day of `docs/devlog/<stream>.md`
   and `docs/devlog/<stream>.d/`, the PRs merged and opened in the last 24 hours, and
   `docs/playtest.md`.
2. Judge the last day honestly: is the game more fun than yesterday? Check the bot test's
   fun metrics trend (time to first reward, longest dead time, rewards per minute) and
   each merged PR's "Why it's more fun" line. Are streams
   duplicating work, blocked on each other, or drifting from the design bible?
3. Refill and reorder every backlog so each stream has 4 to 8 well-sized items (owner, 2026-11-25:
   short lists, basics first; never bring back polish the owner cut while a basic in owner
   direction 9 is unfinished), ordered by
   how much fun they add for players soonest, cross-stream
   dependencies come in the right order (e.g. gameplay adds the data before client shows it),
   and requests between streams are answered. Treat unfolded backlog notes as part of the
   backlog, but leave the note files alone; the integrator folds them. Items for the current milestone in `docs/roadmap.md` come before anything else that is not a bug or an owner-direction item. Keep the roadmap's milestones current.
4. Write `docs/digest/YYYY-MM-DD.md` (under 250 words, and lead with how far each of the four
   basics has come): a short plain-language summary for the owner of what
   changed in the game yesterday, what got more fun (with the fun metrics), what's coming today, anything stuck, and budget use so far.
5. Commit on a branch `ws/director/YYYY-MM-DD`, open a PR (docs only), and turn on
   auto-merge (squash) like any other worker PR.
6. End the run with the digest's text so the owner can read it in the thread.

## Weekly review (Fridays)

See `docs/weekly_task.md`. Like everyone else, it changes `main` only through a PR with
auto-merge on, which lands once the "Test" check is green.
