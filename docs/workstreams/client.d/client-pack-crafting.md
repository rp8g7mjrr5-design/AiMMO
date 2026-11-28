Done: the "craft anywhere" half of **Basics 2: craft anywhere, and the weapon in your hand** (claude/project-thread-dkgkif, owner request 2026-11-28)
The pack window (I) has a Craft column (hand recipes anywhere, bench ones listed and lit at a bench) and your traveller facing you with your best kit in hand.

Follow-ups:
- [ ] **Basics 2: the weapon in your hand in the world.** The pack figure already holds `PackPreview.held_for(pack)` via `HeldItems.attach`; do the same on every avatar in view (the swung weapon; the tool while gathering), and the bandaging motion on H. *Fun: what you just crafted is in your hand on the beach.*
- [ ] **A workbench you build (gameplay, needs a protocol bump after thirst #252).** A `workbench` hand recipe, placed with B like a campfire, saved (add-only table), sent to clients; `Crafting.near_bench` checks any bench in reach, so the stone column in the pack lights up at your own bench. Owner asked for it 2026-11-28.
