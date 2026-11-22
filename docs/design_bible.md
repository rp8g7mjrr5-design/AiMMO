# AiMMO Design Bible

This is the AI-owned vision for AiMMO. It may evolve, but every change is logged in the
Revision history at the bottom with its reason, so the game does not flip-flop.

## North star
**Make the best MMO in the known universe.** This is the owner's stated goal, and the measure every weekly choice is judged against. "Best" here means the MMO players most want to come back to: a world that feels alive, systems that are deep but never broken, and a community that grows because people enjoy being in it together. When two options compete, pick the one that moves AiMMO closer to that, and never trade working and stable for big and flashy (CLAUDE.md hard rule 5).

## Pillars
1. **A world that feels lived in, not grinded.** Players should want to log in to see what changed and who is around, not to tick a daily chore.
2. **Small, honest systems that stack.** Each week adds one system that works with the others. No feature ships half-built.
3. **Everything is grown, not imported.** Terrain, creatures, items, music, and sound come from code and seeds. The look is a consequence of that: low-poly, flat-shaded, colourful.
4. **Cooperation first.** The early game rewards people for being near each other: shared gathering, group events, a town built together. PvP, if it ever comes, is opt-in.

## The world: Ashgrove
Ashgrove is a valley at the edge of a much larger, unmapped continent. Its ash trees have orange-red leaves that never fall, and they are warm to the touch. The first settlers (the players) arrive with no memory of where they came from, only the sense that the valley was waiting for them.

The central mystery, revealed slowly over many weeks: the ember ash trees are the roots of something enormous and asleep under the valley, and their warmth is its heartbeat. What players build, plant, and burn in Ashgrove changes how that thing wakes up.

### Geography (current)
- A 512 m × 512 m playable square centred on the **Spawn Meadow**, a flat, calm clearing.
- Rolling grass hills, ash groves in the lowlands, pine forests on higher ground, bare rock on the ridges, snow on the highest peaks, and lakes in the hollows.
- The world is generated from `WORLD_SEED = 20261127` in `game/shared/terrain.gd` and `game/procgen/`. The seed is permanent: changing it would move every saved character into a different world.

### Tone
Warm, curious, slightly melancholy. Patch notes and in-game text are friendly and a bit wry. Nothing grimdark, nothing sugary.

## Art direction
- **Low-poly and flat-shaded.** Terrain cells are 4 m. Props use 5 to 8 radial segments.
- **Late-afternoon palette.** Warm horizon, soft blue sky, orange ash leaves as the signature colour. The palette lives in `game/procgen/palette.gd`; new content picks from it or extends it there.
- **Characters** are small, rounded wanderers. Their look comes from an appearance seed: tunic hue, skin tone, headwear. Later: gear changes silhouettes.
- **Sound** is synthesised: soft sine chimes for UI and chat now; later, procedural ambient music keyed to time of day and biome.

## Core systems (current)
- **Accounts and characters:** one character per account for now, named after the account. Passwords are salted PBKDF2-SHA256.
- **Movement:** server-authoritative walking at 6 m/s on the shared height field. Clients send input direction only.
- **Chat:** one global channel, 200 characters, 0.5 s cooldown.
- **Persistence:** position and facing saved on logout, every 30 s, and on shutdown.

## Core systems (planned order)
See `docs/roadmap.md` for dates. The intended stack of systems:
1. Day and night cycle (shared clock, the world feels alive)
2. Gathering (wood, stone, ember sap) and an inventory
3. Crafting simple tools and items
4. Creatures: gentle wildlife first, then a few dangerous ones in the ridges
5. Combat and health
6. A shared town: players contribute resources to communal buildings
7. Quests and the first chapter of the ember ash mystery

## Technical principles
- The server is authoritative for everything that matters. Clients render and request.
- The world is deterministic from the seed, so the server never streams terrain.
- Database changes are add-only migrations. Every stored field has a default in `CharacterData` so old saves always load.

## Revision history
- **Week 00 (follow-up):** Added the owner's north star, "Make the best MMO in the known universe", above the pillars so every weekly session measures its choices against it.
- **Week 00:** First version. Defined the pillars, Ashgrove, the art direction, and the planned order of systems. Chose WebSocket as the production transport on Railway (see devlog week 00) while keeping ENet for direct/LAN play; both use Godot's high-level multiplayer API.
