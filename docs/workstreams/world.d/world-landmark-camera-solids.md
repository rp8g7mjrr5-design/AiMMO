Done: **Camera solids for the ruins and beach landmarks** (follow-ups from #244 and #241) (ws/builder/landmark-camera-solids)
Every ruin part and beach landmark part (walls, chimney, timbers, roofs, well, cart, loot, hull, ribs, pier, shack, bones) is a `WorldSolids` solid, cut into thin cells so it hugs the wall.

Follow-ups:
- [ ] **Coast dressing in the camera solids** if the camera is seen inside a driftwood log or a dune fence (`CoastDress.parts()`; left out because it is thousands of small parts and the camera already keeps off the ground).
