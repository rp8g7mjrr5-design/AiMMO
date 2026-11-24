Done: **(director, owner direction 8), part 3: nodes, ruins and spawn on a generated world.** (ws/gameplay/kingdom-placement)
On `gen_version` 1 nodes come from `WorldGen.node_spots()` (index = id) plus a tier-2 ring round the kingdom spawn; herds and bench follow spawn; `Ruins` gives grades and labels; server takes `--world=`/`AIMMO_WORLD`. Ashgrove unchanged.

Follow-ups:
- [ ] Part 2 still waits for a free protocol number (#197 holds v8): when it lands, the login reply carries `WorldGen.config()` so the client builds the same world; the server already applies it.
- [ ] The move of the live world to a generated map (announced step): pick the seed, set `AIMMO_WORLD` on Railway via qa, move every character to the new spawn once (keep skills, items, pack), change "Welcome to Ashgrove". `Server.place_on_this_world` already catches anyone in water or out of bounds; a real move should place everyone at spawn on first login to the new world (needs a per-character world stamp: add-only column, after #197's 0004).
- [ ] A "You enter the Burned Farmstead (Quiet)" notice from `Ruins.at()` when a player crosses into a ruin (needs a small RPC in a bump and a client notice).
- [ ] Bot test on a kingdom: ask qa for a short phase with `--world=<seed>:1` where bots gather from the starter ring and craft at the bench.
