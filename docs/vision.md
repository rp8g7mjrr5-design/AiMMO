# Vision: survive the night, hold your ground

**Owner direction, 2026-11-24. This is the game now.** The owner weighed two directions (a
towns MMO, and a small-server survival game with faction land claims), chose the survival game,
asked for it to be made for mass appeal and to go viral, and left the remaining calls to us.
Every stream reads this file; `docs/roadmap.md` holds the phases and their "done when" lists.

Everything here is our own design under "Inspired by, never copied" (design bible). The feel we
are reaching for: the deep survival sim of *Project Zomboid*, the land-claim politics of the old
Minecraft *Factions* servers, and the wipe-day energy of the big survival shooters, made
quicker to learn and readable on a stream. Those names stay in design docs, never in the game.

## The game in one paragraph
Each server is a freshly generated valley for **32 to 48 players** that lives for a **season of
six to eight weeks**. You arrive with nothing. Staying alive is the first game: hunger, thirst,
cold nights, wounds to tend, and the **Hollows**, the people and animals the Dimming has emptied,
who drift through the day and come in numbers at night, drawn to noise and light. Your band is
the second game: a few friends build a shelter, then walls, then a hold, and stake their land
with a claim stone. A band's grip on its land is only as strong as its members' **resolve**,
which grows while they play and stay alive and drops each time one of them dies. Claim too much
and another band can break your walls and take what you built. Then the season ends, the valley
burns down to ash, and on **wipe day** everyone starts again on a new map.

## What makes it spread (the mass-appeal lean)
The owner wants it to reach a lot of people. So we lean **accessible and action-heavy rather than
brutal**, and we design for moments people clip and share.
- **Quick to learn.** In the first five minutes a new player drinks, eats, lights a fire, swings
  at a Hollow and knows what will kill them. Every danger is visible and explained the first
  time; no hidden timer kills you without warning. Needs are forgiving (hours of play, not
  minutes) and come back fast with food, water and a fire.
- **Good in a short session.** A 30-minute session always pays: a stash topped up, a wall
  raised, a skill level, a night survived. A day and night is about 40 minutes, so most sessions
  see a dusk.
- **Moments worth clipping**, each built as a set piece with its own sound, light and camera
  feel:
  - **Night sieges:** on the darkest nights the Hollows gather and come at the loudest, brightest
    bases. A band holding its walls by torchlight is the game's signature shot.
  - **Raids:** breaching a wall is loud, slow and visible across the valley, so a raid draws a
    crowd (and Hollows).
  - **Wipe day:** a countdown in game and on the server list, the valley's last night, then a new
    map at a set hour that everyone races into.
- **Readable for viewers.** Clear silhouettes (Hollows read grey and ash-cold, players warm and
  cloth-coloured), big readable effects for the moments above and quiet ones the rest of the
  time (art bible sections 9 and 10), a minimal HUD, a **streamer mode** (hides server
  address and other players' names on request), and later a **spectator camera** for
  server-wide moments.
- **Social by default.** Bands of two to eight, a safe spawn town, proximity voice later, and a
  season leaderboard (longest survivor, biggest hold, most nights held) that gives every server a
  story.
- **Fair failure.** Death drops what you carried, never what you know. You are back in under a
  minute.

## The decisions (made 2026-11-24)
1. **Threat: the Hollows** (our own, from Ashgrove's lore), plus real wildlife. Horde and siege
   mechanics with our own identity, the grounded look and no gore needed.
2. **Raiding is on by default**, with a safe spawn town nobody can claim or fight in, and the
   offline protection rule (section "Bands, claims and resolve").
3. **Seasons of six to eight weeks on fresh maps.** Accounts, cosmetics, titles and season
   records carry over; characters' bases, items and world state end with the season. Hard rule 6
   in `CLAUDE.md` says exactly this now.
4. **Death:** you drop everything you carried in a lootable pack where you fell, and keep your
   skills minus a small slice of the current level's XP (never a level).
5. **Server size: 32 to start, 48 as the target**, 64 only if qa's perf gates hold.
6. **The towns idea lives on** as each server's spawn town, raised together by the whole server.

## Surviving
All numbers in data files, tuned like the skill curve.
- **Needs:** hunger, thirst, warmth (nights and rain are cold; fire, shelter and clothes help),
  rest. Each is a quiet icon that only appears when it matters.
- **Wounds:** a few, each with one clear cure: bleeding (bandage), a bite that can fester (clean
  it), a sprain (rest or a splint).
- **Food and fire:** forage, hunt, cook at a fire; food spoils slowly; salting and smoking keep it.
  Farming later.
- **Carry weight**, not a grid: heavy loads slow you; bags carry more.
- **Combat** is the action combat already on `main` (aimed light and heavy swings, block, dodge on
  stamina) against Hollows, wildlife and players.
- **Skills, the long road kept:** our existing skills and XP carry over and grow: Felling,
  Quarrying, Toolcraft, plus foraging, cooking, mending, carpentry, masonry and the weapon
  masteries. Skills are per season character, which keeps every season's road fresh; a season
  record of what you reached carries over.

## Bands, claims and resolve
Our own take on the Factions idea, with its worst parts fixed.
- **Bands:** two to eight players; a name and banner colour; ranks (leader, officer, member,
  recruit); relations with other bands (allied, neutral, at feud).
- **Resolve:** each member has 0 to 10, starting at 5. It climbs about 1 an hour online and alive,
  regains slowly offline up to 5 (real life isn't punished), and drops on death (more when killed
  by a player). A band's resolve is the sum of its members'.
- **Claims:** a **claim stone** stakes 32 m plots joined to each other. Inside them only the band
  and its allies can build, open doors or take from containers, and Hollows don't rise there
  (they still walk in at night).
- **Over-reach:** each plot costs 1 resolve. A band holding more plots than its resolve is
  **over-reached**: its outer plots can be claimed over, and bands at feud with it can breach its
  walls.
- **Breaching:** with tools and crafted breaching gear; loud (it draws Hollows and onlookers) and
  slow (minutes per wall). Builds come in tiers: wood, stone, reinforced.
- **Offline protection:** while every member is offline, the band's walls take a quarter of the
  damage, unless it is over-reached. Stay within your resolve and you can log off safely.
- **The spawn town:** neutral, safe, unclaimable, raised by the whole server through shared
  projects (a trader's stall, a better bench, a notice board, a watch fire). Contributors' names
  stay on its ledger for the season.

## The world: generated, with places that look designed
- A **seed per server per season**. The generator lays out a valley about 1 km across at first
  (2 km later): rivers and lakes, hills, ash lowlands, pine heights, stone ridges, and cold grey
  scars where the Dimming is strongest (more Hollows, better loot).
- **Hand-made set pieces** written as data and placed by the generator: ruined steadings, a
  hollow-haunted mill, a lookout crag, the spawn town plot. Every map is new; every map still has
  places worth a screenshot.
- The terrain stays deterministic from the seed, so the server sends a seed, never terrain. The
  client builds terrain in chunks around the player.
- Today's 512 m Ashgrove stays as the test seed and the current live world until the first season
  starts.

## What carries over from today's build
| Keeps | Changes | Goes |
|---|---|---|
| Godot client, headless authoritative server, WebSocket on Railway, Postgres, accounts | One fixed world becomes a generated world per server and season; terrain built in chunks | The "greatest MMO", thousands-on-one-world framing |
| Gathering with E, timed bars, node depletion; the bench and crafting; skills and XP | Characters belong to a server and season (add-only columns) | Milestones 2 to 7 as written (they fold into the phases) |
| Action camera, vitals, swings, dodge, block | Vitals grow into needs and wounds; inventory gets weight | The towns-MMO plan (PR #184, closed), except the spawn town |
| Grounded Emberlight art and its budgets; grazers and wildlife | New: building, bands and claims, Hollows, death and loot, seasons | |
| CI, bot test, fun metrics, self-updating client, the worker setup | Fun metrics add survival measures (time to first fire, nights survived) | |

## Lessons we keep (from the study of the big MMO that didn't deliver)
`docs/research/promises_study.md` studied the settlement MMO that collapsed in 2026. What
applies here: ship the smallest playable version first; design for the players we actually have
(32 to 48, not thousands); bots test every multiplayer rule, including restarts, before it ships;
performance is a feature; and **promise only what is on `main`**. The roadmap is a forecast,
never a promise to players.

## Never
- Never tell players about a feature before it is on `main` and in the bot test.
- Never sell power, resolve, protection or progress. Cosmetics only, and only once the owner sets
  that up.
- Never end a season early or without a countdown of at least a week in game.
- Never lose accounts, cosmetics, titles or season records.
- Never let the offline rule be bypassed: a band within its resolve is never raided at full
  strength while all its members are offline.
