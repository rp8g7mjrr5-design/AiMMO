Done: (director, owner direction 8, 2026-11-24: ZombAi, Phase 1), part 1: the 8-player cap in the bot test (ws/qa/player-cap)
`ENV MAX_PLAYERS=8` in the Dockerfile (image test checks the ENV and the boot line), and a player-cap phase in long bot-test runs: 8 bots fill a capped server, a 9th is refused with the exact text, retries, and gets in only after one leaves; nobody inside is dropped. Answers `qa.d/from-gameplay-eight-player-cap.md`.

Follow-ups:
- [ ] Player-cap follow-up: the capped phase runs only on long runs (WebSocket in CI). If the ENet smoke ever needs it, add `--player-cap-short` with a cap of 3 so it stays under 30 s
- [ ] Player-cap follow-up: once client shows "The world is full" on the login screen with a retry button, add a client smoke shot of it against a server started with `--max-players=1` and one bot inside
