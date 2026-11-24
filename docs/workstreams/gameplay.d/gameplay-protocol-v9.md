Done: **(director, owner direction 8), part 2: the world config on the wire (protocol bump).** (ws/gameplay/protocol-v9-world-campfires)
Protocol v9: `s2c_world(WorldGen.config())` right after the login reply. Also does the first follow-up of `gameplay-placed-campfires.md` ("Campfires on the wire in the next free bump"): `c2s_place(item)`, `s2c_place_result(item, ok, reason, text)` and `s2c_campfires` are live (integrator: fold as one).

Follow-ups:
- [ ] Save campfires with the world: add-only migration 0005 `world_campfires` (0004 has landed), and the JSON store; load on start, drop any already out.
- [ ] Next bump (v10): stance events, `s2c_gloam`, `c2s_dodge`, the ruin-entered notice: whichever are built by then, one bump.
