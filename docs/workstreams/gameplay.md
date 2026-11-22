# Workstream: gameplay

Owns the rules of the world. See `docs/workstreams.md` for ownership.

## Backlog (top = next)
- [ ] Shared world clock: server owns time of day (one day = 40 real minutes), sends it at login and every minute; expose in `GameConfig`/`net.gd` for client and world
- [ ] Gathering: server-owned resource nodes (ash wood, pine wood, stone, ember sap) with respawn timers, placed deterministically
- [ ] Inventory: add-only migration for `inventory_items`, server-authoritative add/remove, sent to client
- [ ] Crafting: workbench at Spawn Meadow, 4 recipes (axe, pickaxe, torch, campfire)
- [ ] Wildlife AI on the server: wandering grazers that flee players

## Requests from other streams
- **From client:** include the last processed input `seq` for the receiving player in each snapshot (e.g. an extra `ack_seq` argument to `s2c_snapshot`, or a per-client field), so the client can do prediction and reconciliation for its own character. Until then the client only smooths. Needs a protocol bump, so batch it with another protocol change if you can.
