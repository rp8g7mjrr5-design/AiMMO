Done: owner request 2026-11-26, the island map: generator v2 (ws/builder/island-generator)
`IslandGen`: a 3 km island with beach landings, the location pool rolled per world with a layout seed per site.

Follow-ups:
- [ ] **Automatic monthly wipe** (owner, 2026-11-26): on the first Thursday of each month at 19:00 UTC the server rolls a new island seed, archives the old world, clears bases and packs, keeps looks and best days survived; next wipe date in the server list and in game. Needs gameplay's world save and qa's bot coverage across a wipe.
- [ ] Chunk streaming before the official world moves onto a 3 km island (the client builds all ~2,200 terrain chunks today).
- [ ] Set pieces read `layout_seed` and `rot` from `Ruins.all()`; the burned farmstead and the abandoned village first.
- [ ] Bridges where king's roads cross rivers; put toll bridges on those crossings.
