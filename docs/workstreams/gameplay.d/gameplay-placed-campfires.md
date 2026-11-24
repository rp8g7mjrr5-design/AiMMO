Done: **Phase 2 build-ahead: placed campfires.** (ws/gameplay/placed-campfires)
`game/shared/campfires.gd` rules (1.5 m in front, dry ground, clear of nodes, bench and other fires, 3 per player, 32 in the world, four world hours), `Server.place_request` takes one from the pack, fires burn out on their own and feed `gloam_fires()`, so walkers keep 6 m off. Dev-only `/place` and `/kindle`; `s2c_campfires` produced but waits for a bump; not saved yet.

Follow-ups:
- [ ] Campfires on the wire in the next free bump: `c2s_place(item)` running `Server.place_request`, and `s2c_campfires(PackedFloat32Array [id, x, y, z, seconds_left])` (already produced on every change and on login; `_send` skips it until the RPC exists). Ask world for the placed campfire model (lit, embers, burned-out ash) and client for a place key with a ghost preview at `Campfires.spot_in_front` and the refusal lines as notices.
- [ ] Save fires with the world: an add-only `world_campfires` table (id, x, y, z, owner, burns_until as world seconds) in the migration after #197's 0004, and the JSON store; load on start and drop any already out. Until then a restart puts every fire out (each burns under seven real minutes, so little is lost).
- [ ] Cooking (next item, hunger): `raw_meat` cooks into `cooked_meat` when you stand within `Campfires.WARM_RADIUS` of a lit fire (`Campfires.is_warm`).
- [ ] Turn `/kindle` and `/place` into bot coverage of the keepaway with `--gloam` on, once qa turns it on for the main bot test (bot *_3 could fight with a fire at its back).
