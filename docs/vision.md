# ZombAi: vision

**Owner direction, 2026-11-24 and 2026-11-25.** The owner set the name, setting, camera, price,
map style and the reference ("Project Zomboid + 7 Days to Die in a medieval fantasy setting,
with a round survive element at night and base defence"), then, on 2026-11-25: **"We are no
longer making a MMO, it will at most have maybe 100 player servers. Like 7 days or project
zomboid."** So ZombAi is an **open-world zombie survival sandbox on servers of up to about 100
players**, not an MMO and no longer capped at 8 friends. The owner asked the director to pick
the rest. Every stream reads this file; `docs/roadmap.md` holds the phases and their "done
when" lists.

Everything here is our own design under "Inspired by, never copied" (design bible). The feel
we're reaching for: **Project Zomboid's survival depth** (needs, injuries, careful looting) and
its servers full of survivors' stories, **crossed with 7 Days to Die's base building and night
defence**, in a medieval fantasy setting, on a procedural map full of risk-graded ruins like
*Rust*'s monuments. All of it is made quicker to learn and readable on a stream. Those names
stay in design docs, never in the game, and we take their feel only: no names, systems, numbers
or looks from any of them.

## The game in one paragraph
**ZombAi** is a third-person survival game set in a **fallen kingdom**. The kingdom died when the
Dimming rose, and its dead got back up as **the Gloam** (owner's name, 2026-11-24): the
kingdom's dead, filled with the Dimming's twilight. Each server is a freshly generated
stretch of that kingdom: forests, moors, rivers, the old king's roads, and the **ruins**
(burned farmsteads, a drowned village, mines, abbeys, and a castle at the heart of it). Each ruin
is graded by how much it can kill you and how much it pays. You **make your character** and
arrive with nothing. You eat, drink, keep warm, bandage what bleeds, and learn that noise brings
the Gloam and **ember-fire burns them**. With the people you trust you **claim a piece of land**
and build it up from a lean-to to a walled hold, with what you **gather** and what you **loot**
from richer and deadlier ruins. On **horde nights** the Gloam come in numbers for the holds that
have grown loud, bright and rich. A counter keeps score: **days survived**. There is no ending:
the goal is to survive, build and grow stronger for as long as you like. It's played on
**servers of up to about 100 players**: alone, with a few friends, or as part of a whole
server's worth of survivors, under rules the server sets and shows before you join.

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

## Settled (owner, 2026-11-24 and 2026-11-25)
- **Name: ZombAi.** The repository was renamed on 2026-11-24 and the game shows the new name
  from the build after that (section "Rename").
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
- **Not an MMO (owner, 2026-11-25).** One server is one world of up to about 100 players.
  There is no shared universe across servers, no global economy and nothing that needs
  thousands of players to work.
- **Players: servers of up to about 100** (owner, 2026-11-25), PvE against the Gloam and the
  land by default; how players treat each other is a **server rule** (section "Server rules").
  Solo play and a handful of friends work too. Today the official always-on Railway world holds
  8 and must never break; its cap rises in steps (section "Getting to 100").
- **The basics first (owner, 2026-11-25, design bible direction 9):** character
  customization, zombie survival, a randomly generated map, and ruins and landmarks with loot
  come before any polish.

## The lean: accessible, action-heavy, worth sharing
- **Quick to learn.** In the first five minutes a new player drinks, eats, lights a fire, fights
  one of the Gloam and knows what will kill them. Every danger is visible and explained the first time.
  Needs are forgiving and come back fast.
- **Good in a short session.** Thirty minutes always pays: a ruin looted, a wall raised, a
  level and a point in the tree, a night survived. A day and night lasts about 40 minutes.
- **Moments worth clipping:** a horde night held by torchlight; a run into the castle's crypt
  and out again with the hounds behind you; a friend dragged back from a Gloam pack at the
  last second; a stranger's torch on the road at night, and the choice to wave or hide.
- **Readable for viewers.** Clear silhouettes (the Gloam grey and ash-cold, the living warm and
  cloth-coloured), a quiet HUD, effects that are big only for the big moments, and a streamer
  mode.
- **Fair failure.** Death costs you a couple of things from your pack, never what you know. You're back in under a
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
- **Only near people.** The Gloam are simulated in full near players; the empty half of a
  100-player map costs the server next to nothing.
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
| 4 Deadly | The fallen castle, the royal crypt beneath it | Many soldiers, wights, hounds; a key to get in deep | The best gear, the strongest potions and rare scrolls |

- **Signet keys** (our own take on gating loot behind keys): found in grade 3 ruins, they open
  the vaults in grade 4 ones. That makes a run a plan, and gives a band a reason to send its
  best.
- **Size:** a server rule that scales with the player cap: small (about 1.5 km across, up to
  about 16 players), medium (about 3 km, up to about 50), large (about 4 km, up to 100). Roads
  link the ruins, with the high-grade ones toward the centre or the far side from the spawn
  coast. Bigger maps get more ruins of each grade, so 100 players are spread over many places,
  not queued at one castle.
- **Spawns:** new characters arrive at one of several spawn points along the quiet edge of the
  map, spread so a busy server doesn't drop everyone in one meadow.

## Surviving, building, getting stronger
- **Needs:** hunger, thirst, warmth and rest. Each is a quiet icon that only shows when it
  matters.
- **Wounds:** bleeding (bandage), the chill (ember salve), a sprain (rest or a splint).
- **Food and fire:** forage, hunt, cook; food spoils slowly, and salting and smoking keep it.
  Farming comes later.
- **Combat:** the action combat already on `main` (aimed light and heavy swings, block, dodge on
  stamina), extended with bows and crossbows, against the Gloam and wildlife. PvP and friendly fire are
  server rules, off by default (section "Server rules").
- **Building:** snap-grid timber and stone (foundations, walls, doors, roofs, palisades, gates),
  chests, an ember hearth, a bedroll. Tiers: wood, stone, iron-bound. Defences you loot and
  craft toward: spiked barricades, pit traps, arrow slits, a gatehouse, braziers that burn
  the Gloam, a bell to warn the others.
- **Claimed land:** a band stakes its land with a **claim marker** (a banner or boundary stone,
  final look to world). The claim sets where you can build, and grows as you build it up (more
  plots as your hold gets bigger). It sets the base's footprint and its threat, and on a server
  with claim protection on (the default) only the band can build, open doors and chests or
  break anything inside it. Claims can't be placed on a ruin, a king's road or too close to
  someone else's claim, so the map's best spots are first come, and nobody can wall off a ruin.
- **Days survived:** each character counts days survived since their last death, shown quietly on
  the HUD and loudly when you die ("You survived 23 days"), and each world counts its age. Best
  runs are kept per character and per world.
- **Nights come in rounds (owner, 2026-11-24: "round survive element at night").** A night
  (about 17 of the day's 40 minutes) is fought in **rounds**: the Gloam come in waves until
  dawn, each round a little bigger and tougher than the last, with a **short lull** between
  rounds (about a minute) to repair walls, rearm and drag a friend back inside. The round number
  and the days-survived counter sit on screen at night. Rounds come for **you**: at your base they
  hit your walls; caught out in the wild, a smaller wandering pack finds you. Surviving to dawn
  pays (XP and a little loot from what fell at your walls).
- **The Tolling (our horde night, not a fixed-calendar moon).** The big one. It isn't on a
  calendar: it is triggered when your base's **threat** crosses a line, and announced the evening
  before by a far bell that tolls from the direction it will come. A Tolling night has more
  rounds, Gloam soldiers and wights among them, and a last round that tests every wall and gate.
  Its size scales with threat and with days survived.
- **Invasions:** each base has a **threat** that rises with its size, noise, light and stored
  wealth. Threat decides how big the next invasion is and how often they come, shown on a quiet
  gauge so you always know what's coming. The Gloam break doors and weak walls (never stone
  without siege-type Gloam), so upgrades matter. Never instant: an invasion is announced by a
  sound and a sight a minute before it hits.
- **Vehicles:** horses (tame, feed, stable, ride; a horse can be hurt and must be looked after),
  carts (hitched to a horse, hauling a ruin's worth of loot), and boats (rowboat first, then a
  small sail boat for the coast). Vehicles are saved with the world.
- **One level, one skill tree** (owner, 2026-11-25): everything you do pays character XP,
  every level gives a point, and you spend points down five branches (Survival, Fighting,
  Building, Scavenging, Crafting; design bible direction 5). You can't take everything, so a
  band is better when its members specialise. Today's four skills fold into character XP; the
  level and tree belong to the character in that world.
- **Dying** (owner, 2026-11-25): you drop **a couple of items from your pack** (two or three
  random stacks, never what you hold in your hands) in a small sack where you fell, and wake at
  your bedroll or a spawn point in under a minute with everything else. Your level and tree
  are kept. Anyone can pick up the sack, so go back for it. The days-survived counter resets.
- **Character creation is looks only** (owner, 2026-11-25): body, face, skin, hair, beard and
  cloth on the sculpted body. No backgrounds or starting classes: what you become comes from
  the tree.
- **Carry weight**, not a grid.

## Servers: up to about 100 survivors (owner, 2026-11-25)
A server is one persistent world: one seed, one map, its own characters, holds and history. It
holds **up to about 100 players** at once (`MAX_PLAYERS`, at most 100). It is the same
authoritative headless server we run on Railway today, so the rules and the bot test are the
same wherever it runs.

**Who runs servers.**
- **The official world.** Today's always-on Railway server: the owner's friends' world and the
  playtest world. It **never breaks** (CLAUDE.md), it is PvE, and it moves to a generated map in
  one announced step once the generator is ready (Phase 1): characters keep their level, skill tree, items
  and pack and arrive at the new world's spawn; their old position is the only thing that
  doesn't carry over.
- **Dedicated servers anyone can run** (Phase 5): the server build as its own download (Linux
  and Windows, and the Docker image), with a plain config file for the server rules. The
  one-time buy pays for the game; running a server costs nothing extra.
- **A Host button** for a small group comes after, on the same build, started from the client.
- **Finding a server:** a server list in the client with each server's name, player count, map
  size, ping and its rules in one line ("PvE · claims protected · loot refills daily"), plus
  join by address. A full server says so politely and never kicks anyone.

**Everything is per server.** Characters, levels and skill trees, holds and days survived belong to the
character in that server's world. A player can have characters on many servers.

**Holds are safe while their owners are away.** The world never stops on a dedicated server,
so nothing attacks what nobody is there to defend:
- Night rounds and invasions only come for players who are online, and a base is only attacked
  by the Gloam while at least one of its owners is online. A Tolling that comes due while its
  base's owners are all offline waits until one of them logs in, and its evening-before bell
  rings then.
- On a server with PvP, other players can only break into a hold while one of its owners is
  online, unless the server's rules say otherwise and say so in the server list.
- **Days survived** on an always-on server count in-game days a character was alive *and online
  for at least part of that day*, so someone who plays twice a week isn't punished and nobody
  climbs the board by staying logged off.

**Scaling to the crowd.** Night rounds and Tollings scale with how many players are at the
base, so a pair and a band of twelve both get a fair fight. Packs in the wild scale with the
group nearby. Nothing is server-wide: every horde has a base or a group as its target, so 100
players means many small stories, not one big lag spike.

### Server rules
A server's rules decide what kind of server it is. They live in one data file of rule names and
defaults (gameplay owns it), the server sends them at login, and the server list and a
"Rules" panel show them before you join. Defaults are in bold; the official world uses the
defaults.

| Rule | Choices | Why |
|---|---|---|
| Player cap | 2 to 100, **32** for a new server (8 on the official world today) | A server sized to its map and its people |
| Map size | small (about 1.5 km), **medium (about 3 km)**, large (about 4 km) | Roughly 1.5 km for up to 16, 3 km for up to 50, 4 km for up to 100 |
| PvP | **off**, on, or only outside claims | PvE by default, PvP a server option (owner chose this, 2026-11-25); never on by default |
| Friendly fire within a band | **off**, on | |
| Claim protection | **on** (only your band builds, opens chests and doors on your claim), off | On a server of strangers, a claim must mean "mine" |
| Loot refills | ruins refill **daily (in-game)**, weekly, never | Late joiners still find loot on a busy server |
| Day length | 20 to 90 minutes, **40** | |
| Gloam difficulty | gentle, **normal**, hard; and night rounds on or off | Harder is a choice, never the default |
| What death costs | **drop a couple of items from your pack**, drop the whole pack, or hardcore (start a new character) | Fair failure by default (owner, 2026-11-25) |
| XP rate | 0.5x to 3x, **1x** | One curve, scaled |
| World reset | **never**, or on a schedule the server shows | Never on the official world without the owner |

New rules can be added as systems arrive; a rule is only added when the system it changes is on
`main`, and every rule has a bot-test case for its default.

### Bands: groups on a busy server
On a server of 100, the people you play with need a name. A **band** is a group of players who
share a claim, its chests and doors, a band chat and markers on each other's maps. Make one,
invite by name, leave any time; a band has no size limit beyond the server's cap, and a player
is in one band at a time. A solo player is a band of one. Claims, threat and invasions belong to
bands.

### Talking and finding each other
- **Nearby chat** by default (about 40 m), **band chat**, and a **server channel** the server can
  turn off. Chat stays talking-only (design bible direction 1). Proximity voice is Phase 7.
- A **players panel** lists who is on the server; distance and position only for your band.
- Strangers meet in the world: a camp's smoke and firelight are visible from a distance, and the
  king's roads lead past everyone's land.

### Getting to 100
The server we have sends every player to every player. That is fine at 8 and not at 100. The
live cap only goes up after the server proves it can hold that number:
1. **Interest management:** a client only hears about players, the Gloam, animals and drops
   within its bubble (about 150 to 200 m). This comes before the cap passes 24.
2. **The Gloam near players only:** full simulation within the bubbles, a cheap coarse
   simulation (or none) everywhere else.
3. **A load test in CI** (qa): the bot test's 8 bots still run on every PR; a separate load
   test connects as many bots as the next cap step (24, then 50, then 100) for at least 3
   minutes, scattered over the map, and fails on errors, desync, a server tick over budget or
   any lost save.
4. **The official world's cap steps up** 8 → 24 → 50 → 100, each step only after its load
   test passes on `main`, each announced in the patch notes.

## Magic: potions and scrolls (owner, 2026-11-25)
Magic is small, useful and ember-based. It is something you drink or read, never a class:
- **Potions:** a **health potion** (heals over a few seconds, and stops bleeding) and a
  **stamina potion** (refills stamina and slows its drain for a minute). Brewed down the
  Crafting branch from herbs and ember sap, and found in ruins; better grades come from deeper
  ruins. Drinking takes a moment and you can be hit while you drink.
- **One-use scrolls**, found in ruins (rarer and stronger in grade 3 and 4 vaults): a burst of
  ember-fire around you, a flare that lights the field for a night round, a ward that keeps
  the Gloam off one gate until dawn, and the rare scroll that resets your skill tree.
- Nothing else: no runes in walls, no enchanted relics, no spells you learn.
All of it follows the art bible's restraint: effects are warm light and sparks, short and rare.

## Still open
- **How the undead behave** beyond the basics above (how hordes form, whether they break walls,
  how fast they are at night, whether the dead you leave behind rise).
Until settled, workers build the basics described above and leave these details as data that
is easy to tune.

## What carries over from today's build
| Keeps | Changes | Goes |
|---|---|---|
| Godot client and headless authoritative server, ENet and WebSocket; the official always-on Railway world | One fixed valley becomes a generated kingdom per server, built in chunks; the server learns interest management and server rules | The MMO framing, "thousands on one world", anything shared across servers |
| Gathering with E, timed bars, nodes; the bench and crafting; skills and XP | Vitals grow into needs and wounds; inventory gets weight; one global chat becomes nearby, band and server chat | The 8-player co-op cap as a design limit (it stays only as the live world's current setting) |
| The third-person action camera, swings, dodge, block | Ashgrove's ember lore becomes the fallen kingdom's (the Dimming, the ember) | The towns-MMO plan (PR #184, closed); the old "Later, maybe" of 16 to 48 player PvP servers, now folded into server rules |
| Grounded art and its budgets; wildlife; the character creator | New: ruins, the Gloam, building, death and loot, bands, server rules, the server list and dedicated server download | |
| CI, bot test, fun metrics, the self-updating client, the worker setup | Fun metrics add survival measures (time to first fire, nights survived, ruins cleared); qa adds a load test | |

## Rename (done 2026-11-24)
The owner renamed the GitHub repository from AiMMO to ZombAi; GitHub redirects the old URLs.
The window title, the login and update screens, the Windows file details, the README, CLAUDE.md,
the tools and the scheduled worker prompts now say ZombAi. **These keep the old name on purpose,
and must not be renamed**, because friends already have the game installed:
- `config/name="AiMMO"` in `game/project.godot`. Godot names the user data folder after it
  (`app_userdata/AiMMO`), which holds every player's settings and the self-updater's downloaded
  builds. Renaming it would strand both. The window title is set to ZombAi in code instead.
- The executable names inside the downloads (`AiMMO.exe`, `AiMMO.x86_64`, the macOS app). An
  installed game loads the `.pck` named after its own executable.
  The release downloads themselves are named `ZombAi-<platform>.zip` and `ZombAi-<platform>.pck`
  (owner asked, 2026-11-24). That is safe because installed games download whatever pack name
  `update.json` gives them; CI deletes the old `AiMMO-*` downloads from a week's release.
- The macOS bundle identifier (`io.github.aimmo.client`), so macOS keeps treating it as the
  same app.
- Every `AIMMO_*` environment variable and repository variable, because the live Railway server
  and CI read them by those names.
- The Railway service name (`AiMMO-Server`); renaming it is the owner's call, and CI's
  `RAILWAY_SERVICE` variable must be updated in the same step.
Release titles stay `Week NN — <headline>`. Never create a new repository named AiMMO on this
account: it would break the redirect that installed games follow to find updates.
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
- Never break the official always-on world, and never raise its cap past what the load test has
  proved.
- Never let a server's rules be a surprise: what a server allows is shown before you join.
