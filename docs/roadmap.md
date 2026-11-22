# AiMMO Roadmap

The plan for the next 4 to 6 weeks. One headline feature per week, plus bug fixes. This is a
plan, not a promise: a broken system or a serious bug always goes first.

| Week | Headline feature | Notes |
|------|------------------|-------|
| 00 | **First Steps**: shared world, accounts, movement, chat, persistence | Shipped (foundation). |
| 01 | **Day and night** | Shared server clock (one day = 40 real minutes), sun and sky colours, stars, lamps glow at night. Gives the world a heartbeat. Also: client-side movement prediction to fix the floaty feel. |
| 02 | **Gathering and inventory** | Chop ash and pine, pick up stones and ember sap. Server-owned resource nodes with respawn timers. Inventory table (add-only migration), simple inventory UI. |
| 03 | **Crafting** | Workbench at the Spawn Meadow, opened with E into a recipe window (no chat commands). A handful of recipes (axe, pickaxe, torch, campfire). Tools speed up gathering. |
| 04 | **Wildlife** | Procedural critters (deer-like grazers, birds) with simple server-side AI. Purely ambient at first. |
| 05 | **Health and danger** | Health, a few hostile creatures on the ridges, respawning at the meadow. Torches keep danger away at night. |
| 06 | **The Hearth** | First shared town building: players donate resources to raise a communal hearth at spawn. First step of the ember ash mystery. |
| 07 | **Embers Below** | First quest chain: a handful of hand-off quests from the Hearth that send players into the ash groves at night, where the trees' warmth pulses. Chapter One of the mystery. Needs a quest table (add-only migration) and a simple quest log. |

**Director note (2026-11-22):** with four streams shipping in parallel, Week 01 work (clock, sky, settings) started in Week 00. That's fine: streams may build ahead on next week's headline, but the headline for a week is what gets polished and released that week. Gathering's data and art groundwork (node positions, node props, inventory migration) may start late in Week 01 so Week 02 doesn't stall on dependencies.

**Director note (2026-11-22, gathering):** the owner wants gathering to feel like mainstream MMOs: walk up, prompt, press E or click, a timed gather bar with animation, an item toast, and nodes that visibly empty and regrow. Typing `/gather` is debug-only from now on. Protocol v3 on 2026-11-23 carries it (with `ack_seq` and the pack), client wires it right after, world adds highlight and hit effects, qa covers it in the bot test. See "How gathering feels" in the design bible.

**Director note (2026-11-22, owner directions):** three standing rules from the owner now sit in the design bible under "Owner directions". (1) Chat is for talking: every slash command moves to keys and windows, and commands only work on a `--dev-commands` server. (2) An over-the-shoulder action camera with always-on mouse look and camera-relative movement. (3) Gathering targets what you look at. Order for the streams after gathering: camera, then the chat-to-UI moves (pack window, players panel, time tooltip, F1 controls), then crafting, which is built UI-first. The rest of this roadmap is still the AI's to plan.

## Backlog (unscheduled)
- Zone or proximity chat, private messages
- Emotes
- Interest management (only send nearby players) once the population needs it
- Procedural ambient music
- Moving database calls off the server's main thread
- Steam integration (blocked until the owner sets it up)
