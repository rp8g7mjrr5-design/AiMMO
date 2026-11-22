# AiMMO Roadmap

The plan for the next 4 to 6 weeks. One headline feature per week, plus bug fixes. This is a
plan, not a promise: a broken system or a serious bug always goes first.

| Week | Headline feature | Notes |
|------|------------------|-------|
| 00 | **First Steps**: shared world, accounts, movement, chat, persistence | Shipped (foundation). |
| 01 | **Day and night** | Shared server clock (one day = 40 real minutes), sun and sky colours, stars, lamps glow at night. Gives the world a heartbeat. Also: client-side movement prediction to fix the floaty feel. |
| 02 | **Gathering and inventory** | Chop ash and pine, pick up stones and ember sap. Server-owned resource nodes with respawn timers. Inventory table (add-only migration), simple inventory UI. |
| 03 | **Crafting** | Workbench at the Spawn Meadow. A handful of recipes (axe, pickaxe, torch, campfire). Tools speed up gathering. |
| 04 | **Wildlife** | Procedural critters (deer-like grazers, birds) with simple server-side AI. Purely ambient at first. |
| 05 | **Health and danger** | Health, a few hostile creatures on the ridges, respawning at the meadow. Torches keep danger away at night. |
| 06 | **The Hearth** | First shared town building: players donate resources to raise a communal hearth at spawn. First step of the ember ash mystery. |

## Backlog (unscheduled)
- Zone or proximity chat, private messages
- Emotes
- Interest management (only send nearby players) once the population needs it
- Procedural ambient music
- Moving database calls off the server's main thread
- Steam integration (blocked until the owner sets it up)
