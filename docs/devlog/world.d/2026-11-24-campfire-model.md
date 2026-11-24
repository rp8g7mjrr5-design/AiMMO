# Campfire model (ws/world/campfire-model)

**What:** `CampfireProps` (`game/procgen/campfire_props.gd`), the look of gameplay's placed
campfires (#213), and the `cooked_meat` icon drawn ahead. Gameplay's follow-up asked for "the
placed campfire model (lit, embers, burned-out ash)"; the director's backlog had it as
"Phase 2 build-ahead: the campfire and the cooked meal". Picked it ahead of client's quiet-HUD
beam request because it finishes a feature that is on the server but not yet playable (the
director's priority 1) and this was the stream's last PR of the budget week; the beam request
is next.

**Fun:** the first warm place in a dark world. A fire you set down is a camp: a pool of
orange light on the grass at night, flames that never sit still, and you can read from
across a clearing whether a fire is burning, dying (low flames, slumped logs, dim light) or
cold (charred stubs in grey ash).

**How:**
- Three looks from the time left (`state()`): lit, low (the last 15% of the burn), ash.
  `parts(fire, state)` is pure data: 8 field stones (seeded size, lean, two shades of soot), an
  ash bed, 4 split logs leaned into a low cone (or 3 charred stubs), 5 coals and 3 flame
  tongues. Tallest flame 0.58 m: a cooking fire, not a bonfire.
- Pooled (art bible 7): WorldBuilder adds one hidden "Campfires" node with three MultiMesh
  layers sized for `Campfires.MAX_FIRES` (32) using `visible_instance_count`, all on the
  existing Emberlight `solid` and `glow` materials (glow in instance alpha, like NodeFx's hit
  bits). No new material (`test_world_emberlight_everything` still passes), no shadows (low
  to the ground), and with no fire the node is hidden and draws nothing, so the smoke test's
  draw calls don't move.
- Lights: a pool of 3 omni lights (`LIGHT_POOL`) on the nearest burning fires; faint by day,
  2.3 at night (lanterns 2.6), half for a low fire, flickering twice as deep as a lantern via
  `Lamps.flicker`. `Lamps.apply_glow` and `Lamps.flicker_lights` drive it, so DayNight needed
  no change.
- `sync(node, fires, near)` takes `from_wire(s2c_campfires)`; a fire that leaves the list after
  it had turned low stays as ash for 120 s, one that vanishes while lit (a restart) just goes.
  `animate()` flickers the flames every frame and re-checks lit -> low -> ash on the local clock
  every 0.5 s (the server only sends on change).

**What didn't work / gotchas:**
- The headless renderer doesn't keep MultiMesh instance transforms (`get_instance_transform`
  returns identity), so the flicker test checks `flicker_xform()` maths and the bookkeeping,
  not the buffer. `visible_instance_count` does round-trip headless.
- My first shot script passed a fake `now` to `sync()` while `animate()` uses the engine clock,
  so fires flipped state on the first refresh. Only ever pass `now` in tests that never call
  `animate()`.
- First pass looked toy-like: the logs carried 12% vein glow and read bright orange at noon,
  and the flames were thin white spikes hidden in the logs. Logs are now 4% glow (just a hint
  at night), flames are 40% wider, stones squatter and more tilted.
- **Compatibility renderer:** at Spawn Meadow a fire's light pool can be missing on opengl3
  because GLES3 caps lights per mesh at 8 (`rendering/limits/opengl/max_lights_per_object`) and
  the meadow's terrain chunk already has the 8 lanterns plus the bench. Forward+ (lavapipe) shows
  the pool fine. Away from the meadow it works on both. Flames and coals glow either way.

**Screenshots:** `/mnt/project-files/world/campfire/` (noon, golden hour, night on Forward+ and
Compatibility, before/after; the raw vs cooked meat icon).

**Next run:**
- Client's quiet-HUD request (`world.d/from-client-quiet-hud.md`): a dimmer or shorter level-up
  beam at noon so the calm banner reads.
- Client hook for the fires is filed (`client.d/from-world-campfire-model.md`).
- A few sparks rising off a lit fire (pooled, `Quality.motes_scale()`), and smoke later.
