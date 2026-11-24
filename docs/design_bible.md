# AiMMO Design Bible

This is the AI-owned vision for AiMMO. It may evolve, but every change is logged in the
Revision history at the bottom with its reason, so the game does not flip-flop.

## North star
**Make the survival game friends pick for their evenings, and that people love to watch.** Owner direction, 2026-11-24 (draft): the game is **ZombAi**, a third-person survival game in a fallen medieval kingdom, played in co-op by 2 to 8 friends, sold as a one-time buy, and made for mass appeal (`docs/vision.md`). The number one way there is still to make it **fun**: if it isn't fun, it isn't worth shipping (see "Fun comes first"). When two options compete, pick the one that is quicker to learn, better in a 30-minute session with friends and more worth sharing, and never trade working and stable for big and flashy (CLAUDE.md hard rule 5). (Until 2026-11-24 this was "the Greatest MMO of all time"; the skills, camera, combat and art built for it all carry over.)

### The vision in one paragraph (owner direction, 2026-11-24, draft)
A kingdom fell when the Dimming rose, and its dead got back up as the **Hollows**. Each world is
a freshly generated stretch of that kingdom (forests, moors, rivers, the old king's roads, and
ruins graded by how much they can kill you and how much they pay) that one player hosts for 2 to
8 friends. You arrive with nothing; you eat, drink, keep warm and tend wounds; you learn that
noise brings the Hollows and ember-fire burns them; you build a hold together and hold it through
the darkest nights; and you push into deadlier ruins for the gear to push further. In your hands
it is an action game (the over-the-shoulder camera, aimed swings, dodge, block) with gathering
and crafting as real skills that level by doing. The full design is `docs/vision.md`. The core
loop: **gather → craft → build → survive the night → raid the ruins → get stronger**.

## Pillars
1. **A world that feels lived in.** Friends come back to their world to see whose walls held, what the night broke and which ruin is next, never to tick a daily chore. A long road of skills and gear, tedium never (see "The long road").
2. **Small, honest systems that stack.** Each week adds one system that works with the others. No feature ships half-built.
3. **Everything is grown, not imported.** Terrain, creatures, items, music, and sound come from code and seeds. The look is a consequence of that: **Emberlight**, painted low-poly with colour in the vertices and one shared shader, cheap enough for any laptop (see `docs/art_bible.md`).
4. **Together first.** Surviving is better with friends: shared fires, a hold you build together, ruins you clear as a group, a friend dragged back from a Hollow pack. The game is co-op PvE; friendly fire is a host setting, off by default.

## Owner directions (standing rules)
The owner plays and tests; the AI designs everything else. The owner has given the
directions below, and these are standing rules: they win over any other design choice, and
the weekly review and director may refine them but never reverse them. Everything not
covered here (systems, lore, balance, roadmap) stays the AI's call. Fun comes first and sits
above the numbered directions: when two choices both respect directions 1 to 8, pick the
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
- **Long road, never tedium.** A long progression is wanted (direction 5, "The long
  road"); boring work is not. Busywork, chores and dead repetition don't ship. The test is
  per minute, not per month: every minute of play pays a little (XP you can see, a drop, a
  step closer to an unlock), and the next unlock is always in sight. If a system only works
  by making players repeat something dull with nothing showing for it, redesign it. A
  hundred-level skill is fine; a hundred clicks with no feedback is not.

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

### 4. The whole game feels like a modern action MMO
Directions 2 and 3 give the camera and gathering that feel; the owner wants the *whole game*
to have it, with New World as the reference feel. That means, in our own design and our own
names:
- **Action combat, not tab-target.** You aim with the reticle and swing; hits land where you
  aim. Light and heavy attacks, a block, and a dodge roll on a stamina bar. Enemies telegraph
  their attacks so a good player can read and avoid them (fair and readable). No auto-attack,
  no target lock required.
- **Weapons you made.** Weapons come from crafting, not from vendors. Each weapon type plays
  differently and has its own mastery that levels by using it, with choices to make as it
  levels.
- **Trade skills are real skills.** Gathering, refining (wood to planks, stone and ore to
  bars) and crafting are each skills with levels, and high-level crafters make gear nobody
  else can. Crafting is a reason to play, not a menu between fights.
- **Gear worth chasing.** Gear comes in tiers tied to material tiers and zones, with some
  rolled variation so two crafts of the same item can differ. Better gear changes your
  silhouette (art direction: "later, gear changes silhouettes").
- **A world with places that matter.** Zones get harder as you go out from the Spawn Meadow
  and hold better materials. Towns are where you trade, craft at better stations and meet
  people. Territory is bands and claims (`docs/vision.md`, pillar 4).
- **Physical and grounded.** Weighty movement, readable animations, sound on every action,
  day and night that change what is out there.

### 5. The long road: skills that grind well
The owner loves the long skill grind of the classic skill MMOs (RuneScape is the owner's
reference) and wants it here, made fun by the rules above. In our own design:
- **Many skills.** Every activity is a skill: each kind of gathering, each refining craft,
  each crafting discipline, each weapon, and later things like cooking. Start small (four in
  Milestone 1) and add skills as systems arrive; never retire one.
- **A high cap, levelled over months.** Each skill runs to **level 100**. The XP curve is ours
  (do not reuse another game's table or formula): the first levels come in a minute or two,
  level 10 inside a first session, level 50 after weeks of regular play, 100 is a long-term
  badge of honour. Keep the curve's numbers in one data file so they can be tuned.
- **Every level unlocks something.** No empty levels. Each level gives a small visible gain
  (a bit faster, a bit more yield, a better chance at a rare find). Every few levels gives a
  named unlock: a new node tier you can now work, a recipe, a perk, an ability, a cosmetic
  (tool glow, a title). The skills window always shows the next unlock and how far away it is.
- **Level-ups are moments.** A level-up is the loudest bit of juice in the game: a sound, a
  burst of light around the character that others nearby see, a banner naming what you just
  unlocked.
- **Your levels gate content, softly.** Higher-tier nodes, recipes and zones ask for levels,
  so the grind opens the world. Nothing is gated behind payment, luck alone or a daily timer.
- **No anti-fun limits.** No daily XP caps, no XP that shrinks the longer you play, no
  chores you must do every day to keep up. Being near other players should *add* XP
  (better together), never take it away.
- **A total across skills.** The character panel shows a combined total of every skill's
  level, so an all-rounder has something to show too. (Pick our own name for it.)

### 6. Take the best, then beat it
The owner's words: take other MMOs' best features and improve on them, making them better
than their makers imagined. So before designing any system, ask: *which MMO does this best
today, what exactly makes it great, what do its players complain about, and how do we keep
the good part and fix the rest?* Write the answer in a few lines in the PR or devlog. Then
build **our own improved version**: our design, our numbers, our names, our look. The aim is
never "as good as" a reference; it is the version players of that game would wish theirs
had. Examples of the habit: action combat with clearer telegraphs and less input lag than
anyone's; a skill grind where no level is empty; crafting where a master's work is visibly
better; a market that is easy to use and hard to exploit. This sits inside "Inspired by,
never copied": study the feature, never copy its expression.

### 7. A look of our own, cheap to draw
The owner asked for a unique art style in the stylized, painterly-realism family of their
favourite modern MMO (moody golden light, a dark supernatural layer), made our own, and
built in the most efficient way possible for the server, the system and the bots. That is
**Emberlight**, written up in full in `docs/art_bible.md`. On 2026-11-24 the owner played it
and called the look "cheesy" and "silly", and asked for it to feel heavily inspired by the
grounded survival-and-crafting MMO genre (New World is their reference), as low poly, clearly
our own, and legally safe. So Emberlight is **grounded first**: read the art bible's
section 0 (pillars) and section 11 (what reads as cheesy) before any visual change. In short:
- **Grounded painted low-poly:** real proportions (never chibi), muted earthy naturals (no
  lime, no candy colours), weathered materials, big confident facets; colour painted into
  vertices and gradients by one shared shader, never photographic textures. Warm light, cool
  blue shadows, a moody day that spends most of its time in low golden light.
- **Restraint:** effects, UI and colour stay quiet so the world carries the mood; level-ups
  are the one loud moment and even they stay translucent.
- **Ember is the signature and the signal:** ember veins, a valley-wide heartbeat pulse,
  leaves that never fall, rising motes. *If it glows ember, you can use it.* The dark layer
  is ours too: the Dimming, cold grey ash where the warmth has drained.
- **Art costs the server and bots nothing:** they never build meshes, materials or
  textures, and art never changes the protocol.
- **Art has a budget in CI:** draw calls, triangles, materials and texture memory have
  ceilings and a 20% ratchet, and a screenshot style check flags drift.
Every world and client PR that changes what's on screen follows the art bible and keeps
inside the budget.

### 8. ZombAi: survive a fallen kingdom with friends (owner direction, 2026-11-24, draft)
The owner changed the game's direction, in steps on one evening: not an MMO but a survival game
in the spirit of Project Zomboid, then a map that works like Rust's, a post-apocalyptic medieval
fantasy setting, a third-person camera, a one-time buy, the name **ZombAi**, and finally **2 to
8 player co-op** hosted by a friend. The full design is `docs/vision.md`. Standing rules:
- **Co-op first.** 2 to 8 friends; PvE against the Hollows and the land. For now that is today's always-on Railway world, capped at 8, which must never break; hosting from the client comes later. Public
  servers, raiding and seasons are a "later, maybe" only.
- **A generated kingdom with graded ruins.** Every world from a seed; hand-designed ruins placed
  by the generator, each graded by danger and loot.
- **Our own undead.** The Hollows are original (kinds, behaviour, the chill, ember burns them),
  never another game's zombies.
- **Accessible and action-heavy, not brutal:** quick to learn, good in a 30-minute session,
  visible and explained dangers, moments worth clipping.
- **A one-time buy.** Never sell power, safety or progress.

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
- The world is generated from `WORLD_SEED = 20261127` in `game/shared/terrain.gd` and `game/procgen/`. This seed stays permanent for today's live test world (generator version 0). Under ZombAi every world gets its own seed from the host (`docs/vision.md`); a saved character always loads into its own world.

### Tone
Warm, curious, slightly melancholy. Patch notes and in-game text are friendly and a bit wry. Nothing grimdark, nothing sugary.

## Art direction
The full art bible is `docs/art_bible.md` (**Emberlight**, owner direction 7). The essentials:
- **Painted low-poly.** Terrain cells are 4 m. Props use 5 to 8 radial segments, flat-shaded with gradients across the faces. Colour comes from vertex colours and one shared shader, not textures.
- **Golden late-afternoon palette.** Warm light, cool blue shadows, orange ash leaves, and `EMBER` gold reserved for what you can use. The palette lives in `game/procgen/palette.gd`; new content picks from it or extends it there.
- **Characters** are rounded wanderers today, growing toward grounded proportions when gear arrives. Their look comes from an appearance seed: tunic hue, skin tone, headwear. Later: gear changes silhouettes.
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
The phases and what "done" means for each are in `docs/roadmap.md`. In short, after the
foundations (gathering, crafting, skills and XP, the action camera and combat basics):
1. A kingdom from a seed: the generator, roads, ruin sites, chunked building
2. Survive the first night: needs, fire and cooking, the Hollows, death and loot
3. A roof and a wall: building, the ember hearth, night sieges
4. Into the ruins: all four grades, signet keys, smithing, bows, ember weapons
5. Play with friends: hosting, invites, saved worlds
6. Launch-ready: the first hour, settings, the rename, a store build
7. Depth, ongoing
The ember mystery becomes the fallen kingdom's: why the Dimming rose, and what the ember can
still do (the long-term goal is still being asked).

## Technical principles
- The server is authoritative for everything that matters. Clients render and request.
- The world is deterministic from the seed, so the server never streams terrain; it sends the world's seed.
- Database changes are add-only migrations. Every stored field has a default in `CharacterData` so old saves always load.

## Revision history
- **Week 00 (2026-11-24, ZombAi, draft):** The owner said they weren't sure an MMO was the right call. Over the evening they moved to a survival game in the spirit of Project Zomboid, with a map that works like Rust's (generated land, roads and risk-graded ruins), a post-apocalyptic medieval fantasy setting (a fallen kingdom), a third-person camera, a one-time buy, the name ZombAi, and 2 to 8 player co-op hosted by a friend; an intermediate draft with 48-player servers, faction land claims and seasons was dropped to "later, maybe". Rewrote the North star, the vision paragraph and pillars 1 and 4 (co-op PvE, not opt-in PvP between strangers), added owner direction 8, replaced the planned order with phases, and made seeds per world. Kept everything that carries over: fun first, chat is for talking, the action camera, gathering, the long road of skills, take the best and beat it, the grounded art direction and its budgets, and "Inspired by, never copied". Ashgrove's ember lore becomes the fallen kingdom's. Still being asked: magic, how the undead behave in detail, and the long-term goal.
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
