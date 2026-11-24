# ZombAi: vision

**Draft owner direction, 2026-11-24. Not adopted yet.** While this is in an open draft PR, workers
keep following `main`. The owner has settled the name, setting, camera, price, map style and
**2 to 8 player co-op**. A few things are still being decided (section "Still open"). Every
stream reads this file once it lands; `docs/roadmap.md` holds the phases.

Everything here is our own design under "Inspired by, never copied" (design bible). The feel
we're reaching for: the deep survival sim of *Project Zomboid*, the procedural map full of
risk-graded monuments of *Rust*, and the friends-together co-op of the best small-group survival
games. All of it is made quicker to learn and readable on a stream. Those names stay in design
docs, never in the game.

## The game in one paragraph
**ZombAi** is a third-person survival game set in a **fallen kingdom**. The kingdom died when the
Dimming rose, and its dead got back up as **the Gloam** (owner's name, 2026-11-24): the
kingdom's dead, filled with the Dimming's twilight. Each world is a freshly generated
stretch of that kingdom: forests, moors, rivers, the old king's roads, and the **ruins**
(burned farmsteads, a drowned village, mines, abbeys, and a castle at the heart of it). Each ruin
is graded by how much it can kill you and how much it pays. You arrive with nothing. You eat,
drink, keep warm, bandage what bleeds, and learn that noise brings the Gloam and **ember-fire
burns them**. With your friends you **claim a piece of land** and build it up from a lean-to to
a walled hold, with what you **gather** and what you **loot** from richer and deadlier ruins. On
**horde nights** the Gloam come in numbers for the holds that have grown loud, bright and rich. A
counter keeps score: **days survived**. There is no ending: the goal is to survive, build and
grow stronger for as long as you like. It's played with **2 to 8 friends** in a shared world:
for now the always-on server, later one a friend hosts.

## The heart of it (owner, 2026-11-24)
**The goal is survival.** No story ending, no final boss to beat: a world is a sandbox you keep
alive in for as long as you like, and **days survived** is the score. The core loop (owner,
2026-11-24): **loot the ruins and gather resources to build up the land you've claimed.** What
the owner loves most, and what every phase serves:
1. **Base building.** A hold that grows from a lean-to to a walled keep, with real choices about
   where to build, what to wall and what to upgrade.
2. **Getting invaded.** The Gloam come for your base, and the bigger, louder and richer it gets,
   the bigger the invasions: a few stragglers at first, then **horde nights**, then rare great hordes
   with soldiers and wights that test every wall and gate. Holding the walls with friends is the
   game's signature moment.
3. **Looting toward upgrades.** Every ruin trip brings back parts for something better: stronger
   walls and gates, better tools and weapons, armour, workshops, traps and defences.
4. **Vehicles, medieval style.** Earned through looting and building: a **horse** (found wild or
   in ruined stables, tamed, fed and stabled), a **cart** to haul big loads, and **boats** for
   rivers, lakes and the coast. Each opens more of the map and bigger ruin runs.

## Settled (owner, 2026-11-24)
- **Name: ZombAi.** The repo, app and builds are renamed later (section "Rename plan"). The
  player-facing name changes when the rename ships, not before.
- **Setting: post-apocalyptic medieval fantasy.** A kingdom that fell, not a modern city: swords,
  axes, bows, crossbows, lanterns, carts, stone keeps, chapels. The grounded art direction stays
  as it is (`docs/art_bible.md`: muted, weathered, real proportions, moody light). The Dimming
  and the ember are the kingdom's ruin and its last hope.
- **Camera: third person.** The over-the-shoulder action camera already on `main` stays.
- **Price: a one-time buy.** No subscription, no pay-to-win, nothing that sells power, safety
  or progress. Anything beyond the base game (for example cosmetic packs) is the owner's call,
  later.
- **Map: works like Rust's** (in our own design). A procedurally generated landmass with biomes,
  rivers, roads and ruins placed by a generator, every world different.
- **Players: 2 to 8 friends in co-op**, PvE against the Gloam and the land. For now that is
  today's always-on Railway world, capped at 8, so friends can drop in any time; hosting your
  own world comes later. Solo play works too.

## The lean: accessible, action-heavy, worth sharing
- **Quick to learn.** In the first five minutes a new player drinks, eats, lights a fire, fights
  one of the Gloam and knows what will kill them. Every danger is visible and explained the first time.
  Needs are forgiving and come back fast.
- **Good in a short session.** Thirty minutes always pays: a ruin looted, a wall raised, a skill
  level, a night survived. A day and night lasts about 40 minutes.
- **Moments worth clipping:** a horde night held by torchlight; a run into the castle's crypt
  and out again with the hounds behind you; a friend dragged back from a Gloam pack at the
  last second.
- **Readable for viewers.** Clear silhouettes (the Gloam grey and ash-cold, the living warm and
  cloth-coloured), a quiet HUD, effects that are big only for the big moments, and a streamer
  mode.
- **Fair failure.** Death drops what you carried, never what you know. You're back in under a
  minute.

## The Gloam (our undead)
The kingdom's dead, emptied by the Dimming. They fit the name without copying anyone's zombie.
- **Behaviour:** they shamble by day and get faster and gather at night. They're drawn to noise
  (fighting, chopping, breaking walls, bells) and to the smell of blood. Alone they're
  beatable; packs are deadly.
- **Kinds** (each with a clear silhouette and telegraph): the common **walker**; the **Gloam
  soldier** in rusted mail, found in castles and forts, slow and hard to put down; the
  **Gloam hound**, fast and in packs, found on the moors; the **Bell-wight**, rare, whose
  shriek calls every one of the Gloam nearby (silence it first). More come in the "Depth" phase.
- **Ember burns them.** Torches keep them wary, ember-tipped weapons hit hard, and an ember
  hearth inside your walls stops them rising in your hold. This makes the existing ember motif
  the core of the game.
- **The chill.** A Gloam's grip can leave the chill, which slowly drains your warmth. An ember
  salve cures it if you treat it the same day. It's dangerous but never a hidden death sentence.

## The map: a generated kingdom with graded ruins
- **Generator:** a seed per world. It lays out the land (coast or highland rim, rivers to the
  sea or a lake, forests, moors, farmland gone wild, stone hills, snow on the high ground), then
  the **king's roads** between the ruins, then the ruins themselves, then resource nodes,
  wildlife and Gloam spawns. The terrain stays deterministic from the seed, so a server sends a
  seed and never terrain, and the client builds terrain in chunks around the player.
- **Ruins** are hand-designed set pieces written as data and placed by the generator, each with a
  risk grade, a loot table and its own Gloam. Every world has the high-grade ones and a random
  mix of the rest.

| Grade | Examples | Danger | Pays |
|---|---|---|---|
| 1 Quiet | Roadside shrine, burned farmstead, woodcutter's hut | A few Gloam | Food, cloth, basic tools |
| 2 Uneasy | Abandoned village, toll bridge, watchtower | Small groups, a hound pack nearby | Better tools, the first weapons, the first iron |
| 3 Grim | The old mine, the drowned village, a walled abbey | Soldiers, tight spaces, darkness | Ore, ember salve, armour pieces, **signet keys** |
| 4 Deadly | The fallen castle, the royal crypt beneath it | Many soldiers, wights, hounds; a key to get in deep | The best gear and ember relics |

- **Signet keys** (our own take on gating loot behind keys): found in grade 3 ruins, they open
  the vaults in grade 4 ones. That makes a run a plan, and gives a band a reason to send its
  best.
- **Size:** about 1 to 1.5 km across (a host setting: small, medium, large), with roads
  linking the ruins and the high-grade ones toward the centre or the far side from the start.

## Surviving, building, getting stronger
- **Needs:** hunger, thirst, warmth and rest. Each is a quiet icon that only shows when it
  matters.
- **Wounds:** bleeding (bandage), the chill (ember salve), a sprain (rest or a splint).
- **Food and fire:** forage, hunt, cook; food spoils slowly, and salting and smoking keep it.
  Farming comes later.
- **Combat:** the action combat already on `main` (aimed light and heavy swings, block, dodge on
  stamina), extended with bows and crossbows, against the Gloam and wildlife. No PvP in the core
  game (friendly fire is a host setting, off by default).
- **Building:** snap-grid timber and stone (foundations, walls, doors, roofs, palisades, gates),
  chests, an ember hearth, a bedroll. Tiers: wood, stone, iron-bound. Defences you loot and
  craft toward: spiked barricades, pit traps, arrow slits, a gatehouse, braziers that burn
  the Gloam, a bell to warn the others.
- **Claimed land:** a group stakes its land with a **claim marker** (a banner or boundary stone,
  final look to world). The claim sets where you can build, and grows as you build it up (more
  plots as your hold gets bigger). It's co-op, so a claim is about your base's footprint and its
  threat, not keeping other players out.
- **Days survived:** each character counts days survived since their last death, shown quietly on
  the HUD and loudly when you die ("You survived 23 days"), and each world counts its age. Best
  runs are kept per character and per world.
- **Horde nights (our own, not a fixed-calendar moon):** a horde night isn't on a timer you can
  read off a calendar. It is triggered by your base's **threat** crossing a line (see below) and
  given a warning the evening before (signs in the world: name and look being chosen with the
  owner). The size and mix of the horde scale with threat and with days survived. The name is pending the
  owner's pick ("the Tolling" is on offer: a far bell rings the evening before).
- **Invasions:** each base has a **threat** that rises with its size, noise, light and stored
  wealth. Threat decides how big the next invasion is and how often they come, shown on a quiet
  gauge so you always know what's coming. The Gloam break doors and weak walls (never stone
  without siege-type Gloam), so upgrades matter. Never instant: an invasion is announced by a
  sound and a sight a minute before it hits.
- **Vehicles:** horses (tame, feed, stable, ride; a horse can be hurt and must be looked after),
  carts (hitched to a horse, hauling a ruin's worth of loot), and boats (rowboat first, then a
  small sail boat for the coast). Vehicles are saved with the world.
- **Skills, the long road kept:** our skills and XP carry over and grow (Felling, Quarrying,
  Toolcraft, plus foraging, cooking, mending, carpentry, masonry, smithing and the weapon
  masteries). Skills belong to the character in that world.
- **Carry weight**, not a grid.

## Co-op: how friends play together (owner, 2026-11-24)
**Now: one always-on world.** The owner wants friends to be able to drop in any time and try it.
So, for now, co-op is **today's dedicated server on Railway**: one persistent world, always on,
capped at **8 players**, updated the way it is today. Nothing about the live server breaks.
- The cap is a server setting (`MAX_PLAYERS`, 8 on Railway); a full world says so politely.
- When the generator is ready (Phase 1), the Railway world **moves to a generated map** in one
  announced step: characters keep their skills, items and pack, and arrive at the new world's
  spawn. Their old position is the only thing that doesn't carry over.
- Everything built later (holds, chests) is saved by that server and survives every deploy.

**Later: friends host their own worlds.** Once the game is ready for people beyond the owner's
friends (Phase 5):
- A "Host" button in the client starts our own server build on the player's machine with their
  world; friends join with an invite code or the host's address. It is the same authoritative
  server, so the rules and the bot test stay the same.
- A host keeps several worlds (each with its seed, everything built and its characters), picks
  or rolls a seed for a new one, and keeps them as long as they like.
- Up to 8 players per world. Sending every player to every player is fine at 8; the effort goes
  into the Gloam, ruins and building instead.
- The one-time buy pays for the game, not for hosting. The Railway world stays as the owner's
  friends' world and the playtest world.

## Later, maybe: dedicated servers for bigger groups
Not in the core plan. If co-op lands well, a dedicated server mode for bigger groups (16 to 48)
could follow: players or communities run our server build, with optional PvP rules from the
earlier draft (bands, land claims held by resolve, raids with offline protection, seasons that
end in a fresh map). Nothing is designed or built for it until the owner asks.

## Still open (being asked)
- **Magic:** whether the fallen kingdom has magic, and how much (none; ember craft only; or a
  small, costly school of ember magic).
- **How the undead behave** beyond the basics above (how hordes form, whether they break walls,
  how fast they are at night, whether the dead you leave behind rise).
Until answered, workers build only what this file already settles.

## What carries over from today's build
| Keeps | Changes | Goes |
|---|---|---|
| Godot client and headless authoritative server (now also started by the host), ENet and WebSocket | One fixed valley becomes a generated kingdom per world, built in chunks | The MMO framing, "thousands on one world", public servers, raiding and seasons (see "Later, maybe") |
| Gathering with E, timed bars, nodes; the bench and crafting; skills and XP | Vitals grow into needs and wounds; inventory gets weight | Milestones 2 to 7 as written |
| The third-person action camera, swings, dodge, block | Ashgrove's ember lore becomes the fallen kingdom's (the Dimming, the ember) | The towns-MMO plan (PR #184, closed) |
| Grounded art and its budgets; wildlife | New: ruins, the Gloam, building, death and loot, hosting and invites | |
| CI, bot test, fun metrics, the self-updating client, the worker setup | Fun metrics add survival measures (time to first fire, nights survived, ruins cleared) | |

## Rename plan (after the owner confirms)
The game is called ZombAi in design docs from now on. The rename everywhere else waits for the
owner's go-ahead, because some steps are theirs:
1. **Owner:** rename the GitHub repository (Settings → General). GitHub redirects the old URL, so
   nothing breaks. Rename the Railway service if wanted. Run a proper name check before any
   store page: a quick web search found no game called ZombAi, but that isn't a trademark search.
2. **client:** the window title, the login screen, `project.godot`'s application name, export
   preset names and build file names.
3. **qa:** CI and release workflows (release titles become `ZombAi Week NN — ...`), the
   self-updater's repository path (it follows GitHub's redirect, but update it anyway).
4. **Director:** CLAUDE.md's title and the remaining "AiMMO" mentions in the docs.
The Budda Games studio intro stays.

## Lessons we keep
From `docs/research/promises_study.md` (the settlement MMO that collapsed in 2026): ship the
smallest playable version first; design for the players we actually have; bots test every
multiplayer rule before it ships, restarts included; performance is a feature; and **promise
only what is on `main`**.

## Never
- Never tell players about a feature before it is on `main` and in the bot test.
- Never sell power, safety or progress. It's a one-time buy.
- Never lose a player's save, world or character.
- Never make a death the player couldn't have seen coming.
