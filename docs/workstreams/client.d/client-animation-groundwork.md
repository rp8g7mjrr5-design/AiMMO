Follow-ups:
- [ ] Skin the traveller (#171's parts) to `AvatarSkeleton` and swap `WalkAnim` + `GatherSwing` for `AvatarAnimator` in `client.gd` (one skinned mesh per avatar, 1 draw call instead of 5).
- [ ] Wire v7's `s2c_swing` into `AvatarAnimator.swing()` for every avatar in view, and a craft result into `craft()`.
- [ ] Once gameplay ships the v8 stance events (see gameplay.d/from-client-animation-events.md): jump key (Space), rest key, and `knock_down()` / `get_up()` / `sit()` / `stand()` on `s2c_stance`.
- [ ] A walk toggle: the server moves everyone at 6 m/s, which is a run. A slower walk would also give players the walk cycle.
- [ ] Carried tools: an axe, pick or hammer in the right hand while gathering or crafting, attached to the `RightHand` bone.
