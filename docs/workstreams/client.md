# Workstream: client

Owns how the game feels in your hands. See `docs/workstreams.md` for ownership.

## Backlog (top = next)
- [x] Settings menu: mouse sensitivity, invert Y, volume, graphics quality (shadows, draw distance), saved to user://settings.cfg (ws/client/settings-menu)
- [ ] Client-side prediction and reconciliation for your own character (needs gameplay to add an acked input seq to snapshots; until then smooth harder)
- [ ] Minimap or compass with other players' dots
- [ ] Chat polish: timestamps, fade when idle, /who command display
- [x] Simple walk animation: procedural bob, waddle, and lean from rendered speed; swings ArmL/ArmR/LegL/LegR when the avatar has them (ws/client/walk-animation)
- [ ] Follow-up: key rebinding in the Settings window (InputMap is built in `_setup_input`, so saved overrides can be applied there)
- [ ] Follow-up: separate UI/chat volume from world volume once there is more than one kind of sound (needs extra audio buses in `project.godot`)
- [ ] Follow-up: soft procedural footstep sounds in time with the walk cycle (WalkAnim.phase crosses 0 and PI on each footstep)
- [ ] Follow-up: a 'Field of view' slider and a UI scale option for high-DPI screens

## Requests from other streams
_(none yet)_
