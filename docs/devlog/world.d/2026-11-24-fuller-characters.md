## 2026-11-24: fuller characters (owner: "too sticky")
- Only the loft rings in `AvatarBuilder.parts()` changed. The chest is about 0.44 m across and 0.31 m deep (was 0.38 m by 0.24 m). The upper arm is 16 cm across at the shoulder (was 12), the thigh is 21 cm (was 17), and the hands and boots are bigger. The belt gear, chest strap, mantle and pack moved out to sit on the new surface. `PACK_BACK` is now 0.245 and `ARM_RADIUS` 0.082, and the pack still fits between the arms.
- The bones, pivots, part order and the dict shape are unchanged, so PR 192's skinning and clips work as they are. The triangle count is the same (same ring counts). Smoke: 205/257/243 draw calls, night 493k primitives (under 500k).
- The first pass (about +10% girth) barely showed in shots. The final pass is about +20% on the limbs and +15% on the torso.
- Customization thread: body type is their girth factor applied on top of these rings, and this default is their "average".
