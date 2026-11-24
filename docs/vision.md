# Vision: towns the community raises, on a map worth crossing

Owner direction, 2026-11-24: *"I want a beautiful map with towns that build up from
community."* The owner asked us to study the promises of the big settlement MMO that didn't
arrive, and to deliver them. The study is `docs/research/promises_study.md`; this file is our
answer. It is the headline of AiMMO from here on: every stream reads it, and the milestones that
build it are in `docs/roadmap.md`.

Everything here is our own design, under "Inspired by, never copied" (design bible): our names,
our stages, our look. The names below (sites, stages, buildings, the skill) are working names
the director may refine, but never toward another game's terms.

## The promise in one paragraph
Ashgrove starts as wild valley with a single fire in the Spawn Meadow. Everything players
gather and craft can go into raising the places they live in: you carry stone to a marked
footing and watch the wall course you paid for appear, you put in an evening of labour and a
roof goes on, and when the last beam lands everyone online sees the moment. Buildings are real
services (a storehouse, a better bench, a kiln, a forge, a market board, a watch fire), so a
town's growth is the server's progression. A hand-shaped map ties it together: a few town sites
with their own character, roads players build between them, landmarks you can see from far
off, and a painted map window that fills in as you explore and shows every town's stage. Later,
the Dimming (the cold that drains the valley's warmth) creeps out at night toward towns and the
whole server defends them, and much later willing groups contest which banner flies over a
town's perks. Nothing anyone built is ever lost to a chore or to strangers.

## How it answers the promises
| The promise players wanted | What fell short (study, section 2) | Our answer |
|---|---|---|
| The world remembers what we do | Contribution was an abstract bar; NPCs built the town | **Raising**: each delivery visibly adds to a building in front of you, the same minute |
| A town we built | Stages flipped by experience from any activity | Buildings are **projects** with a bill of materials and labour, paid by players by hand |
| Places that differ | Four types fixed by the map | Each site's surroundings give it a **character**, and at Hamlet its contributors pick a **charter** that decides its later buildings |
| Real stakes together | Sieges never reached players; destruction erased months | **Dimming tides** (PvE, server-wide defence) can make buildings go cold, never vanish; opt-in contests come late and fight over perks, not rubble |
| Trade across the map | Caravans unproven | **Hauling**: heavy crates you carry on foot along roads players built; opt-in risk later |
| A corner of my own | Freeholds barely arrived | **Homesteads** on plots a Village opens, much later, after storage and the market |
| Massive scale | Empty world, lag at scale | **Few sites, close together**, sized for the players we have; interest management before 100 online |
| A team that ships what it shows | Delays, paid alphas, pivots | **Promise only what is on `main`**; every phase is playable on its own; the roadmap is a forecast |

## Core loop, extended
**gather → craft → fight → level up → explore further** gains one more turn:
**... → raise the town → the town opens better crafting and further roads → ...**
Every milestone after this one feeds or is fed by towns (better stations for gear tiers, roads
to the second zone, a market in a market town, defence as group content).

## Raising: how a town gets built
1. **Sites.** A few fixed **town sites** on the map, each with a plot layout of footings
   (where each building will stand) and a radius. The Spawn Meadow is the first site and every
   player's home. A site starts as **cold ground**: a ring of marker stones and a ledger post.
2. **Projects.** Each building is a project with a **bill**: materials (ash wood, stone, planks,
   ember sap, later bars) and **labour** (a number of work presses, like gathering). Bills are
   data in one file, tuned like the skill curve.
3. **Delivering.** Walk up to a footing or the ledger post, look at it, press E: the prompt says
   what it still needs and what you carry, e.g. "[E] Lay 12 Stone (38 / 120)". A press delivers
   what you hold toward the bill. Juice: the stack flies from you to the footing, a thunk, a
   toast ("+12 Stone to the Storehouse"), and the scaffold **visibly grows**: each tenth of the
   bill adds a piece (posts, then a wall course, then rafters, then the roof).
4. **Labour.** At a project with its materials in, press E to work: a timed bar and a motion like
   gathering (hammering, hauling, setting stone). Labour gives XP in a new skill, **Raising**
   (cap 100 like every skill, its own unlocks: work faster, carry more per delivery, a builder's
   title, later "master builder" projects only a high Raising level can lead).
5. **Better together.** Several people delivering or working at one site within a minute form a
   **crew**: a small XP bonus and the work bar runs a little faster for each of them, shown on
   screen ("Crew of 3").
6. **Raised.** When the bill is paid, the last piece drops in with a burst everyone near sees
   (the level-up beam's cousin), a server-wide banner names the building and the town, and the
   building's service turns on at once. The ledger board lists the biggest contributors to every
   building, permanently.
7. **Stages.** A town's stage is how many of its buildings stand: **Cold ground → Kindling →
   Steading → Hamlet → Village → Town**. Each stage opens the next set of footings and changes
   how the town looks from afar (more lights at night, a taller silhouette, smoke from more
   chimneys). Stage gates are counts of finished buildings, never a timer.
8. **No chores, no decay.** Built things never decay because nobody logged in. A town may have
   an optional **warmth** that players feed with fuel for a small bonus in its radius (a bit more
   XP, a faster bench); warmth runs down slowly and costs nothing when it is out.
9. **Sized for the population.** A bill's size scales gently with how many characters were active
   in the last week, between a floor and a ceiling, so ten players and five hundred both see a
   building rise in days, not months. The scaling is visible on the ledger, never secret.

### The first buildings (the Spawn Meadow)
| Building | Stage it opens | What it does for everyone |
|---|---|---|
| Fire ring | Kindling | Respawn point and a warm radius that keeps night danger back (feeds Milestone 2's night creatures) |
| Ledger board | Kindling | Shows every project, its bill, the crew and top contributors |
| Storehouse | Steading | A personal store for each player at that town (storage from the old Milestone 5) |
| Raised bench | Steading | A better workbench: faster crafts and the higher Toolcraft recipes |
| Kiln | Hamlet | Refining wood to planks and clay to bricks (feeds gear tiers) |
| Watch fire | Hamlet | Lights the town on the map from anywhere, warns of Dimming tides |
| Forge | Village | Smelting ore to bars and gear tiers (Milestone gear) |
| Market board | Village | The player market (trade milestone) |
| Lantern road | any | Lit, flattened path to the next site: faster walking and safe at night |

## The map: hand-shaped, beautiful, cheap
The terrain stays deterministic from `WORLD_SEED` (the server never streams it). What changes is
that we stop leaving the layout to noise. A new authored layer, `game/shared/world_map.gd`
(owned by `world`), is plain data that both the server and the client read:
- **Regions** with a name and a mood (the meadow, the ash lowlands, the pine heights, the stone
  ridges, the lake hollows), so each has a reason to walk there.
- **Town sites**: position, radius, footings (id, position, size, facing) and the site's
  character. Ashgrove gets four: the **Spawn Meadow** (centre), a **lakeside landing**, a
  **ridge quarry** and a **pine steading**, each 120 to 200 m from the meadow, each with a
  landmark you can see from the next.
- **Roads** as polylines: the terrain flattens and paints a path along them. The first roads
  are faint tracks; a Lantern road project turns one into a lit road.
- **Height stamps**: authored shapes added on top of the noise (flatten a town plot, cut a pass,
  raise one tall lookout crag with a view over the whole valley, shape a lake shore). Stamps
  are smooth and local, so saved characters elsewhere stand where they stood; anyone a stamp
  moves is lifted onto the new ground on login (the existing unstuck path).
- **Landmarks**: a few hand-placed set pieces (the lookout crag, an old giant ember ash, a cold
  grey scar where the Dimming touched the valley) placed so there is always one in view.

**The map window (M).** A painted map in Emberlight colours: hill-shaded relief from the height
field (one 256 px image, generated once, within the art bible's texture rule), vector lines for
roads, shores and region names, town icons that show each town's stage and what it is building
now, the watch fires, you and your party. Areas you have never seen are softly fogged and fill
in as you walk (saved per character). The compass and the map show the way to the nearest
project that needs what you carry.

**Beyond Ashgrove.** The second zone (the roadmap's "Beyond the valley") is laid out on paper
first as a hand-drawn region plan in this file's style (sites, roads, landmarks, moods), then
built on its own seed and stamps, with its own cold sites.

## Fit with what we have (honest scope)
- **Server.** Town state is a handful of numbers per site: per project, the amount of each
  material and labour paid, plus top contributors. It lives in a new add-only table (the next
  migration number), loaded on boot and saved within a few seconds of any change, because
  Railway redeploys on most merges: **town progress must survive every deploy** (lesson 10).
  The JSON store gets the same for local runs.
- **Protocol.** One bump in gameplay's bump PR: `s2c_towns` (every site's stage and project
  progress, on login and on change, a few hundred bytes), `c2s_deliver(site, project, item,
  count)`, labour on the existing timed-channel pattern (`c2s_work_start` / cancel), and
  `s2c_raised` (who, what, where) for the banner. No per-tick traffic.
- **Render budget.** The night spawn shot is at about 286 of 300 draw calls today, so **world
  must make room first** (the mid-distance tree LOD, grazer shadows off on Low, merging). Each
  site's buildings are baked from a procedural kit (posts, beams, plank walls, stone courses,
  thatch and shingle roofs) into a few merged meshes per stage on the shared `solid` and `glow`
  materials, built once at world build and switched by visibility as the state changes. Target:
  at most 6 draw calls and 40k triangles per visible town, no new materials.
- **Population.** The server sends every player to every player today. That is fine to about 50
  online; interest management (only send what is near) is scheduled before 100, as a qa-gated
  perf item, not after a crisis.
- **Bots.** Bots deliver, work, see a building rise, and log in again after a server restart to
  find it still standing. A building is never "done" until that runs in CI.

## Phases
The milestone details and "done when" lists are in `docs/roadmap.md`. In short:
1. **The first fire** (groundwork, alongside the current milestone): the authored map layer with
   the four sites marked and the meadow plot flattened, town state that persists, the map window.
2. **The Hearth rises** (its own milestone, right after First blood): the Spawn Meadow raised
   from cold ground to Steading by players, the Raising skill, crews, the ledger, banners.
3. **Gear from the town's stations**: the Kiln and the Forge are town projects that open refining
   and gear tiers.
4. **Many hearths**: the other three Ashgrove sites can be kindled, charters, roads and hauling,
   watch fires, Dimming tides (PvE defence, needs creatures).
5. **Beyond the valley**: the hand-planned second zone with cold sites of its own.
6. **Market towns**: the market board, trade between players, regional prices from hauling.
7. **Ground worth holding**: stewards chosen by contributors, homesteads, and opt-in contests
   between willing groups over a town's perks.

## Never (the overpromise guard)
- Never tell players about a phase before it is on `main` and in the bot test.
- Never sell access to unfinished systems, and never let money buy town progress.
- Never wipe the world. Never let a town lose buildings to time, chores or people who didn't opt
  in.
- Never start phase N+1's systems while phase N's "done when" is false, except groundwork that
  is already listed as such.
