Done: **Basics 3 and 4: a map of what you've found (M).** (claude/project-thread-jikqlf, owner request 2026-11-27: "a Map as well to pull up with M to show the world")
`MapWindow` on M: WorldMap's relief painted on a worker thread, ruins by grade, coast landmarks, your arrow, hover names, wheel zoom, drag, right-click resets. The whole island shows (owner asked to "show the world"), so there is no fog yet.

Follow-ups:
- [ ] Fog the ground you haven't seen, per character and per wipe (needs a saved explored-cells mask; the owner asked for the whole world first, so weigh it with the owner's direction before building).
- [ ] Pin a spot on the map (click) and show it on the compass strip.
- [ ] A client smoke shot of the map (`--open-map`, island world) so the look is checked in CI.
- [ ] The top-left HUD line still says "Ashgrove" on the island (`hud_label` in `client.gd`); show the world's name.
