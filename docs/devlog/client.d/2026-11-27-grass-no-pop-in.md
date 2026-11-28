## 2026-11-27: grass with no edge and no pop-in (claude/project-thread-i6uld8)

Owner, 2026-11-28 (playtest screenshot): "I don't like how I can see the grass loading in."
Fun: the meadow around you looks like it goes on, instead of a carpet that follows you with a
hard edge and grows in when you turn.

### What was wrong
- Grass was a 24 m disc around a point 9 m ahead of the camera, full density to 17 m, then
  every tuft shrank over the last 7 m. From the action camera that reads as a dense dark wall
  ~30 m out, then bare painted turf.
- The disc's centre was pinned ahead of the camera, so turning round moved it 18 m in one frame:
  whole cells appeared at full size in the middle of the view.
- The blade sheet's mipmaps were averaged (`generate_mipmaps`), which drops thin blades' alpha
  under the 0.4 cut, so tufts a few dozen metres out vanished in the mip chain anyway.

### What shipped (`game/procgen/grass.gd`)
- Every tuft draws a rank (one more rng value per try, in INSTANCE_CUSTOM.x). The share of tufts
  that stand at distance d is `visible_fraction(d) = (1 - smoothstep(FULL 12, RANGE 52, d))^2`;
  the shader grows a tuft out of the ground as that share passes its rank (over a 0.1 band), so
  the meadow thins gradually and walking toward grass thickens it a tuft at a time. Far tufts
  stand up to 50% bigger and lose their dark roots (blend toward the ground's tone), so the
  thin far meadow melts into the painted turf instead of reading as a band.
- Far cells hold only the tufts that could stand there: `tier_cap(d)` picks the smallest of 13
  rank caps over `visible_fraction(d - 2 m)` (0 past the range: no ground sampled at all). A cell
  is rebuilt with a higher cap as it comes nearer; `cell()` is split into `samples()` (the slow
  ground sampling, cached per cell) and `tufts()` (placement), so a tier rebuild costs ~0.4 ms
  instead of 0.5-2.3 ms. Capped output is exactly the uncapped tufts ranked under the cap, same
  order (tested), so nothing moves on a rebuild.
- The centre eases after the camera (rate 1.5/s; snaps on a jump over RANGE). Cell building is a
  time budget (1.5 ms a frame, at least one cell) instead of 2 cells a frame.
- `coverage_mips()`: the blade sheet's mip levels are built by hand, a texel opaque if any texel
  under it is, so far blades stay solid.

### Cost
- Client smoke render budget (llvmpipe): primitives noon 486k -> 516k, night 518k -> 549k
  (+30k: ~11k tufts in range on the Ashgrove meadow against ~5k before). Draw calls, materials,
  texture memory unchanged; software frame time within noise. Under the 560k ceiling, but with
  only ~11k to spare at night; the baseline is reset to these frames.
- On the live island meadow the MultiMesh holds ~8.6k tufts (was ~6.3k).

### Tried and dropped
- RANGE 58 with a linear falloff and 7 coarse tiers looked best (grass to the horizon of the
  meadow) but put night at 560k primitives, on the ceiling. Squaring the falloff with bigger far
  tufts kept most of the look for a third of the extra tufts.

### Notes to next time
- `tests/client_smoke/grass_shots.gd` shoots a meadow on the live island (settled noon/golden,
  a quarter second after a 180 turn, 20 frames of a 6 m/s run). Use it for any grass change.
- If the primitive ceiling gets tight, the cheapest lever is THIN (3.0 roughly halves the far
  tufts again) or FULL; the near 12 m is what the eye reads.
