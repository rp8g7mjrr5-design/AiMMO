# AiMMO Roadmap

The road from today to the game in the design bible's "The vision in one paragraph":
**gather → craft → fight → level up → explore further**, and, since the owner's direction of
2026-11-24, **raise the town** (`docs/vision.md`: a beautiful map with towns the community builds). The roadmap is a list of
**milestones in order**, not dates. Each milestone has a goal a player can feel and a
"done when" list. Streams work on the **current milestone** first; they may build ahead on
the next one only when nothing in the current one is unblocked for them (the exception is the
listed groundwork for Milestone 3, "The first fire", which sits under the current items). A broken system or
a serious bug always goes first. The weekly review names each week's release after what that
week added to the current milestone, and moves the "current" marker when a milestone's
"done when" list is all true.

Every milestone follows the owner directions in `docs/design_bible.md`, especially fun comes
first, 5 (the long road) and 6 (take the best, then beat it): before a milestone's first
system PR, its stream writes a few lines in its devlog on which MMO does that feature best,
what players love and hate about it, and how ours improves on it. Everything a milestone puts
on screen follows the Emberlight art bible (`docs/art_bible.md`) and stays inside its render budget.

## Milestone 0: Foundations (finishing now)
Shared world, accounts, movement, chat, persistence, day and night, gathering, crafting at
the workbench, the self-updating client. Real gathering (v3), the
action camera and the F1 controls card are done. Left as of 2026-11-23, first in every
backlog: the workbench window on `c2s_craft` (client), then the chat gate (gameplay) and its
CI check (qa), the pack window on I (client), and facing yaw in protocol v5 (gameplay, then
client).
**Done when:** a new player can gather and craft with keys and windows only, no chat command
anywhere, through the over-the-shoulder camera.

## Milestone 1: The long road begins (skills and XP) ← current
**Goal:** every gather and craft visibly moves you toward a level, every level gives you
something, and there is always a next unlock in view.
- Four skills to start, with our own names: **Felling** (ash and pine), **Quarrying**
  (stone), **Tapping** (ember sap), **Toolcraft** (crafting at the bench). Cap 100, our own
  curve, numbers in one data file (`game/shared/skills.gd`).
- XP on every gather and craft, shown as it lands. Small bonus XP for working near another
  player.
- Each level: a small speed or yield gain. Every few levels: a named unlock. Includes the
  first **tier-2 nodes** (an old ember ash, a richer stone seam) a short walk from the
  meadow that need a level to work, and the first recipes that need a Toolcraft level.
- Level-up moment: sound, a light burst others can see, a banner naming the unlock.
- A skills window (its own key) with levels, progress bars, next unlock, and the total
  across skills. A small on-screen goal: "Next: Felling 5 unlocks ...".
- Saved per character (add-only migration; old characters start at level 1 with 0 XP).
**Done when:** a fresh character levels a skill within 90 s of their first gather; reaches
level 5 in some skill within about 10 minutes; the skills window shows all four with their
next unlock; levels survive logout; tier-2 nodes refuse a too-low level with a clear hint;
the bot test covers XP, a level-up and persistence, and qa's fun metrics report time to
first level-up.

## Milestone 2: First blood (action combat with crafted weapons)
**Goal:** something worth fighting just outside the Spawn Meadow, with weapons you made.
- Health and stamina. Aimed light and heavy attacks, block, dodge roll. Enemies telegraph.
- First weapons crafted at the bench from Milestone 1 materials (a couple of weapon types
  that play differently), each with its own mastery skill that levels by use.
- Creatures: gentle wildlife first (the old Week 04), then a few hostile ones in the
  ridges and at night (the old Week 05). Drops that feed crafting. Torches and campfires
  keep danger back at night.
- Fair failure: you respawn at the meadow and lose little.
- First chapter of the ember ash mystery hinted by what the creatures guard.
**Done when:** a player can craft a weapon, fight and kill a creature with readable,
responsive combat (input feedback under 100 ms), level a weapon mastery, and die and come
back without losing progress; bots fight in the bot test.

## Milestone 3: The Hearth rises (players raise the first town)
**Goal:** the owner's headline (`docs/vision.md`): the Spawn Meadow is built by its players.
Every gather and craft can go into a building you watch go up, and the town that stands is
the server's shared progress. Groundwork for it ("The first fire", below) runs alongside
Milestones 1 and 2.
- Town state that persists through every deploy and restart (add-only migration), sites and
  footings from the authored map layer `game/shared/world_map.gd`.
- Projects with bills of materials and labour, delivered and worked with E at the footing.
  Each tenth of a bill visibly adds to the scaffold; a raised building drops in with a burst and
  a server-wide banner.
- The **Raising** skill (cap 100, its own unlocks), crews (several builders nearby: bonus XP and
  faster work), the ledger board naming contributors.
- The meadow from cold ground to **Steading**: Fire ring, Ledger board, Storehouse (a store per
  player) and the Raised bench. Each turns its service on the moment it stands.
- The map window (M): painted relief, the four Ashgrove sites and their stages, explored fog.
**Done when:** a group of fresh characters raises the Fire ring in one evening and sees each
delivery change the scaffold; the meadow reaches Steading through play; every building's
service works; town progress survives a server restart in the bot test; bots deliver, work
and log back in to find the building standing; the town fits the render budget (at most 6 draw
calls per visible town).

## Milestone 4: Better gear (tiers and refining, from the town's stations)
**Goal:** a reason to keep crafting: each tier of material makes clearly better gear, made at
stations the town raised.
- The Kiln and the Forge are meadow projects (Hamlet and Village stages) that open refining
  skills (wood to planks, stone and ore to bars) and the first ore.
- Armour and weapons in tiers, with some rolled variation per craft; master crafters make
  better rolls. Gear changes your silhouette.
- A character panel with equipped gear.
**Done when:** there are at least three gear tiers, refined materials made at town stations,
armour that changes how fights go and how you look, and a crafted item's quality depends on
skill level.

## Milestone 5: Many hearths (the rest of Ashgrove settles)
**Goal:** the valley fills with towns that differ, joined by roads players built.
- The lakeside landing, ridge quarry and pine steading can be kindled. Each site's surroundings
  shape what it can build; at Hamlet its contributors pick a charter that decides its later
  buildings.
- Lantern roads between sites (a project per road), hauling heavy crates on foot for the big
  bills.
- Watch fires and **Dimming tides**: now and then at night the Dimming creeps toward a town and
  the server defends it together; a lost building goes cold (service off) until relit with a
  small repair bill, never removed.
- Interest management before the population needs it (qa perf gate at 50 and 100 bots).
**Done when:** at least two towns besides the meadow have been raised past Kindling by play,
a road links them, a tide has been fought off in the bot test, and nothing ever deleted a
building.

## Milestone 6: Beyond the valley (a second zone)
**Goal:** a harder place with better resources that you need Milestone 4 gear to survive.
- A new zone next to Ashgrove, planned by hand first in `docs/vision.md`'s map style (sites,
  roads, landmarks, moods), then built on its own seed with authored stamps; the old world is
  unchanged. Its own look, creatures, tier-3 and tier-4 materials, landmarks and cold town
  sites.
- Soft gating: you can walk in, but it is dangerous below the right gear and levels.
- Chapter two of the mystery as a short quest chain ("Embers Below").
**Done when:** a geared player can travel there, survive, gather and fight things that can't
be found at home, and bring them back to craft or to raise a town.

## Milestone 7: Market towns (trading)
**Goal:** a place to meet and trade.
- Player trading: direct trades, then the market board (a town building) that is easy to use
  and hard to exploit. Prices differ by town, so hauling pays.
**Done when:** two players can trade safely, anyone can buy and sell through a town's market,
and a haul between towns is worth making.

## Milestone 8: Better together (parties and group content)
**Goal:** doing things with friends is the best way to play.
- Parties with shared kill credit, XP and crew credit, party markers on the compass and map.
- Group events in the world and elite creatures that need a group; bigger tides.
- Proximity or zone chat (from the backlog).
**Done when:** a party of four can form, take on an elite or event together, and all get
rewarded, with the bot test running parties.

## Milestone 9: Ground worth holding (stewards, homesteads, opt-in contests)
**Goal:** groups build up and care for places in the world, for those who want it.
- Stewards chosen by a town's contributors; they pick the next projects and the charter path.
- Homesteads: plots a Village opens, for a player's own small building and garden.
- Opt-in PvP: flag yourself for it; willing groups contest which banner holds a town's perks
  (lower fees, a station bonus). Contests never remove buildings.
**Done when:** a town has a steward, a player has a homestead, and two willing groups can
contest a town's perks while players who never flag are never forced into it.

## Groundwork: The first fire (alongside Milestones 1 and 2)
Small, independent items that make Milestone 3 fast and give the map its shape now. They sit
just under each stream's current-milestone items:
- **world:** the authored map layer `game/shared/world_map.gd` (regions, the four sites with
  footings, faint tracks, the first height stamps: the meadow plot, the lookout crag), and
  making room in the render budget for towns.
- **gameplay:** town state that persists (migration, store, load on boot, save on change), and
  the Raising data file (bills, stages) with no protocol yet.
- **client:** the map window (M) from the height field and the map layer.
- **qa:** a bot-test restart step that proves world state survives a server restart.

## Further out
More skills (cooking, fishing-like and others, each with our own name), more zones, deeper
chapters of the mystery, seasonal world events, Steam (blocked until the owner sets it up).

## The next six weeks (director forecast, 2026-11-23)
A forecast, not a promise: it is redrawn every morning from what actually landed. Release
weeks start Friday; the PR budget week starts Wednesday (`docs/budget.md`), so each stream
has about 40 PRs between Wednesdays. At 2026-11-23's pace (60 worker PRs landed in a day) a
milestone takes two to four days of work, and the budget, not the work, sets the pace.

| Week | Dates | Focus |
|------|-------|-------|
| 00 | to Thu 26 Nov | Close Milestone 0 (craft window on `c2s_craft`, chat gate, pack window, facing yaw v5) and Milestone 1 (level-up moment, skills window, tier-2 nodes and props, Toolcraft recipes, pace check, bot-test gates). |
| 01 | 27 Nov to 3 Dec | Groundwork "The first fire" (map layer, persistent town state, map window) alongside Milestone 2's start: health and stamina, light and heavy attacks, dodge, the first two crafted weapons and their mastery skills, gentle wildlife outside the meadow. |
| 02 | 4 to 10 Dec | Milestone 2 done: hostile creatures in the ridges and at night with clear telegraphs, fair death and respawn, torches and placed campfires, the first hint of the mystery. |
| 03 | 11 to 17 Dec | Milestone 3, the Hearth rises: deliveries and labour at the meadow's footings, the Raising skill, crews, the ledger, Fire ring and Ledger board raised by play, the map window. |
| 04 | 18 to 24 Dec | Milestone 3 done (Storehouse, Raised bench, Steading); Milestone 4 starts with the Kiln and refining. |
| 05 | 25 to 31 Dec | Milestone 4: the Forge, the first ore, three gear tiers, rolled quality, the character panel. |

## Week history
| Week | Release | Notes |
|------|---------|-------|
| 00 | **First Steps** | Foundation, day and night, gathering, crafting, action camera, self-updating client (Milestone 0). |

## Director notes
**Director note (2026-11-22):** with four streams shipping in parallel, Week 01 work (clock, sky, settings) started in Week 00. That's fine: streams may build ahead on next week's headline, but the headline for a week is what gets polished and released that week. Gathering's data and art groundwork (node positions, node props, inventory migration) may start late in Week 01 so Week 02 doesn't stall on dependencies.

**Director note (2026-11-22, gathering):** the owner wants gathering to feel like mainstream MMOs: walk up, prompt, press E or click, a timed gather bar with animation, an item toast, and nodes that visibly empty and regrow. Typing `/gather` is debug-only from now on. Protocol v3 on 2026-11-23 carries it (with `ack_seq` and the pack), client wires it right after, world adds highlight and hit effects, qa covers it in the bot test. See "How gathering feels" in the design bible.

**Director note (2026-11-22, owner directions):** three standing rules from the owner now sit in the design bible under "Owner directions". (1) Chat is for talking: every slash command moves to keys and windows, and commands only work on a `--dev-commands` server. (2) An over-the-shoulder action camera with always-on mouse look and camera-relative movement. (3) Gathering targets what you look at. Order for the streams after gathering: camera, then the chat-to-UI moves (pack window, players panel, time tooltip, F1 controls), then crafting, which is built UI-first. The rest of this roadmap is still the AI's to plan.

**Director note (2026-11-23, vision and roadmap):** the owner set the direction: the New
World feel for the whole game, the RuneScape-style long skill grind, take the best of other
MMOs and beat it, and the goal of being the best MMO. The old week table (wildlife, health,
the Hearth, quests) is folded into milestones 2, 4 and 5. Milestone 1 (skills and XP) is
current and is seeded in every stream's backlog right after the Milestone 0 items still in
flight.

**Director note (2026-11-23, morning):** Milestone 1 is about half built in a day (skills,
XP, protocol v4, XP floaters, skill badges, the level-up burst). Its remaining done-when items
are the level-up banner, the skills window, tier-2 nodes with a level gate, and bots that level
up in CI. Milestone 0 is not closed yet: the workbench window still sends `/craft`, so the chat
gate can't go on. Both are at the top of today's backlogs. Backlogs were trimmed to 12 ordered
items per stream; everything else sits under "Later" in each file, so workers stop picking
low-value follow-ups ahead of milestone work.

**Director note (2026-11-24, owner direction: towns the community raises):** the owner wants
a beautiful map with towns that build up from community, delivering the spirit of the big
settlement MMO promises that never arrived. The study is `docs/research/promises_study.md`, the
design `docs/vision.md`. Towns move up from Milestone 5 to Milestone 3, right after First blood
(which is already in flight), and gear now comes from stations the town raises. The second zone,
trading, parties and territory move down one or two places. Groundwork ("The first fire") is
seeded under each stream's current-milestone items.

## Backlog (unscheduled)
- Zone or proximity chat, private messages
- Emotes
- Interest management (only send nearby players): scheduled in Milestone 5, earlier if qa's perf runs say so
- Procedural ambient music
- Moving database calls off the server's main thread
- Steam integration (blocked until the owner sets it up)
