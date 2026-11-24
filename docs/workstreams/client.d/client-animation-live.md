Done: Skin the traveller (#171's parts) to `AvatarSkeleton` and swap `WalkAnim` + `GatherSwing` for `AvatarAnimator` in `client.gd` (claude/animation-live)
One skinned mesh per traveller, posed by AvatarAnimator: idle, walk, run and gathering are live.

Follow-ups:
- [ ] Pass `height` (metres above the turf) to `AvatarAnimator.step` once the server has real jumps, and only then. Smoothing lag on slopes would read as airborne.
