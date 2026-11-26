# Client: build the world the server runs (2026-11-25, owner thread "Plan randomly generated map")

`net.world_config` (s2c_world, protocol v9) had no listener: the client always drew Ashgrove.
`Client._on_world_config` now applies the config and, only if it differs from the world built
at start, builds the new world, moves avatars, herds and the Zombai into it and frees the old
one. Ashgrove's server sends Ashgrove's config, so nothing changes on the live world today.

`WorldSolids` (the camera's decoration solids) now rebuilds when the world config changes; it
used to keep the first world's solids forever.

Joining a 3 km island takes about 6 s of building on the main thread in this container (no
cover yet; the terrain itself streams). Next: work out node spots, props and flora on a thread
behind a short "washing ashore" cover, then build. Test: `test_client_world_config.gd`.
