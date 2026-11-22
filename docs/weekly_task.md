# AiMMO — Weekly Review Procedure

This runs every Friday at noon (America/Chicago). Features are built all week by the
workstreams and merged by the integrator (see `docs/workstreams.md`). The weekly review does
not build features. It makes sure the week adds up to something good, names it, and sets up
the next week. The update must be live and playable by the weekend.

## 1. Orient
1. `CLAUDE.md`, the rules. Follow them over anything else.
2. `docs/design_bible.md`, especially the North star.
3. `docs/roadmap.md` and every `docs/workstreams/<stream>.md` backlog.
4. This week's merged PRs, `docs/devlog/<stream>.md` entries, and last week's `docs/devlog/week-NN.md`.
5. `docs/playtest.md`. Make sure every report is tagged `[open]`, `[fixed in Week NN]`, or `[can't reproduce: reason]` and is in a stream's backlog.

## 2. Health check
- Run all unit tests and the full bot test on the current `main`.
- Check the latest GitHub Actions run and that the server is deployed and healthy.
- If anything is broken, fixing it comes first (any file, smallest fix, explained in the devlog).
- Check each workstream ran this week and look for stuck PRs. Close PRs stuck over 24 hours with a reason, and put the item back in its backlog.

## 3. Name the week
- Pick the week's headline: the most player-visible thing merged this week.
- Set the current `## Week NN — <headline>` heading in `CHANGELOG.md` and tidy that week's bullets into fun, clear patch notes.
- Write `docs/devlog/week-NN.md`: what each stream shipped, what didn't work, known bugs, and specific notes for next week.

## 4. Plan
- Update `docs/roadmap.md` so it always covers the next 4 to 6 weeks.
- Rebalance every stream's backlog to match the roadmap and the North star. Each stream should have at least 5 well-sized items, cross-stream dependencies ordered correctly, and requests between streams answered.
- If the design vision changed, log it in the design bible's revision history with the reason.

## 5. Ship
- Open a PR with these changes, wait for the "Test" check, and merge it (`main` is protected; never push to it directly). Confirm the Actions run on `main` passes, the server redeploys, and the GitHub Release `Week NN — <headline>` shows the final notes and client builds.
- If the deploy fails, roll back to the last good commit and confirm the previous version is live.

## 6. Report
End with a short summary for the owner: the week's headline, what each stream shipped, how much of the weekly budget in `docs/budget.md` each stream used, notable fixes, known issues, and whether the update is live.
