# AiMMO Art Bible: Emberlight

This is how Ashgrove looks, and how it stays cheap to draw. It is an owner direction
(2026-11-23, see "7. A look of our own, cheap to draw" in `docs/design_bible.md`): the
owner wants a look in the same family as their favourite modern MMO (stylized, painterly
realism with moody golden light and a dark supernatural layer), made unmistakably ours, and
built in the most efficient way possible for the server, the client and the bots.

Owned by the director. Every change is logged in the design bible's Revision history, like
any other change to the vision. `world` builds the look, `client` owns the render settings
and quality options, `qa` enforces the budgets and the style check in CI.

## 1. The style in one line
**Emberlight: painted low-poly.** Grounded proportions and real lighting logic, simplified
into chunky low-poly shapes, with colour *painted into the geometry* (vertex colours,
gradients and one shared shader), never photographic textures. Golden late-afternoon light,
cool blue shadows, and a living ember glow that pulses through everything the sleeping thing
under the valley touches.

The family is "stylized realism". What makes it ours, and what makes it cheap, is the same
thing: **no textures, one shader, colour in the vertices.** A texture-painted realistic MMO
cannot look like this, and could not run on this budget.

## 2. Palette
The palette lives in `game/procgen/palette.gd`. New content picks from it or extends it
there, with a comment saying what the colour is for. No other file hard-codes a colour for
world art (qa lints this, see section 8).

**The 60 / 30 / 10 rule.** About 60% of any screen is muted natural colour (grass, bark,
rock, sky), about 30% is warm light (sunlight, lit faces, haze), and at most 10% is ember
accent. Ember is rare on purpose: that is why it reads.

| Token | Hex | Use |
|---|---|---|
| `EMBER` | `#F2A541` | **The signature.** Glow on anything you can use: gatherable nodes, interactables, magic, level-ups. Reserved: never on plain decoration. |
| `EMBER_CORE` | `#FFD27A` | The hot centre of a glow, sparks, the brightest pixel of an ember vein |
| `ASH_LEAF` | `#DB854D` | Ember ash crowns, the valley's name colour (exists today) |
| `SMOULDER` | `#B5432A` | Deep ember red: dying embers, danger, the edge of a vein |
| `COLD_ASH` | `#6E7A86` | The Dimming (section 4): drained, blue-grey ash |
| `SOOT` | `#2B2A2E` | The darkest value. Never pure black anywhere in the world |
| `SHADE` | `#4A5878` | Shadow tint. Shadows lean blue-violet, never grey or black |
| `HAZE` | `#E8C9A0` | Valley haze and fog by day: warm, golden |
| existing | see `palette.gd` | SAND, GRASS, MEADOW, FOREST, ROCK, SNOW, LAKEBED, WATER, TRUNK, PINE stay; they are the 60% |

Rules of thumb:
- **Warm light, cool shadow.** The lit side of everything leans gold; the shaded side leans
  `SHADE`. This one rule does most of the "painterly" work.
- **No neon, no pure colours.** Natural colours stay below about 0.65 saturation. Only
  `EMBER`/`EMBER_CORE` glows go brighter.
- **Night is blue and ember, never black.** Moonlit `SHADE` blues, and the ember glow
  carries the light.
- **Gameplay signal:** *if it glows ember, you can use it.* Players learn that in a minute
  and it stays true in every zone.

## 3. Shape language
- **Chunky and grounded.** Thick trunks, heavy bases, a slight taper to the top. Things sit
  *in* the ground (root flares, buried stone), never on it.
- **A little lean and twist.** Nothing tall is perfectly vertical or perfectly symmetric.
  Each instance gets a small seeded lean, twist and scale.
- **Bevelled, not sharp.** Low-poly facets with soft edges: 5 to 8 radial segments for
  props (as today), flat-shaded faces, but gradients across them so they never look like
  bare untextured blocks.
- **Readable from the shoulder camera.** Every gatherable, interactable or enemy reads by
  silhouette alone at 30 m. Tools and weapons are about 1.2x real size so they read in hand.
- **Characters** keep their rounded wanderer build for now and grow toward grounded
  proportions (about 5.5 to 6 heads tall, chunky hands and boots) when gear arrives in
  Milestone 3, so gear has room to change the silhouette. Never chibi, never thin-realistic.

## 4. Signature motifs
These are what a player should recognise in one screenshot.
1. **Ember veins.** Thin glowing cracks of `EMBER` through bark, stone seams and sap: the
   sleeping thing's warmth showing through. Every gatherable and special thing has some;
   richer tiers have more.
2. **The heartbeat.** Every ember glow in the world pulses together, slowly (about one
   beat every 4 s), from one shared value. Stand still at night and you can see the whole
   valley breathe. One global shader parameter, so it costs nothing per object.
3. **Leaves that never fall.** Ember ash crowns stay orange-red all year and glow faintly at
   night (exists today; keep it the valley's calling card).
4. **Rising motes.** At dusk and at night, a few ember motes drift upward near ash trees and
   seeps. Few, slow, and capped by the quality setting.
5. **Lit from within.** Tall things shade from dark at the base to warm at the top, as if the
   light comes from the trees as much as the sun.

**The dark supernatural layer: the Dimming.** Where the sleeper's warmth has been drawn
out, colour drains toward `COLD_ASH` and `SOOT`, the veins go `SMOULDER` and flicker out of
beat, and the motes fall instead of rise. It is our dark-fantasy side: cold, grey and
quiet, the opposite of the warm valley. It comes in with the hostile areas (Milestone 2 on).

## 5. Light and atmosphere
- **Golden-hour bias.** The day and night cycle spends more of its time with the sun low:
  long warm light, long blue shadows. Noon is short and still warm.
- **Warm key, cool fill, strong rim.** The sun is the warm key light, the sky ambient is the
  cool fill, and the shared shader adds a soft rim on silhouettes against the sky.
- **Height haze.** Warm `HAZE` fills the valley floors and lake hollows by day; it goes blue
  at night. Fog distance is also the draw distance (section 7), so the haze is the culling.
- **Glow, not lights.** Ember things glow through emission and one cheap bloom pass, not
  through real lights. Real lights are few (section 7).

## 6. "Inspired by, never copied": what to avoid
We share a family (stylized realism, moody light, a supernatural layer) with the owner's
favourite MMO. We never share its expression. Concretely:
- **No photographic or hand-painted texture look**, no realistic PBR materials, no
  high-detail realistic models. Ours are painted low-poly (and procedural, CLAUDE.md hard
  rule 3).
- **No purple-black, tendril or "corrupted" look** for the dark layer, and no blue
  magic-energy glow as the signature. Our supernatural is warm ember; our darkness is cold
  grey ash (the Dimming).
- **No colonial-explorer or 17th-century costume look**, no gold-on-dark-parchment UI, no
  UI layouts, icons, fonts or HUD looking like any existing game.
- **No names** borrowed for styles, zones or effects. "Emberlight" and "the Dimming" are ours.
When in doubt, push it further toward ember, ash and late-afternoon warmth.

## 7. Performance is part of the style
The look is designed so that it is cheap. These rules are as binding as the palette.

### The server and the bots never touch art
- The headless server and the bot test never build meshes, materials, textures, shaders or
  particles, and never load the visual classes in `game/procgen/`. They already don't
  (`game/main.gd` builds the world only for the client); keep it that way.
- Code in `game/server/` and `game/shared/` never references a visual `game/procgen/` class
  (qa lints this). Shared data that art needs (node positions, the workbench spot) is plain
  data in `game/shared/`, and art reads it, never the other way round.
- Art changes never change the protocol or what the server sends. The world is deterministic
  from the seed, so the server never streams terrain, meshes or textures.
- Bot behaviours check what players do over the network. Art checks belong in unit tests
  and the client smoke test, not in the 8-bot loop.

### One shared shader, colour in the vertices
- **One shader family, `Emberlight`** (`game/procgen/emberlight.gd`), for all world art:
  `solid`, `foliage` (adds wind sway), `glow` (adds ember veins and the heartbeat). Water and
  sky keep their own small shaders. Ramp lighting (soft bands), the warm/cool split, rim
  light, and a cheap "brush noise" tint from world position, all computed in the shader with
  no texture lookups.
- **Colour comes from vertex colours and gradients**, including baked ambient occlusion
  (darker where parts meet the ground or each other). Ember veins are marked in a vertex
  colour channel, so glow needs no extra material.
- **Materials are built once and shared.** Per-object variation comes from vertex colours,
  instance custom data or instance uniforms, never from a new material. Target: 24 or fewer
  distinct materials in the whole world.
- **Textures are the exception.** Only UI icons and small lookup images, at most 256 px,
  generated once on first use and cached for the session (as `ItemIcons` does). None in the
  world shaders.

### Draw less
- **Instance everything repeated** with MultiMesh (as trees, rocks, flora, nodes and lamps
  are today), and **chunk it by area** (about 64 m) so the camera culls what it can't see.
  One MultiMesh spanning the whole 512 m world can never be culled.
- **Level of detail by distance.** Near: full mesh. Mid: a simpler mesh with fewer segments
  and no small parts. Far: gone into the haze. Use `visibility_range_begin/end` per layer.
  Small things fade first (flowers 90 m, as today; props about 160 m; trees about 300 m).
- **Fog is the far plane.** The camera's far distance matches where the haze is solid, so
  nothing past it is drawn.
- **Lights:** one shadowed sun (shadow distance 120 m or less), every other light unshadowed,
  and at most 8 lit at once near the player. Glow through emission instead of lights.
- **Effects are pooled.** Effects reuse a fixed pool (as `NodeFx` does): no meshes or nodes
  created or freed while playing, no per-frame allocations. Particles are capped by quality.
- **No expensive screen effects.** No SDFGI, VoxelGI, SSR or SSIL. SSAO off by default
  (vertex AO does that job). One bloom (glow) pass.
- **Quality setting** (client): Low, Medium (default), High scale shadow distance, view
  distance, flora density and motes. The look must hold on Low.

### Budgets (enforced by qa in CI)
Target machine: a 2020 laptop with integrated graphics, 1080p, Medium: 60 fps (16.6 ms a
frame, at most about 4 ms of it on the CPU side of rendering).

CI renders in software, so frame time there is reported, not gated. What is gated is what
software and real GPUs agree on, measured at the client smoke test's spawn shots:

| Measure | Ceiling |
|---|---|
| Draw calls per frame | 300 |
| Primitives (triangles) per frame | 600,000 |
| Distinct world materials | 24 |
| Texture memory | 32 MB |
| World build time on startup | 3 s (reported in CI, gated once measured) |

Plus a ratchet: a PR that raises draw calls or primitives by more than 20% over the stored
baseline (`tests/client_smoke/render_baseline.json`) fails the Test check, the same way the
fun metrics work. Updating the baseline is a deliberate change in the PR, with a reason.
If today's world is already over a ceiling when qa first measures it, qa sets the ceiling to
today's number and `world` brings it down; ceilings only ever go down.

## 8. Checks (qa)
- **Render budget** in the client smoke test (section 7 table and ratchet), written to
  `render_stats.json` in the CI artifact.
- **Style check** on the smoke screenshots (noon, night, and dusk once it exists): warmth
  (the warm/cool balance), saturation (no neon), the night shot is blue-and-ember (not black,
  not grey), and ember accents stay a small share of the frame. Compared against
  `tests/client_smoke/style_baseline.json` with a tolerance: a big drift fails, a small one
  is reported for the integrator to look at. A contact sheet of all shots goes in the
  artifact.
- **Palette lint:** no colour literals for world art outside `palette.gd` (files that have
  them today are listed and the list only shrinks).
- **Art-free server lint:** `game/server/` and `game/shared/` never reference visual
  `game/procgen/` classes or create meshes, materials or textures.
