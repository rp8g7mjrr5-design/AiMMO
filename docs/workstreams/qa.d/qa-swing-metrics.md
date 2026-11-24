Done: A hunt in the bot test, and swing metrics (ws/qa/swing-metrics)
The hunt was already in (gameplay_hunt); `qa_fun_metrics` now hears v7 swings, refusals and blows as feedback, counts a kill from its first drop, and the report prints combat totals. `gameplay_first_swing`'s `_tell_fun_metrics` is gone.

Follow-ups:
- [ ] Swing metrics follow-up: after three `main` CI runs, consider gating combat in `fun_baseline.json` (e.g. `kills_min` 1 on long runs, `swings_hit` share) once the hunt never skips; today it is reported only
- [ ] Swing metrics follow-up: add swings and kills to `tools/fun_trend.py`'s table and vs-yesterday line (with the perf columns item)
