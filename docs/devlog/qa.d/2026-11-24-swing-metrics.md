**Swings, refusals, hits and kills in the fun metrics (ws/qa/swing-metrics).** Backlog item 2.
The hunt half of the item was already on `main` (gameplay's `gameplay_hunt`, one hunter per
long run, lures and downs a grazer and checks hide and raw meat), so this run did the metrics half.

**Built (tests/ only):**
- `fun_metrics.gd`: `swing()`, `swing_refused()`, `swing_landed(hit)` are feedback (the game
  answering a press) and count `swings`, `swings_refused`, `swings_hit`; `kill()` counts
  `kills`. `is_kill_drop(item)` is true for the first entry of any `Wildlife.drops(kind)`:
  the server sends one `s2c_gather_result` per drop in that order, so the hide marks one kill
  and its drops still count as rewards through the old path.
- `qa_fun_metrics.gd` listens for `swing_begun` / `swing_landed` (ours only) and
  `attack_refused`, and counts a kill from `_on_gather_result`.
- `gameplay_first_swing.gd`: dropped `_tell_fun_metrics()` (gameplay's v7 workaround), since
  the fun metrics now hear v7 themselves. `longest_wait_s` stayed at 0.12-0.2 s per bot in the
  full run, so nothing lost an answer.
- `fun_report.py`: combat totals (`swings`, `swings_refused`, `swings_hit`, `kills`,
  `bots_swung`) in the summary JSON and a `combat:` line in the table. Reported, not gated.
- Tests: 3 new unit tests in `test_qa_fun_metrics.gd` (feedback and counts, one kill per
  grazer with 3 items of reward, no gather node's item looks like a kill drop, read from
  `ResourceNodes.KINDS` and `TIER2`), 1 in `test_fun_report.py`.

**Results:** unit 858/858 (Postgres), python 61+ OK. Full bot test 8 x 180 s WebSocket with
fun and perf checks PASSED in 341 s: `combat: 18 swings by 8 bot(s), 2 struck, 16 more presses
refused, 1 kill(s)`. ENet 45 s PASSED (16 swings, 0 kills: no hunt on short runs, as designed).

**Why not gated yet:** the refusals are almost all `gameplay_first_swing`'s deliberate "busy"
probe (a light pressed mid-haymaker, two per bot), and only bot `_2` hunts, so `kills` is 0 or 1
depending on whether the hunt fit. A gate now would flake; follow-up after three CI runs.
`swings_hit` is 0 for first_swing on purpose (it swings at air); only the hunter hits.

**Perf note seen:** `cpu_ms_per_tick` 1.97 vs baseline 1.25 (note, not a failure). Generated
kingdoms (#206/#207) landed today, plausibly the cause; worth watching with the perf re-baseline item.

**Next run:** the restart-in-the-middle check (director part 2), or the smoke-shot hooks.

**CI fix on this PR (gameplay_wildlife, tests/ only).** The PR's first CI run failed one check
that this diff doesn't touch: `bot_1: [gameplay_wildlife] grazer 2 bolted but no herd-mate went
with it`. `main` was green on its last 5 runs. The server only sends herd-mates within
`Wildlife.HERD_RADIUS` (16 m) of the bolter running with it, and skips downed ones; since the
hunt landed, bot `_2`'s `/lure` pulls the nearest grazer away from its herd and downs it, so the
stalker can rush a grazer whose mates are all gone or out of reach. I couldn't confirm the herd
from CI (the test-output artifact host is blocked here), so this is the likely cause, not a proven one.
Fix: when the target bolts, the stalk checks the latest `s2c_wildlife` for a herd-mate clearly
inside 16 m (2 m slack) or already fleeing. With one there, the old check holds unchanged; with
none, it counts `herd_alone` and ends the stalk instead of failing. Re-run locally: PASSED in 339 s
(`herd_bolts=1 herd_alone=0`). If `herd_alone` shows up often in CI, ask gameplay to have
`/lure` prefer a grazer from a herd the stalker isn't near.
