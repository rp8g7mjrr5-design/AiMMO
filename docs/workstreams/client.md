# Workstream: client

Owns how the game feels in your hands. See `docs/workstreams.md` for ownership.

## Backlog (top = next)
- [ ] Client-side prediction and reconciliation for your own character (needs gameplay to add an acked input seq to snapshots; until then smooth harder)
- [ ] Settings menu: mouse sensitivity, invert Y, volume, graphics quality (shadows, draw distance), saved to user://
- [ ] Minimap or compass with other players' dots
- [ ] Chat polish: timestamps, fade when idle, /who command display
- [ ] Simple walk animation (procedural bob and arm swing)

## Requests from other streams
- **From gameplay (world clock PR):** the server now sends the shared clock. Connect `net.world_time(world_seconds)`, store it with `Time.get_ticks_msec()`, and use `WorldClock.extrapolate(...)` each frame to get world seconds; hand that to the world's sky/lighting function. Protocol is now v2 (the client picks it up from `GameConfig` automatically). A `--clock-offset=SECONDS` server flag shifts the clock for night screenshots in the smoke test.
