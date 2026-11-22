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

## 2026-11-22 (third run): resource node placement (data only)

**Built.** `game/shared/resource_nodes.gd` (`ResourceNodes`), the one list of gatherable
nodes: 397 of them (ash 142, pine 112, stone 112, ember_sap 31). Each node is
`{id, kind, pos, rot, scale}`; `id` is its index. Two passes from an rng seeded
`WORLD_SEED + 101`: a starter ring of 7 nodes (2 ash, 2 pine, 2 stone, 1 ember sap) 16 to
34 m from spawn, then the wild pass, where the land picks the kind (ash in lowlands below
6 m with a 12% chance of an ember-sap seep, pine on higher flat ground, stone on slopes over
1.0 or above 12 m). Rules: 6 m minimum spacing, dry ground only, nothing above 22 m, nothing
within 12 m of spawn, 6 m inside the border. `KINDS` holds what each gives (item, amount,
respawn seconds, `night_only` for ember sap). Lookups: `all`, `get_by_id` (safe for
client-sent ids), `near` (32 m grid index, nearest first, kind filter), `nearest`,
`in_range` (`GATHER_RANGE` 3 m, horizontal only), `fingerprint`, `describe`. Builds in about
15 ms, once, cached. The server logs `[server] resource nodes: ...` at startup so the bot
test exercises the code path on the server.

**Why these calls.**
- Top unblocked item: `ack_seq` still waits for tomorrow's protocol bump.
- A separate list instead of reusing `Props.scatter`: Props is world's decoration (1800
  trees and rocks, in `game/procgen/`), and the server shouldn't depend on procgen or own
  1800 states. Fewer, deliberate nodes are better gameplay too. Cost: a decorative tree can
  stand on top of a node until world reconciles; I asked world (their backlog) to skip
  scatter props within ~3 m of a node using `ResourceNodes.near`.
- Starter ring with every kind near spawn, because the design bible's cooperation pillar
  wants new players gathering side by side, and nobody should have to walk 100 m to try
  the first system. One ember-sap seep there so night matters at spawn too.
- Ids are permanent once gathering ships (inventory, quests and depletion state will refer
  to them). The unit test pins a fingerprint (`397-661be157...`); any change to placement,
  `Terrain`, or `WORLD_SEED` turns it red on purpose. New nodes must come from a new pass
  appended at the end.
- No database or protocol change. Depletion state will live in server memory (nodes reset
  on restart, which is fine for respawning resources).

**Tests.** 9 unit tests in `tests/unit/test_gameplay_resource_nodes.gd` (pinned
fingerprint, determinism, ids, targets reached, dry ground in bounds, spacing, starter
ring, `near` vs brute force, `nearest`/`in_range`). All 98 unit tests pass with Postgres.
Bot test (8 bots, 180 s, websocket, Postgres) PASSED; client smoke test passes. No bot
behaviour: there is nothing a player can do with nodes yet. The gathering PR adds one.

**Notes to next run.**
- Next: `ack_seq` in snapshots (protocol v3), allowed from 2026-11-23. Then inventory
  (migration + `CharacterData` defaults + fixture), then gathering, which will need a
  `s2c_nodes` state message (depleted ids) for the client and world to hide depleted nodes.
- If the fingerprint test ever fails on another platform (float formatting), switch the
  fingerprint to rounded integers in centimetres rather than loosening the test.

## 2026-11-22 (fourth run): inventory (the pack), no protocol change

**Built.** `game/shared/inventory.gd` (`Inventory`): a pack is a Dictionary of item id to
quantity. Four items (`ash_wood`, `pine_wood`, `stone`, `ember_sap`, matching
`ResourceNodes.KINDS[*].item`), stacks capped at 99 per id. Pure functions: `add` (caps,
refuses unknown ids and non-positive amounts, returns how many went in), `remove` (all or
nothing), `count`, `has`, `held`, `total`, `describe`, `normalize`. Migration
`0002_inventory_items.sql`: `inventory_items (character_id, item, qty >= 0, updated_at)`,
primary key `(character_id, item)`. `CharacterData.DEFAULTS.inventory = {}`, normalized
through `Inventory.normalize`. `PgStore` loads the rows into `ch.inventory` and upserts the
whole pack in one statement on every save; `JsonStore` keeps it inside the character.
`server.gd` has `give_item(peer, item, qty)` / `take_item(peer, item, qty)`, the only way
systems should change a pack. New chat command `/bag` (aliases `/pack`, `/inventory`,
`/inv`, `/i`). New fixture `tests/fixtures/week00_inventory.sql` with the
`-- schema-version: 0002` header qa asked for.

**Why these calls.**
- Top unblocked item: `ack_seq` still waits for tomorrow (protocol v2 went out today).
- No `s2c_inventory` yet. Adding an RPC to `net.gd` changes the RPC table, which is a
  protocol change, and the once-a-day limit is already spent. The client gets the pack in
  the login `character` Dictionary (adding a key is not a protocol change; old clients
  ignore it) and players see it through `/bag`. `s2c_inventory` should ride along with
  `ack_seq` in protocol v3, so it's one bump for both.
- Removed items stay in the Dictionary at 0 and are saved as `qty = 0` instead of the row
  being deleted. Hard rule 1 says never delete player data; this keeps the server free of
  DELETEs on player tables entirely, and the next save after a reload never needs to know
  which rows went stale.
- `normalize` keeps unknown item ids. If an item is ever retired from `ITEMS`, nobody's
  saved stack of it vanishes; it shows up by its id in `/bag` and stays in the database.
- Upsert the whole pack every save (one statement, at most a handful of rows) rather than
  tracking dirty items. Cheap at this size; revisit if packs grow to hundreds of ids.
- If loading inventory rows fails, the store returns `{}` for the character, so the login
  is refused instead of handing out an empty pack that could later be saved over the real one.
  (An upsert of an empty pack writes nothing anyway, but this keeps the failure loud.)
- Put the pack round-trip and fixture test in `test_gameplay_inventory.gd`, not
  `test_save_compat.gd`, because that file belongs to qa. qa's pending generic save-compat
  test (PR #29) also passes with the new fixture: I ran their file locally against this branch.

**Tests.** 9 unit tests in `tests/unit/test_gameplay_inventory.gd` (stacking and cap,
all-or-nothing remove, normalize repairs and keeps unknown ids, items match node kinds,
CharacterData defaults are never shared, `/bag`, JsonStore and PgStore round-trips, the
fixture loads with a qty-0 and an unknown item and round-trips). 121 unit tests pass with
Postgres. Bot test (8 bots, 180 s, websocket, Postgres) PASSED: new behaviour
`gameplay_inventory.gd` checks every login character has an `inventory` Dictionary and
that `/bag` answers (16 answers across 8 bots x 2 logins). Client smoke test passes.

**Known gaps.** Nothing gives items yet, so every live pack is empty until gathering ships.
`give_item` / `take_item` have no caller yet (they are thin wrappers over the unit-tested
`Inventory.add` / `remove`); the gathering PR calls them and exercises them in the bot test.

**Notes to next run.**
- Next (from 2026-11-23): protocol v3 = `ack_seq` in snapshots + `s2c_inventory(items)`
  sent after login and after every `give_item` / `take_item`. Then gathering
  (`c2s_gather`, `s2c_nodes`), which needs a protocol bump too: if v3 lands on the 23rd,
  either put `c2s_gather`/`s2c_nodes` into v3 as well or wait until the 24th.
