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

## 2026-11-22 (fifth run): gathering, server side, through `/gather`

**Built.** `game/shared/gathering.gd` (`Gathering`), pure functions over one world state
`{taken: {id: n}, respawn_at: {id: t}}`. `check` returns why a node can't be gathered
("unknown", "far", "depleted", "day", "cooldown") or "". Wood and stone nodes give
`KINDS.amount` per gather, 3 times (`CHARGES`), then respawn after `KINDS.respawn`; an
ember-sap seep gives once and only at night (`WorldClock.is_night`). `pick_target` picks the
nearest gatherable node within `GATHER_RANGE` of the player (optionally one kind), `take` /
`give_back` change the state, `hint` names the nearest live node with a compass direction
(north = -Z, east = +X, the same as client's compass in PR #33). `server.gd` gets
`gather(peer, kind_word)`, using the server's own copy of the position and `give_item`. New
chat command `/gather` (aliases `/g`, `/harvest`, `/chop`, `/mine`; `/gather pine`,
`/gather rock`, `/gather sap`). `/help` lists it, and the empty `/bag` now tells players to
use it.

**Why these calls.**
- `ack_seq` (protocol v3) is still not allowed today (v2 shipped today, and it is 15:00
  Chicago on the 22nd). Gathering was next, but its backlog shape needs `c2s_gather` and
  `s2c_nodes`, both protocol changes. Rather than ship nothing, I split it: the rules and
  the server state now, playable through chat like `/bag`; the RPCs ride in v3. Players can
  fill their pack today, which also makes the inventory PR mean something.
- `ChatCommands.run` stays pure; `/gather` changes world state, so the server intercepts it
  (`ChatCommands.is_gather`) before `run`. The command name/argument parsing helpers live
  in `ChatCommands`, the rules in `Gathering`.
- 3 charges per wood/stone node instead of depleting on the first gather: the starter ring
  has only 6 wood/stone nodes and every new player starts there. Ember sap stays one-shot,
  rare and at night, as the design bible wants.
- Depletion state is in server memory and resets on restart (as planned in the resource
  nodes run). Nothing new in the database; items go through the existing pack and save.
- A full pack calls `give_back`, so a node is never spent on nothing.
- Cooldown 1.5 s per player on top of the 0.5 s chat cooldown, so a macro can't strip the
  starter ring in a second.
- Left the depleted look alone: world's `NodeProps.set_depleted` needs node state on the
  client, which needs `s2c_nodes` (v3). Until then a spent tree still looks whole, and
  `/gather` there says "This pine is spent; it comes back in about 3 minutes" plus a hint.

**Tests.** 9 unit tests in `tests/unit/test_gameplay_gathering.gd` (charges, depletion and
respawn timing, every refusal, night-only sap, target picking, give_back, hint skips spent
nodes, compass names, kind parsing and `/gather` aliases, reply lines). All unit tests pass
with Postgres. New bot behaviour `gameplay_gathering.gd`: after each login every bot walks
to a wood/stone node within 60 m of spawn (shuffled list, moves on if a node is spent),
types `/gather`, needs "You gather ...", and on the second login checks the pack still holds
at least what the server reported, so gathered items are proven saved. Bot test (8 bots,
180 s, websocket, Postgres) PASSED, every bot gathered twice. Client smoke test passes.

**Known gaps.** No visual feedback beyond the chat line until v3. Bots never test ember sap
(the bot test runs at any hour); the unit tests cover it. If 8+ bots ever share fewer nodes
the behaviour can fail on contention: then raise `SEARCH_RADIUS`, not lower the bar.

**Notes to next run.**
- From 2026-11-23: protocol v3 = `ack_seq` + `s2c_inventory` + `c2s_gather(node_id)` +
  `s2c_nodes`. `c2s_gather` should call the same `Gathering.check` with that id (validate
  it: `get_by_id` is safe). For `s2c_nodes`, run `Gathering.respawn_due` in the server tick
  (every second is plenty) and broadcast what changed.
- Crafting can start the same way (`/craft`) if v3 is not done yet.

**CI fix (same run).** The first CI run failed: CI also runs a 45 s ENet bot test, where a
login lasts only ~15 s, and two bots spent it on a 12 s start delay plus a walk to a random
node up to 60 m away. The behaviour now starts 3 s after login and goes for the nodes
nearest where the bot stands (starting one of the 4 nearest in, so bots spread out). Locally
the 45 s ENet test passed 3 times in a row with every bot gathering on both logins, and the
180 s websocket test passed too. Lesson for next time: run the 45 s ENet bot test as well,
not just the 3-minute one.

## 2026-11-22 (sixth run): crafting through `/craft`, tools that help gathering

**Built.** `game/shared/crafting.gd` (`Crafting`): the workbench at `WORKBENCH_XZ` (x 3,
z -2, 3.6 m from the spawn point, inside the empty meadow centre, no node within 4 m), use
range `BENCH_RANGE` 6 m, and four recipes: stone axe (3 ash wood, 2 stone), stone pickaxe
(3 pine wood, 3 stone), torches (1 pine wood + 1 ember sap -> 3, anywhere), campfire (2 ash,
2 pine, 4 stone). `check` returns "unknown", "owned", "bench", "missing" or "full"; replies
name exactly what is missing and where the bench is. `Inventory.ITEMS` gains the four
products. `Gathering` gains `TOOLS`, `tool_for`, `amount_for` (+1 per gather with the right
tool) and `cooldown_for` (x0.5); `check` takes the player's cooldown as an optional last
argument, so old callers are unchanged. `server.gd` gets `craft(peer, word)`: check, then
`take_item` per ingredient, then `give_item`, with rollback if a step ever fails. Chat:
`/craft` (aliases `/make`, `/build`; `/recipes` lists), and `/help` mentions it.

**Why these calls.**
- Protocol v3 (the owner-requested real gathering) is still blocked today: v2 shipped
  today and it is 16:30 Chicago on the 22nd. Crafting was the next unblocked item and fits
  without a protocol change, the same way `/gather` did.
- No migration: products are ordinary item ids in `inventory_items`. Old saves load as
  before (nothing in them changes); unknown-id handling in `Inventory.normalize` already
  keeps anything future versions retire.
- Tools never wear out and you can only hold one of each: durability is a grind tax with no
  fun at this stage (pillar 1), and "you need one axe" keeps the pack readable. Revisit if
  the economy needs a sink.
- Tools give +1 item and half the cooldown rather than only "speed": through chat, a 1.5 s
  cooldown barely shows, but a bigger haul does. `TOOL_SPEED` is the hook for v3's timed
  gather channel.
- The torch needs ember sap (night-only), so torches are a night activity, which fits the
  Week 05 "torches keep danger away" plan. It is the only recipe without the bench.
- Ingredient costs are first guesses sized against the starter ring (6 wood/stone nodes,
  3 charges x 2 items): one axe is about 2 tree gathers + 1 rock gather.
- The workbench has no visible prop yet; request filed in world's backlog. Until then the
  refusal tells players the distance and compass direction to it, and new players arrive
  in range anyway.

**Tests.** `tests/unit/test_gameplay_crafting.gd`, 8 tests: recipes well-formed and in
`Inventory`, bench placement (dry, clear, spawn in reach), word parsing, every refusal in
order, reply text, the take/give bookkeeping, tool effects on amount/cooldown/check, and
`/craft` routing. Bot behaviour `gameplay_crafting.gd`: after each login the bot holds
still, needs the recipe list from `/craft`, then `/craft axe` must be judged by the server's
own position (sent to the bench when far, pack-checked when near; positions within 1 m of
the edge are skipped).
Results: 153 unit tests pass with Postgres. Bot test 8 bots x 180 s websocket + Postgres
PASSED (every bot listed recipes twice, 15 clear axe checks, 0 skipped); 8 bots x 45 s ENet
PASSED. Client smoke test passes. The first 180 s run had the bench at x 4, z -3, exactly
5 m from spawn, which sits on the 1 m "too close to call" edge, so first logins were
skipped; moved it to x 3, z -2 (3.6 m) so a new player is clearly in reach.

**Gotcha.** A static function named `is_tool` on a `class_name` script collides with
`Script.is_tool()`: the call parses as the built-in with 0 arguments. Renamed to
`makes_tool`.

**Known gaps.** Bots never actually complete a craft (they can't afford one in a bot-test
login); the unit tests prove the bookkeeping, and the server glue is a thin loop over
`take_item`/`give_item`. Campfires and torches do nothing yet: placing campfires is the next
backlog item after v3.

**Change in the same run (owner direction: chat is for talking).** After the PR opened, the
coordinator passed on the owner's standing rule (PR #40): no gameplay through chat, new
systems UI-first. So `/craft` is now a hidden debug/bot command: dropped from `HELP` (the
unit test now asserts it is *not* listed), the recipe list no longer says "type /craft", and
the changelog fragment no longer tells players to type anything. The rules and the server's
`craft()` stay: they are exactly what `c2s_craft(recipe_id)` will call. Asked client for the
workbench window and added `c2s_craft` to the backlog for v3/v4. Until the `--dev-commands`
gate lands (separate backlog item), the hidden command still works on the live server.

**Notes to next run.**
- 2026-11-23: protocol v3 first (director's top item). Try to fit `c2s_craft` +
  `s2c_craft_result` into the same bump. Scale the gather channel by
  `Gathering.TOOL_SPEED` when `tool_for` finds a tool, and send `s2c_inventory` after
  crafts too.

## 2026-11-22 (seventh run, 18:00 Chicago): the timed gather channel, without a protocol bump

**Why not protocol v3 now.** The director scheduled the v3 bump for 2026-11-23, and the
"one bump per day" rule. It is 00:00 UTC on the 23rd but 18:00 on the 22nd in Chicago, and
v2 merged at 05:36 Chicago on the 22nd. The budget week and the previous run both count days
in America/Chicago (the owner's day), so a v3 PR opened now would most likely merge on the
same Chicago day as v2 and make the owner re-download twice in one day. I held the bump and
built everything v3 needs that is not protocol, so the v3 run is only wiring.

**Built.** `game/shared/gather_channel.gd` (`GatherChannel`): `SECONDS` per kind (ash and
pine 2.0 s, stone 2.4 s, ember sap 1.6 s), `seconds_for` scales by `Gathering.TOOL_SPEED`
when a tool helps, `start` / `cancel_reason` ("moved" past 0.5 m flat, or "far") / `is_due`
/ `progress` / `finish_check` (re-runs `Gathering.check` at the end without the cooldown).
`server.gd`: `gather_start(id, node_id)` returns `{ok, reason, seconds}` with the same checks
as `/gather` plus "busy" and "full" (a full stack never starts); `gather_cancel(id, reason)`
uses no charge and no cooldown; `_tick_channels` runs every server tick after movement;
`_finish_channel` takes the charge and fills the pack, or ends "depleted"/"day"/"full" with
nothing spent; `_gather_event(id, event, node_id, info)` is the one place v3 swaps for
broadcasts (today it sends the gatherer a system line). The instant `/gather` is refused
("Easy; you're still gathering.") while a channel runs, so press-E can't double-dip. A
disconnect cancels quietly. Hidden dev command `/channel [kind]` / `/channel stop` (not in
`HELP`, not in patch notes).

**Testable server.** `server.gd` got `now_seconds()` with a `test_now` override and, when
`net` is null, `_send` records into `test_outbox`. So the unit tests drive the real server
functions with a fake clock instead of copying their logic. Use this for v3's tests too.

**Tests.** `tests/unit/test_gameplay_gather_channel.gd`, 8 tests: durations and tools,
channel rules, start then complete (nothing until the end, one charge, busy, instant
`/gather` refused, cooldown after), cancel by moving (no charge, no cooldown, can restart),
cancel on request and on disconnect (nothing sent), contested node (three finish and empty
a pine, the fourth gets nothing and is told it is spent), start refusals, `/channel`
routing. 187 unit tests pass with Postgres. Bot behaviour `gameplay_gather_channel.gd`: after
the bot's first `/gather` it walks to a node, starts a channel and walks off (must cancel,
must not pay), then goes back and holds still (must pay at the end, never cancel). Two 8 x
180 s websocket runs with the final behaviour passed: 13 and 10 cancels, 11 and 8 completed
gathers across the 8 bots; a bot or two per run found every nearby node spent and gave up,
which the behaviour allows.

**What didn't work.** First version of the behaviour stood at the node the first gather
used; the client's gather prompt behaviour "holds E" whenever a bot stands still, so it had
drained that node and its refusals were misread as ours. Now the bot walks to the nearest
node and treats any refusal as "try the next node". Then the 45 s ENet run went red twice in
six ("never gathered anything", 5 spent): bots standing still for this behaviour let the
prompt drain the few nodes near spawn that other bots still needed. The behaviour now runs
only when `bot.duration >= 120` (CI's 180 s run); with that, 45 s ENet passed 3/3 and main
passed 4/4 before my change. Note for qa: gathering bots are close to starving in the 180 s
run too (one bot saw 12 spent nodes before its one gather); more bots or behaviours that
stand still will tip it. Consider a bot-test clock offset or a few extra charges via a
server test flag.

**Notes to next run (v3, after 00:00 Chicago on 2026-11-23).**
- Put the new RPCs on a child node (`Net/Play`) per qa's note, or names that sort after every
  existing RPC; `tests/protocol/net_v2.gd` already exists.
- `c2s_gather_start(node_id)` -> `gather_start`; on refusal send the gatherer a refusal line
  (or an `s2c_gather_end(..., reason)`). `c2s_gather_cancel()` -> `gather_cancel(id, "stopped")`.
- Rewrite `_gather_event`: "begin"/"cancelled"/"done" -> `s2c_gather_begin`/`s2c_gather_end` to
  everyone within view; "done" also `s2c_gather_result` + `s2c_inventory`; when
  `info.depleted`, `s2c_node_state(node_id, true)`; `Gathering.respawn_due` results ->
  `s2c_node_state(id, false)` (call it once a second in `_process`).
- Switch the bot behaviour from `/channel` to the RPCs; keep `/channel` as a dev command.

## 2026-11-22 (eighth run, 20:00 Chicago / 02:00 UTC on the 23rd): v3 messages, server side, still no bump

**Why not protocol v3 yet (again).** The run started at 02:02 UTC on 2026-11-23, which is
20:02 on 2026-11-22 in Chicago. v2 merged on the 22nd (Chicago), so the "one bump per day"
rule, counted in the owner's day like the budget week, still says no. Same call as the
seventh run. Next gameplay run after 00:00 Chicago (06:00 UTC) on the 23rd does the bump.

**Built: every v3 message is produced by the server now; the bump only adds RPCs.**
- `_send` looks up the RPC on `Net` or on any child of `Net` (`_rpc_node`). A message the
  running protocol has no RPC for is skipped and logged once ("... is not in protocol v2 yet;
  not sent"), so old clients never get an unknown RPC. **For v3:** add `Net/Play` (a child
  node with the new `@rpc` methods, created in `net.gd`'s `_ready`, per qa's sorted-name note)
  and the server starts sending them with no server change.
- `_gather_event` now sends `s2c_gather_begin(peer, node, seconds)` and
  `s2c_gather_end(peer, node, "done" | reason)` to `players_in_view(pos)`
  (`GameConfig.VIEW_RANGE` = 120 m flat, a guess at a comfortable sight line; tune when
  client fog is final), `s2c_gather_result(item, count)` to the gatherer, and still the
  system line. A disconnecting gatherer's end goes to the others only.
- `gather_request(id, node_id)` is the `c2s_gather_start` handler (refusal: private
  `s2c_gather_end` with the reason + a system line). `c2s_gather_cancel` should call
  `gather_cancel(id, "stopped")`.
- `_respawn_nodes(now)` replaces every direct `Gathering.respawn_due` call and runs once a
  second from `_process`, so each respawn is announced exactly once:
  `_node_changed(node, depleted)` sends `s2c_node_state` to everyone online (not just in
  view: emptied nodes are route-planning info). Both gather paths call it on depletion.
- `give_item`/`take_item` set `inv_dirty`; `_flush_inventories()` at the end of every tick
  sends one `s2c_inventory(Inventory.to_wire(inv))` per changed pack (a craft = one message).
- `_send_world_state(id)` at login: `s2c_inventory` and `s2c_nodes(depleted_ids)`.
- `craft_request(id, recipe_id)` is the `c2s_craft` handler: exact ids only
  (`Crafting.is_recipe`), answers `s2c_craft_result(recipe_id, ok, text)`. `craft()` (dev
  command) now wraps the same `_craft` core.
- Fixed the fixture comment qa asked for (`week00_characters.sql` names
  `test_qa_save_compat.gd`).

**Tests.** `tests/unit/test_gameplay_v3_hooks.gd`, 9 tests (audience, begin/done, cancel
and disconnect, private refusal, depleted/respawned once + login state, instant gather
coalescing, craft_request, RPC routing and skipping, wire inventory). 212 unit tests pass
with Postgres. No bot behaviour: nothing new reaches a client before v3, and the existing
gather/channel/craft behaviours exercise every changed path. Bot test 8 x 180 s websocket:
see PR.

**Not done, and why.** qa's watchdog log-noise request: `tests/ops/run_watchdog_test.py`
looks for "peer N connected" in the log, so dropping that line would break qa's test.
Left as is; if qa still wants it, they can switch the test to a different marker first.

**Notes to next run (v3, after 06:00 UTC on 2026-11-23).**
- `net.gd`: add `Play` child with `c2s_gather_start(node_id)`, `c2s_gather_cancel()`,
  `c2s_craft(recipe_id)`, `s2c_gather_begin`, `s2c_gather_end`, `s2c_gather_result`,
  `s2c_inventory`, `s2c_nodes`, `s2c_node_state`, `s2c_craft_result`, plus signals; add
  `ack_seq` to snapshots (`s.seq`, e.g. a per-recipient `s2c_snapshot` arg; changing an
  existing RPC's args is fine since v2 clients are refused at login anyway, but check qa's
  protocol test). Bump `PROTOCOL_VERSION` to 3. Wire the c2s signals to `gather_request`,
  `gather_cancel(id, "stopped")`, `craft_request`.
- Switch `gameplay_gather_channel.gd` from `/channel` to the RPCs (new `gameplay_gather_v3.gd`).

## 2026-11-22 (ninth run, 21:00 Chicago / 03:00 UTC on the 23rd): fix the flaky bot tests, still no bump

**Why not protocol v3 yet (third time).** 21:02 in Chicago, still the 22nd, the day v2
merged. Same "one bump per day, in the owner's day" call as the seventh and eighth runs. The
next gameplay run after 00:00 Chicago (06:00 UTC) does the bump; everything server side is
already waiting for it (see the eighth run's notes, unchanged).

**What I did instead: the integrator's red-main request (bugs first).** Two flakes, both
seen on docs-only pushes, so they were test-harness races, not regressions:

1. `gameplay_chat_commands: no reply to /time after 4 tries` (and `/who`). Cause: every
   command behaviour (the client gather prompt presses `/gather` every 1.6 s while a bot
   stands still, `/channel` retries every 1.2 s, `/craft`, `/bag`) and bot.gd's chatter
   shared one 0.5 s cooldown, and `_on_chat` dropped a line inside it silently. A retry
   every 3 s can land in someone else's window four times running.
   Fix, server side (`server.gd` `_on_chat`): talk and slash commands now have separate
   cooldown stamps (`last_chat`, `last_command`), so chatter never eats a command; and a
   dropped line gets `ChatCommands.TOO_FAST` ("Slow down a moment: that line wasn't sent.
   Try again.") to the sender, at most once per cooldown window (`last_too_fast`) so
   spamming can't make the server spam back. This is a real player fix too: a typed line
   that vanished without a word, or a press of E that swallowed a sentence, both felt broken.
   `_on_chat` now uses `now_seconds()` so it is unit testable with `test_now`.
   Fix, bot side: `gameplay_chat_commands` and `gameplay_inventory` resend 0.6 to 0.9 s after
   a TOO_FAST and refund the try (capped at 12 refunds so a stuck cooldown still fails).
2. `gameplay_gather_channel: walked away but the gather still paid out`. Not a server race:
   behaviours run in file-name order each frame and the last one to set `bot.move` wins.
   `gameplay_gathering` runs after `gameplay_gather_channel`. The channel behaviour started on
   *any* "You gather" line, including the client gather prompt's, while `gameplay_gathering`
   was still active and steering the bot to its own node (or holding it still there), so
   the "walk away" never happened and the server, correctly, paid out. Now the channel
   behaviour waits until `gameplay_gathering._active` is false after a good gather (falls
   back to the old trigger if that behaviour isn't loaded). The server's cancel logic was
   fine: `_tick` moves players before `_tick_channels`, and the unit tests cover it.

**Tests.** New `tests/unit/test_gameplay_chat_cooldown.gd` (4 tests: talk refused out loud,
separate buckets, one notice per window, blank lines ignored). 225 unit tests pass with
Postgres. Bot test 8 x 180 s websocket passed twice locally (every bot answered /time and
/who on both logins; every bot completed at least one timed gather and cancelled at least one
by walking away), 8 x 45 s ENet passed.

**Not done.** qa's watchdog log-noise request is still parked (see eighth run).

**Notes to next run (v3).** Unchanged from the eighth run, plus: the bot behaviours that
parse system lines ignore TOO_FAST already; keep it that way in `gameplay_gather_v3.gd`.

## 2026-11-22 (tenth run, 22:20 Chicago / 04:20 UTC on the 23rd): protocol v3

**The bump and the date.** The last three runs held v3 for "one bump per day in the
owner's day" (Chicago). This run starts at 22:20 Chicago on the 22nd, so the same rule says
the PR must not land before 00:00 Chicago. Built and tested the whole bump now and opened the
PR only after midnight Chicago (I scheduled a wake for it), so the rule holds and no run is wasted.

**What shipped.**
- `game/shared/net_play.gd`: the `Net/Play` child that `net.gd` makes in `_ready`, with every
  v3 RPC (`c2s_gather_start`, `c2s_gather_cancel`, `c2s_craft`, `s2c_gather_begin`,
  `s2c_gather_end`, `s2c_gather_result`, `s2c_inventory`, `s2c_nodes`, `s2c_node_state`,
  `s2c_craft_result`). Each re-emits a signal declared on `Net`, so callers use `net.<signal>`.
  Net's own RPC list is byte-for-byte v2's, so v1/v2 clients still reach the login check and
  get "out of date" (qa's protocol test; my unit test also compares against `net_v2.gd`).
- `ack_seq`: third argument of `s2c_snapshot`, per recipient (the session's last applied
  `seq`, -1 before any input). I did not change the `snapshot` signal (client.gd and bot.gd
  connect it with two arguments; changing it would have broken another stream's file).
  Instead `Net` emits `snapshot_ack(ack_seq)` first and keeps `last_ack_seq`.
- Server: `_on_gather_start` / `_on_gather_cancel` / `_on_craft` (logged-in only) call the
  prepared `gather_request`, `gather_cancel(id, "stopped")`, `craft_request`.
- **Bug found while writing the bot behaviour:** `s2c_gather_end` went to `players_in_view`
  at the *end*, so a watcher who walked out of view during someone's 2 s gather got the
  begin and never the end: their client would show that player chopping forever. The
  channel now remembers its begin audience and the end goes to them plus anyone in view.
- `/gather` dropped from `/help` (still works, hidden); the empty-pack line says "press E".
- `PROTOCOL_VERSION` 3. No `tests/protocol/net_v3.gd` needed for this bump (v2 copy exists).

**Tests.** `tests/unit/test_gameplay_protocol_v3.gd` (8 tests: RPCs on Play not Net, every
RPC reaches its signal and the ack comes before the snapshot, press E / let go / re-press with
no cooldown, handlers ignore peers not logged in, bad node ids refused out loud, Make button,
per-player ack in snapshots, the walk-off watcher). The routing test in
`test_gameplay_v3_hooks.gd` now checks Play is found after `_ready`. New bot behaviour
`gameplay_gather_v3.gd` replaces `gameplay_gather_channel.gd` (`/channel` is no longer used by
any bot): login state arrives, ack_seq never ahead of our inputs or going back, walk away ->
"moved", `c2s_gather_cancel` -> "stopped", hold -> "done" + result + bigger pack, and every
other bot's begin we see must be followed by its end.

Results: 245 unit tests pass with Postgres; protocol test passes on websocket and ENet (v1,
v2 and protocol-2/4 clients told to update, current client logs in); watchdog test passes;
bot test 8 x 180 s websocket PASSED (every bot: 6-7 starts, 2 walk-offs, 2 cancels, 2
completions, ~40 other bots' gathers seen begin and end, ~3550 acks); 8 x 45 s ENet PASSED;
client smoke test passed.

**What didn't work first.** The first 180 s run failed: 7 of 8 bots never started a timed
gather. `client_gather_prompt.gd` (today's client, still on `/gather`) "holds E" whenever
`bot.move` is zero, and its instant gather every 1.6 s kept the 1.5 s gather cooldown busy,
so every `c2s_gather_start` was refused "cooldown" (retries landed in lock-step with the
prompt). A real player's E press is one or the other, never both, so the behaviour now
"stands still" with a 1 mm/s drift (`STILL`) that the prompt doesn't count as holding E;
about 1 cm over a gather, well inside the 0.5 m tolerance. Once the client's press-E sends
`c2s_gather_start` this goes away; `refusal_reasons` is a stat now so it's visible.

**Not done.** Gather/craft system lines still go out next to the RPCs, because today's client
reads them; drop them for v3 clients once the client switches (backlog follow-up). qa's
watchdog log-noise request is still parked (eighth run). The chat-command gate (owner
direction 1) still waits for the client's press-E to send `c2s_gather_start`.

**Notes to next run.** Next protocol bump (v4: facing yaw + `s2c_roster`) must copy today's
`net.gd` to `tests/protocol/net_v3.gd` *and* note that `net_play.gd` is part of v3 too: the
qa compat test only reads `net.gd`, so if v4 adds RPCs to `Play`, v3 clients' Play numbering
shifts. That's harmless for login (Net is unchanged) since v3 clients are refused anyway, but
put new v4 RPCs on Play freely; never on Net.

**Follow-up in the same run (CI on PR #75 went red).** After merging `main` (qa's fun
metrics, PR #64), CI failed on `rewards_per_min_median got 34% worse: 2.75 vs baseline 4.15`.
Cause: my behaviour's 1 mm/s drift stopped the client prompt from "holding E", and its
walk-away/cancel checks pay nothing, so bots earned less. The real lesson was in the game,
though: timed gathers still checked the instant gather's 1.5 s cooldown, so a player who kept
pressing E would sit through a dead 1.5 s after every 2 s bar. Design call: **a timed gather
has no cooldown; the server-timed bar is the pacing** (`gather_start` passes cooldown 0; one
at a time still, "busy"). The instant `/gather` dev command keeps its cooldown. The bot
behaviour now stands truly still (no drift needed any more) and, after its three checks,
keeps pressing E for up to 4 more gathers per login like a player working a node.
Bot test 8 x 180 s websocket with fun check: PASSED, rewards/min median 9.55 (baseline
4.15), first reward 8.5 s, longest wait 0.12 s. 8 x 45 s ENet PASSED, 286 unit tests pass.
Worth raising the fun baseline once this is on main (qa's file, so it's their call).

## 2026-11-23 (eleventh run, ~09:00 Chicago): skills and XP, server side (Milestone 1, part 1)

**Picked.** No open gameplay PR; budget 10/40 this week. Top unblocked backlog item for the
current milestone: skills data and XP, server side, no bump. (The chat-command gate still
waits for the client's press-E to send `c2s_gather_start`, client PR #83 is not on `main`;
facing yaw and the skills messages need protocol v4.) **What a player feels:** every gather
and craft now moves them toward a level, and each level-up is cheered in chat with what it
gives and what comes next, a minute into their first session.

**Who does skills best, and how ours improves (owner direction 6).** The classic long-road
skill MMOs (the one everyone thinks of, with its 99s and capes) are the benchmark: players
love that every action ticks XP, that a skill is a long personal goal, and that a max skill
is a badge. They hate: an exponential curve where the last few levels are half the total
(so "level 92 is half way"), long middle stretches with no unlock, and that the best XP is
often alone and AFK. Ours: our own polynomial curve (`150*L^1.1 + 0.15*L^3`, rounded to 5;
no doubling every few levels, level 50 is ~10% of the road, not ~1%), every level a felt gain
(gathers 0.3% quicker per level, 30% at 100), a named unlock every few levels with the next
one always named in the level-up line, and a 25% "better together" bonus instead of
rewarding standing alone. Levels aren't stored, only XP, so the curve can be retuned without
touching anyone's save.

**Built.**
- `game/shared/skills.gd` (`Skills`): the four skills (ids permanent), `KIND_SKILL`,
  `GATHER_XP` (wood 10, stone 12, sap 30), Toolcraft XP 8 per ingredient used, the curve
  (`xp_step`, `xp_for_level` cached, `level_for` by binary search, `xp_to_next`, `progress`),
  `gain()` (returns gained/xp/level_before/level/unlocks reached), `UNLOCKS` (Felling and
  Quarrying: 5 tier-2 node *soon*, 10 and 25 +1 yield; Tapping 5 and 15 +1 sap; Toolcraft 3 and
  5 recipes *soon*), `yield_bonus`, `speed_factor`, `normalize` (keeps unknown skill ids,
  like the pack keeps retired items), `level_up_text`, `describe`.
- `GatherChannel.seconds_for(kind, inv, level)` and `Gathering.amount_for(kind, inv, level)`
  take the skill level (default 1 = unchanged, so every older test and caller is identical).
- Migration `0003_character_skills.sql` (character_id, skill, xp BIGINT >= 0). `CharacterData`
  gets `skills: {}` (normalized by `Skills.normalize`, not `Inventory.normalize`, which would
  have capped XP at the stack size; there's a test for that). `PgStore` loads skills with the
  pack (a failed query returns {} like the pack does) and upserts them with
  `GREATEST(old, new)`, so a stale save can never lower XP. JsonStore needed no change.
- Server: `award_xp(id, skill, amount)` is the only way XP changes; called after every
  completed timed gather, instant `/gather`, and successful craft. `has_company(id)` gives
  the bonus. A level-up queues a system line that `_send_queued_lines` sends right after
  the reply it came with (gather line, craft reply / `s2c_craft_result`), and
  `_flush_inventories` flushes anything left at the end of the tick. Level-up lines start
  with the skill name, never "You", so no behaviour or client parser takes them for a
  gather or craft reply. Hidden `/skills` dev command (not in HELP).
- Fixture `week01_skills.sql` (schema 0003, a 0-XP skill and an unknown one); the week 00
  characters load with no XP (checked).

**Tests.** `tests/unit/test_gameplay_skills.gd`: curve monotonic and capped; the time targets
under a pace model (channel time plus 6 s walk per node, ignoring the speed gains): level 2
bare-handed ~60 s, level 5 ~11 min bare / less with an axe, level 10 with an axe ~45 min,
level 50 ~20 days and level 100 ~200 days at 2 h a day; gains and unlocks; speed and yield;
normalize and old characters; text; server pays XP for timed, instant gathers and crafts,
nothing for a cancelled gather or a refused craft; the level-up line follows the gather line
and the next gather is quicker; company bonus on and off; both stores keep XP; a stale save
never lowers it; the fixture loads. Bot behaviour `gameplay_skills.gd`: login character has
`skills`, XP never drops (within a login or across a reconnect), our paid-out gathers show up
as XP, level-up lines name a real skill and agree with `/skills`.

**Notes to next run.** v4 (part 2) only needs to send what `award_xp` already returns. Keep
the level-up system line for v3 clients. Tier-2 nodes (part 3) should check
`skill_level(id, skill)` in `gather_start`/`gather` before `Gathering.check`.

**Results.** 316 unit tests pass with Postgres (save-compat runs the new fixture through
0003). Bot test 8 x 180 s websocket PASSED: every bot answered /skills 3-4 times, XP
survived each reconnect, 5 of 8 bots reached a level 2 inside the run (110-189 XP each),
rewards/min median 9.65, first reward 6.9 s. Client smoke test passed.

## 2026-11-23 (twelfth run, ~10:00 Chicago): protocol v4, skills reach the client (Milestone 1, part 2)

**Picked.** No open gameplay PR; budget 11/40. The chat-command gate (second item) is still
blocked, but now only by the craft window: press-E sends `c2s_gather_start` since client PR
#83, while `craft_window.gd` still sends `/bag` and `/craft <id>`, so turning commands off
would break crafting for players. Request filed in client's backlog. Next was facing yaw
(owner direction 2) and the v4 skills messages (current milestone). **Call: v4 carries only
the skills messages.** `c2s_input` already carries a yaw; making movement camera-relative
is a movement-rules change that needs the client in step, and the skills messages are what
three other streams are waiting on now (client's banner and skills window, world's
`LevelUpFx` from #79). Facing yaw and `s2c_roster` go in v5, with no daily limit any more.
**What a player feels:** nothing yet on its own; it unblocks the "+10 Felling" pop next to
the haul toast, the level-up banner naming the unlock, and the burst over a friend who levels
next to you.

**Built.**
- `Net/Play`: `s2c_skills(skills)`, `s2c_xp(skill, gained, total_xp)`,
  `s2c_level_up(skill, level, unlocks)`, `s2c_level_up_seen(peer_id, skill, level)`; Net
  signals `skills_changed`, `xp_gained`, `level_up`, `level_up_seen`. Net's own RPC list is
  untouched (v1-v3 clients still get "out of date").
- `PROTOCOL_VERSION` 4. Frozen `tests/protocol/net_v3.gd` and `net_play_v3.gd` (the frozen
  net preloads the frozen Play; the only line that differs from the shipped file).
- Server: `_send_world_state` sends `s2c_skills(skills_wire(...))` (all four, 0 for untouched,
  unknown ids stay in the save but aren't sent). `award_xp` now queues `[to, method, args]`
  instead of bare lines: `s2c_xp`, then on a level-up `s2c_level_up` (unlocks as the table's
  dicts), `s2c_level_up_seen` to everyone else in view, then the old system line.
  `_send_queued_lines` sends them right after the gather/craft reply, so the order a client
  sees is result -> gather line -> xp -> level_up -> level-up line.
- The level-up system line stays for now: today's client only shows chat. Follow-up in the
  backlog to drop it once the banner exists.

**Tests.** `tests/unit/test_gameplay_protocol_v4.gd` (9): RPC placement and frozen copies,
re-emit on Net, login sends every skill, XP after the haul, nothing for a cancel, level-up to
the player and the burst to watchers only (not yourself, not out of view), the Felling 5
unlock in the payload, Toolcraft XP after a craft and none after a refused one, and the
**message contract** (backlog follow-up from the duplicate v3 run): a full scenario
(world state, clock, reject, chat and a command, gather to depletion, cancel by moving, bad
node, crafts ok/refused/unknown, respawn, snapshot) and every message it produced has an RPC
on Net or Play with the same argument count. The v3 test now checks the frozen v3 Play
instead of today's. Bot behaviour `gameplay_skills_v4.gd` (passive): one `s2c_skills` per
login matching the login character and never below the last total, every `s2c_xp` adds up
exactly, every `s2c_level_up` matches the level of the running total and the unlock table,
`s2c_level_up_seen` never about ourselves, every paid-out gather has gathering XP.

**Results.** 342 unit tests pass with Postgres. Protocol test passes on websocket and ENet
(v1, v2, v3 clients and protocol 3/5 told to update, current client logs in). Bot test
8 x 180 s websocket with fun check PASSED (8-12 `s2c_xp` per bot, totals consistent across
the reconnect), 8 x 45 s ENet PASSED, client smoke test passed.

**What didn't go to plan.** No bot levelled up in either 180 s run (59-146 XP per bot,
split between Felling and Quarrying, so no skill reached the 150 for level 2; a second run
alone on the machine was the same, so it isn't CPU contention: today's behaviours spread
their gathers over both kinds, and the last run's 5-of-8 level-ups were the lucky side). The level-up path is covered by the unit
tests over the same server code; the behaviour checks it whenever a bot does level.
Next run could give the bot test a reliable level-up, e.g. a fixture character near level 2
that one bot logs in as (`tests/fixtures/` is ours; the bot launcher is qa's).

**Notes to next run.** v5 = facing yaw (server sets facing from the camera heading,
camera-relative W/A/S/D, clamp/validate) + `s2c_roster`; freeze `net_v4.gd` and
`net_play_v4.gd`, put new RPCs on Play, never Net. If yaw changes `c2s_input`'s arguments,
that's on Net: arguments don't shift numbering, but run the protocol test anyway.

## 2026-11-23 (run after v4): PR #89 red on a flaky gathering bot check, fixed

**What broke.** #89's CI passed the 180 s websocket bot test but failed the 45 s ENet one:
`bot_7: [gameplay_gathering] never gathered anything (tried 5 nodes, 3 spent)`. Not caused by
v4: the identical failure (same bot, same counts) hit world's #79 run at 06:44, because the
test world clock and spawns are deterministic. bot_7 walked 187 m (twice the others): it
spawns far from the nodes, the other bots had already emptied nodes 1 and 5, and in a ~15 s
login it kept walking to nodes the server had already told it were spent.

**Fix (my own behaviour, `tests/bot_test/behaviours/gameplay_gathering.gd`).** The bot now
listens to `nodes_depleted` / `node_state`, skips nodes it knows are empty, picks each next
node nearest-from-where-it-stands (not nearest-from-login), and drops a target that empties
while it is still walking. The first node of a login is still one of the nearest four so
bots spread out. Merged `main` into the branch (no conflicts) rather than rebasing.

**Results.** 366 unit tests pass with Postgres. Five 45 s ENet runs passed, and after the fix
every bot showed `spent_seen=0` (before: up to 3). Full 8 x 180 s websocket run with
`--fun-check` and the client smoke test: both passed (bot test PASSED in 233 s).

**Note to next run.** No new item this run: diagnosing the flake and the full test cycle
filled it, and a small item started on top would have been rushed. Next run: if #89 has
landed, take the top gameplay backlog item from `main` (tier-2 nodes need `skill_level` in
`gather_start`/`gather`, see the part 1 notes).

## 2026-11-23 (run after #89): bots level up in the bot test, no false "never gathered", flood guard

**Why it's more fun.** Mostly plumbing for fun: qa can now time "first level-up" on every
bot-test run (the moment the skills milestone is about), so a change that makes levelling
slower shows up red instead of silently. The flood guard keeps a busy grove smooth for the
players standing in it.

**Picked.** The two qa requests on my bot behaviour (requests first), plus the small
flood-guard item. #89 had landed, so nothing of mine was open. Not tier-2 nodes this run:
two requests plus a full test cycle filled it, and tier-2 wants a fresh run.

**Built.**
- `tests/bot_test/behaviours/gameplay_gather_v3.gd`: works one skill (Felling: 27 ash/pine
  nodes within 80 m of spawn vs 5 stone), keeps pressing E after the three checks until
  Felling 2 (`LEVEL_GOAL`), tracks empty nodes from `s2c_nodes`/`s2c_node_state` and
  "depleted" refusals, picks the nearest live node from where it stands, widens the search
  40/80/120/160 m and then waits 5 s for a respawn instead of giving up (`MAX_NODES` 40 per
  login). "Never started a single timed gather" now fails only if a node refused for a reason
  other than "depleted". Found on the way: `WAIT_FIRST` waited for
  `gameplay_gathering._phase_gathered`, which stays false when that behaviour runs out of
  nodes, so the bot sat idle all login; it now goes once gameplay_gathering lets go (or after
  30 s). New stats: `levelled`, `focus_level`, `waited_respawn`.
- `server.gd`: `PLAY_REQUEST_GAP` (0.1 s) per player and kind for `c2s_gather_start` and
  `c2s_craft` via `_play_allowed`; floods are dropped silently. Ported from the duplicate-v3
  patch by hand. Three v3 tests that sent a second request in the same instant now step the
  test clock by the gap (+0.01 s: 100.0 + 0.1 - 100.0 is just under 0.1 in floats).

**Results.** 383 unit tests pass with Postgres. Bot test 8 x 180 s websocket with
`--fun-check` PASSED: **8 of 8 bots levelled up**, median 32.7 s of gathering to the first
level (qa's limit 90 s), worst 39.9 s, 109 s wall clock median; every bot `gave_up=0`.
8 x 45 s ENet PASSED. Client smoke passed.

**Notes to next run.** Take Milestone 1 part 3 (tier-2 nodes gated by level). The bot now
reaches Felling 2 only; a live check of the level gate needs a fixture character already
near level 5 (follow-up in the backlog). If a real client ever double-sends a start inside
100 ms it gets no answer for the second; client's prompt waits for begin/end, so fine today.

## 2026-11-23, PR #98 fix run (merge main, XP-bar race in CI)
- PR #98 was red and conflicted. Conflict: the director rewrote `docs/workstreams/gameplay.md` on main; I took main's version and re-applied this PR's ticks (flood guard, both qa requests).
- Red CI: `client_xp_meter` failed on 3 of 8 bots with "bar landed at 0.000, server progress is 0.6". Cause: bot.gd freezes a bot for 1.5 s before its mid-run disconnect and doesn't call `on_play` then; a gather already running finishes in that freeze and pays XP; after the reconnect `client_xp_meter.on_login` clears the meter but keeps `_pending`, so its next check reads an empty bar. Main rarely hit it because bots used to gather in short bursts; this PR keeps them pressing E until Felling 2, so a gain right before the disconnect became likely.
- The real fix is one line in client's behaviour (reset `_pending` in `on_login`); that file isn't ours, so I filed the request in `docs/workstreams/client.md` and worked around it: `gameplay_gather_v3` doesn't start a gather within `QUIET_BEFORE_DISCONNECT` (5 s) of `bot.disconnect_at`. `/gather`, crafting and qa's ledger can still hit the race rarely until client fixes it.
- Tests (local, Postgres): 397 unit tests pass; bot test 8 x 180 s websocket `--fun-check` PASSED, 8 of 8 levelled, median 35.7 s gathered to first level; client smoke passed.
- Next run: no new item this run (stopped after the fix to keep it small; PR #98 is still the one landing). Top unblocked item is Milestone 1 part 3 (tier-2 nodes gated by level).

## 2026-11-23 (run after #98 landed): tier-2 nodes gated by level (Milestone 1, part 3)

**Fun, in one sentence:** at Felling 5 or Quarrying 5 the level-up banner now points at something real, a big glowing tree or seam a short jog from spawn that pays double XP and a new material, and before then trying one tells you exactly how far you have to go.

**Built.**
- `ResourceNodes`: pass 3 `_place_tier2` on its own rng (`WORLD_SEED + 211`), appended after the wild pass, so ids 0-396 are untouched (`fingerprint(397)` still pins the old hash; the whole list is pinned as 405). Eight slots around the meadow (old ash, seam, alternating), 48-55 m out on dry ground, ash only on fairly level ground, 8 m from any other node (world asked for about 4 m; the old ash is 3 m in radius). Scale 0.95-1.05 (world's request). Every node now carries `tier`, `skill`, `min_level`; `ResourceNodes.info(node)` merges `TIER2[kind]` over `KINDS[kind]` (label, item, amount, respawn, charges, `seconds_scale`). `tier2()` lists them.
- `Gathering.check(..., skills)` returns `"level"` first after `"unknown"`, before `"far"`: the answer to "can I work that?" doesn't depend on where you stand, and it let the bot probe the gate without walking 50 m (which would have fought the other behaviours for the bot's legs). `can_work`, `required_level`, `level_text` ("Needs Felling 5. You're Felling 3."), `node_charges`, `amount_at`; `pick_target` and `hint` take skills too and the hint never sends a level-1 player to a node they can't work. `GatherChannel.seconds_at` / `finish_check(..., skills)`.
- Numbers: XP per gather 2x (`Skills.TIER_XP_SCALE`; old ash 20, seam 24), bar 1.2x as long, so about 1.7x the XP per second; 4 charges, 300 s / 360 s respawn. This folds in the parked "retune GATHER_XP" follow-up. Felling 5 / Quarrying 5 unlocks are no longer "coming soon".
- Server: `skills_of(id)`, passed to every check and refusal; per-node amount, bar time and tier XP in `/gather`, `gather_start` and `_finish_channel`.
- Items `ember_heartwood` and `veinstone` live in `Inventory.NEW_ITEMS` (is_item and label know them; normalize already kept any id). **Why not `ITEMS`:** world's `test_world_item_icons` requires every `ITEMS` entry to have an icon, and icons are world's. World draws them, next gameplay run moves them (backlog follow-up).
- Bots: `gameplay_gather_v3` asks for the nearest tier-2 node once per login before its first real node and expects `level` plus a "Needs ..." system line; it and `gameplay_gathering` never pick tier-2 nodes they can't work.

**Outside our paths (said in the PR):** two world unit tests assumed every node is tier 1 and went red on the real ring: `test_world_closeup` called `solid_columns(kind, scale)` without the tier (one argument added), and `test_world_node_props` allowed parts 1.6 m x scale from the node (tier 2 now 3.2 m; the old ash crown is at 1.82 m). The first bot test then failed the same way in two world bot behaviours: `world_closeup` wants exactly 7/6 detail parts per ash/stone (tier 2 has 10; now "at least tier 1's" for tier 2) and `world_resource_nodes` wants parts within 2.0 m (tier 2 now 3.2 m x scale). Smallest possible edits, written into world's requests so it can check them. The alternative was shipping nothing, since the tier field is what world asked for.

**Not ours, still red:** `main` is red on `test_qa_art_lint` (node_props.gd has 15 colour literals, allowance 11) since world's #100 and qa's #95 landed together. This PR's CI will be red on that one test until world or qa fixes main; auto-merge waits, then lands it. I did not touch either file.

**Bot test, first run:** besides the two world checks above, the gate worked on every bot (`gate_refused` 2 and `gate_lines` 2 per bot, one per login), 7 of 8 bots levelled (median 33.7 s gathered to first level).

**Tests.** Unit: `test_gameplay_tier2.gd` (8 tests: ring placement and ids, info, the gate and its words, pick/hint, payouts, server refusal and payout end to end). All unit tests pass locally except the art lint above. Bot test, second run (8 x 180 s websocket, Postgres, `--fun-check`): PASSED, 8 of 8 levelled, median 33.7 s gathered to first level. Client smoke passed; its render note says night primitives are 624k against the art bible's 600k target (a note, not a failure; eight extra props add a little, world owns the budget).

**Next run:** if world has drawn the icons, move the two items into `ITEMS`. Otherwise part 4 (Toolcraft unlocks: ember-hardened axe/pickaxe from heartwood and veinstone) is unblocked now that the materials exist.

## 2026-11-23 (run after #104 landed): Toolcraft unlocks, the ember axe and pickaxe (Milestone 1, part 4)

**Fun, in one sentence:** Toolcraft 5 now hands you something you hold, an ember axe or pickaxe made from your old stone one, and the very next gather's bar is about a third shorter and pays one more item, so the upgrade is felt at once.

**Owner direction 6 (take the best, beat it), short.** The skill MMOs whose tool tiers players love tie each tier to a gathering level and make the new tool visibly faster; players hate tool upgrades that are pure stat sheets (no felt change), tools that break and must be re-bought, and tiers that need a skill they never trained. Ours: tools never wear out, the upgrade turns your current tool into the better one (no pack clutter, no going back), each needs only the one gathering skill it serves (heartwood from Felling 5 for the axe, veinstone from Quarrying 5 for the pickaxe) plus Toolcraft 5, and the gain is on the bar you watch every gather.

**Built.**
- `Crafting.RECIPES`: `ember_axe` (1 ember sap, 4 ember heartwood, 1 stone axe) and `ember_pickaxe` (1 ember sap, 4 veinstone, 1 stone pickaxe), at the bench, `level: ["toolcraft", 5]`, `upgrades: <stone tool>`. `required`, `level_ok`, `owned_tool` (carrying the ember tool makes the stone one "owned"), `level_text`, `article` ("an ember axe"). `check(inv, id, pos, skills = null)`: "level" comes right after "unknown" and is checked only when skills are passed. **Why null skips it:** the client's `CraftWindow.row` calls `check` without skills and qa/client tests require the row and server to agree for the same call; skipping keeps that true and the server always passes skills. Client asked to pass them.
- `Gathering.TOOLS` is now kind -> tools best first; `TOOL_POWER` per tool, `tool_speed` / `tool_extra`; ember 0.35x bar and cooldown, +2 items (stone 0.5x, +1). `GatherChannel.seconds_for` uses `tool_speed`. Tier-2 nodes get the same.
- `Skills.UNLOCKS.toolcraft[5]` is real now (no "coming soon"); Toolcraft 3 stays "soon".
- Server `_craft` passes `skills_of(id)` to check and refusal. No protocol change, no migration (items are new rows in `inventory_items`).
- Items: `ember_heartwood` and `veinstone` moved into `ITEMS` / `ITEM_ORDER` (world drew them in #108); `NEW_ITEMS` is empty. The ember tools wait in a new `Inventory.UNDRAWN` (fallback bundle icon) because world's `test_world_item_icons` requires everything in `ITEMS` and `NEW_ITEMS` to have its own icon. Request filed with world.
- Bot behaviour `gameplay_toolcraft.gd`: once per login `/craft ember axe` must be refused with "An ember axe needs Toolcraft 5. You're Toolcraft N." (N < 5). Unit tests `test_gameplay_toolcraft.gd` (7 tests: items, level gate and words, upgrade/owned, faster and richer gathers incl. tier 2, server refusal and the full craft with XP).

**Known.** Toolcraft 5 is ~1,700 XP, which is about 27 campfires: a long grind next to Felling 5's ~10 minutes. Left as is (long road), follow-up in the backlog. The workbench window grows to six rows; client may need to make it taller.

**Tests (local, Postgres).** 435 unit tests pass. Bot test 8 x 180 s websocket `--fun-check` PASSED: 8 of 8 levelled (median 38.7 s gathered to first level), `gameplay_toolcraft` refusals=2 per bot (one per login), 11/11 characters persisted. Client smoke passed (same 624k night primitives note as last run, world's).

**Next run:** the chat gate ("chat is for talking") is unblocked on the client side (#101 merged), but the bot test needs `--dev-commands` passed by qa's runner/CI first, or `/gather`/`/craft` bots break. Suggestion for that run: read the switch with `CliArgs.setting(args, "dev-commands", "AIMMO_DEV_COMMANDS", ...)` so qa can turn it on from the environment before the gate goes live. Else: the first-session pace check.

## 2026-11-23 (afternoon): chat is for talking (owner direction 1)

**Fun, in one sentence.** A player who types "/help" or "/bag" out of MMO habit gets one friendly pointer to the F1 controls instead of a wall of commands, and the chat feed stays people talking, never other players' debug lines.

**Built.** `ChatCommands.NOT_FOR_CHAT` ("Chat is for talking. Press F1 for controls.") and `ChatCommands.dev_commands_on(args, env)` returning `[on, why]`; `Server.dev_commands` (set in `start()`, logged as `[server] dev commands: on|off (why)`). In `_on_chat`, after the command cooldown, a "/" line on a server with dev commands off gets only that hint: nothing runs, nothing is broadcast, no node or item changes. Talk is untouched (a "/" mid-line is still talk). Spamming slashes still earns one `TOO_FAST`, not a hint per line. Retired the `/channel` dev command (`ChatCommands.is_channel`, `CHANNEL_NAMES`, `Server._channel_command`): nothing used it since press-E moved to `c2s_gather_start`.

**The call I made, and why.** The flag decides first (`--dev-commands`, `--dev-commands=0`), then `AIMMO_DEV_COMMANDS`. With neither, commands are **off when any Railway variable is set** (`RAILWAY_ENVIRONMENT`, `_NAME`, `_ID`, `RAILWAY_PROJECT_ID`, `RAILWAY_SERVICE_ID`, `RAILWAY_DEPLOYMENT_ID`; Railway injects these on every deploy) and **on everywhere else**. The backlog asked for "only with `--dev-commands`", but the bot-test runner and CI (qa's files) don't pass the flag yet, and four bot behaviours still need `/gather`, `/bag`, `/craft`, `/time`, `/who`. Gating strictly today would turn `main` red; waiting for qa first leaves players with the command dump another day. Railway is the only server players reach, so this ships the player-facing rule now and keeps CI green. If Railway's variables were ever missing, the live server would simply behave as before (commands on) and the start-up log line says so; the integrator can confirm "dev commands: off (public server (...))" in the Railway log. Follow-up in the backlog: once qa passes the flag explicitly, make the default plain "off".

**Tests.** `test_gameplay_chat_gate.gd` (6 tests: every command off gets one hint to the sender, no broadcast, no other message, no item or node change, no gather started; talk still flows; cooldown still collapses spam; dev mode answers `/time`; the hint names F1 and no slash; the switch's precedence incl. Railway). The command tests in `test_gameplay_chat_cooldown.gd` and `test_gameplay_protocol_v4.gd` now set `dev_commands = true` themselves. `/channel`'s test replaced by one that checks it is gone.
No new bot behaviour: the bot-test server keeps dev commands on (it has to, for the bots), so a bot can't see the gate; qa's "chat is for talking, in CI" item adds the no-flag server check, and I filed how to start it (`AIMMO_DEV_COMMANDS=0`) in qa's requests.

**Local results (Postgres).** Unit: 453 of 454 pass; the one failure, `test_client_skills_window::test_goal_skips_unlocks_not_in_the_world_yet`, is already red on `main` (`bb48678`): my Toolcraft PR (#110) made Toolcraft 5 a real unlock while the skills window's test (#109, merged minutes apart) assumed it was still "soon". Client's open PR #111 already rewrites that test to find soon unlocks from the data, so I left client's file alone; this PR's CI goes green once #111 is on `main` and main is merged in. Bot test 8 x 180 s websocket `--fun-check` PASSED: 8 of 8 levelled (median 35.7 s gathered to first level), 11/11 characters persisted. Client smoke not run: no file the client loads changed (only a comment in `gather_channel.gd`).

**Next run:** if this PR's CI is red only on the skills-window test, merge `main` in once #111 has landed and push. Then the first-session pace check, or facing yaw + `s2c_roster` (protocol v5).

## 2026-11-23: first-session pace check, and a full pack no longer stops levelling

**Picked.** The backlog's top item, facing yaw, turned out to be half done already: `c2s_input(seq, move, yaw)` has carried the camera yaw since v1 and `_on_input` wraps and validates it. What's left is a v5 bump for `s2c_roster` and `c2s_unstuck`, which needs client work to be any fun, so I took the next item, Milestone 1's first-session pace check, and noted the yaw finding on the item. Fun in one sentence: the first ten minutes of a new character always end on Felling 5 (the old ember ash), and nothing on the way stops the bar from filling.

**Built.** `tests/unit/test_gameplay_first_session_pace.gd` drives the real server (fake clock, `gather_start` + `_tick_channels`, real nodes and respawns): a fresh character walks at `WALK_SPEED` to the nearest tier-1 ash or pine with a charge left, presses E (0.3 s reaction per press) until it is spent, then walks to the next one. Results: bare-handed Felling 2 at 47.4 s and Felling 5 at 569.5 s (168 gathers, 1.1 km walked); with a stone axe 32.6 s and 401.7 s. The roadmap's "90 s / about 10 min" holds, so `CURVE_A`/`CURVE_P` are unchanged. Bare-handed gets 60 s of slack over 10 min ("about"); with an axe it must be inside 10 min.

**What it found.** The first run never reached Felling 5: at ~98 gathers both wood stacks hit `Inventory.MAX_STACK` (99) and every gather was refused "full", around Felling 4. A real player who only chops hits the same wall. Two fixes considered:
- Raise `MAX_STACK` to 999: the right long-term call, but qa's `test_qa_save_compat` pins `changed_pack({99, 99}).pine_wood == MAX_STACK`, which only holds at 99/100, and that file is qa's. Request filed in qa's backlog; follow-up added to ours.
- **Shipped:** a timed gather on a full stack still runs, uses its charge and pays the XP, with no items, no `s2c_gather_result`, and the line "Your pack can't hold any more ash wood. You leave it, but the work still counts." (`Gathering.full_text`). The charge is used so a full pack can't farm XP off one node without walking. `gather_start` no longer refuses "full"; `_finish_channel` no longer gives the charge back. The instant `/gather` dev command keeps the old refusal (bots only). Client asked to toast that line.

**Tests.** New: the pace file (3 tests, includes a check that the run actually fills a wood stack, so the rule stays covered), `test_a_full_stack_still_teaches` in the gather-channel tests (replaces the "full stack never starts" check). `gameplay_gather_v3` bot behaviour no longer fails "done but no s2c_gather_result" when its stack is full. No new bot behaviour: a bot can't fill 99 of one item in 3 minutes; the unit test covers it through the real server functions. Local (Postgres): unit 467/467 pass; bot test 8 x 180 s websocket PASSED, 8 of 8 levelled (median first level-up 38.7 s of gathering); client smoke passed.

**Next run.** If qa has loosened the save-compat check, raise `MAX_STACK` to 999. Otherwise the v5 bump (`s2c_roster`, `c2s_unstuck`), or the Quarrying/Tapping pace runs.

## 2026-11-23: protocol v5, the players roster and Return to Spawn Meadow (`ws/gameplay/protocol-v5-roster-unstuck`)

**Fun, in one sentence:** a player who wanders off, gets lost in the ridges or wedged on a rock is one button press from the meadow and the bench, and the players panel can show who is online and how far along they are, live, without anyone typing `/who`.

**Built.** Protocol 4 to 5, three RPCs on `Net/Play` (Net's own list untouched, so v1 to v4 clients are still told to update; the live protocol test confirms it for every frozen copy):
- `s2c_roster(entries)`: `[{id, name, level}]`, sorted by name case-insensitively, `level` = sum of the four skill levels (`Server.total_level`). `_roster_dirty` is set on login, logout and any level-up (in `award_xp`), and `_flush_roster` sends it once per tick, so eight bots logging in together cost eight rosters, not 36.
- `c2s_unstuck()` / `s2c_unstuck_result(ok, text, wait_seconds)`: `Server.unstuck_request` puts you on a 3 m arc south of spawn (`unstuck_spot`, spread by peer id, clear of the workbench at (3, -2)), cancels a running gather as "moved", zeroes the held move, and starts `GameConfig.UNSTUCK_COOLDOWN` (60 s). Within `UNSTUCK_NEAR` (12 m) of spawn it says "You're already in Spawn Meadow." and keeps the cooldown free. Rate-limited like the other play requests (`_play_allowed`).
- Frozen `tests/protocol/net_v4.gd` + `net_play_v4.gd`. `test_gameplay_protocol_v4` now checks the frozen v4 Play instead of today's, and its message-contract scenario covers the two new server messages.

**Facing yaw (the backlog item's first half) needed no bump.** `c2s_input(seq, move, yaw)` has carried a yaw since v1; client's action camera already sends the camera heading while moving and the server takes it (finite, wrapped to ±PI) as the avatar's facing in every snapshot. I wrote that into the backlog tick rather than inventing a second field. If someone wants a turn-rate clamp later, it goes in `_on_input`.

**Tests.** `test_gameplay_protocol_v5.gd` (10 tests: RPC lists, re-emits, roster order and levels, once per tick, level-up and disconnect refresh, unstuck ok/cooldown/near/gather cancel/spots/logged-out). Bot behaviour `gameplay_roster_v5.gd`: a roster listing us after every login, sorted, unique, levels >= 4; one unstuck a second after the first login (expects "already"), one in the last 5 s of the second play phase while not gathering (expects ok and a snapshot within 3 m of spawn). I put the second ask at the very end on purpose: earlier, a teleport would cut into gather_v3's, the ledger pair's and crafting's position-dependent checks and make CI flaky.

**Local results (Postgres).** Unit 487/487. Bot test 8 x 180 s websocket PASSED, 11/11 characters persisted (the teleported final positions included), 8 of 8 bots levelled, every bot: roster of 8, unstuck_already=1, unstuck_home=1. Protocol test PASSED on websocket and enet (v1 to v4 clients told to update). Client smoke PASSED (net.gd/net_play.gd are loaded by the client).

**Next run:** if #118 or this PR is red, fix that first. Then the level-up system line for v4+ clients (client's banner has landed), or the chat-gate default ("off unless --dev-commands") now that qa's bot test passes the flag.

**2026-11-23, later run: #118 brought up to date.** #118 had a merge conflict (backlog and devlog lines from v5 and Emberlight landing alongside). Merged `main` in, kept both sides' entries, dropped the now-done facing-yaw item. `main` itself was red twice over: `test_qa_fun_metrics` (my roster behaviour called `c2s_unstuck.rpc_id` directly; the integrator's #125 switches it to `bot.send_play`), and once that is fixed, `--fun-check` fails because the unstuck answer isn't counted as feedback by qa's metrics (`longest_wait_s_median` 5 s vs 0.05, every bot, seen on #125's own CI). I took #125's exact one-line change (so merging #125 later is a no-op) and made `gameplay_roster_v5.gd` report `s2c_unstuck_result` to the fun metrics itself (`_tell_fun_metrics`), because `qa_fun_metrics.gd` is qa's file; request filed with qa to hook `net.unstuck_result` there, after which I drop the helper. Lesson for next time: any new `s2c_` answer to a `send_play` press needs to count as fun-metric feedback, or the wait metric reads it as silence.

## 2026-11-23: ember tools take their place in the pack (`ws/gameplay/ember-tools-in-pack`)

**Fun, in one sentence:** the ember axe you ground to Toolcraft 5 for lands next to your stone tools with its own icon, where you'd look for it, instead of trailing after the campfires as if the game didn't know it.

**Picked.** The top item (first-session pace) is #118, still landing. The level-up line follow-up turned out to need nothing from the server: client's `LevelUpBanner.consume_system` already swallows the line, and bots plus qa's echo matching still use it, so I noted that and left it. Next was the Toolcraft follow-up: world drew `ember_axe` / `ember_pickaxe` in #112, so both move from `Inventory.UNDRAWN` into `ITEMS` and `ITEM_ORDER` after `stone_pickaxe`. Before this, `Inventory.held()` put them in the "unknown extras" tail, so the pack window and `s2c_inventory` listed them after the campfire. Ids unchanged, so saved packs load the same. `UNDRAWN` stays as an empty const (two tests and the next undrawn item use it).

**Bot-test flake found and fixed (my v5 behaviour).** One local run failed `gameplay_gather_v3`: "gather ended moved while standing still at (124, 2.7, 31)". The roster behaviour's last-seconds "Return to Spawn Meadow" crossed a gather start on the wire (it only checks `gather_begun`, which hadn't arrived), and the teleport ended that gather "moved". Now the roster behaviour stamps `bot.set_meta("unstuck_at", ...)` when it asks and gather_v3 treats a "moved"/"far" end within 3 s of it as the unstuck working and stops testing (it's the bot's last 5 s anyway). Both behaviour files are identical in this PR and #118, so whichever lands first the other merges cleanly.

**Also carried:** the same `gameplay_roster_v5.gd` fix as #118 (send_play, and its answer counts as fun-metric feedback), because `main` is red without it.

**Tests (Postgres, local).** Unit 504/504 (new `test_ember_tools_sit_with_the_stone_tools`: in ITEMS and order, icons drawn, `held()` and `to_wire()` order, old ids still load). Bot test 8 x 180 s websocket `--fun-check` PASSED (wait median 0.1 s). Client smoke PASSED (the icon shelf and pack window read `ITEM_ORDER`). No new bot behaviour: nobody reaches Toolcraft 5 in 3 minutes, and nothing new is pressed.

**Next run:** if #118 or this PR is red, fix it first. Then the chat-gate default ("off unless `--dev-commands`"): qa's bot test passes the flag now, but `tests/client_smoke/run.sh` and `tests/protocol/run_protocol_test.py` start servers without it, so check neither types a slash command before flipping it.

## 2026-11-23 (evening): health and stamina rules, Milestone 2 build-ahead (`ws/gameplay/vitals-rules`)

**Fun, in one sentence:** nothing a player feels today; it unblocks next week's first fight with a stamina bar that never locks you out (a last-gasp dodge always goes out, the bar is back in ~2.5 s, sprinting outside a fight is free) and health that comes back on its own so you are gathering again within seconds of a fight.

**First, #128.** It had a merge conflict (the devlog tail and one line of `gameplay_roster_v5.gd`, both from #118 landing), so CI never ran on it. Merged `main` in, kept both devlog entries and the `unstuck_at` stamp, unit 518/518, pushed; auto-merge was already on.

**Picked.** Walked the backlog top-down. Ember tools: #128. Toolcraft 3 "Bench sense": I built it (an `ember_lantern`, 3 ash, 3 pine, 2 stone, 1 sap, Toolcraft 3, a per-recipe `xp_scale` 1.5 so it pays 108 XP, about 12 lanterns from 3 to 5 instead of ~20 campfires, and a real wood sink), and its own tests passed, but it broke three tests in other streams' files: client's `test_client_pack_window` (pins `used_in("stone")` exactly), client's `test_client_skills_window` (once Bench sense isn't "soon", Toolcraft 3 at 475 XP becomes a fresh player's goal ahead of Felling 5, which is a real design question for client), and world's `test_world_item_icons` (fails for any undrawn id in `Inventory.UNDRAWN`). I can't edit those, so I parked it with requests to client and world and a follow-up with the numbers. The level-up line and the v3 gather echo lines turned out to be already handled client-side (`LevelUpBanner.consume_system`, `GatherPrompt.is_echo`), so dropping them server-side is only bandwidth; left as is. Workbench greying is client's. That made the Milestone 2 build-ahead the top unblocked item.

**Take the best, then beat it (owner direction 6).** Stamina-driven action combat is best today in the soulslikes and in the action MMO the owner named as the reference feel: one bar shared by dodge, heavy attacks and block makes every move a decision, and dodge-rolling through a readable telegraph is the moment players love. What their players hate: running dry and being locked out (no dodge, a guard break that stuns you mid-fight), long regen pauses that feel like dead time, stamina drain on plain travel, and slow out-of-combat health that sends you to sit and wait. Ours keeps the one-bar decision and fixes those: any stamina left buys one last-gasp dodge; hitting 0 only makes you "winded" for a fixed 1 s while the bar is already refilling (0.6 s delay, 40/s); a block that runs the bar dry still holds for that hit and leaves you winded, the fair warning that the next won't; sprint costs nothing outside combat; health regenerates 10%/s once 6 s have passed with no hit taken or dealt. Input lag and telegraphs are the client's and the creature AI's half; these rules are deliberately cheap to evaluate per tick so the server can answer within one tick.

**Built.** `game/shared/vitals.gd` (`Vitals`): pure functions over `{hp, max_hp, stamina, max_stamina, spent_at, hit_at, winded_until}`: `full`, `check`, `spend` (light 8, heavy 22, dodge 25, sprint 12/s in combat), `hit` (block 75% for 0.8 stamina per point), `dealt`, `tick`, `shares`. Nothing calls it yet; not saved, not sent: no migration, no protocol change. Wiring is a backlog follow-up.

**Tests.** `test_gameplay_vitals.gd` (9 tests). No bot behaviour: there is nothing a player or bot can do with it until it is wired. Unit 526/526 locally; bot test below.

**Next run:** if #128 or this PR is red, fix it first. Check whether client and world answered the Bench sense requests; if so, the lantern goes in (the design is in the backlog follow-up). Otherwise wire `Vitals` into the session and tick (no bump), or the chat-gate default.

## 2026-11-23 evening: every gathering skill's first level is paced (pace-every-skill)

**Picked.** Bench sense (`ember_lantern`) is still waiting on client and world. qa answered the stack-cap request, but client's `test_client_pack_window` still hard-codes "12 of 99" and a 99 "(full)" stack, so raising `MAX_STACK` would turn CI red from a file gameplay doesn't own; request filed in `docs/workstreams/client.md`. `Vitals` wiring would change nothing a player can see until client sends sprint/dodge. So this run took the next item that guards fun directly: the roadmap's "first level within 90 s" promise for Quarrying and Tapping, not only Felling. Fun in one sentence: a player who heads for the rocks or the sap first gets the same early level-up a woodcutter does, and the test keeps it that way.

**Built.** `test_gameplay_first_session_pace.gd`: `_play` / `_next_tree` take the node kinds and the skill, `_midnight(srv)` sets `clock_offset` so the world clock reads midnight (the fake `test_now` doesn't move it; ~8 real minutes of night are left, far more than the run). New tests: `test_quarrying_first_session`, `test_quarrying_with_a_stone_pickaxe` (level 5 within 10 min too), `test_tapping_first_night`. Numbers: Quarrying bare-handed level 2 at 55.6 s (level 5 at 9.7 min), pickaxe 40.1 s (6.7 min); Tapping at night level 2 at 60.4 s after 8 seeps and a lot of walking (1 charge each). Curve unchanged: nothing failed.

Also dropped `gameplay_roster_v5._tell_fun_metrics` (qa's `qa_fun_metrics` hears `net.unstuck_result` itself now).

**Didn't do.** Tapping level 5 isn't checked: sap is night-only with 10-minute respawns, so it is meant to be a slow, special skill. If players find Tapping 2 -> 3 too sparse, give seeps 2 charges rather than more XP.

**Next run:** if client fixed `test_client_pack_window`, raise `MAX_STACK` to 999 (flip the pace test's "fills a wood stack" check: at 999 Felling 5 never fills one; cover the full-stack rule from `test_gameplay_gather_channel` instead). Otherwise the lantern if client and world answered, else `Vitals` wiring or the chat-gate default.
