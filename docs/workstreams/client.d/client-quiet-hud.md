Done: "Top (owner direction, 2026-11-24: grounded art direction ... Make the HUD quiet" (ws/client/quiet-hud)
`HudStyle` gives the whole HUD one quiet look: one ember accent, calm type with a thin soft edge, warm-grey panels and buttons. Shots in `/mnt/project-files/client/quiet-hud/`.

Done: From gameplay (2026-11-24, eight-player cap): "reset `_full_for = 0.0` in `_on_vitals`" (ws/client/quiet-hud)
Done: From gameplay (2026-11-24, hunt toast): pack window test uses `PackWindow.slot_count(Inventory.ITEM_ORDER.size() + 1)` (ws/client/quiet-hud)
Done: From gameplay (2026-11-24, kingdom placement): workbench window uses `Crafting.workbench_xz()` (ws/client/quiet-hud)

Follow-ups:
- [ ] Follow-up (quiet HUD): the login panel, patch notes and Settings window still use their old sizes (30 px title); bring them onto `HudStyle` sizes and give the login title the ZombAi name once the director's rename lands.
- [ ] Follow-up (quiet HUD): the time dial's sky colours and the vitals bar's health red are still their own; check them against the art bible palette at night on a real GPU.
- [ ] Follow-up (quiet HUD): a smoke shot of the workbench window (`--open-workbench`) so the HUD style check covers a window, not only toasts (qa owns `tests/client_smoke/run.sh`).
