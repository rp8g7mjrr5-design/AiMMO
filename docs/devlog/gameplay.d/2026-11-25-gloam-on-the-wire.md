Protocol v10: the Gloam walkers on the wire (builder, ws/builder/gloam-on-the-wire)

What shipped:
- `s2c_gloam(PackedFloat32Array)` on Net/Play, unreliable_ordered like `s2c_wildlife`: 6 floats
  per walker in view, `[id, x, z, yaw, state_index, windup_left]` (`Gloam.to_wire_near`,
  `Gloam.from_wire`, `Gloam.WIRE_STRIDE`). `windup_left` is the seconds until a raised grab
  closes (state "grab"), else 0: the client gets the telegraph's timing, not just the state.
  Same 5 Hz beat and the same 3 empty goodbyes as wildlife (`_send_gloam`, `s.gloam_bye`).
  Nothing goes out while nobody has a walker in view, so the live world (no `--gloam`) sends none.
- `s2c_gloam_hits(peer, kind, walker_ids, downed)`: everyone in view, swinger included, right
  after `s2c_swing_hits`, only when a walker was struck. Decided against changing
  `s2c_swing_hits`'s signature: a separate RPC left every v7 test and the client's existing
  `swing_landed` handlers untouched, and `downed` gives the client its "put down" moment.
- Signals on Net: `gloam_changed`, `gloam_struck`. Frozen `net_v9.gd` / `net_play_v9.gd`.
- Unit tests `test_gameplay_protocol_v10.gd`; `gameplay_gloam` bot behaviour now also checks its
  walker shows in `s2c_gloam`, the windup shows before the grab, every connecting haymaker comes
  back in `s2c_gloam_hits` and the last one lists it as downed. Local 130 s bot test passed
  (wire_seen=32, windup_seen, wire_hits=4, downed). Protocol test passed.

Left out of this bump on purpose (sized for one run): `c2s_dodge`, walkers rising at ruins (no
ruins on `main` yet) and turning `--gloam` on in the main bot test (qa). Campfires already went
out in v9, and `gloam_fires()` still returns [] until placed fires feed in.

Also this run: fixed #225's red CI. `gameplay_skills_v4` counted a hunt's drops (which arrive
as `s2c_gather_result` since the first hunt) as gathers owed gathering XP; it now skips
`Wildlife.drops` items. Flaky on main too, only when a bot lands a kill.
