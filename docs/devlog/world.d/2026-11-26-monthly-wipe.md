# Monthly wipes (world)

Owner, 2026-11-26: "lets do monthly. Does this happen automatically?" Yes: a server started with
`AIMMO_WIPE=monthly` (or `--wipe=monthly`) on a generated world wipes itself on the first
Thursday of every month at 19:00 UTC.

## How it works
- `WipeSchedule` (shared): pure date maths on Unix seconds, so tests pick any date.
- `WorldWipe` (server): at boot keeps the store's current world until its wipe time, else rolls
  one. The first world takes the AIMMO_WORLD seed; every later one a fresh random seed (never the
  one just played). Gen version and size follow AIMMO_WORLD.
- Migration 0005 (add-only): `worlds` (every world kept forever, `wiped_at` set when it ends),
  `characters.world_id`, `wipe_archive` (position + pack as JSON).
- The wipe at runtime: warnings at 60, 10 and 1 minutes; at the time it saves everyone, sends
  them off with a line, records the new world and calls `use_world` (no restart needed: the
  client already rebuilds for a new `s2c_world`).
- **Lazy per character.** Nothing is bulk-cleared. The first login on a world a character wasn't
  on archives their pack and position, sets every item to qty 0 (rows kept), and washes them up
  on a landing. Someone who never comes back is never touched. A server that was down at wipe
  time wipes when it boots.

## Notes to self
- Off is exactly as before: `world_record` stays `{}` and every new path is a no-op. Ashgrove
  refuses wipes even when asked.
- Turning wipes on for a world whose characters have `world_id` 0 (everyone from before) wipes
  them all on their next login. That's right for a move onto a new island, but it's a production
  change: owner's go-ahead and an announcement first.
- If archiving fails, the pack is left alone and the wipe is retried at their next login.
- Tested on Postgres 16 locally (`test_postgres_keeps_worlds_and_archives`) and on the JSON store.
