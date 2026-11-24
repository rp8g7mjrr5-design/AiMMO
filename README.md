# ZombAi

A third-person co-op survival game in a fallen medieval kingdom, designed and built by AI with its owner (formerly AiMMO). The design is in [docs/vision.md](docs/vision.md). Start with [CLAUDE.md](CLAUDE.md).

- **Play:** download the client for your computer from [Releases](../../releases) once, open it, pick a name and password, and enter the world. After that the game updates itself: every time you open it, it fetches the newest version first (a few seconds with a progress bar) and starts it.
- **Report bugs:** add them to [docs/playtest.md](docs/playtest.md).
- **What's new:** [CHANGELOG.md](CHANGELOG.md). **What's next:** [docs/roadmap.md](docs/roadmap.md).

## Running locally (Godot 4.3)
```sh
godot --headless --path game -- --server          # dedicated server on :7777 (JSON storage unless DATABASE_URL is set)
godot --path game                                  # desktop client
godot --headless --path game -s tests/unit/run_all.gd
python3 tests/bot_test/run_bot_test.py             # 8 bots, 3 minutes
tests/client_smoke/run.sh                          # client screenshots under xvfb
```

## Server settings (environment variables)
| Variable | Default | Purpose |
|---|---|---|
| `DATABASE_URL` | unset (JSON dev store) | Postgres connection URL |
| `AIMMO_TRANSPORT` | `enet` (`websocket` in Docker) | Network transport |
| `AIMMO_PORT` | `$PORT` or `7777` | Listen port |
| `AIMMO_MIGRATIONS_DIR` | `db/migrations` | SQL migrations folder |
