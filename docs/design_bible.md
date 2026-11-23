# AiMMO Design Bible

This is the AI-owned vision for AiMMO. It may evolve, but every change is logged in the
Revision history at the bottom with its reason, so the game does not flip-flop.

## North star
**Make the Greatest MMO of all time.** This is the owner's stated goal, and the measure every weekly choice is judged against. The number one way there is to make it **fun**: if it isn't fun, it isn't the best (see "Fun comes first" under Owner directions). "Greatest" here means the MMO players most want to come back to: a world that feels alive, systems that are deep but never broken, and a community that grows because people enjoy being in it together. When two options compete, pick the one that moves AiMMO closer to that, and never trade working and stable for big and flashy (CLAUDE.md hard rule 5).

## Pillars
1. **A world that feels lived in, not grinded.** Players should want to log in to see what changed and who is around, not to tick a daily chore.
2. **Small, honest systems that stack.** Each week adds one system that works with the others. No feature ships half-built.
3. **Everything is grown, not imported.** Terrain, creatures, items, music, and sound come from code and seeds. The look is a consequence of that: low-poly, flat-shaded, colourful.
4. **Cooperation first.** The early game rewards people for being near each other: shared gathering, group events, a town built together. PvP, if it ever comes, is opt-in.

## Owner directions (standing rules)
The owner plays and tests; the AI designs everything else. The owner has given the
directions below, and these are standing rules: they win over any other design choice, and
the weekly review and director may refine them but never reverse them. Everything not
covered here (systems, lore, balance, roadmap) stays the AI's call. Fun comes first and sits
above the numbered directions: when two choices both respect directions 1 to 3, pick the
more fun one.

### Fun comes first (the first rule)
**If it isn't fun, it isn't the greatest MMO.** Fun is how we measure the North star. Every
change, in every stream, is judged first by one question: *does this make the game more fun
to play, right now, for a real player?* "Technically correct but boring" is not done.
What that means in practice:
- **Tight feedback.** Every player action answers within about 100 ms on the client: a
  sound, a motion, a flash, a number, a camera nudge. The server still decides the result;
  the client shows that the input landed at once and confirms or corrects it.
- **Short loops that pay off.** A new player gets a first reward (an item, a craft, a
  discovery) within about 60 seconds of spawning, and something new to want within about
  5 minutes. Every loop (gather, craft, explore, fight) ends in a payoff the player can see,
  hear and use, and the payoff feeds the next loop.
- **Juice.** Hits, pickups and crafts get layered feedback: a hit reaction, particles, a
  pitch-varied procedural sound, a toast, the item flying into the pack. Make small things
  feel good before adding more things.
- **No dead time.** Avoid long walks with nothing to see, waits with nothing to do, empty
  menus and silent screens. If a player waits, give them something to watch or decide.
- **Clear goals, always.** The player should always know one thing they could do next and
  why it would be good.
- **Surprise and discovery.** Reward curiosity: a rare drop, a hidden spot, a creature doing
  something odd, the world changing at night.
- **Better together.** Doing something near another player should be more fun than doing it
  alone (shared node bonuses, group moments, seeing each other's effects).
- **Fair and readable.** Never punish players for things they couldn't see coming. Lose
  little on failure; never lose a whole session's progress.
- **Cut boring work.** Grind, busywork and chores don't ship. If a system only works by
  making players repeat something dull, redesign it.

How each stream applies it:
- **gameplay:** tune timings and rewards for pace (gather and craft times, drop rates,
  respawns) and add the server events the client needs for feedback (hit, crit, rare drop,
  level-up). Prefer a rewarding loop over a deep but slow one.
- **world:** make places worth walking to: landmarks in view, something to find along every
  path, visible reactions (nodes shake, leaves fall, sparks fly), and a world that changes.
- **client:** responsiveness and juice: instant input feedback, animation, sound, camera
  feel, toasts and clear goals on screen. Never leave the player staring at nothing.
- **qa:** measure fun, not only correctness (see "Fun checks" below), and file "this feels
  slow or boring" as a bug with numbers.
- **integrator and director:** a PR that makes nothing more fun, or makes the game slower or
  duller, is sent back or reprioritised. Backlogs are ordered by player fun first.

**Fun checks.** Each worker PR has a "Why it's more fun" line: one or two sentences on what a
player will feel that they didn't before, or, for pure plumbing, which upcoming fun it
unblocks. The bot test reports fun metrics for a fresh character (time to first reward,
longest stretch with no feedback, rewards per minute, loops completed) and fails when they
get worse past a threshold, so the game can't quietly get slower or emptier.

### 1. Chat is for talking
Chat exists only so players can talk to each other. **No gameplay goes through chat.**
- Every player action has a proper control: a key, a click, a window or a button. Nothing a
  player needs is reachable only by typing.
- Slash commands do nothing on a normal server. The existing ones move to real UI:
  `/gather` → press E at a node, `/bag` → the pack window (I), `/who` → a players panel,
  `/time` → the time dial's tooltip, `/help` → a controls overlay (F1) and first-login hints.
- Debug commands may stay for bots and developers, but only when the server starts with
  `--dev-commands` (the bot test and local runs). They are never listed in `/help`, the UI or
  patch notes. On a normal server a line starting with "/" is refused with a short system
  hint ("Chat is for talking. Press F1 for controls.") and is never broadcast.
- New systems (crafting, combat, trade, quests) are built UI-first. No "start with a chat
  command" shortcuts.

### 2. The camera feels like a modern action MMO
The reference feel is the over-the-shoulder action camera of today's action-combat MMOs (the
owner's favourite is New World). We copy the *feel*, not anyone's code or presentation:
- Third person, **over the right shoulder**: the character sits a little left of centre and
  low in frame, with the world ahead of them readable. Default distance about 3.5 m, pivot at
  about head height, shoulder offset about 0.6 m.
- **Mouse look is always on** while playing: the cursor is captured and hidden, moving the
  mouse turns the camera, no button needs holding. A small centre reticle shows where you
  are looking. Opening a window (pack, settings, chat input) frees the cursor; closing it
  captures it again.
- **Movement is camera-relative**: W walks where the camera looks, A/D strafe, S backs up, and
  the character turns to face the camera's heading while moving. A free-look key (hold Alt)
  lets you look around without turning.
- **Smooth, weighty follow**: the camera eases after the character (no jitter, no snapping),
  with a short zoom range (about 1.5 m to 6 m) on the wheel and a shoulder-swap key.
- **Never through the ground**: the camera pulls in when terrain, trees or rocks are in the
  way and eases back out.
- **Look to interact**: the thing you interact with is what the reticle is on (within reach),
  falling back to the nearest one in reach. This is how gathering picks its node.
- Settings: sensitivity, invert Y, field of view and shoulder side.

### 3. Gathering feels like a modern MMO
See "How gathering feels" below. The node you gather is the one under the reticle (direction
2). Nodes visibly empty and regrow, the gather bar and motion are server-timed, and every
gather ends with satisfying feedback: a hit reaction on the node, a sound, a toast, and the
item landing in your pack.

### Inspired by, never copied
We borrow genre mechanics and feel only. Mechanics and feel are free for anyone to use; the
expression of another game is not. So, always:
- **No names** from any existing game: no place, faction, character, creature, item, skill,
  resource or system names, and no near-misses or puns on them.
- **No lore, story, quests, dialogue or text** taken from or closely retelling another game.
- **No art, models, icons, UI layouts or HUD look, fonts, music or sounds** from another game,
  and none made to look like them. Ours are procedural (CLAUDE.md hard rule 3) and use our
  own palette, so they will look like Ashgrove.
- **No logos, trademarks or marketing lines**, and never say AiMMO is related to, approved by,
  or "the new version of" another game. Patch notes and in-game text name no other game.
- Inside design docs it is fine to say which game's *feel* inspired a direction; player-facing
  text never does.
When unsure whether something is too close, make it more Ashgrove: ember ash, the sleeping
thing under the valley, the warm late-afternoon palette.

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
- **Chat:** one global channel, 200 characters, 0.5 s cooldown. Talking only (owner direction 1).
- **Persistence:** position and facing saved on logout, every 30 s, and on shutdown.

### How gathering feels (owner direction, 2026-11-22)
Gathering works the way players already know from mainstream MMOs, never through chat commands:
1. Walk up to a tree, rock or seep and look at it. When one is in reach and under the reticle (or, failing that, the nearest in reach) it is softly highlighted and a prompt shows its action and key, e.g. "[E] Chop Ember Ash".
2. Press the interact key (E) or click the node. Your character turns to it and plays a looping gathering motion (chop, strike, scoop), with matching procedural sound.
3. A short gather bar fills (about 2 s, set by the server). Moving, jumping or pressing E again cancels it; nothing is lost.
4. When it fills, the item pops into your pack: a "+1 Ash wood" toast, a small chime, and the pack updates at once.
5. Each node gives a few gathers, then visibly empties (stump, rubble, dry seep) for everyone nearby and grows back later.
6. Other players see you gathering. Several players can work the same node; each gather takes one charge.
The server times the bar and decides the result; the client only shows it. `/gather` stays as a hidden debug and bot command, not listed in `/help` or patch notes. We borrow the genre's mechanics only: no names, art, UI or sounds from any existing game.

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
- **Week 00 (2026-11-23, fun first):** Added "Fun comes first" at the top of the owner directions. The owner said the number one way to make the greatest MMO is to make it fun, and if it isn't fun it isn't the best. Turned that into concrete guidance (tight feedback, short loops that pay off, juice, no dead time), a lens for each stream, a "Why it's more fun" line on every worker PR, and bot-test fun metrics in qa. Directions 1 to 3 (chat is for talking, the action camera, how gathering feels) and "Inspired by, never copied" are unchanged.
- **Week 00 (2026-11-22, owner directions):** Added "Owner directions": chat is for talking only (slash commands move to keys and windows, debug commands only behind `--dev-commands`), an over-the-shoulder action camera with always-on mouse look and camera-relative movement, gathering that targets what the reticle is on, and an "Inspired by, never copied" section. The owner loves how New World's camera and gathering feel and asked for that feel, while the AI keeps designing everything else; the guardrails keep us to mechanics and feel, never names, lore, art, UI or text.
- **Week 00 (2026-11-22, gathering feel):** Added "How gathering feels". The owner disliked typing `/gather` and pointed at mainstream MMOs as the model, so gathering becomes walk up, prompt, press E or click, timed gather bar with animation, item toast, and visibly emptied nodes. `/gather` is kept only as a debug fallback.
- **Week 00 (follow-up):** Added the owner's north star, "Make the Greatest MMO of all time", above the pillars so every weekly session measures its choices against it.
- **Week 00:** First version. Defined the pillars, Ashgrove, the art direction, and the planned order of systems. Chose WebSocket as the production transport on Railway (see devlog week 00) while keeping ENet for direct/LAN play; both use Godot's high-level multiplayer API.
