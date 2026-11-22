[weekly_task.md](https://github.com/user-attachments/files/35228458/weekly_task.md)
# AiMMO — Weekly Update Procedure

This runs every Friday at noon (America/Chicago). You are the sole developer of AiMMO. The update must be live and playable by the weekend.

## 1. Orient (read before touching code)
1. `CLAUDE.md`, the rules. Follow them over anything else.
2. `docs/design_bible.md`
3. `docs/roadmap.md`
4. The latest `docs/devlog/week-NN.md`, your notes to yourself.
5. `docs/playtest.md`, the human's bug reports. Mark each one `[open]`, `[fixed in Week NN]`, or `[can't reproduce: reason]`.

## 2. Health check
- Run all unit tests and the bot test on the current `main`.
- Check the latest GitHub Actions run and whether the server deployed successfully.
- If anything is broken, **fixing it is this week's first priority**, before any new feature.

## 3. Choose this week's update
- Take the next item from `docs/roadmap.md`, unless something more important came up (a broken system, a critical bug, or a design problem you noticed).
- Pick **one headline feature**. Size it so it can be built and fully tested in this session.
- Write the plan at the top of a new `docs/devlog/week-NN.md` before coding.

## 4. Build
- Implement the feature, following the layout and rules in `CLAUDE.md`.
- Any database change goes in a new, add-only migration.
- All new visuals and sounds are procedural.
- Add unit tests and a bot-test behavior for the feature.

## 5. Test
- Run all unit tests and the full bot test (8+ simulated players, 3+ minutes).
- Confirm that existing player data still loads after migrations.
- If tests fail: fix and retest. If you can't get to green, **revert this week's feature**, ship fixes only (or nothing), and explain why in the devlog.

## 6. Ship
- Update `CHANGELOG.md` with player-facing patch notes for Week NN.
- Push to `main`. Confirm the GitHub Actions run passes, the server redeploys, and a GitHub Release named `Week NN — <headline feature>` is published with client builds attached.
- If the deploy fails, roll back to the last good commit and confirm the previous version is live.

## 7. Write it down
- Finish `docs/devlog/week-NN.md`: what shipped, what didn't, known bugs, and specific notes for next week.
- Update `docs/roadmap.md` so the plan always covers the next 4–6 weeks.
- If you changed the design vision, log it in the design bible's revision history.

## 8. Report
End with a short summary for the owner: the headline feature, notable fixes, known issues, and whether the update is live.
