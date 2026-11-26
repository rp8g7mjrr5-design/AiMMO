Builder run, 2026-11-26 (client backlog item "Basics 2: campfires on screen and the place key").

Why this item: the four basics, zombie survival is the one players feel most, and the server
had placed campfires since v9 with nothing on the client. Owner PR #241 touches gathering and
beach files; none of them are in this change. No protocol change.

What shipped:
- `client.gd` draws fires: `net.campfires_changed` -> `PlaceGhost.fires_from_wire` ->
  `CampfireProps.sync(world.Campfires, ...)`, and `CampfireProps.follow` about once a second so
  the 3 lights sit on the nearest fires. Re-synced after the island world is rebuilt.
- `PlaceGhost` (`game/client/place_ghost.gd`): a see-through ring and logs from
  `CampfireProps.parts` (stones and logs only), one node, two MultiMeshes, two unshaded
  materials, never freed while playing. `reason_at` is `Campfires.check_spot` over the fires
  the client was sent, so it goes red on a fire, a node, the bench, water and the edge.
  It can't see owners, so "too_many" comes back from the server and `refuse()` holds the ghost
  red for 1.2 s.
- Key **B** (`place`, in `ControlsOverlay` and the F1 list). B shows the ghost, B or left-click
  sets it down, right-click or Esc puts it away. Opening any window, or the pack losing its
  campfire, cancels. While placing, every input tick carries the camera's yaw, so you turn to
  aim and the server places it where the ghost stands (it uses the session's last yaw).
- A fire that catches is answered by sound (`Sfx.kindle`, a 0.6 s whumph and crackle) and the
  fire appearing, no words. Refusals show their line centre screen except within
  `Vitals.COMBAT_SECONDS` of losing health (`in_fight()`, clean fight: sound and red only).
  The bandage refusal uses the same rule now.

Tried and changed:
- First ghost alpha 0.38 with ash grey disappeared in the meadow grass at noon; now straw-pale
  at 0.55 (still see-through). Shots: `/mnt/project-files/client/campfire-place/`.
- Sending an extra `c2s_input` with the aim on confirm would shift prediction's seq labels
  for one tick; dropped it in favour of sending the yaw every tick while placing.
- The bot behaviour first built a `CampfireProps` node: `test_qa_art_lint` forbids art in bot
  behaviours, so it checks the wire reading and the ghost rule only (drawing is unit tested).

Notes to next self:
- Placing reads `gather_prompt.pack` for the campfire count; if the pack moves elsewhere,
  move `has_campfire()` with it.
- The same ghost and key can place a workbench when gameplay's "workbench you build" lands
  (`c2s_place("workbench")`): give `PlaceGhost` a kind and the bench's parts.
- In the local 45 s bot test the /kindle bot (*_5) hadn't kindled yet, so `client_campfires`
  saw no fires; CI's full run is the real check.
