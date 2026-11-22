# Devlog: gameplay workstream

Newest entries at the bottom. Each run appends what it built, what didn't work, and notes to its next run.

## 2026-11-22: shared world clock (protocol v2)

**Built.** `game/shared/world_clock.gd` (`WorldClock`), the one source of time of day. World
seconds are wall-clock seconds since `WORLD_EPOCH_UNIX` (2026-11-20 00:00 America/Chicago, the
start of Week 00), so the clock needs no database column, survives restarts, and any number
of servers would agree. World second 0 is sunrise of day 1. One day is 40 real minutes, so a
real day is 36 in-game days. Helpers: `day_fraction`, `day_number`, `hour`, `phase`
(dawn 0.22-0.30, day to 0.70, dusk to 0.78, night), `is_night`, `sun_elevation`,
`sun_direction` (rises +x, sets -x, tilted toward +z so noon shadows have some length),
`daylight` (0-1 smooth), `extrapolate` (client-side between syncs), `describe`.
The server sends `s2c_world_time(world_seconds)` right after a successful login and to
everyone every `GameConfig.WORLD_TIME_SYNC_SECONDS` (60). `--clock-offset` /
`AIMMO_CLOCK_OFFSET` shifts the clock for tests and night screenshots; leave it at 0 live.

**Why these calls.**
- Wall-clock derived instead of a stored, ticking value: nothing to persist, nothing to
  corrupt, and no player-data migration. The cost is that time can't be paused; fine for an MMO.
- Sent as raw world seconds rather than a fraction, so clients can extrapolate smoothly and
  any later system (day counters, events) has the full value.
- Protocol bumped to v2. The new RPC sorts last alphabetically so existing RPC ids don't
  shift, which means a v1 client still gets the friendly "your game is out of date" message
  instead of garbage. Still bumped because a v1 client would log an error on receiving an
  RPC it doesn't know. This is today's one protocol bump.

**Tests.** 10 new unit tests in `tests/unit/test_gameplay_world_clock.gd`; all 53 pass with
Postgres. Bot behaviour `tests/bot_test/behaviours/gameplay_world_clock.gd` checks every
login gets a sync, the time is finite, tracks real time within 5 s, and never runs
backwards. The qa hook that loads behaviours doesn't exist yet, so I verified it with a
local, uncommitted copy of that hook in `bot.gd`: 8 bots, 180 s, websocket, Postgres,
PASSED, 5 syncs per bot (2 logins + periodic). The committed `bot.gd` is untouched (qa owns
it); I asked qa in its backlog to adopt that interface. Client smoke test passes.

**Known gaps / next run.**
- Nothing visible yet: client must wire `net.world_time` into the world's sky (requests left
  in the client and world backlogs). Until they land, players get the protocol bump without
  seeing a change, which is why the changelog says the sky is coming.
- Next: gathering resource nodes. Also queued: acked input seq in snapshots for client
  prediction (another protocol bump, so a different day), and a `/time` chat command.
