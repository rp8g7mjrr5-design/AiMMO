# ZombAi Design Bible

This is the AI-owned design for ZombAi (the repository was AiMMO until 2026-11-24). It may
evolve, but every change is logged in the Revision history at the bottom with its reason, so the
game does not flip-flop.

## North star
**Make the survival sandbox people keep coming back to: a server you live on, a base you hold, a story you tell your friends.** Owner direction, 2026-11-25: ZombAi is **not an MMO**. It is a third-person open-world zombie survival sandbox in a fallen medieval kingdom, played on **servers of up to about 100 players**, sold as a one-time buy (`docs/vision.md`). The feel references are open-world zombie survival sandboxes (the owner named 7 Days to Die and Project Zomboid); we take their feel, never their content ("Inspired by, never copied"). The number one way there is still to make it **fun**: if it isn't fun, it isn't worth shipping (see "Fun comes first"). When two options compete, pick the one that is quicker to learn, better in a 30-minute session, makes a better story to tell, and never trade working and stable for big and flashy (CLAUDE.md hard rule 5). (This was "the Greatest MMO of all time" until 2026-11-24 and "2 to 8 friends in co-op" until 2026-11-25; the skills, camera, combat and art built for both carry over.)

### The vision in one paragraph (owner direction, 2026-11-25)
A kingdom fell when the Dimming rose, and its dead got back up as **the Zombai**. Each server runs
a freshly generated stretch of that kingdom (forests, moors, rivers, the old king's roads, and
ruins graded by how much they can kill you and how much they pay) for **up to about 100
players**. You make your character, arrive with nothing, eat, drink, keep warm and tend wounds;
you learn that noise brings the Zombai and ember-fire burns them; you find a few people worth
trusting, claim land, build a hold together and keep it through horde nights; and you push into
deadlier ruins for the gear to push further. Other survivors are everywhere: neighbours to trade
with, strangers to help on the road, and, only where the server's rules allow it, a threat of
their own. In your hands it is an action game (the over-the-shoulder camera, aimed swings, dodge,
block), and everything you do feeds one character level and a skill tree you shape. The core loop (owner):
**loot the ruins and gather resources to build up the land you've claimed**, then hold it
through invasions and horde nights. There is no ending: the goal is survival, and **days
survived** is the score.

## Pillars
1. **A world that feels lived in.** People come back to their server to see whose walls held, what the night broke, what the neighbours built and which ruin is next, never to tick a daily chore. A long road of skills and gear, tedium never (see "The long road").
2. **Small, honest systems that stack.** Each week adds one system that works with the others. No feature ships half-built.
3. **Everything is grown, not imported.** Terrain, creatures, items, music, and sound come from code and seeds. The look is a consequence of that: **Emberlight**, painted low-poly with colour in the vertices and one shared shader, cheap enough for any laptop (see `docs/art_bible.md`).
4. **Survivors, together.** A server is a community of survivors, not a crowd. Surviving is better in a group: shared fires, a hold you build together, ruins you clear as a band, a friend dragged back from a Zombai pack. Strangers are a resource and a story before they are a threat. The Zombai and the land are the main enemy; how much players can hurt each other is a **server rule** (see "Server rules" in `docs/vision.md`), PvE by default.

## Owner directions (standing rules)
The owner plays and tests; the AI designs everything else. The owner has given the
directions below, and these are standing rules: they win over any other design choice, and
the weekly review and director may refine them but never reverse them. Everything not
covered here (systems, lore, balance, roadmap) stays the AI's call. Fun comes first and sits
above the numbered directions: when two choices both respect directions 1 to 9, pick the
more fun one. Direction 7 (a look of our own, cheap to draw) binds every visual change.

### Fun comes first (the first rule)
**If it isn't fun, it isn't worth shipping.** Fun is how we measure the North star. Every
change, in every stream, is judged first by one question: *does this make the game more fun
to play, right now, for a real player?* "Technically correct but boring" is not done.
What that means in practice:
- **Tight feedback.** Every player action answers within about 100 ms on the client: a
  sound, a motion, a flash, a number, a camera nudge. The server still decides the result;
  the client shows that the input landed at once and confirms or corrects it.
- **Short loops that pay off.** A new player gets a first reward (an item, a craft, a
  discovery) within about 60 seconds of spawning, and something new to want within about
  5 minutes. Every loop (gather, craft, explore, loot, fight, build) ends in a payoff the player
  can see, hear and use, and the payoff feeds the next loop.
- **Juice.** Hits, pickups and crafts get layered feedback: a hit reaction, particles, a
  pitch-varied procedural sound, a toast, the item flying into the pack. Make small things
  feel good before adding more things.
- **No dead time.** Avoid long walks with nothing to see, waits with nothing to do, empty
  menus and silent screens. If a player waits, give them something to watch or decide.
- **Clear goals, always.** The player should always know one thing they could do next and
  why it would be good.
- **Surprise and discovery.** Reward curiosity: a rare drop, a hidden spot, a creature doing
  something odd, the world changing at night, another survivor's camp in the woods.
- **Better together.** Doing something near another player should be more fun than doing it
  alone (shared node bonuses, group moments, seeing each other's effects). On a big server,
  meeting someone should be an event, not noise.
- **Fair and readable.** Never punish players for things they couldn't see coming. Lose
  little on failure; never lose a whole session's progress.
- **Long road, never tedium.** A long progression is wanted (direction 5, "The long
  road"); boring work is not. Busywork, chores and dead repetition don't ship. The test is
  per minute, not per month: every minute of play pays a little (XP you can see, a drop, a
  step closer to an unlock), and the next unlock is always in sight. If a system only works
  by making players repeat something dull with nothing showing for it, redesign it. A
  fifty-level tree is fine; a hundred clicks with no feedback is not.

How each stream applies it:
- **gameplay:** tune timings and rewards for pace (gather and craft times, drop rates,
  respawns, loot refills) and add the server events the client needs for feedback (hit, crit,
  rare drop, level-up). Prefer a rewarding loop over a deep but slow one.
- **world:** make places worth walking to: landmarks in view, something to find along every
  path, visible reactions (nodes shake, leaves fall, sparks fly), and a world that changes.
- **client:** responsiveness and juice: instant input feedback, animation, sound, camera
  feel, toasts and clear goals on screen. Never leave the player staring at nothing.
- **qa:** measure fun, not only correctness (see "Fun checks" below), and file "this feels
  slow or boring" as a bug with numbers. Measure the server at the size it is meant to hold.
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
- Server administration (kicks, bans, rule changes) is done through the server's own config
  and admin tools, never through player chat commands.
- New systems (crafting, combat, trade, building) are built UI-first. No "start with a chat
  command" shortcuts.
- On a server of up to 100, chat needs reach: nearby chat by default, with group and
  server-wide channels (see `docs/vision.md`, "Talking").

### 2. The camera feels like a modern third-person action game
The reference feel is the over-the-shoulder action camera of today's third-person action
games (the owner first pointed at New World's). We copy the *feel*, not anyone's code or
presentation:
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
- **Never through the ground**: the camera pulls in when terrain, trees, rocks or walls are in
  the way and eases back out. Indoors (ruins, your own hold) it pulls in tighter.
- **Look to interact**: the thing you interact with is what the reticle is on (within reach),
  falling back to the nearest one in reach. This is how gathering, looting and building pick
  their target.
- Settings: sensitivity, invert Y, field of view and shoulder side.

### 3. Gathering and looting feel like a modern action game
See "How gathering feels" below. The node you gather or the container you search is the one
under the reticle (direction 2). Nodes visibly empty and regrow, the gather and search bars and
motions are server-timed, and every gather or search ends with satisfying feedback: a hit
reaction or a lid that opens, a sound, a toast, and the item landing in your pack.

### 4. The whole game feels like a modern action game
Directions 2 and 3 give the camera, gathering and looting that feel; the owner wants the
*whole game* to have it. In our own design and our own names:
- **Action combat, not tab-target.** You aim with the reticle and swing; hits land where you
  aim. Light and heavy attacks, a block, and a dodge roll on a stamina bar. The Zombai and
  wildlife telegraph their attacks so a good player can read and avoid them (fair and
  readable). No auto-attack, no target lock required.
- **Weapons you made or found.** Weapons come from crafting and from ruins, never from a shop
  that sells power. Each weapon type plays differently, and the Fighting branch of the skill
  tree (direction 5) makes you better with the ones you choose.
- **Crafting is a path, not a menu.** Gathering, refining (wood to planks, stone and ore to
  bars) and crafting all pay XP, and a character who goes down the Crafting branch makes gear
  nobody else can. On a big server that makes crafters worth knowing and trading with.
- **Gear worth chasing.** Gear comes in tiers tied to material tiers and ruin grades, with some
  rolled variation so two crafts of the same item can differ. Better gear changes your
  silhouette (art bible section 3).
- **A world with places that matter.** Danger and reward rise with the ruin grades and with
  distance from the spawn coast (`docs/vision.md`, the map). There are no NPC towns; the
  places people meet are the ones players build.
- **Physical and grounded.** Weighty movement, readable animations, sound on every action,
  day and night that change what is out there.

### 5. The long road: one character, one skill tree (owner direction, 2026-11-25)
The owner: "instead of multiple skills there was just one skill tree for your character and
branches to go down." So a character has **one level and one skill tree**, not a list of
separately levelled skills. In our own design:
- **One level, from everything you do.** Every gather, craft, search, kill, wall raised and
  night survived pays **character XP**, shown as it lands. The XP curve is ours (never another
  game's table or formula) and lives in one data file: the first level in a minute or two,
  level 10 inside a first session, the cap (**level 50** to start) after weeks of regular play.
  A server may scale XP as a server rule; the curve stays one table.
- **One point per level, spent in the tree.** The tree has **five branches**, each a path you
  walk down:
  - **Survival:** needs drain slower, wounds heal faster, foraging and cooking yield more, the
    chill wears off sooner.
  - **Fighting:** stronger swings and blocks, more stamina, cheaper dodges, bows and crossbows,
    finishing moves on downed Zombai.
  - **Building:** stronger timber and stone, faster building and repairs, gates, traps and
    defences you can only build down this branch.
  - **Scavenging:** faster searches, better finds in ruins, quieter footsteps, more carry
    weight, opening locked chests.
  - **Crafting:** better tools and weapons, smithing and iron, potions and scrolls (direction
    on magic in `docs/vision.md`).
  Each branch starts with cheap, broad nodes and goes deeper into stronger, narrower ones; a
  node needs the one above it. There are far more nodes than points (about 80 nodes for 50
  points), so **a character can't take everything**: you choose what kind of survivor you are,
  and a band is better when its members go down different branches.
- **Every level unlocks something.** No empty levels: a level is a point to spend now, and the
  tree window always shows what your next point could buy and how far away it is. Some nodes
  unlock recipes and buildings outright, so the tree also gates content, softly. Nothing is
  gated behind payment, luck alone or a daily timer.
- **Level-ups are moments.** A level-up is the loudest bit of juice outside a fight: a sound,
  a burst of light around the character that others nearby see, a banner, and a nudge to spend
  the point.
- **Changing your mind.** A rare one-use scroll from ruins resets the tree, so a wrong turn is
  never permanent and never cheap.
- **No anti-fun limits.** No daily XP caps, no XP that shrinks the longer you play, no
  chores you must do every day to keep up. Being near other players should *add* XP
  (better together), never take it away.
- **The tree is kept through death** by default (fair failure); what death costs is a server
  rule (`docs/vision.md`).
- **Today's skills fold in, nothing is lost.** The four skills already on `main` (Felling,
  Quarrying, Tapping, Toolcraft) stop levelling separately: a character's saved skill XP is
  added up into their character XP once, with an add-only migration that keeps the
  old skills rows untouched (CLAUDE.md hard rules 1 and 6). The skills window becomes the tree
  window.

### 6. Take the best, then beat it
The owner's words: take other games' best features and improve on them, making them better
than their makers imagined. So before designing any system, ask: *which game does this best
today (survival sandboxes first, then any genre), what exactly makes it great, what do its
players complain about, and how do we keep the good part and fix the rest?* Write the answer
in a few lines in the PR or devlog. Then build **our own improved version**: our design, our
numbers, our names, our look. The aim is never "as good as" a reference; it is the version
players of that game would wish theirs had. Examples of the habit: action combat with clearer
telegraphs and less input lag than anyone's; a skill tree where no level is empty and every branch is a real choice; looting
that is quick and readable instead of a spreadsheet; base defence where you always know what's
coming; a server browser and rules screen that tells you exactly what kind of server you are
joining. This sits inside "Inspired by, never copied": study the feature, never copy its
expression.

### 7. A look of our own, cheap to draw
The owner asked for a unique art style in the stylized, painterly-realism family, made our
own, and built in the most efficient way possible for the server, the system and the bots.
That is **Emberlight**, written up in full in `docs/art_bible.md`. On 2026-11-24 the owner
played it and called the look "cheesy" and "silly", and asked for it to feel heavily inspired by
grounded survival-and-crafting games, as low poly, clearly our own, and legally safe. So
Emberlight is **grounded first**: read the art bible's section 0 (pillars) and section 11
(what reads as cheesy) before any visual change. In short:
- **Grounded painted low-poly:** real proportions (never chibi), muted earthy naturals (no
  lime, no candy colours), weathered materials, big confident facets; colour painted into
  vertices and gradients by one shared shader, never photographic textures.
- **Clear, sunny days and moody nights** (owner, 2026-11-25, approving the test-camp look): a
  clean blue sky and a strong sun with real shadows by day, no haze over the land; the mood
  comes from dawn, dusk and real night, and from the ruins and the Dimming.
- **Restraint:** effects, UI and colour stay quiet so the world carries the mood; level-ups
  are the one loud moment outside a fight and even they stay translucent.
- **Ember is the signature and the signal:** ember veins, a world-wide heartbeat pulse,
  leaves that never fall, rising motes. *If it glows ember, you can use it.* The dark layer
  is ours too: the Dimming, cold grey ash where the warmth has drained, and the Zombai who
  carry it.
- **Art costs the server and bots nothing:** they never build meshes, materials or
  textures, and art never changes the protocol. That matters more at 100 players per server.
- **Art has a budget in CI:** draw calls, triangles, materials and texture memory have
  ceilings and a 20% ratchet, and a screenshot style check flags drift. A crowd of players
  and a horde of the Zombai must fit the budget too.
Every world and client PR that changes what's on screen follows the art bible and keeps
inside the budget.

### 8. ZombAi: an open-world survival sandbox on servers of up to 100 (owner direction, 2026-11-25)
The owner set the direction in steps: not an MMO but a survival game in a post-apocalyptic
medieval fantasy setting (a fallen kingdom), a third-person camera, a one-time buy, the name
**ZombAi**, a generated map with risk-graded ruins, and, on 2026-11-25, "we are no longer making
a MMO, it will at most have maybe 100 player servers, like 7 Days or Project Zomboid". The full
design is `docs/vision.md`. Standing rules:
- **Servers, not a shard.** Each server is its own world for **up to about 100 players**
  (`MAX_PLAYERS`, 100 at most). Nothing is designed for more than one server's players at once:
  no global economy, no cross-server anything, no "thousands on one world".
- **Anyone can run a server.** The same authoritative headless server we run on Railway ships
  as a dedicated server anyone can host; the official always-on world is one of them and
  **must never break**. A Host button for a small group comes later on the same build.
- **Server rules decide the kind of server.** PvP, friendly fire, claim protection, loot
  refills, day length, Zombai difficulty, what death costs, and the map's seed and size are
  server rules, shown to a player before they join. The defaults are PvE and forgiving.
- **A generated kingdom with graded ruins.** Every server's world from a seed; hand-designed
  ruins placed by the generator, each graded by danger and loot; the map's size scales with the
  player cap.
- **Our own undead.** The Zombai are original (kinds, behaviour, the chill, ember burns them),
  never another game's zombies.
- **Accessible and action-heavy, not brutal:** quick to learn, good in a 30-minute session,
  visible and explained dangers, moments worth clipping. Harder is a server rule, never the
  default.
- **A one-time buy.** Never sell power, safety or progress. Running a server costs nothing
  extra.
- **Nights come in rounds,** and the big horde night is **the Tolling**, triggered by a base's
  threat, never by a calendar, and aimed at a base, never at the whole server. Magic is a light
  touch from loot.
- **The goal is survival.** No story endgame. The heart of it is base building, getting invaded at
  your base, and looting toward upgrades and vehicles (horses, carts, boats).

### 9. The basics first (owner direction, 2026-11-25)
The owner, tuning each worker one at a time: "we need to start with the basics: character
customization and zombie survival, with a randomly generated map and landmarks and stuff for loot."
Until those four work end to end in a real session, they come before any polish, in every stream:
1. **Character customization** on the sculpted body (art bible section 3): every saved
   Appearance choice shows on the new body, and a new player picks a look before they play.
2. **Zombie survival:** the Zombai walker on screen and in the fight, hunger and the first night.
3. **A generated map:** every world from a seed (Phase 1), big enough to explore and fast to load.
4. **Landmarks with loot:** ruins you can see from a distance, walk to, and search for loot
   that is worth the walk (crates, chests, bodies, graded by the ruin).
Polish of something that already works (extra effects, follow-up tuning, the old Ashgrove map)
waits until these four are playable. A worker with nothing left on the basics in its own area
fixes bugs or builds tests for the basics before it polishes.

### Studio intro (owner direction, 2026-11-23)
The owner supplied the **Budda Games** intro video and asked for it to replace Godot's boot
splash. It is the studio's own logo, so it is the one owner-supplied asset in the client and an
owner-approved exception to CLAUDE.md hard rule 3 (procedural art): it lives only at
`game/client/intro/budda_games_intro.ogv`, ships in client builds only, and nothing else may be
imported on its back. It plays once on each normal launch, any key, click or pad button skips
it, automated runs skip it, and the engine splash is off with the video's background colour.

### Inspired by, never copied
We borrow genre mechanics and feel only. Mechanics and feel are free for anyone to use; the
expression of another game is not. So, always:
- **No names** from any existing game: no place, faction, character, creature, item, skill,
  resource or system names, and no near-misses or puns on them. That includes the survival
  games we take feel from: no "blood moon", no named zombie types, no named traits or
  occupations from them.
- **No lore, story, quests, dialogue or text** taken from or closely retelling another game.
- **No art, models, icons, UI layouts or HUD look, fonts, music or sounds** from another game,
  and none made to look like them. Ours are procedural (CLAUDE.md hard rule 3) and use our
  own palette, so they look like the fallen kingdom and nothing else.
- **No exact systems.** We may want "a big horde night" or "a map with risky monuments"; we
  never copy another game's numbers, tables, calendars, skill lists, trait systems or menu flow.
- **No logos, trademarks or marketing lines**, and never say ZombAi is related to, approved by,
  or "the new version of" another game. Patch notes, in-game text and the store page name no
  other game.
- Inside design docs it is fine to say which game's *feel* inspired a direction; player-facing
  text never does.
When unsure whether something is too close, make it more ours: ember and ash, the Dimming, the
Zombai, a medieval kingdom gone quiet.

## The world: a fallen kingdom
The kingdom died when the Dimming rose: a twilight that drained the warmth out of the land and
got into its dead. They rose as **the Zombai**. What still holds the Dimming back is the
**ember**: the warm, glowing sap of the ember ash trees, and the fire it makes. The kingdom's
lore (why the Dimming rose, what lies under the old castle, what the ember can still do) is
told through the ruins, never as a quest line you must finish.

**Ashgrove**, the 512 m valley the game started in, is the live test world (generator version 0,
`WORLD_SEED = 20261127` in `game/shared/terrain.gd`). Its ember ash trees, the heartbeat pulse
and the sleeping warmth under the valley become the kingdom's: the ember is that warmth, and
the Dimming is what drains it. The live world moves to a generated map in one announced step
(`docs/vision.md`); after that every server's world gets its own seed, and a saved character
always loads into its own world.

### Tone
Quiet, weathered, a little dangerous, with warmth in the people. Patch notes and in-game text
are friendly and a bit wry. Grim where the ruins are, never grimdark for its own sake, never
sugary.

## Art direction
The full art bible is `docs/art_bible.md` (**Emberlight**, owner direction 7). The essentials:
- **Painted low-poly.** Terrain cells are 4 m. Props use 5 to 8 radial segments, flat-shaded with gradients across the faces. Colour comes from vertex colours and one shared shader, with only the small `SurfaceTex` brightness detail as images made in code.
- **Clear sunny days, moody nights.** A clean blue sky and a strong warm sun with real shadows by day, no haze over the land; rose dawns and dusks; navy, moonlit nights where ember carries the colour. `EMBER` gold is reserved for what you can use. The palette lives in `game/procgen/palette.gd`; new content picks from it or extends it there.
- **Characters** are one sculpted body, grounded adults with real proportions; their look comes from the character creator (body, skin, hair, face, cloth). Gear changes silhouettes. The Zombai use the same body in the ash-cold palette.
- **Sound** is synthesised: soft sine chimes for UI and chat now; later, procedural ambient music keyed to time of day, biome and danger.

## Core systems (current)
- **Accounts and characters:** one character per account per world for now, named after the account, with a saved appearance. Passwords are salted PBKDF2-SHA256.
- **Movement:** server-authoritative walking at 6 m/s on the shared height field. Clients send input direction only.
- **Chat:** one global channel, 200 characters, 0.5 s cooldown. Talking only (owner direction 1). Nearby, group and server channels come before the live cap goes past the low tens.
- **Persistence:** position and facing saved on logout, every 30 s, and on shutdown.
- **Player cap:** `MAX_PLAYERS` (8 on the live world today); a full server says so politely and never kicks anyone.

### How gathering feels (owner direction, 2026-11-22)
Gathering works the way players already know from today's action and survival games, never through chat commands:
1. Walk up to a tree, rock or seep and look at it. When one is in reach and under the reticle (or, failing that, the nearest in reach) it is softly highlighted and a prompt shows its action and key, e.g. "[E] Chop Ember Ash".
2. Press the interact key (E) or click the node. Your character turns to it and plays a looping gathering motion (chop, strike, scoop), with matching procedural sound.
3. A short gather bar fills (about 2 s, set by the server). Moving, jumping or pressing E again cancels it; nothing is lost.
4. When it fills, the item pops into your pack: a "+1 Ash wood" toast, a small chime, and the pack updates at once.
5. Each node gives a few gathers, then visibly empties (stump, rubble, dry seep) for everyone nearby and grows back later.
6. Other players see you gathering. Several players can work the same node; each gather takes one charge.
Searching a crate, chest or body in a ruin works the same way (look, E, a short search bar, the loot lands in your pack). The server times the bar and decides the result; the client only shows it. `/gather` stays as a hidden debug and bot command, not listed in `/help` or patch notes. We borrow the genre's mechanics only: no names, art, UI or sounds from any existing game.

## Core systems (planned order)
The phases and what "done" means for each are in `docs/roadmap.md`. In short, after the
foundations (gathering, crafting, skills and XP, the action camera and combat basics), and with
the basics first (direction 9):
1. A kingdom from a seed: the generator, roads, ruin sites, chunked building
2. Survive the first night: needs, fire and cooking, the Zombai, death and loot
3. A roof and a wall: claimed land, building, the ember hearth, invasions and horde nights
4. Into the ruins: all four grades, signet keys, smithing, bows, ember weapons
5. Servers for up to 100: interest management, chat channels, server rules, the dedicated
   server download, a server list
6. Launch-ready: the first hour, settings, a store build
7. Depth, ongoing
The goal is survival, with no story endgame (owner, 2026-11-24).

## Technical principles
- The server is authoritative for everything that matters. Clients render and request.
- The world is deterministic from the seed, so the server never streams terrain; it sends the world's seed.
- **Built for 100 on one server.** A client only hears about what is near it (interest
  management by distance, about a 150 to 200 m bubble), the Zombai are simulated in full only near
  players, and anything per-player-per-tick is budgeted for 100. The live cap only goes up after
  a load test at that number passes (`docs/vision.md`, "Getting to 100").
- Database changes are add-only migrations. Every stored field has a default in `CharacterData` so old saves always load.

## Revision history
- **Week 01 (2026-11-25, types confirmed, no traders):** The owner accepted the third round as proposed: the Zombai types list (walker, sprinter, brute, soldier, hound, dragger, Bell-wight, rotbelly, your risen body) is confirmed; no computer-run traders at launch, players trade through a trade window; groups stay **bands**; nights in rounds and the Tolling stay as written.
- **Week 01 (2026-11-25, the Zombai, their types, your risen body, the coast):** The owner's second round of answers. The undead are renamed from the Gloam to **the Zombai** (player-facing everywhere; code names such as `gloam.gd` may stay until a worker renames them safely). Zombai are few in the open by day, thick around ruins and in packs at night. There are **types** (a draft list in `docs/vision.md`: walker, sprinter, brute, soldier, hound, dragger, Bell-wight, rotbelly, your own risen body), with sprinters one of them. When you die **your body rises** as a Zombai carrying the items you dropped. The map has one coast where everyone lands by boat, and mountains and the Dimming's grey wall on the other sides, with danger rising inland. Older entries below keep the old name as history.
- **Week 01 (2026-11-25, one skill tree, light deaths, potions):** The owner answered the first round of questions on fitting the docs to the survival game: "just one skill tree for your character and branches to go down", "you should just lose a couple items in your bag on death", "magic like health potions and stamina potions and one-use scrolls", and no backgrounds. Direction 5 is now one character level (cap 50 to start) and one skill tree with five branches (Survival, Fighting, Building, Scavenging, Crafting), more nodes than points so characters specialise, a rare scroll to reset; today's four skills fold into character XP through an add-only migration. Death drops two or three random stacks in a sack where you fell and keeps the rest and the tree (the "What death costs" server rule now offers that, the whole pack, or hardcore). Magic is health and stamina potions and one-use scrolls; runes in walls and enchanting relics are dropped. Character creation is looks only.
- **Week 01 (2026-11-25, survival servers, not an MMO):** The owner, after reviewing the art bible: "We need the bible redone. We are no longer making a MMO, it will at most have maybe 100 player servers. Like 7 days or project zomboid." Rewrote the North star, the vision paragraph and pillar 4 (survivors together; PvE by default, PvP a server rule), and replaced direction 8's "2 to 8 friends in co-op" with servers of up to about 100 players that anyone can run, shaped by server rules shown before you join. Directions 2 to 6 keep their meaning but drop the MMO framing (the reference is now modern third-person action games and survival sandboxes); direction 3 adds looting to gathering; direction 5 makes what death costs and XP rate server rules. Direction 7 now says clear sunny days with no haze (the owner approved the test-camp look on 2026-11-25), and the art bible's lighting follows. "The world" is now the fallen kingdom, with Ashgrove as the live test world. Phase 5 becomes "Servers for up to 100", and the technical principles add interest management and a load test before the live cap rises. Direction 9 (the basics first, PR #220) is unchanged. `docs/vision.md`, the art bible's framing, the roadmap and CLAUDE.md follow. The design forks this opened (PvP, the cap path, map size, claims, loot refills, wipes) are settled with a recommendation in `docs/vision.md`, "Server rules", until the owner says otherwise; the owner then chose PvP's: PvE by default, PvP a server option.
- **Week 01 (2026-11-25, the basics first):** The owner asked to start with the basics: character customization, zombie survival, a randomly generated map, and landmarks with loot. Added owner direction 9: those four come before polish in every stream, and each worker's backlog was cut down to them (world first, 2026-11-25).
- **Week 01 (2026-11-24, model direction):** The owner saw the sculpted test-camp characters ("this is a way better start", "needs polishing") and asked to fine-tune the models and give them direction. The art bible's "Characters" section is now the model direction: one continuous sculpted body on the same 18-bone skeleton instead of segment meshes, build as a single `bulk` number, readable faces (full jaw, painted eyes and brows, real beards, clean hairline), clothing as proud layers with straight hems at set heights, four reference archetypes (woodcutter, scout, elder, smith), and a new per-character cost of 1 draw call and at most 5,000 triangles, cached at build. The old per-character limit (6 draw calls, 3,000 triangles) is replaced because one skinned mesh costs far fewer draw calls. The in-game body follows as its own PR.
- **Week 00 (2026-11-24, ZombAi):** The owner said they weren't sure an MMO was the right call. Over the evening they moved to a survival game in the spirit of Project Zomboid, with a map that works like Rust's (generated land, roads and risk-graded ruins), a post-apocalyptic medieval fantasy setting (a fallen kingdom), a third-person camera, a one-time buy, the name ZombAi, and 2 to 8 player co-op hosted by a friend; an intermediate draft with 48-player servers, faction land claims and seasons was dropped to "later, maybe". Rewrote the North star, the vision paragraph and pillars 1 and 4 (co-op PvE, not opt-in PvP between strangers), added owner direction 8, replaced the planned order with phases, and made seeds per world. Kept everything that carries over: fun first, chat is for talking, the action camera, gathering, the long road of skills, take the best and beat it, the grounded art direction and its budgets, and "Inspired by, never copied". Ashgrove's ember lore becomes the fallen kingdom's. The goal is pure survival; the heart of it is base building, getting invaded, and looting toward upgrades and medieval vehicles (horses, carts, boats). Later the same evening: a days-survived counter, horde nights of our own (not a fixed-calendar blood moon), the name "Hollows" dropped (the undead are now **the Gloam**, the owner's pick), and the core loop of looting and gathering to build up claimed land. Finally the owner gave the reference (Project Zomboid + 7 Days to Die in a medieval fantasy setting, with rounds of survival at night and base defence) and asked the director to pick the rest: nights are fought in rounds, the big horde night is the Tolling (threat-triggered, never on a calendar), and magic is a light touch from loot (runes as wall wards, relics, single-use scrolls).
- **Week 01 (2026-11-24, less blocky, low-res look):** The owner asked for characters "less blocky and more low res actual", and for animations. The art bible now adds **low-res paint** to Emberlight: organic low-poly shapes (smooth lofted bodies, never boxes) and a procedural texel grain in the shared shader that makes every surface read like a low-resolution painted texture with nearest-neighbour filtering, without any texture files. The light bands were widened so rounded shapes shade smoothly. Characters were rebuilt from smooth lofts, with separate upper and lower limb pieces ready for a skeleton. Animation (a skinned skeleton and a full set of weighty moves) is its own piece of work and builds on this.
- **Week 01 (2026-11-24, character overhaul):** The owner said "our dudes look fat and silly". The art bible's "Characters" section now sets lean, grounded adult proportions (about 7 heads, 1.78 m, shoulders wider than hips, long legs, hands to mid-thigh), a back-first silhouette of layered survival gear (hood or hair, wool mantle, framed pack and bedroll, belt with pouch and knife, chest strap, bracers, tall boots), gear colours in the palette, and a per-character cost (5 merged meshes, 5 draw calls). `AvatarBuilder` was rebuilt to match. This replaces the earlier plan of 6 heads with gear in Milestone 3: characters are adult-proportioned now, and gear grows from these layers.
- **Week 01 (2026-11-24, grounded art direction):** The owner said the current style "is cheesy and looks silly" and asked for the game to feel heavily inspired by the genre of their favourite MMO (New World): a grounded, moody survival-and-crafting MMO, done as low poly, with a style clearly our own and without legal trouble. Direction 7 now says Emberlight is **grounded first**, and `docs/art_bible.md` was rewritten around that: five pillars (grounded before cute, mood from light, earth first and ember rare, weathered, restraint), palette saturation and value rules, light by time of day, character proportions (toward 6 heads, never chibi, no wizard hats), materials, UI tone, effects restraint, a sharper legal "inspired by, never copied" list, and a named list of what read as cheesy with its status. A first pass fixed the worst of it: olive and straw grass instead of lime, rust two-lobed ash crowns on thicker trunks instead of candy lollipops, earthy cloth, hoods and hair instead of cyan tunics and wizard hats, a smaller head, a dusty sky and a whole-frame grade, moonlit-blue night fill, and a translucent level-up column. The performance rules and CI budgets are unchanged.
- **Week 00 (2026-11-23, studio intro):** The owner uploaded the Budda Games intro video and asked for it to play instead of the Godot boot splash. Added "Studio intro" under the owner directions, recording it as the single owner-approved exception to the procedural-art rule (client builds only, one file), so the integrator does not revert it and nobody reads it as permission to import other assets.
- **Week 00 (2026-11-23, art style):** The owner asked how to make the art style unique, in the stylized or painterly realism family of their favourite modern MMO, and then for it to be done in the most efficient way for the server, the system and the bots. Added owner direction 7 and `docs/art_bible.md`: the **Emberlight** style (painted low-poly, colour in vertices and one shared shader, warm light and cool shadows, ember as signature and gameplay signal, the Dimming as our own dark layer, a concrete "what to avoid" list so we never copy), and performance as part of the style (server and bots never touch art, instancing chunked for culling, distance LODs, few lights, pooled effects, no expensive screen effects, quality tiers, and CI-enforced render budgets with a 20% ratchet plus a screenshot style check). Pillar 3 now names the style instead of "flat-shaded, colourful". Nothing already built changes meaning; existing props move onto the shared shader over the next world runs.
- **Week 00 (2026-11-23, vision and roadmap):** The owner gave the game its direction: the New World feel for the whole game (not only the camera and gathering), the RuneScape-style long skill grind, and the goal of beating every other MMO, built by the owner and AI together. Added "The vision in one paragraph" and the core loop (gather → craft → fight → level up → explore further), owner directions 4 (the whole game feels like a modern action MMO), 5 (the long road: many skills to level 100, every level unlocks something) and 6 (take the best, then beat it: study the best version of each feature in other MMOs and build an improved, original one). Reconciled grind with fun: pillar 1 and the old "Cut boring work" bullet become "Long road, never tedium", judged per minute (every minute pays a little, the next unlock is always in sight), so a long grind is wanted and tedium still never ships. The planned order of systems is now the milestone list in `docs/roadmap.md`. "Inspired by, never copied" applies to both reference games: no skill names, XP tables or exact systems from either.
- **Week 00 (2026-11-23, fun first):** Added "Fun comes first" at the top of the owner directions. The owner said the number one way to make the greatest MMO is to make it fun, and if it isn't fun it isn't the best. Turned that into concrete guidance (tight feedback, short loops that pay off, juice, no dead time), a lens for each stream, a "Why it's more fun" line on every worker PR, and bot-test fun metrics in qa. Directions 1 to 3 (chat is for talking, the action camera, how gathering feels) and "Inspired by, never copied" are unchanged.
- **Week 00 (2026-11-22, owner directions):** Added "Owner directions": chat is for talking only (slash commands move to keys and windows, debug commands only behind `--dev-commands`), an over-the-shoulder action camera with always-on mouse look and camera-relative movement, gathering that targets what the reticle is on, and an "Inspired by, never copied" section. The owner loves how New World's camera and gathering feel and asked for that feel, while the AI keeps designing everything else; the guardrails keep us to mechanics and feel, never names, lore, art, UI or text.
- **Week 00 (2026-11-22, gathering feel):** Added "How gathering feels". The owner disliked typing `/gather` and pointed at mainstream MMOs as the model, so gathering becomes walk up, prompt, press E or click, timed gather bar with animation, item toast, and visibly emptied nodes. `/gather` is kept only as a debug fallback.
- **Week 00 (follow-up):** Added the owner's north star, "Make the Greatest MMO of all time", above the pillars so every weekly session measures its choices against it.
- **Week 00:** First version. Defined the pillars, Ashgrove, the art direction, and the planned order of systems. Chose WebSocket as the production transport on Railway (see devlog week 00) while keeping ENet for direct/LAN play; both use Godot's high-level multiplayer API.
