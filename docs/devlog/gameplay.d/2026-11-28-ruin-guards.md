# Walkers rise at ruins (ws/builder/ruin-guards)

**Fun:** walking up to a ruin is now a choice. You see the Zombai shuffling in the yard before you get there, the loot is behind them, and a cleared small ruin stays yours while you search it.

**What shipped.** All in `game/shared/gloam.gd` (pure rules), so `server.gd` was untouched (the owner's thirst PR #252 has it open). `rise_near_players` first calls the new `rise_at_ruins(state, players, now, night, Ruins.all())`:
- A ruin wakes when any player is within its radius + `GUARD_WAKE` (50 m). Waking fills it to `guard_cap(grade, night)` at once (day 1/2/3/4, night 2/4/5/7); after that one guard per `GUARD_EVERY_DAY` 60 s / `_NIGHT` 20 s while under cap.
- Guards rise inside 0.85 of the pad's radius, on dry ground, never within `GUARD_MIN` 18 m of any player (beyond a night's 14 m sight) and never in the spawn's `SAFE_RADIUS`.
- A guard carries `ruin: <id>` and a home halfway between where it rose and the pad's centre. After a noise or fire it keeps that home (open walkers still adopt the spot), so it drifts back to its ruin after a chase.
- A ruin nobody is near is forgotten, so coming back finds it full again (its old guards crumble on the usual 70 m / 20 s rule).
- Guards count against the players' own caps through `count_near`, so open ground beside a guarded ruin stays empty by day: "few in the open by day, thick round the ruins".
- `MAX_WALKERS` 24 -> 32 to leave room for guards with 8 players at night. Guards are processed first.

**Calls made.** 18 m rather than `RISE_MIN` 26 m: with 26 m a Quiet farmstead (radius 22) could never refill while you are anywhere near it, and a castle (radius 60) never at all while you fight in it. 18 m keeps them out of sight and still lets a big ruin bite back. The walker isn't saved, no wire change (the walker dict's new `ruin` key never goes on the wire), no protocol bump.

**Tests.** `tests/unit/test_gameplay_ruin_guards.gd` on the live island config (1126, 3 km). No bot behaviour: CI's bot test plays Ashgrove, which has no ruins, so nothing there can exercise it; follow-up filed for qa's island phase. `tests/bot_test/test_night.py`'s sample log line updated to the new describe text (the check itself only reads the `gloam: on` prefix).

**Not done / next.** Beach landmarks (wreck, shack) have no guards; they aren't `Ruins.all()` sites. The first-walker tuning item ("a real threat") is still open and pairs well with this: a guard at a grade 1 ruin is the first fight most players will now have.

**What broke on the way.** First version counted guards with the plain 70 m `count_near` / crumble rule. On the castle (radius 60) a player at the wake edge is up to 160 m from a guard on the far side, so those guards crumbled after 20 s and the ruin churned, and open walkers rose beside it. Guards now carry their ruin's centre and wake ring (`ruin_pos`, `wake`): they stay, and count against your cap, while anyone is inside that ring (`_guards_near`).
