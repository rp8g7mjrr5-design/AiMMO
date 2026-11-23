# AiMMO Roadmap

The road from today to the game in the design bible's "The vision in one paragraph":
**gather → craft → fight → level up → explore further**. The roadmap is a list of
**milestones in order**, not dates. Each milestone has a goal a player can feel and a
"done when" list. Streams work on the **current milestone** first; they may build ahead on
the next one only when nothing in the current one is unblocked for them. A broken system or
a serious bug always goes first. The weekly review names each week's release after what that
week added to the current milestone, and moves the "current" marker when a milestone's
"done when" list is all true.

Every milestone follows the owner directions in `docs/design_bible.md`, especially fun comes
first, 5 (the long road) and 6 (take the best, then beat it): before a milestone's first
system PR, its stream writes a few lines in its devlog on which MMO does that feature best,
what players love and hate about it, and how ours improves on it.

## Milestone 0: Foundations (finishing now)
Shared world, accounts, movement, chat, persistence, day and night, gathering, crafting at
the workbench, the self-updating client. Still in flight and still first in every backlog:
protocol v3 real gathering, the action camera, chat is for talking (slash commands to real
UI), crafting through `c2s_craft`.
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

## Milestone 3: Better gear (tiers and refining)
**Goal:** a reason to keep crafting: each tier of material makes clearly better gear.
- Refining skills (wood to planks, stone and ore to bars) and the first ore.
- Armour and weapons in tiers, with some rolled variation per craft; master crafters make
  better rolls. Gear changes your silhouette.
- A character panel with equipped gear.
**Done when:** there are at least three gear tiers, refined materials, armour that changes
how fights go and how you look, and a crafted item's quality depends on skill level.

## Milestone 4: Beyond the valley (a second zone)
**Goal:** a harder place with better resources that you need Milestone 3 gear to survive.
- A new zone next to Ashgrove (same seed rules: new zone, its own seed, the old world
  unchanged), with its own look, creatures, tier-3 and tier-4 materials, landmarks.
- Soft gating: you can walk in, but it is dangerous below the right gear and levels.
- Chapter two of the mystery as a short quest chain (the old Week 07 "Embers Below").
**Done when:** a geared player can travel there, survive, gather and fight things that
can't be found at home, and bring them back to craft.

## Milestone 5: A town of our own (towns and trading)
**Goal:** a place to meet, trade and build together.
- The Hearth (the old Week 06): players donate resources to raise communal buildings at
  the meadow, which unlock better crafting stations.
- Player trading: direct trades, then a market that is easy to use and hard to exploit.
- Storage, a bank or chest per player.
**Done when:** two players can trade safely, anyone can buy and sell through the market,
and the town visibly grows from what players gave.

## Milestone 6: Better together (parties and group content)
**Goal:** doing things with friends is the best way to play.
- Parties with shared kill credit and XP, party markers on the compass.
- Group events in the world and elite creatures that need a group.
- Proximity or zone chat (from the backlog).
**Done when:** a party of four can form, take on an elite or event together, and all get
rewarded, with the bot test running parties.

## Milestone 7: Ground worth holding (territory and opt-in PvP)
**Goal:** groups build up and contest places in the world, for those who want it.
- Groups (our own design and name) that claim and improve settlements.
- Opt-in PvP: flag yourself for it; contests over territory between willing groups.
- Territory perks that matter to the whole town (better stations, lower fees).
**Done when:** a group can claim and improve a settlement, another willing group can
contest it, and players who never flag for PvP are never forced into it.

## Further out
More skills (cooking, fishing-like and others, each with our own name), more zones, deeper
chapters of the mystery, housing, seasonal world events, Steam (blocked until the owner sets
it up).

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

## Backlog (unscheduled)
- Zone or proximity chat, private messages
- Emotes
- Interest management (only send nearby players) once the population needs it
- Procedural ambient music
- Moving database calls off the server's main thread
- Steam integration (blocked until the owner sets it up)
