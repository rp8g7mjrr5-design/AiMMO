# Render budget: hidden nodes draw nothing (qa)

`main` has failed the client smoke render budget since #243 ("world materials 17 is over the
ceiling 16" on every shot). The campfire placement ghost (`PlaceGhost`) waits hidden in every
world with its own translucent `StandardMaterial3D` override, and `RenderStats.count_materials`
counted it even though it never draws until the player is placing a fire.

Fix: `count_materials` skips a hidden Node3D and everything under it, as its comment always said
("everything drawn"). Unit test covers hidden and shown. The ceiling stays 16; while placing, the
ghost is one more material for those seconds only. Landed with the beach-trees PR (#247), which
was the first PR to reach the smoke step after #243.
