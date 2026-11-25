# Continuous development: the lean setup

ZombAi (repo renamed from AiMMO) is built by a small set of scheduled AI runs, set by the owner
on 2026-11-25 to cost as little as possible while the game is on the basics:

- **builder**: one worker for the whole game. Each run ships one small, tested improvement
  from the top of the basics as a pull request with GitHub auto-merge on, so GitHub
  squash-merges it once the required "Test" check passes. No session calls merge.
- **integrator** (daily): keeps `main` healthy, reviews what landed, folds the notes, triages
  playtest reports, refills the backlogs and writes the owner's digest. It took over the old
  qa cheap checks and the director's daily job.
- **weekly review** (Fridays): steps back, names the week's release, plans the next.

The old world, gameplay, client, qa and director runs are retired. Their backlogs stay as the
four **areas** the builder picks from. Every session still follows `CLAUDE.md` first. Nothing
here relaxes a hard rule.

**Read lean.** Every run reads `CLAUDE.md`, `docs/worker_brief.md` and only the part of this
file for its role. The bibles (`docs/vision.md`, `docs/design_bible.md`, `docs/art_bible.md`,
`docs/roadmap.md`) are opened only for the section an item names. The brief is a one-page
summary of them, kept current by the integrator.

## The owner's own work (owner, 2026-11-25)

The owner builds on the game too, on the side. Their work is anything on a branch that does
not start with `ws/`, `claim/` or `integrate/` (for example `claude/...` branches from their
own sessions, or a branch they push by hand), every open PR from such a branch, and their
direct commits.

- **Never touch it.** No edits, rebases, reverts, closes, review demands or auto-merge on the
  owner's PRs or branches. If one of them breaks `main`, the integrator still restores `main`
  (CLAUDE.md hard rule 2) and says so in the digest, but never rewrites the owner's branch.
- **Stay out of their way.** Before picking an item, the builder lists the files changed by
  every open owner PR and by owner branches pushed in the last 3 days, and skips any item
  that would touch those files or the same feature. Take the next item instead.
- **Their changes win.** On a merge conflict with code the owner landed on `main`, keep the
  owner's version and rebuild your change on top of it.
- **Their notes count.** A backlog item the owner ticks, adds or reorders is followed as written.

## Areas and file layout

The builder may edit any game path for the item it is building. The areas only decide which
backlog an item lives in and where its notes go:

| Area | Mostly touches | Backlog |
|---|---|---|
| `world` | `game/procgen/`, `game/shared/terrain.gd`, `game/shared/worldgen.gd` | `docs/workstreams/world.md` |
| `gameplay` | `game/server/`, `game/shared/`, `db/migrations/`, `tests/fixtures/` | `docs/workstreams/gameplay.md` |
| `client` | `game/client/`, `game/main.*`, `game/procgen/sfx.gd`, `game/project.godot`, `game/export_presets.cfg` | `docs/workstreams/client.md` |
| `qa` | `tests/`, `.github/`, `Dockerfile`, `docker/`, `railway.json`, `tools/`, `docs/playtest.md` | `docs/workstreams/qa.md` |

**Integrator only:** `CHANGELOG.md`, `CLAUDE.md`, `docs/workstreams.md`, `docs/worker_brief.md`,
`docs/weekly_task.md`, `docs/budget.md`, `docs/devlog/week-NN.md`, the running devlogs
`docs/devlog/<area>.md`, the backlogs `docs/workstreams/<area>.md`, `docs/digest/`, and (with
the weekly review) `docs/vision.md`, `docs/research/`, `docs/roadmap.md`, `docs/design_bible.md`
and `docs/art_bible.md`. The owner may of course change any of these.

## Notes go in new files (no shared running files)

Almost every merge conflict between workers came from two PRs editing the same running file:
a backlog (ticking an item, adding follow-ups, a request) and a devlog (appending notes). So
no builder PR edits a running file. Each PR adds new files
instead, and the integrator folds them in, the same way `changelog.d/` works:

| What | New file in your PR | Folded into |
|---|---|---|
| Player-facing patch note | `changelog.d/<stream>-<slug>.md` | `CHANGELOG.md` |
| Devlog notes for your next run | `docs/devlog/<stream>.d/YYYY-MM-DD-<slug>.md` | `docs/devlog/<stream>.md` |
| Tick, follow-ups for your own backlog | `docs/workstreams/<stream>.d/<stream>-<slug>.md` | `docs/workstreams/<stream>.md` |
| Request to another stream | `docs/workstreams/<other>.d/from-<stream>-<slug>.md` | that stream's "Requests from other streams" |

`<stream>` here is the **area** the item came from (world, gameplay, client or qa). Use the
date in America/Chicago and your branch slug, so two PRs never pick the same name.
A **backlog note** is short and uses these headings (leave out any you don't need):

```md
Done: <the item, quoted closely enough to find it> (ws/builder/<slug>)
One line on what shipped. Details belong in the devlog note, not here.

Follow-ups:
- [ ] <new item>

Request (from <area>, YYYY-MM-DD): <what you need and why>
```

**Reading:** a stream's backlog is `docs/workstreams/<stream>.md` plus every unfolded note in
`docs/workstreams/<stream>.d/` on `main`. An item a note marks Done is done; follow-ups and
requests in notes are live items. Your devlog is the tail of `docs/devlog/<stream>.md` plus
the newest notes in `docs/devlog/<stream>.d/`.

**Fixing a note:** a later automated PR may edit or delete an unfolded note an earlier
automated PR added (for example to untick an item that turned out unfinished). Never edit a
note the owner wrote.

Code files can still collide between the builder's landing PR and its new one, or with the
owner's own work. Builder step 2 covers that: merge `main` in and fix it.

**Protocol changes** (`game/shared/net.gd`, `GameConfig.PROTOCOL_VERSION`) belong to
the gameplay area. Installed games update themselves on launch and when the server turns them away
(PR #67), so there is no daily limit: bump when a feature needs it, as soon as it is ready.
Keep at most one bump PR open at a time and put every protocol change that is ready into it,
and note the bump in the changelog fragment. From v4 on, the bump PR also adds a frozen copy of the old `net.gd` as
`tests/protocol/net_v<old>.gd` (see `tests/protocol/README.md`).

## One run per role at a time (claims)

A run can take longer than the gap to the next one, and two runs of one role at once build the
same item twice, so every builder and integrator run holds a **claim** while it works: a branch
`claim/<role>` that `tools/ws_claim.sh` creates atomically. It needs no clone, so take it before
doing anything expensive:

```sh
CLAIM() { bash <(gh api repos/rp8g7mjrr5-design/ZombAi/contents/tools/ws_claim.sh -H "Accept: application/vnd.github.raw") "$@"; }
CLAIM take builder "starting"        # exit 3 = another run is working: stop now, one line
CLAIM note builder "<item you picked>"   # once you've picked, and every ~45 min of a long run
CLAIM release builder "<PR link or why>" # last thing you do, whether you shipped or not
```

A claim nobody refreshed for 150 minutes belongs to a run that died and the next run takes it
over. Never take or release another role's claim.

**No private follow-up runs.** Never schedule a reminder, wake-up or one-off task to finish work
later. Leave the branch pushed and a devlog note; the next scheduled run picks it up.

**Older scheduled prompts.** If a scheduled prompt disagrees with this file, this file wins.

## Schedule

Set by the owner on 2026-11-25 (the owner turns the schedules on and off themselves). All times
America/Chicago:

| Session | Runs at | Model |
|---|---|---|
| builder | 3 times a day: 07:07, 13:07, 21:07 | the strongest model |
| integrator | daily at 04:56 | a cheaper model (upkeep, no game code) |
| weekly review | Fridays at 11:42 | a cheaper model |

GitHub auto-merge lands green PRs between integrator runs, so a daily integrator only means the
changelog and notes are folded once a day.

## Builder procedure (each run)

0. **Cheap checks first, before cloning.** Follow `docs/budget.md`; if the builder is at its
   weekly cap and has no open PR to fix, stop with one line. If the builder already has two open
   `ws/builder/` PRs and both are green or waiting on CI with auto-merge on, stop with one line.
   Then **take the `builder` claim**; if it's busy, stop with one line. From here on, release the
   claim before you stop, on every path.
1. Attach and clone the repo (shallow: `--depth 50`). **Read lean:** `CLAUDE.md`,
   `docs/worker_brief.md`, this procedure, the **Backlog** and **Requests** sections of the four
   area backlogs (skip "Done") with their unfolded notes in `docs/workstreams/<area>.d/`, and
   the newest one or two notes in the item's `docs/devlog/<area>.d/` (or the last 40 lines of
   `docs/devlog/<area>.md`). If your change shows anything on screen, also read the art bible's
   sections 0, 11 and 12 (and section 3 for characters). Open other bible sections only when the
   item names them.
2. **Look after your open PRs.** List your open `ws/builder/` PRs (and any older `ws/world/`,
   `ws/gameplay/`, `ws/client/`, `ws/qa/` PRs still open). Red CI, a merge conflict or a review
   comment: fix it first (merge `main` in, don't rebase), push, make sure auto-merge is on.
   Auto-merge off with no comment saying why: turn it on. At most **two** open builder PRs; if
   you already have two, fix what needs fixing and stop.
3. **See what the owner is doing** ("The owner's own work"): list open PRs and branches pushed
   in the last 3 days that are not `ws/`, `claim/` or `integrate/`, and the files they change.
4. **Pick one item.** In this order: a red `main` or a crash, a bug in `docs/playtest.md`, then
   the top unblocked backlog item for the **basics** (worker brief), across all four areas,
   favouring the basic that is furthest behind. Skip items the owner is working on, items
   already in one of your open PRs, and items marked Done in a note. Size it so it is built and
   tested in this run; split it if not. Write one sentence on what a player will feel that they
   didn't before (fun comes first).
5. Branch `ws/builder/<short-slug>` from the latest `main` and build it, following `CLAUDE.md`
   (procedural art, add-only migrations, save compatibility, no secrets). Add at least one unit
   test, and a bot behaviour for anything players can do.
6. **Test lean.** Run the unit tests locally
   (`godot --headless --path game -s tests/unit/run_all.gd`) and only the extra checks your
   change needs (for example a short `--duration 45` bot test when you touched the server or
   the protocol). Don't run the full 3-minute bot test or the client smoke test locally: the
   PR's CI runs both, and auto-merge waits for them (CLAUDE.md hard rule 2 still holds).
   Screenshots for an on-screen change come from your own short render or CI's smoke artifact.
7. Write the notes as new files (see "Notes go in new files", using the item's area): a
   changelog fragment `changelog.d/<area>-<slug>.md` (1 to 3 fun, clear player-facing lines), a
   devlog note, and a backlog note ticking the item with any follow-ups.
8. Open a PR titled `[<area>] <what players get>`. The body starts with a **Why it's more fun**
   line. Turn on auto-merge with the squash method:
   `gh api -X PUT repos/<owner>/<repo>/pulls/<n>/ccr/auto_merge -f merge_method=squash`. Never
   call merge yourself, and don't wait for CI: if it goes red, the next run fixes it (step 2).
9. Release the claim with the PR link and stop. Never ask questions; make the call and write
   down why in the devlog note.

**CI is the real test run.** CI tests a PR once, on its PR run. Docs-only PRs (`docs/`,
`changelog.d/`, root `*.md`) run only the unit tests and the fast checks, so integrator PRs land
in a few minutes.

## Integrator procedure (daily)

0. **Cheap exit first, before cloning.** Check: PRs merged in the last 24 hours, open `ws/*` PRs,
   the latest `main` CI result, untagged reports in `docs/playtest.md`, and whether any area's
   Backlog has fewer than 4 open items. If nothing merged, nothing is open, `main` is green, no
   report is untagged and every backlog has 4 or more items, stop with one line. Otherwise take
   the `integrator` claim; if it's busy, stop with one line.
1. Attach and clone (shallow). Read `CLAUDE.md`, `docs/worker_brief.md` and this procedure.
2. **Health first.** Check the latest CI run on `main` and the Railway deploy. If `main` is red
   or the deploy failed, revert the breaking commit through a PR with auto-merge on, before
   anything else (the smallest fix in any file is also fine; say so in the PR).
3. **Review, don't merge.** GitHub auto-merge does the merging; the integrator never calls
   the merge API. Look at every `ws/*` PR merged since your last run and every one still open,
   oldest first. **Never touch the owner's own PRs or branches** ("The owner's own work"):
   no comments asking for changes, no auto-merge, no reverts, no closing.
   - Review against the hard rules: add-only migrations, procedural
     only, no secrets, save compatibility (old fixtures still load), tests added.
   - Review for fun (design bible, "Fun comes first"): the PR has a "Why it's more fun"
     line that is true, and it doesn't make the game slower, duller or noisier for players
     (the bot test's fun metrics didn't get worse). A PR missing the line gets a comment
     asking for it; one that makes the game less fun is treated like a rule break.
   - **Open PR that breaks a rule:** turn its auto-merge off
     (`gh api -X DELETE repos/<owner>/<repo>/pulls/<n>/ccr/auto_merge`) and leave a PR comment
     with what to fix. The builder fixes it next run and turns auto-merge back on.
   - **Open PR with no auto-merge** (the builder forgot): if it passes review, turn auto-merge on.
   - **Open PR with a merge conflict:** merge `main` into the branch, resolve, push, and let
     auto-merge finish it after CI.
   - **Merged PR that breaks a rule:** open a revert PR with auto-merge on and add the item
     back to its area's backlog with a note.
   - If a PR has been stuck for over 24 hours, close it with a reason and put the item back in
     its area's backlog.
4. **Fold the changelog and the notes.** The release notes already show
   unfolded `changelog.d/*.md` fragments on top of the week's entry, so players see new notes
   as soon as a PR lands, and workers read unfolded notes as part of their backlog and devlog.
   Fold whenever anything is waiting (the integrator runs once a day). In one PR, together with
   the backlog refill and digest of steps 7 and 8:
   - move every changelog fragment into `CHANGELOG.md` under the current week's heading (`## Week NN — <headline>`;
     create it if this is the first merge of the week, with a provisional headline);
   - append every devlog note in `docs/devlog/<stream>.d/` to the end of `docs/devlog/<stream>.md`,
     oldest first, each under a `## YYYY-MM-DD — <slug>` heading;
   - apply every backlog note in `docs/workstreams/<stream>.d/`: tick the Done item (with the
     note's one line and branch, kept short), add its follow-ups under the Backlog, and add its
     requests under "Requests from other streams". If an item can't be found, add the note's
     line under the Backlog as done so nothing is lost;
   - delete every note and fragment you folded (keep `changelog.d/README.md` and each folder's `.gitkeep`).
   Notes the owner wrote are folded like any other.
5. Confirm the last day's merges passed CI, the server redeploys, and the `Week NN` release updates. Railway
   deploys the server itself from `main` when server files change (`railway.json`
   `watchPatterns`), and waits for that commit's CI to pass first ("Wait for CI" is on in
   Railway, set by the owner 2026-11-23); CI no longer deploys a second time. A red `main`
   therefore never reaches players, but fix or revert it at once: nothing else deploys
   until `main` is green again. If the deploy breaks, revert and
   confirm the previous version is live.
6. **Triage `docs/playtest.md`** (this was qa's job): tag new reports and add each to the
   right area's backlog, near the top.
7. **Refill the backlogs** (this was the director's job): every area keeps 4 to 8 well-sized
   items, the basics first (worker brief), ordered by how much fun they add soonest, with
   dependencies in the right order (data before the UI that shows it) and requests between
   areas answered. Never bring back polish the owner cut while a basic is unfinished. Leave
   items the owner added where they put them. Keep `docs/worker_brief.md` true to the bibles.
8. **Write the digest** `docs/digest/YYYY-MM-DD.md` (Chicago date, under 200 words, plain
   language for the owner): how far each of the four basics came, what landed yesterday, what
   the builder will do next, anything stuck, and budget use so far.
9. Put steps 4, 6, 7 and 8 in **one** docs-only PR on `integrate/YYYY-MM-DD`, with auto-merge on
   (squash). Never push to `main` directly. Release the claim and end with the digest's text and
   the PR link.

**Week numbers:** weeks start Friday. Week 00 started 2026-11-20. Week NN is the number of
whole weeks since then.

## Weekly review (Fridays)

See `docs/weekly_task.md`. Like everyone else, it changes `main` only through a PR with
auto-merge on, which lands once the "Test" check is green.
