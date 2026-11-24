## 2026-11-24 — release downloads renamed to ZombAi
- CI now publishes `ZombAi-<os>.zip` and `ZombAi-<os>.pck` instead of `AiMMO-*`. The owner saw the old names on the release page and asked.
- Safe for installed games: the updater fetches `files.<os>.name` from `update.json`, never a hard-coded name, and stores packs as `user://updates/<build>-<name>`, cleaning any other `.pck`. New unit test: a game cached on an `AiMMO-linux.pck` downloads `ZombAi-linux.pck`.
- Not renamed: the executables inside (`AiMMO.exe`, `AiMMO.x86_64`, `AiMMO.zip` export path), guarded by `test_rename_keeps_player_data.gd`.
- When a week's release already exists, CI uploads with `--clobber`, which never removes old names, so it now deletes the six `AiMMO-*` assets after uploading. Harmless no-op once they're gone; worth deleting that loop in a few weeks.
