Done: owner playtest 2026-11-24, blocky pale pool over Spawn Meadow at night (claude/night-lighting-fix, PR #181)
Lanterns no longer paint SHADE; warm separate pools, seep lights, moonlit rim.

Follow-ups:
- [ ] Night on the Compatibility renderer (opengl3, CI's smoke and any GPU without Vulkan) is near black: pines and figures get no moon light() and little ambient (luma 0.05 on the CI night shot vs a moonlit blue on Forward+). Find why and lift it to a readable moonlit blue, then re-baseline night.
