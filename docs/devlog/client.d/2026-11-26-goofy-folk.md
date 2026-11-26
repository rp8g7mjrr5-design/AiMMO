## 2026-11-26: the goofy cartoon folk (owner's pick)

**What:** I replaced the sculpted traveller (#229) with `Toon` (`game/procgen/toon.gd`), on survivors and the Zombai. The owner saw the sculpted body in game and said it "doesnt look good at all", then "we can make them funny" and asked whether "super small" would be easier. I rendered three directions in the meadow with the game's lighting: A small and chunky, B clean carved low poly, C goofy cartoon. The scratch script was `zz_scratch/dirs.gd`, and the shots are in `/mnt/project-files/art-direction/character-directions/`. The owner picked **C**.

**How:**
- Each figure is made of primitive parts (ball, capsule, cylinder, from `PrimitiveMesh.get_mesh_arrays()`, so it works headless). Each part rides one bone rigidly, and the parts merge into one skinned mesh.
- It uses smooth normals, one linear vertex colour per part, and the usual shade toward the feet.
- It uses the "folk" Emberlight material with `texel_grain` and `brush` set to 0. The grain was the "pixel noise" in the owner's screenshot.
- A survivor is about 4,100 to 4,300 triangles and a walker about 2,100. The walker builds with `ZOMBAI_DETAIL` 0.6, because up to 24 can be out at night.
- A figure builds in about 15 ms, so the sculpting thread, the disk cache and `TravellerBodies` are gone. `Traveller` and `SculptField` are deleted.
- On a player's machine, the old `user://travellers` cache folder stays on disk, unused and harmless. A future change could delete it on start.

**Skeleton:**
- `Toon.bones()` has `AvatarSkeleton`'s names and order with cartoon offsets.
- The leg chain (hip height, hip drop, thigh, shin) is `AvatarSkeleton`'s scaled by `LEG_SCALE` 0.74. Because of that, the clips' two-bone leg IK, which is written for the 0.92 m hip, still plants feet when:
  - the gait is drawn at `speed / LEG_SCALE`, and
  - `root_pos` is multiplied by `LEG_SCALE`.
- `AvatarAnimator.leg_scale` covers the first point and `apply_pose(..., root_scale)` the second. `ZombaiFigures` does the same for the shamble, and advances phase by `strides_per_metre(gs) / LEG_SCALE`.
- Short legs therefore take quick little steps. This is in character.

**What didn't work or was cut:**
- The first `Toon` pass was over 5,000 triangles (5,300 to 5,500). I fixed this with a `_detail` scale on segment counts.
- `_detail` is a static var set at the top of `parts()`. It is not thread-safe, which is fine for now because nothing builds off the main thread.
- Hood: the ball sits behind the head, so from the front the hood shows mostly as a rim. It reads well from behind thanks to the tail and cloak.

**Known:**
- `ZombaiBody.parts()` and `ZombaiBody.mesh()`, which build the old kit-of-parts walker, are now unused by the game. `test_client_zombai` still checks them. Delete both together in a cleanup.
- `AvatarBuilder.parts()` is likewise only used by tests and the bots' look checks.
- The appearance window's camera (`look_camera`) still aims at 1.15 m. That frames the shorter figure's chest and head fine, but it is worth a check in the window.

**Next:**
- Give the cartoon body a little more bounce in the clips (squash on landing, a wobble in the belly) without going floaty.
- Expressions: blink, and a surprised look when a Zombai grabs.
