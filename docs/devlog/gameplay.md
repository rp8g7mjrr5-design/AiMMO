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

## 2026-11-22 (second run): chat slash commands

**Built.** `game/server/chat_commands.gd` (`ChatCommands`). Any chat line that starts with
`/` is a command: the server replies to the sender alone with `s2c_system` and never
broadcasts the line. Commands: `/time` (alias `/clock`) answers
"It is Day 3, 14:05 (day). Dusk comes in about 9 minutes."; `/who` (aliases `/online`,
`/players`) lists online names, sorted, capped at 20 plus "and N more"; `/help` (also `/`,
`/?`) lists them; anything else says "Unknown command /x. Try /help." Added
`WorldClock.next_phase()` and `WorldClock.seconds_until_next_phase()` for the countdown.

**Why these calls.**
- Picked `/time` because it was the top unblocked backlog item: the `ack_seq` item above it
  needs a protocol bump and v2 already went out today, so it waits for tomorrow.
- No protocol change: `s2c_system` already existed and the client already shows it in chat.
  The client sends `/...` lines through `c2s_chat` unchanged, so it works with no client edit.
- Added `/who` and `/help` in the same small module because a single command with no help
  is undiscoverable, and `/who` is useful for the owner's playtests. Still one feature
  (chat commands), all pure functions.
- Commands share the normal chat cooldown (0.5 s) so they can't be used to spam the server.
  A dropped command gets no reply, same as dropped chat; the bot behaviour retries for that.
- The countdown is in real minutes, rounded, because that's what a player waiting for
  night (ember sap, later) actually wants to know.

**Tests.** 6 new unit tests in `tests/unit/test_gameplay_chat_commands.gd` (parsing, help,
unknown, /time at sunrise and noon, the phase countdown checked across a whole day including
the midnight wrap, /who sorting and cap). Bot behaviour
`tests/bot_test/behaviours/gameplay_chat_commands.gd`: after each login every bot sends
`/time` then `/who`, expects its own system-message answers (retrying past the cooldown),
and fails if any `/` line is ever broadcast as chat.

**Notes to next run.**
- Next: `ack_seq` in snapshots (protocol v3) on 2026-11-23 or later; client is waiting on it.
  Then resource node placement.
- If the client later wants local echo of the command or a different colour for command
  replies, that's a client change; the server side is done.
