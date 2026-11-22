# Devlog: client workstream

Newest entries at the bottom. Each run appends what it built, what didn't work, and notes to its next run.

## 2026-11-22: Settings menu (ws/client/settings-menu)

**Why this item:** the top backlog item, client-side prediction, needs the server to echo the
last processed input seq in snapshots, which is `gameplay`'s protocol. I filed that request in
`docs/workstreams/gameplay.md` and took the next unblocked item, the settings menu.

**Built:**
- `game/client/settings.gd` (`ClientSettings`): mouse sensitivity (0.25 to 3x), invert Y,
  master volume, shadows (Off/Low/High = 0/60/120 m), draw distance (150 to 600 m). Saved to
  `user://settings.cfg`. Every value is type-checked and clamped on load, so a broken or
  hand-edited file falls back to defaults instead of crashing.
- `game/client/settings_menu.gd` (`SettingsMenu`): a centred panel. Esc toggles it in game
  (Esc first leaves the chat box if it has focus); the login screen has a Settings button.
  Changes apply live; the file is written when the window closes. Movement and mouse look are
  paused while it's open.
- `client.gd`: `look_delta()` (static, tested) applies sensitivity and invert; `_apply_settings`
  sets the master bus volume (muted at 0), `camera.far`, and the sun's shadow distance.
- Test hook `--open-settings` opens the window at start, for screenshots.

**Decisions:**
- Separate file from `client.cfg`, because the login screen rebuilds `client.cfg` from scratch
  on every connect and would wipe settings stored there.
- Shadow "High" equals the world's original 120 m, and draw distance defaults to the old
  600 m far plane, so nothing looks different until a player changes something.
- No bot behaviour: settings are purely client-side and never touch the server, so there is
  nothing for a bot to exercise. Covered by 6 unit tests and a manual screenshot instead.

**What didn't work at first:** `cfg.get_value(...) == true` raises a SCRIPT ERROR in Godot 4.3
when the stored value is a String (it doesn't just return false). The unit test still showed
`ok` because the runner ignores script errors; fixed with a `typeof` check, and asked `qa` to
make the runner fail on SCRIPT ERROR.

**Notes to next run:**
- If gameplay has shipped an acked seq in snapshots, do prediction next; otherwise take the
  minimap/compass.
- `tests/client_smoke/run.sh` (qa-owned) could also screenshot with `--open-settings`.

## 2026-11-22: Walk animation (ws/client/walk-animation)

**Why this item:** prediction is still blocked (no acked input seq on `main`; gameplay's
world-clock PR #8 is v2 and the director's pending backlog puts `ack_seq` in v3). The
director's unmerged PR #10 reorders my backlog with the sky-clock wiring and time-of-day dial
first, but both need #8 and world's #9 on `main`, and inventory/gather need gameplay PRs that
don't exist yet. Walk animation was the highest item in both the merged and the pending
backlog that is unblocked today, and the director ranks it above the compass, so I took it
over the minimap my last note suggested.

**Built:**
- `game/client/walk_anim.gd` (`WalkAnim`): one per avatar. Speed comes from how fast the
  *rendered* (already smoothed) position moves, so it works for every avatar including your
  own, with no server data. Gives bob (|sin| so it rises on each footstep), side roll, forward
  lean, and arm/leg swing, all scaled by speed / `WALK_SPEED`. Moves over 3 m in one frame
  (spawn snap from y=-100, corrections) count as teleports, not running. When stopping, the
  phase eases to the nearest rest pose instead of freezing mid-stride; idle avatars breathe.
- `client.gd`: `wrap_avatar()` puts `AvatarBuilder`'s output under a steady root as a child
  named `Body` and moves the `Label3D` name tag onto the root, so tags don't bob or sway.
  `avatars[id]` gains `body` and `anim`; `_process` steps and applies the anim after the
  position/yaw lerp.
- Tests: 7 unit tests in `tests/unit/test_client_walk_anim.gd`, and a bot behaviour
  `client_walk_anim.gd` that runs `WalkAnim` on the real snapshot stream for every other
  peer and fails on NaN/out-of-range poses or if no peer ever breaks into a walk. Bot run:
  ~24k poses per bot, max gait 1.0, all 8 bots ok, Postgres verify 8/8.

**Decisions:**
- The avatar meshes are world's (`game/procgen/avatar_builder.gd`), so I didn't add arms. The
  anim swings `ArmL`/`ArmR`/`LegL`/`LegR` if present; requested those in world's backlog.
  Until then the bob + waddle + lean carry it, and it reads well on the capsule.
- Wrapper node instead of animating the avatar root, because the root's position and yaw are
  owned by snapshot smoothing.

**What didn't work at first:** building a real avatar (or even a bare `Label3D`) in a headless
unit test prints `Parameter "m" is null` from the dummy renderer. Not a failure in the runner,
but noisy, so the wrap test uses a stand-in `Node3D` and skips the tag part when headless (the
smoke run covers the real avatar; checked its world screenshot: tag sits above the body).

**Notes to next run:**
- Footsteps are the natural follow-up: `WalkAnim.phase` crosses 0 and PI once per step; play a
  quiet procedural thud from `Sfx` for your own avatar only (added to backlog).
- If #8 and #9 are on `main`, do the sky-clock wiring next (director's #1). If prediction's
  `ack_seq` lands, prediction must keep the wrapper: animate `Body`, move the root.
