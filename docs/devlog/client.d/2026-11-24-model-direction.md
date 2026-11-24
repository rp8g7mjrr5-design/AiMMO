# Model direction (docs only)

**What:** the owner liked the sculpted test-camp characters ("this is a way better start") and asked to "fine tune our models more, give them direction". Art bible section 3, "Characters", is rewritten as the model direction: one continuous sculpted body (round cones and ellipsoids blended in a distance field, surface nets, cut down with meshoptimizer), proportions on today's skeleton, build as one `bulk` number, faces, clothing layers with straight hems, four archetypes, colour, and a new cost of 1 draw call and at most 5,000 triangles. Two new rows in section 11 (skull faces, saw-tooth hems and sack coats).

**What didn't work (in the scratch sculptor):** cut eye sockets went black and read as a skull; hollow cheeks did the same. Painting eyes and brows on a full jaw fixed it. Picking colour per triangle gave saw-tooth borders; slicing triangles along the hem planes and painting by position gave straight ones. A rounded coat skirt read as a sack around both legs; a flat cut (`ymin`) fixed it. Forearms melted into the belt and got painted as belt; forearms and hands are now their own blend group joined by a hard min, and own their surface.

**Known:** the scratch body is about 16,000 to 18,000 triangles after slicing and takes about 28 s to build. The in-game version must paint before cutting down and cache built looks (backlog note).

**Shots:** `/mnt/project-files/art-direction/overhaul/model-direction-sheet.png`.
