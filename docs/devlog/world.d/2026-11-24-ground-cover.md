## Ground cover patches (ws/world/ground-cover)

**Picked.** Top backlog item, owner direction 2026-11-24 (grounded art), step (1): ground cover. Steps (2) lanterns and (3) level-up sparks are next. **What a player will feel:** walking out of Spawn Meadow, the ground has a story (a damp mossy hollow, a sunny straw-coloured rise, a scuffed patch of earth), so the valley reads as a real, old place instead of a flat green carpet.

**Built.**
- `Palette.MOSS`, `DRY_GRASS`, `BARE_EARTH` (all under 0.45 saturation) and `Palette.ground_at(x, z, h, slope, jitter)`: `ground()` plus seeded cover. `Palette.ground()` is unchanged for its other callers.
- `Palette.cover_weights(x, z, h, slope)`: two FastNoiseLite fields seeded from `WORLD_SEED` (cover ~38 m, earth ~22 m). Moss and dry grass are the two ends of one field so they never fight; moss is biased up in the forest band (h 5 to 7 blend) and near the lake shore, dry grass up on the open valley. Bare earth is its own field with a small slope bonus. Each blend capped (`COVER_MAX` 0.65, `EARTH_MAX` 0.6) so the base grass always shows through. Shore, rock (slope > 0.55 or h > 13) and snow get nothing.
- `TerrainMesh._tri` calls `ground_at` with the face centre. Still flat-shaded per face, still one material; build time unchanged within noise (1.84 s).

**Tried.** First pass used narrow smoothstep bands (0.10 to 0.55) and a 14 m earth field: a 1 m step changed a weight by up to 0.43, which reads as hard-edged blotches. Wider bands and a 22 m earth field bring it under 0.2 per metre. `COVER_MAX` 0.55 was almost invisible at the spawn camera; 0.65 reads without turning into a quilt.

**Measured.** Over a +-300 m grid of grassland: moss on ~22%, dry on ~14%, earth ~11%, plain base grass ~25%. Smoke style: noon sat_mean 0.296 -> 0.286, warmth 0.113 -> 0.106, luma 0.536 -> 0.521 (a touch flatter and earthier, as intended; well inside the baseline, so not rewritten). Render budget unchanged (vertex colours only).

**Looked at.** Noon, golden hour (0.29) and midnight from the spawn camera, before and after (project files `world/ground-cover/`). The spawn view is subtle: a straw rise and an earth patch to the right of the bench. Honest note: from the low action camera the patches read most on the mid-ground; a higher shot over the valley would show them better.

**Tests.** `test_world_ground_cover.gd` (6 tests): tokens are muted earthy naturals; the meadow has moss, dry and earth patches in sensible shares with plenty of plain grass; under 0.2 change per metre and never full cover; forest mossier, open valley drier; shore, rock, cliff and snow untouched; deterministic and a built chunk shows several tones on one material. No bot behaviour: nothing on the network, and the art lint keeps procgen out of bots. Unit suite with Postgres: 780 pass. 8-bot 180 s websocket bot test passed (276 s). Client smoke passed (style and render budget ok).

**Next run.** Wilderness lanterns (timber posts, iron and horn lanterns), then rounder level-up sparks.
