## 2026-11-26: clean carved characters (owner switched from C to B)

**What:**
- The goofy cartoon folk (#238) were in game for under an hour. Then the owner said: "Now that i look at it i want to go with B clean carved real proportions".
- `Carved` (`game/procgen/carved.gd`) replaces `Toon` on survivors and Zombai.

**How it's built:**
- It runs on the real `AvatarSkeleton`, with no leg scaling. `AvatarAnimator.leg_scale` and `apply_pose(..., root_scale)` stay in, but are set to 1.
- Parts are 6- and 7-sided tapered prisms, faceted 7x5 balls and blocks (`PrimitiveMesh.get_mesh_arrays()`, which works headless).
- Each part rides one bone and all parts merge into one skinned mesh.
- Normals are flat, one per face, oriented to the primitive's own normals.
- It uses the "carved" Emberlight material with the grain and brush set to 0. This replaces "folk", so the material count stays at 16.

**Numbers:**
- About 1,100 to 1,200 triangles per survivor and about 1,000 per walker.
- About 3 ms to build one.

**Known:**
- The hood is a faceted ball set back from the face, with a cowl on the shoulders and a cloak. From the front, in undyed wool, it can read close to hair. A peaked hood is a possible follow-up.
- `ZombaiBody.parts()`/`mesh()` and `AvatarBuilder.parts()` are still only used by tests. The cleanup follow-up stands.
- The island-look thread is turning on world-wide flat `facets` and turning the grain off by default in Emberlight. The carved figures already have flat normals and no grain, so either order of merge is fine.
