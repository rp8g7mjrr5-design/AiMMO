# AiMMO Roadmap

The road from today to the game in `docs/vision.md` (owner direction, 2026-11-24): **a
small-server survival game** with generated worlds, the Hollows, bands that claim land with
resolve, raids, and seasons that end in wipe day. The roadmap is a list of **phases in order**,
not dates. Each has a goal a player can feel and a "done when" list. Streams work on the
**current phase** first; they may build ahead on the next one only when nothing in the current
one is unblocked for them. A broken system or a serious bug always goes first. The weekly review
names each week's release after what it added to the current phase, and moves the "current"
marker when a phase's "done when" list is all true. Milestones 0 and 1 below are the
foundations already built; anything still open in them stays first in its backlog.

Every phase follows the owner directions in `docs/design_bible.md` (fun comes first, the
mass-appeal lean in `docs/vision.md`, take the best and beat it): before a phase's first system
PR, its stream writes a few lines in its devlog on which game does that feature best, what
players love and hate about it, and how ours improves on it. Everything on screen follows the
art bible (`docs/art_bible.md`) and stays inside its render budget.

## Milestone 0: Foundations (finishing now)
Shared world, accounts, movement, chat, persistence, day and night, gathering, crafting at
the workbench, the self-updating client. Real gathering (v3), the
action camera and the F1 controls card are done. Left as of 2026-11-23, first in every
backlog: the workbench window on `c2s_craft` (client), then the chat gate (gameplay) and its
CI check (qa), the pack window on I (client), and facing yaw in protocol v5 (gameplay, then
client).
**Done when:** a new player can gather and craft with keys and windows only, no chat command
anywhere, through the over-the-shoulder camera.

## Milestone 1: The long road begins (skills and XP) (finishing now)
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

## Phase 1: The turn (generated worlds, servers and seasons) ← current
**Goal:** the game runs on a fresh generated valley per server and season, and players can see
which server they are on and when its season ends. Everything already built (gathering,
crafting, skills, combat basics) works there.
- A seed per server and season; characters belong to a server and season (add-only columns;
  today's characters become season 0 of the first server, untouched).
- The generator v1: a valley about 1 km across from a seed (rivers and lakes, ash lowlands, pine
  heights, ridges, Dimming scars) with resource nodes placed by it, and a first set piece
  (the spawn town plot). Today's Ashgrove stays as the test seed and the live world until
  season 1.
- The client builds terrain and props in chunks around the player, inside the render budget.
- A server list on the login screen (name, players / cap, season day, days to wipe).
- The player cap as a server setting (32 to start).
**Done when:** two servers with different seeds run side by side in the bot test, characters
stay on their own server, a generated world is gatherable and craftable end to end, the
client's spawn shot on a generated world fits the render budget, and qa's 32-bot run passes the
perf budget.

## Phase 2: Survive the first night
**Goal:** staying alive is a game: you get hungry, thirsty and cold, and the Hollows come at
night.
- Hunger, thirst, warmth and rest on top of today's vitals, forgiving and readable.
- Fires to cook and warm by; water from lakes and rivers; foraging and the first cooking.
- The Hollows: slow by day, packs at night, drawn to noise and light; real telegraphs, using the
  combat already on `main`. Wildlife hunting (grazers drop hide and meat).
- Death drops a lootable pack where you fell; respawn at the spawn town in under a minute; a
  small XP slice lost, never a level.
**Done when:** a fresh player learns, in one evening, to avoid dying of cold, hunger and to a
Hollow; the fun metrics report time to first fire and nights survived; bots die, loot and
respawn in the bot test.

## Phase 3: A roof over your head
**Goal:** building a shelter that keeps the night out.
- Snap-grid building: foundations, walls, doorways and doors, floors, roofs, in wood then stone,
  procedural and on the shared materials.
- Doors with owners, chests, a bedroll that sets your respawn.
- Building is saved per server and season and survives every restart and deploy.
**Done when:** a player builds a shelter that Hollows can't get into at night, it survives a
server restart in the bot test, and a walled base fits the render budget.

## Phase 4: Bands and claims
**Goal:** friends become a band and stake their land.
- Bands (2 to 8), ranks, relations; a band panel.
- Resolve per member and per band; claim stones and 32 m plots; build, door and container
  permissions inside claims; Hollows don't rise in claims.
- The spawn town as a safe, unclaimable zone, and its first shared project.
**Done when:** a band claims land, outsiders can't build or loot there, resolve moves with time
online and deaths, and all of it runs in the bot test.

## Phase 5: Raids and night sieges (the clip moments)
**Goal:** the moments people share.
- Breaching tools and build tiers; over-reach; claiming over outer plots; the offline damage
  rule.
- Night sieges: on the darkest nights Hollows gather on the loudest, brightest bases.
- The moments get their own sound, light and camera feel; a server-wide feed line ("A siege is
  gathering at the north ridge").
**Done when:** an over-reached band can be raided, a band within its resolve is never raided at
full strength while all members are offline, a night siege can be held or lost, and the bot
test runs a raid and a siege.

## Phase 6: Wipe day (seasons live)
**Goal:** the season is an event.
- Season settings (length 6 to 8 weeks), an in-game and server-list countdown, the last night,
  and the new map at a set hour.
- Season records (longest survivor, biggest hold, nights held) on a leaderboard and kept on the
  account; titles that carry over.
- Streamer mode; the player cap raised to 48 if the perf gates hold; a second public server.
**Done when:** a season ends and a new one starts on a fresh seed without touching accounts or
records, the countdown and leaderboard work, and qa's 48-bot run passes the perf budget.

## Phase 7: Depth (ongoing)
Wounds and illness, farming, fishing, more Hollow kinds and bigger sieges, more biomes and set
pieces, carts, proximity voice, a spectator camera, the spawn town's later projects.

## The next six weeks (director forecast, 2026-11-24)
A forecast, not a promise: it is redrawn every morning from what actually landed.

| Week | Dates | Focus |
|------|-------|-------|
| 00 | to Thu 26 Nov | Close Milestones 0 and 1; Phase 1 starts (server and season ids, generator v1 groundwork, server list). |
| 01 | 27 Nov to 3 Dec | Phase 1 done: generated valley, chunked terrain, two servers in the bot test. |
| 02 | 4 to 10 Dec | Phase 2: needs, fire and cooking, the first Hollows at night, death and loot. |
| 03 | 11 to 17 Dec | Phase 3: snap-grid building, doors, chests, bedroll respawn. |
| 04 | 18 to 24 Dec | Phase 4: bands, resolve, claim stones, the safe spawn town. |
| 05 | 25 to 31 Dec | Phase 5: breaching, over-reach, offline rule, the first night sieges. |

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

**Director note (2026-11-24, new direction):** the owner chose the small-server survival game
over the towns MMO and asked for mass appeal, leaving the details to us. See `docs/vision.md`.
Milestones 2 to 7 are replaced by Phases 1 to 7: combat, creatures and death fold into Phase 2,
towns shrink to the spawn town (Phase 4), territory becomes bands and claims (Phases 4 and 5),
and the second zone becomes the generator. Phase 1 is seeded at the top of every backlog.

## Backlog (unscheduled)
- Zone or proximity chat, private messages
- Emotes
- Interest management (only send nearby players) once the population needs it
- Procedural ambient music
- Moving database calls off the server's main thread
- Steam integration (blocked until the owner sets it up)
