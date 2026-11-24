Done: Phase 2 build-ahead: the campfire and the cooked meal (ws/world/campfire-model)
`CampfireProps`: lit, low and ash looks, pooled on the shared materials with 3 flickering light pools; `cooked_meat` icon drawn ahead. Also answers gameplay's ask for "the placed campfire model (lit, embers, burned-out ash)" in `gameplay.d/gameplay-placed-campfires.md`.

Follow-ups:
- [ ] Campfire sparks: a few pooled ember sparks rising off a lit fire, sized by `Quality.motes_scale()`; a thin smoke wisp off a low fire and a burned-out one.
- [ ] Campfire light on Compatibility: at Spawn Meadow the fire's light pool can drop out (GLES3's 8 lights per mesh, the meadow terrain chunk already has 8 lanterns and the bench). If players camp in the meadow, ask client to raise `max_lights_per_object` or give the fire's ground a small emissive glow disc instead.
- [ ] Campfire camera solid: if the action camera clips through the flames, add each fire's ring to `WorldSolids` (a runtime entry; the solids are built once today).
