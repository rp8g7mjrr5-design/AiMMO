Done: owner request 2026-11-26, automatic monthly wipes (ws/builder/monthly-wipe)
Ticks "Automatic monthly wipe" from world-island-generator.md. `AIMMO_WIPE=monthly` on a generated world: first Thursday of every month at 19:00 UTC (`WipeSchedule`), a new seed, packs archived then emptied as each player returns (`WorldWipe`, migration 0005), looks and names kept. Off by default and never on Ashgrove.

Follow-ups:
- [ ] Show the next wipe date in the server list once there is one (today: a line at login, warnings at 60/10/1 minutes).
- [ ] Clear bases at the wipe when bases exist (they'll need a world_id like characters).
- [ ] "Best days survived" doesn't exist yet: when it does, keep it across wipes (owner/coordinator: records stay).
- [ ] Bot-test coverage across a wipe once the official world runs an island with wipes on (`--wipe=monthly` plus a test clock); today the unit tests drive the whole wipe on the server.
- [ ] Moving the official Railway world onto a wiping island is a production change: owner's go-ahead first, and announce it, because everyone's pack is archived and emptied on their first login there.
