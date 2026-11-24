# AiMMO Roadmap

The road from today to **ZombAi** in `docs/vision.md` (owner direction, 2026-11-24, draft):
a third-person survival game in a fallen medieval kingdom, on generated maps full of
risk-graded ruins, against the Hollows. The roadmap is a list of **phases in order**, not dates.
Each has a goal a player can feel and a "done when" list. Streams work on the **current phase**
first; they may build ahead on the next one only when nothing in the current one is unblocked
for them. A broken system or a serious bug always goes first. Milestones 0 and 1 below are the
foundations already built; anything still open in them stays first in its backlog. The game is
**2 to 8 player co-op**, hosted by a friend (owner, 2026-11-24).

Every phase follows the owner directions in `docs/design_bible.md` (fun comes first, the lean in
`docs/vision.md`, take the best and beat it): before a phase's first system PR, its stream
writes a few lines in its devlog on which game does that feature best, what players love and
hate about it, and how ours improves on it. Everything on screen follows the art bible
(`docs/art_bible.md`) and stays inside its render budget.

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

## Phase 1: A kingdom from a seed ← current (once adopted)
**Goal:** every world is a new, generated stretch of the fallen kingdom, and what we already
built (gathering, crafting, skills, combat basics) works in it.
- A world config (seed, size, generator version) the server sends at login; today's 512 m
  Ashgrove stays as version 0 until the first generated world goes live.
- The generator v1: land, rivers, biomes, the king's roads, and **ruin sites** with grades,
  resource nodes and the spawn point placed from the seed.
- Terrain, props and ruins built in chunks around the player, inside the render budget.
- The first two ruins as data-driven set pieces (a grade 1 burned farmstead, a grade 2 abandoned
  village), built from a procedural medieval kit (timber, stone, thatch, all weathered).
**Done when:** five seeds each give a playable world with water, every node kind, roads and
ruins; a fresh character can gather and craft end to end in one; the spawn shot fits the render
budget; the world builds in under 3 s.

## Phase 2: Survive the first night
**Goal:** staying alive is the game, and the Hollows are the reason the night is scary.
- Hunger, thirst, warmth and rest on top of today's vitals, forgiving and readable.
- Fire, water, foraging, cooking, hunting.
- The Hollows: the common Hollow and the Hollow hound, drawn by noise, faster at night, with
  clear telegraphs; torches and ember-fire hurt them; the chill and the ember salve.
- Death drops a lootable pack where you fell; respawn in under a minute.
**Done when:** a fresh player learns, in one evening, to avoid dying of cold, hunger and to the
Hollows; fun metrics report time to first fire and nights survived; bots fight, die, loot and
respawn in the bot test.

## Phase 3: A roof and a wall
**Goal:** a shelter that keeps the night out, built with friends.
- Snap-grid timber and stone building, doors, palisades and gates, chests, an ember hearth that
  stops Hollows rising inside, a bedroll respawn. Saved and restored through every restart.
- Night sieges: on the darkest nights the Hollows gather on the loudest, brightest holds.
**Done when:** a group builds a hold that Hollows can't get into, a night siege can be held or
lost, the hold survives a server restart in the bot test, and a walled hold fits the render
budget.

## Phase 4: Into the ruins
**Goal:** the map's risk ladder: go further, risk more, come back stronger.
- All four ruin grades (the mine, the drowned village, the abbey, the fallen castle and its
  crypt), each with its own Hollows (soldiers, the Bell-wight) and loot tables.
- Signet keys and vaults; smithing, iron and the first armour; bows and crossbows; ember
  weapons.
**Done when:** a geared group can clear each grade, grade 4 needs keys from grade 3, and loot
from each grade is clearly better than the one below.

## Phase 5: Play with friends
**Goal:** one friend hosts, the others join, and it just works.
- A Host button that starts the server build on the player's machine with a chosen world; join
  by invite code or address; several saved worlds per host; seed and size choice; friendly fire
  and difficulty as host settings.
- Joining a world in progress, leaving and coming back, the host closing the world safely.
**Done when:** a host on a home connection runs a world for 8 players (the bot test runs 8 bots
against a host-started server), worlds survive closing and reopening, and a friend can join in
under a minute from the main menu.

## Phase 6: Launch-ready
**Goal:** a stranger buys it, starts it and has a good first hour.
- A first-hour path that teaches needs, fire, the Hollows and building without a wall of text.
- Settings and accessibility, streamer mode, performance on the target laptop, the rename to
  ZombAi everywhere, a store-ready build.
**Done when:** a new player reaches their first night and survives it without outside help, and
the build passes the perf budget on Low and Medium.

## Phase 7: Depth (ongoing)
Wounds and illness, farming, fishing, carts and horses, more Hollow kinds and ruins, weather,
proximity voice, a spectator camera.

## The next six weeks (director forecast, draft)
A forecast, not a promise. It is redrawn once the owner confirms the direction.

| Week | Dates | Focus |
|------|-------|-------|
| 00 | to Thu 26 Nov | Close Milestones 0 and 1; Phase 1 groundwork (world config, generator v1 land and roads). |
| 01 | 27 Nov to 3 Dec | Phase 1: ruin sites, chunked building, the first two ruins. |
| 02 | 4 to 10 Dec | Phase 2: needs, fire and cooking, the first Hollows, death and loot. |
| 03 | 11 to 17 Dec | Phase 3: building, the ember hearth, the first night sieges. |
| 04 | 18 to 24 Dec | Phase 4: grade 3 and 4 ruins, keys, smithing, bows. |
| 05 | 25 to 31 Dec | Phase 5: host button, invites, saved worlds. |

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

**Director note (2026-11-24, ZombAi, draft):** the owner is reshaping the game: renamed
ZombAi, a post-apocalyptic medieval fantasy (a fallen kingdom), third person, a one-time buy,
and a map that works like Rust's (generated land, roads and risk-graded ruins), with the Hollows
as our own undead. The owner then chose 2 to 8 player co-op hosted by a friend; public servers are a "later, maybe". Magic, undead behaviour and the long-term goal are still being asked. See `docs/vision.md`.
Backlogs are not reseeded until the owner confirms.

## Backlog (unscheduled)
- Zone or proximity chat, private messages
- Emotes
- Interest management (only send nearby players) once the population needs it
- Procedural ambient music
- Moving database calls off the server's main thread
- Steam integration (blocked until the owner sets it up)
