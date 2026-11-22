# Weekly work budget

The owner pays for a fixed amount of usage. This file caps how much work the automated
sessions do per week so they stop at a chosen point. Only the owner (or the weekly review,
at the owner's request) changes these numbers.

| Setting | Value |
|---|---|
| Max PRs opened per workstream per week | 10 |
| Integrator | runs only when there is something to merge |

**How workers check it (step 0 of every run):** count PRs whose head branch starts with
`ws/<stream>/` created since the start of the current week (Friday 00:00 America/Chicago):

```sh
SINCE=<YYYY-MM-DD of the most recent Friday>   # e.g. date -d "last friday" +%F, or today if today is Friday
gh api "repos/rp8g7mjrr5-design/AiMMO/pulls?state=all&per_page=100" --paginate \
  --jq "[.[] | select(.head.ref | startswith(\"ws/<stream>/\")) | select(.created_at >= \"${SINCE}\")] | length"
```

If the count is at or above the cap, do nothing else: do not clone, build, or test. End the
run with one line saying the budget is reached. (Fixing your own already-open PR is still
allowed, because it doesn't open a new one.)

The weekly review reports how much of the budget each stream used.
