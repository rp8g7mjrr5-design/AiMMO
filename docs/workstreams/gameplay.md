# Workstream: gameplay

Owns the rules of the world. See `docs/workstreams.md` for ownership.

## Backlog (top = next)
- [ ] Shared world clock: server owns time of day (one day = 40 real minutes), sends it at login and every minute; expose in `GameConfig`/`net.gd` for client and world
- [ ] Gathering: server-owned resource nodes (ash wood, pine wood, stone, ember sap) with respawn timers, placed deterministically
- [ ] Inventory: add-only migration for `inventory_items`, server-authoritative add/remove, sent to client
- [ ] Crafting: workbench at Spawn Meadow, 4 recipes (axe, pickaxe, torch, campfire)
- [ ] Wildlife AI on the server: wandering grazers that flee players

## Requests from other streams
_(none yet)_
