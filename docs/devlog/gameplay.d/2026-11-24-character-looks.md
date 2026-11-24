Owner-requested thread work (not a scheduled run), spanning gameplay, client and world files.

What shipped:
- `game/shared/appearance.gd` (Appearance): a look is a Dictionary of 10 small ints (body, height, skin, face, hair, hair_colour, beard, headwear, tunic, trousers). `check()` is strict (what the server accepts from a client), `normalize()` is forgiving (what loads from a save). Indices are permanent: add choices at the end only.
- Migration 0004 adds `characters.appearance TEXT NOT NULL DEFAULT ''`. '' = never chosen, drawn from the seed exactly as before. CharacterData carries `look`; PgStore writes it in save_character; JsonStore keeps it as a dict.
- Protocol v8 on Net/Play: `c2s_set_look(look)` and `s2c_look(peer_id, look)`. Frozen `net_v7.gd` / `net_play_v7.gd`. The server sends s2c_look right after each s2c_player_joined, and to everyone when a look is saved (saved to the store at once). LOOK_GAP 1 s per player.
- AvatarBuilder.parts(seed, look) / build(..., look) / skinned(seed, look). An empty look gives byte-for-byte the old parts (unit tested). `head_gear()` and `dress()` are the only style-specific code: if the body style is redrawn, re-implement those two and keep the Appearance indices.
- Client: LookWindow (opens at login while the look is unchosen, "Later" skips it for now) and "Change appearance" in the Esc menu. The camera swings in front of you while it is open; drag to orbit. Every arrow redraws your own avatar locally; nothing is sent until Set out / Save.
- Bots: `gameplay_looks_v8` saves a random look, changes it once, checks the echo, checks every other player's look arrives, and checks the look survives the reconnect.

Not done / next:
- The owner asked for new body style drafts the same night. Height and build are deliberately simple (skeleton scale, x/z girth) so they carry over to any style.
- No way yet to see another player's face up close except walking up to them.
- No claim was taken: this session's git access is limited to its own branch, so it could not push `claim/*`.
