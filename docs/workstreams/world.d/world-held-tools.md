Done: "Basics 2: held tools and weapons." (ws/builder/held-tools)
`HeldItems` (game/procgen/held_items.gd): carved meshes for all 9 tools, weapons and the torch, plus `attach(skeleton, id)` on the RightHand bone.

Request (from world, 2026-11-27, to client): the meshes are ready for "craft anywhere, and the weapon in your hand": call `HeldItems.attach(avatar_skeleton, id)` each frame with the best carried weapon (or the gathering tool while gathering, "" for fists); it keeps the node when the id is the same. Grip, haft direction and edge side are in the file header.
