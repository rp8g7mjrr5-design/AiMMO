# Workstream: gameplay

Owns the rules of the world. See `docs/workstreams.md` for ownership.

## Backlog (top = next)
- [x] Shared world clock: `WorldClock`, `s2c_world_time`, protocol v2 (in review, PR #8)
- [ ] **Fix the clock bot behaviour to fit qa's hook.** qa's hook (PR #7) loads behaviours that extend `tests/bot_test/bot_behaviour.gd` and calls `setup` / `on_login` / `on_play` / `on_snapshot` / `on_finish`, and reports any other script as a failure. `gameplay_world_clock.gd` extends `RefCounted` with `setup(bot, net)` / `finish(...)`. Whichever of #7 and #8 merges second must port it, or the bot test goes red. Director's call: qa's interface is the standard; gameplay adapts.
- [ ] Acked input seq in snapshots (`ack_seq` for the receiving player) so client can predict your own character. Protocol v3: **not on 2026-11-22** (v2 already bumped today). Client is waiting on this.
- [ ] `/time` chat command that replies with `WorldClock.describe()` as a system message
- [ ] Resource nodes, data only: deterministic placement of ash, pine, stone and ember-sap nodes from the world seed in `game/shared/` (pure function, unit tested), so world can draw them and the server can own them from the same list
- [ ] Inventory: add-only migration for `inventory_items`, `CharacterData` defaults so old saves load, server-authoritative add/remove, `s2c_inventory` to the client, new fixture in `tests/fixtures/`
- [ ] Gathering: interact with a node in range, server checks distance and cooldown, grants items, node depletes and respawns on a timer; bot behaviour that gathers
- [ ] Ember sap is rarer and only seeps at night (uses `WorldClock`): the first system that makes day and night matter
- [ ] Crafting: workbench at Spawn Meadow, 4 recipes (axe, pickaxe, torch, campfire); tools speed up gathering
- [ ] Placed campfires: a crafted campfire can be set down, burns for a few world hours, other players see it (ties to Week 05 "torches keep danger away")
- [ ] Wildlife AI on the server: wandering grazers that flee players (Week 04)

## Requests from other streams
- **From client:** include the last processed input `seq` for the receiving player in each snapshot (`ack_seq`), so the client can predict its own character. Needs a protocol bump. *Director: scheduled as the third backlog item, not on the same day as v2.*
- **From world (day/night sky):** have the client call `DayNight.sync_to_server(...)` when server time arrives. *Director: answered by world switching to `WorldClock` and client doing the wiring; no gameplay work needed.*
