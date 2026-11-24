# Character animation goes live (2026-11-23)

Builds on the groundwork PR (skeleton, clips, `AvatarAnimator`), now that #171's traveller is on main.

- `AvatarBuilder.build()` now returns the root with a posable "Skeleton" (one skinned mesh) and the name tag. `parts()`, `rig()` and `LIMB_PIVOTS` are unchanged, so every looks test and seed still holds. `AvatarBuilder.skinned(seed)` gives the skeleton alone.
- Skinning (`AvatarSkeleton.skin_parts`): each vertex is weighted along its chain by where it sits at rest, blended across each joint over ±3.5 cm. That makes an elbow, a knee or the waist bend as one smooth piece. Head gear (anything centred above 1.57 m) rides the head whole, and the pack and bedroll ride the chest whole, so they never shear. The skeleton's forearm and hand joints follow #171's 0.09 rad arm splay, so elbows bend where the sleeves are.
- **One draw call per traveller instead of five.** The client smoke test at spawn went from 251 to 243 draw calls at noon (two travellers in view).
- `client.gd` steps an `AvatarAnimator` per avatar (with the gather node, as GatherSwing had) and applies it to the skeleton. `WalkAnim` and `GatherSwing` are no longer used by the client. GatherSwing's static helpers (stroke shapes, `face_yaw`, `style_for`) are still the source for the gather loop. `Footsteps` takes any animator with WalkAnim's interface.
- New bot behaviour `client_avatar_animator`: runs the animator on the live snapshot stream for every avatar in view and cycles one avatar through down, getup, sit and stand. 8 bots × 180 s passed, with every body state reached.

Not done yet:
- Swings (v7) aren't hooked up, because #180 isn't merged.
- Jump, rest and a visible knock-down wait on gameplay's v8 events (`docs/workstreams/gameplay.d/from-client-animation-events.md`).
- No `height` is passed to the animator yet. Smoothing lag on a slope would read as "airborne", so pass it only for real server jumps.
- The old `client_walk_anim` and `client_gather_swing` bot behaviours and their unit tests still test the retired classes. They're harmless; qa can retire them.
