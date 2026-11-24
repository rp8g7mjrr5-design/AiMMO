**Why this item:** top of the client backlog, an owner-direction item (character overhaul,
art bible section 3): the new lean 1.78 m travellers were still walking on angles tuned for
the old stubby figure. Fun line: the person you're walking with stops goose-stepping and
waddling across the meadow and moves like someone who lives outdoors, so the valley reads as
grounded instead of silly at a glance.

**Built:** retuned `WalkAnim`'s constants only (no new code paths, so footsteps, prediction and
the gather swing are untouched):
- `LEG_SWING` 0.5 -> 0.34 rad: each foot now reaches 0.31 m fore and aft instead of 0.44 m
  on the 0.92 m legs.
- `ARM_SWING` 0.65 -> 0.4 rad: hands swing 0.25 m instead of 0.38 m; still a little wider
  than the legs, as people swing.
- `SWAY_ROLL` 0.06 -> 0.018 rad: head sway 3 cm instead of 11 cm. This was the waddle.
- `BOB_HEIGHT` 0.07 -> 0.08 m: "a little more bob" per the item, so the weight still reads.
- Cadence (`STRIDE_CYCLES_PER_SEC` 1.55, about 186 steps a minute) and `LEAN` kept: at
  `WALK_SPEED` 6 m/s that is a jog cadence and it already looked right.

**Gather swing checked:** worked out where the hand lands at the bottom of each stroke with
the new arms (shoulder 1.42 m, 0.63 m arm, plus the stroke's lean): chop about 0.88 m high and
0.58 m forward, mine 0.78 m / 0.53 m, collect 0.84 m / 0.59 m; chop and mine wind up to about
2 m, over the head. No change needed. A new unit test pins those bands
(`test_strokes_land_with_adult_arms`), so a later rig change that breaks it fails.

**Before/after:** `/mnt/project-files/animation/walk-stride-before-after.png` (side and front,
six frames through one step at full speed), rendered with a scratch SceneTree script that
builds `AvatarBuilder` figures and stops a `WalkAnim` at even phases (not committed).

**Tests:** `test_client_walk_anim.gd` +2 (adult limits from `AvatarBuilder`'s lengths; the pose
never passes them even faster than walk speed), `test_client_gather_swing.gd` +1. Bot behaviour
`client_walk_anim` now also fails if any pose on the real snapshot stream goes past the leg
swing or roll. 795 unit tests, the 8-bot 180 s WebSocket bot test and the client smoke test pass.

**Notes to next run:** the legs are still rigid pivots, so at 6 m/s the feet cannot keep up
with the ground (about 1.9 m covered per step against 0.6 m of foot travel); at a jog that
reads as flight, but a knee bend (world split thigh and shin into separate pieces for exactly
this) would make it read properly. That needs a knee pivot in `AvatarBuilder` (world owns it),
so a request went to world. Not judged in motion by a human yet; tune by eye from the clip.
