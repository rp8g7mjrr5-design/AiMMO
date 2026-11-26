Done: "Basics 3, a generated map that loads fast: terrain, grass and props in chunks" (terrain part) (claude/project-thread-iojvhn)
Terrain streams around the camera (3 km island 29 s -> 0.3 s); props scatter cached per world.

Follow-ups:
- [ ] Client follows `s2c_world`: apply the config, work out node spots, props and flora on a thread behind a short cover, then rebuild the world (about 8 s of data on a 3 km island today).
- [ ] Flora placement on an island (3.4 s): fewer tries on shores, or chunked like the terrain.
