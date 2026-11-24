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
