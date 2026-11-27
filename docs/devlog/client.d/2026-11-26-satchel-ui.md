# Satchel UI (owner pick, 2026-11-27)

The owner said the inventory and menus looked basic. I mocked up three directions in the real
client behind a temporary `AIMMO_UI_STYLE` switch (field journal parchment, leather satchel,
ash-and-ember glass), shot pack (day and night), workbench and settings for each, and the owner
picked the satchel. Shots: project files `ui-style/`.

- `game/procgen/ui_skin.gd` (UiSkin): the leather nine-patch (384 px, 40 px margins, about
  95 ms to build once at startup in GDScript) and the check-box icons. Colours in `palette.gd`
  (`UI_LEATHER`, `LEATHER_THREAD`, `IRON_SHADE`, `IRON_LIT`); `LEATHER` was taken by the
  character palette.
- `HudStyle`: `panel()` is now the leather (a StyleBoxTexture); the old warm grey is
  `flat_panel()`. `theme(true)` is the over-the-world theme (chat, top bar, dial, compass,
  prompts, vitals, notice, perf) with flat panels. `title()`, `title_case()` and `slot_look()`
  are new; every window title goes through `title()`.
- Tried and dropped: the parchment journal (dark ink text needed its own colour set for every
  label and glared at night) and the glass panel (clean but read as any game's menu).
- The controls overlay grew past 720 px with the leather's padding; trimmed its margin to 12
  and its row gap to 3.
- Known: the pack window still uses the old 5-wide slot grid; the grid inventory with item
  sizes (owner asked, Tarkov or ARC Raiders style mechanically) is the next PR.
