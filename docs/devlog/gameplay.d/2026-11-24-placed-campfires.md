# Placed campfires, server side (ws/gameplay/placed-campfires)

**Fun:** the first thing you make that stays in the world, and the first place the Gloam
won't follow you at night. Today it is server-only (dev commands); it becomes playable when
the bump, world's model and client's place key land.

## What I built
- `game/shared/campfires.gd` (`Campfires`): pure rules over `{fires, next_id}`. Placed
  `PLACE_DISTANCE` 1.5 m in front (forward is (sin yaw, cos yaw), as in `Gloam.summon`) on the
  ground; refused (with player-facing lines in `REFUSALS`) on water, near the world's edge, within
  3 m of another fire, 2.5 m of a resource node or the bench, past 3 per player (owner is the
  lower-case character name so it survives a reconnect) or 32 in the world. Burns
  `BURN_WORLD_HOURS` 4 (400 real seconds, about a third of a night). `to_wire` gives
  `[id, x, y, z, seconds_left]` per fire; `near`/`is_warm` (`WARM_RADIUS` 4 m, inside the 6 m
  keepaway) are ready for cooking.
- Server: `campfires` state (reset with the world), `place_request(id, item)` (only "campfire";
  takes one from the pack only on success; what `c2s_place` will run), `_tick_campfires` every
  tick (burned-out fires leave, the owner gets "Your campfire has burned down to ash."),
  `_broadcast_campfires` on every change and the list in `_send_world_state` when any burn.
  `gloam_fires()` now returns every lit fire, so the walkers' keepaway (already unit tested in
  `Gloam`) works for real.
- Hidden dev commands: `/place campfire` (from the pack) and `/kindle` (free, rules apply),
  `/kindle status`.

## Calls I made
- **No flag.** The item asked for a flag or invisibility on the live world. Placing needs either
  a dev command (off on Railway) or an RPC that doesn't exist until the bump, so players can't
  place fires at all yet; a `--campfires` flag would guard nothing. `s2c_campfires` is skipped
  by `_send` until the RPC exists (logged once: "not in protocol v7 yet").
- **Not saved yet.** Saving needs an add-only table, and #197 holds migration 0004 while in
  review; `test_migrations` wants sequential numbers, so a 0005 now would fail until #197 lands
  and a 0004 would collide with it. A fire burns under seven real minutes, so a restart costs at
  most one campfire. Follow-up filed for the migration after 0004.
- **Refuse rather than put out the oldest** at the per-player cap: a crafted campfire is 8
  materials, and silently burning one out would feel like a loss.

## Tests
- `test_gameplay_campfires.gd`, 11 tests: numbers hold together (burn time, warm radius inside
  the keepaway), set down in front on the ground, every refusal and that it changes nothing,
  per-player and world caps, burning down, the wire format, chat command names, the pack path
  (no item, one taken, refusal free, only campfires), burn-down tells the owner and everyone,
  newcomers get the list, the dev commands (and none on a player server), and the walker that
  comes at you across your fire stops at the ring's edge and never grabs.
- Bot behaviour `gameplay_campfires.gd` (bot *_5, once, 20 s into its first login, borrowing
  itself between gathers): `/place campfire` must be refused "no campfire", `/kindle` must catch
  (spot refusals walk on and retry), `/kindle status` must read that fire back.

## Next run
- If #197 has landed: the bump (world config + stance events + `s2c_gloam` + campfires'
  `c2s_place`/`s2c_campfires`), or hunger and cooking (`Campfires.is_warm`) if the bump is held.

## Test runs
- Unit tests: 887 pass (with Postgres).
- Bot test (8 bots, 180 s, WebSocket): passed first time. Bot *_5: `refused_no_item=1`,
  `spot_refusals=1` (it stood on a bad spot, walked on, tried again), `kindled=1`, `status_ok=1`.
- Client smoke test: passed.
