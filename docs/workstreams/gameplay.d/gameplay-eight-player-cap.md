Done: **(director, owner direction 8, 2026-11-24: ZombAi, Phase 1), part 1: the 8-player cap.** (ws/gameplay/eight-player-cap)
`Server.max_players` from `--max-players` / `MAX_PLAYERS` (unset, 0, negative or junk = no cap), a login past it gets "The world is full (8 / 8). Try again soon.", nobody is kicked; qa asked to set `MAX_PLAYERS=8` in the Dockerfile.

Follow-ups:
- [ ] Client's hp-0 request (from-client-vitals-bar): built and tried (one `_send_vitals_if_changed` at the top of `knock_down`, before the reset), but it fails client's `client_vitals_bar` bot behaviour (request filed with client). Re-add it the run after client fixes the behaviour.
- [ ] Bot test with a cap: once qa can start the server with `--max-players`, a run (or a short extra phase) where a 9th bot is turned away with the full text and the 8 inside never see a disconnect.
- [ ] When a seat opens, the client could retry on its own every few seconds while showing "Waiting for a seat (8 / 8)" (client request, once players hit the cap for real).
