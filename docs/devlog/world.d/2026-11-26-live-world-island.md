# The official world moves onto the island (world)

Owner, 2026-11-26, "yes" to moving the live world onto the wiping island once it was ready.
- `Dockerfile`: `AIMMO_WORLD=1126:2:3000`, `AIMMO_WIPE=monthly`. 1126 is only the first seed.
  Unset both (or set them on Railway, which overrides the image) to go back to Ashgrove.
- Protocol v11, with no new RPCs: clients from before #231 always drew Ashgrove whatever
  `s2c_world` said, so they are told to update instead of walking on the wrong ground.
  `net_v10.gd` and `net_play_v10.gd` are frozen.
- Every existing character has `world_id` 0, so their pack is archived and emptied on their
  first login on the island, and they wash up on a beach. The patch notes say so.
- Checked a boot with the live settings locally: world 1 (seed 1126), 34 places, 4,198 nodes,
  next wipe Thursday 3 December 19:00 UTC, clean stop.
- The bot test and CI still run Ashgrove (no AIMMO_WORLD there). Next: bot coverage on an island.
