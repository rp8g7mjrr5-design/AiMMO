# ZombAi Art Bible: Emberlight, grounded

This is how ZombAi's fallen kingdom looks, and how it stays cheap to draw, on servers of up
to about 100 players (`docs/vision.md`). Every worker whose change shows
anything on screen reads this first (CLAUDE.md, "Owner directions"). Owned by the director;
every change is logged in the design bible's Revision history, like any other change to the
vision. `world` builds the look, `client` owns the HUD, render settings and quality options,
`qa` enforces the budgets and the style check in CI.

## 0. What the owner asked for (owner direction, 2026-11-24)
The owner played the build and said the style "is cheesy and looks silly". They want ZombAi to
feel **heavily inspired by grounded survival-and-crafting games** (their first reference was New
World; the game is now an open-world zombie survival sandbox, not an MMO, owner 2026-11-25): a
real-feeling wilderness, painterly light, weathered materials, the sense that the world is old
and a little dangerous. On 2026-11-25 the owner approved the test-camp look: **clear, sunny days
with no haze** (section 5). Done in **low poly**, with a style that
is **clearly our own**, and without getting us in trouble (section 6).

So the bar for every visual change is: *would this look at home in a grounded open-world
survival game, rendered as chunky low-poly?* If it would look at home in a mobile party game
or a toy box, it is wrong for ZombAi.

### The five pillars
1. **Grounded before cute.** Real proportions, real materials, real weight. Nothing is round
   because round is friendly; things are the shape their job and their age made them.
   **Except the characters** (owner, 2026-11-26: "we can make them funny"): people and the
   Zombai are goofy cartoon folk in the world's muted colours (section 3, "Characters").
2. **Mood comes from light.** Atmosphere is built with light, not with brighter colours: clear
   sunny days with a strong sun and real shadows, rose dawns and dusks, and real night. No haze
   over the land. A good screenshot could be a painting of a bright, quiet day in an old
   country, or of a lantern on a dark road.
3. **Earth first, ember rare.** About 90% of the screen is muted, lived-in naturals (olive,
   moss, bark, stone, rust, straw). The ember glow is the one saturated note, and it means
   "you can use this".
4. **Weathered and worn.** Everything has been out in the weather: darker at the base, paler
   where the sun hits, never factory-clean, never plastic.
5. **Restraint.** Effects, UI and colour whisper until something important happens. The world
   is the show; the HUD and effects are the frame.

## 1. The style in one line
**Emberlight: grounded painted low-poly.** Grounded proportions and real lighting logic,
simplified into chunky faceted shapes, with colour *painted into the geometry* (vertex
colours, gradients and one shared shader), never photographic textures. A muted, weathered
kingdom under a clear sun and cool blue shadows, with a faint ember glow pulsing through
everything the old warmth under the land still touches, and the cold grey of the Dimming where
it has drained away.

**Low-res paint** (owner direction, 2026-11-24: "less blocky and more low res actual"). Two
things carry it. Shapes are *organic low poly*: smooth, rounded silhouettes with real
anatomy and few polygons, never boxes. Surfaces carry a *low-res texel grain*: the colour
breaks into small square texels, like a low-resolution hand-painted texture shown with
nearest-neighbour filtering. The grain is computed in the shared shader from each mesh's own
position (no texture files, no lookups), so it costs almost nothing and sticks to things as
they move. Characters use about 5.5 cm texels, props the same, and the ground about 40 cm.
The light bands are wide and soft, so a rounded body shades smoothly around its curve while
faceted rocks and crowns still read as painted planes.

The family is "stylized realism". What makes it ours, and what makes it cheap, is the same
thing: **no texture files, one shader, colour in the vertices, a procedural low-res grain.** A texture-painted
realistic game cannot look like this, and could not run on this budget.

## 2. Palette
The palette lives in `game/procgen/palette.gd`. New content picks from it or extends it
there, with a comment saying what the colour is for. No other file hard-codes a colour for
world art (qa lints this, see section 8).

**The 60 / 30 / 10 rule.** About 60% of any screen is muted natural colour (grass, bark,
rock, sky), about 30% is warm light (sunlit faces, rust crowns, warm stone), and at most 10% is ember
accent. Ember is rare on purpose: that is why it reads.

**Saturation and value rules.**
- **Naturals stay below about 0.45 saturation** (HSV) in the palette, and the whole frame is
  graded a touch flatter on top (section 5). Only `EMBER` / `EMBER_CORE` glows go brighter.
- **No lime, no candy.** Greens lean olive, moss and spruce (hue toward yellow-grey or
  blue-grey, never toward highlighter). Oranges lean rust and burnt sienna, never traffic cone.
- **Darks carry the mood.** Pines, bark, forest floor and shadows are genuinely dark (value
  0.15 to 0.35). A screen with no real darks reads as a toy.
- **Never pure black, never paper white.** `SOOT` is the darkest value, old snow is the
  brightest.

| Token | Value | Use |
|---|---|---|
| `GRASS` | `(0.33, 0.41, 0.25)` | Olive valley grass. The biggest share of most screens |
| `MEADOW` | `(0.39, 0.45, 0.27)` | Dry autumn meadow on the valley floor, olive going straw |
| `FOREST` | `(0.25, 0.33, 0.22)` | Forest floor and higher slopes: dark moss |
| `ROCK` | `(0.46, 0.44, 0.41)` | Weathered grey stone, a touch warm |
| `SAND` / `LAKEBED` | `(0.68, 0.62, 0.48)` / `(0.30, 0.33, 0.27)` | Silt shores, not a beach postcard |
| `SNOW` | `(0.86, 0.87, 0.88)` | Old snow. Never paper white |
| `WATER` | `(0.20, 0.33, 0.38, 0.80)` | Deep cold valley water, not pool blue |
| `TRUNK` | `(0.32, 0.25, 0.20)` | Weathered bark |
| `PINE` | `(0.15, 0.27, 0.21)` | Dark spruce: pines are the shadows of the forest |
| `ASH_LEAF` / `ASH_LEAF_DRY` | `(0.62, 0.31, 0.17)` / `(0.66, 0.46, 0.25)` | Ember ash crowns, rust to dry ochre. The valley's calling card |
| `EMBER` | `#F2A541` | **The signature.** Glow on anything you can use: gatherable nodes, interactables, magic. Never on plain decoration |
| `EMBER_CORE` | `#FFD27A` | The hot centre of a glow, sparks, the brightest pixel of an ember vein |
| `SMOULDER` | `#B5432A` | Deep ember red: dying embers, danger, the edge of a vein |
| `COLD_ASH` | `#6E7A86` | The Dimming (section 4): drained, blue-grey ash |
| `SOOT` | `#2B2A2E` | The darkest value |
| `SHADE` | `#4A5878` | Shadow tint. Shadows lean blue-violet, never grey or black |
| `HAZE` | `#E8C9A0` | Warm horizon glow at dawn and dusk only. Not a day haze (no haze by day, 2026-11-25) |
| `CLOTH` (8 dyes) | see `palette.gd` | Characters' cloth: undyed wool, madder, woad, weld, walnut, lichen, sloe, charcoal |
| `HAIR`, `skin()` | see `palette.gd` | Natural hair and skin ranges. No orange skin, no bright hair |

Rules of thumb:
- **Warm light, cool shadow.** The lit side of everything leans gold; the shaded side leans
  `SHADE`. This one rule does most of the "painterly" work.
- **Night is blue and ember, never black.** Moonlit blues, and the ember glow carries the
  light.
- **Gameplay signal:** *if it glows ember, you can use it.* Players learn that in a minute and
  it stays true in every zone.

## 3. Shape language
- **Chunky and grounded.** Thick trunks, heavy bases, a slight taper to the top. Things sit
  *in* the ground (root flares, buried stone), never on it.
- **Big facets, few of them.** Low poly means *visible, confident facets*, like a carved
  wooden model, not smoothed blobs. 5 to 8 radial segments for props, flat-shaded faces with
  gradients across them so they never look like bare untextured blocks.
- **Irregular and asymmetric.** Nothing tall is perfectly vertical or perfectly symmetric.
  Each instance gets a seeded lean, twist and scale. Tree crowns are **lopsided clusters of
  lobes** (today: two per ash), never one ball on a stick ("lollipop trees" read as a toy).
- **Readable from the shoulder camera.** Every gatherable, interactable or enemy reads by
  silhouette alone at 30 m. Tools and weapons are about 1.2x real size so they read in hand.

### Characters
**Goofy cartoon folk** (owner direction, 2026-11-26). The sculpted grounded traveller shipped,
and the owner said "this doesnt look good at all we need to rework our character entirely",
then "we can make them funny" and "would it be easier for ai to make everything super small?".
Three directions were rendered in the game (small and chunky, clean carved, goofy cartoon) and
the owner picked the **goofy cartoon**. So the characters are the one place the game is
allowed to be funny: the **world stays grounded** (pillars 2 to 5 still hold everywhere, and
pillar 1 holds for everything that is not a person or a Zombai). Funny comes from shape and
face, never from colour: the clothes, skin and hair keep the muted `Palette` dyes.

**The look** (`Toon`):
- **A big round head on short legs**, about 1.6 m tall (times the look's height), hips at
  0.68 m. A pear-shaped body: a round belly under a smaller chest, belted.
- **A face that reads from the game camera:** googly eyes (bone-white `Palette.EYE_WHITE`
  with dark pupils that look a little apart, a little different per person), bushy brows in
  the hair's colour (heavy on "Strong brow"), a long droopy nose, ears, a small smile line.
  Beards are real round mass on the jaw; moustaches a fat sausage.
- **Noodle arms, big hands:** thin arms with a rounded shoulder, a leather cuff at the wrist,
  and a big hand with three chunky fingers and a thumb. Short legs in big round boots.
- **Back first:** a little leather pack with a bedroll on top, or the hood's long tail and a
  wool cloak for the hooded. Hair styles are big simple shapes (a mop, a knot, a curtain, two
  braids); a felt cap has a brim.
- **Smooth toy shapes, flat colour, no grain.** Each part is a simple ball, capsule or
  cylinder with smooth shading, one flat dye per part plus the usual darker-toward-the-feet
  shade. The shared "folk" Emberlight material turns the texel grain and brush OFF: on a face
  the grain read as pixel noise (owner's screenshot, 2026-11-26).
- **The Zombai are the same folk, dead:** ash-grey flesh (`ZombaiBody.flesh`, never green),
  clothes drained of colour, blank eyes with a pinprick pupil, a slack open mouth and the
  wound they died of. The living read warm and the dead read cold at a glance.

**Never:** bright or candy colours, glowing eyes, outlines, cartoon stars or effects, gore
played for laughs, or anything copied from another game's characters (section 6). Goofy, not
childish: they still live outdoors in a fallen kingdom.

**Skeleton:** the traveller's 18 bones and names (`AvatarSkeleton`), so every `AvatarClips`
pose plays unchanged, at the toon's proportions. The leg chain is `AvatarSkeleton`'s scaled
by `Toon.LEG_SCALE` (0.74), so the clips' leg IK still plants the feet: the animator draws the
gait at speed / LEG_SCALE (short legs take quick little steps) and scales the root's offset
by LEG_SCALE.

**Cost:** one skinned mesh per figure on the shared folk material: 1 draw call, about 4,000
triangles for a survivor (at most 5,000) and about 2,100 for a walker (up to 24 at night).
A figure builds in about 15 ms of GDScript, so there is no sculpting thread or disk cache.

**Animation** is its own piece of work (the owner asked for it on 2026-11-24): weighty, with
the weight on the planted foot, swings that wind up before they land, nothing snaps. The
cartoon body can take a little more bounce later, never floaty.

**Creatures** are animals first: real gaits, real proportions, muted coats (the grazers'
build is right; keep tails and markings understated).

## 4. Signature motifs
These are what a player should recognise in one screenshot, and they are ours.
1. **Ember veins.** Thin glowing cracks of `EMBER` through bark, stone seams and sap: the
   sleeping thing's warmth showing through. Every gatherable and special thing has some;
   richer tiers have more. Thin lines, never big glowing patches.
2. **The heartbeat.** Every ember glow in the world pulses together, slowly (about one beat
   every 4 s), from one shared value. Stand still at night and you can see the whole valley
   breathe. One global shader parameter, so it costs nothing per object.
3. **Leaves that never fall.** Ember ash crowns stay rust-red all year and glow faintly at
   night: the valley's calling card. Rust and dry ochre by day, deep smouldering red at night.
4. **Rising motes.** At dusk and at night, a few ember motes drift upward near ash trees and
   seeps. Few, slow, and capped by the quality setting.
5. **Lit from within.** Tall things shade from dark at the base to warm at the top, as if the
   light comes from the trees as much as the sun.

**The dark supernatural layer: the Dimming.** Where the sleeper's warmth has been drawn
out, colour drains toward `COLD_ASH` and `SOOT`, the veins go `SMOULDER` and flicker out of
beat, and the motes fall instead of rise. It is our dark-fantasy side: cold, grey and quiet,
the opposite of the warm valley. It comes in with the hostile areas (Milestone 2 on).

## 5. Light and atmosphere

### Light by time of day
**Clear, sunny days, no haze** (owner, 2026-11-25, approving the test-camp look). By day the
sky is a clean, deep blue and the sun is strong, with crisp, real shadows and the land readable
to the horizon. The mood lives at the ends of the day and at night, and in places (a dark ruin,
the grey of the Dimming), not in a haze over everything. `SkyClock` holds the keys; these are
the targets.

| Time | Sky | Key light | Ground and shadows | Feel |
|---|---|---|---|---|
| Dawn | Deep blue top, ember-rose horizon | Low, red-orange, weak | Long blue shadows, clear air | Cold and quiet, the land waking |
| Morning | Clear blue, paler at the horizon | Warm gold (`GOLDEN_LIGHT`) rising to white | Long shadows shortening, warm faces | Fresh and bright; the day opens up |
| Noon and afternoon | Clean, deep sky blue, never flat postcard cyan | Strong warm white sun | Olive and rust in full colour, crisp shadow shapes (sky fill kept low) | Sunny and clear for most of the day; bright but never washed out or lime |
| Golden hour and dusk | Warm horizon, then rose-violet top and ember horizon | Low gold, then sinking red-orange | Long shadows, ground goes dark first, crowns hold the last light | Short and precious; melancholy; lamps and fires come on, the Zombai stir |
| Night | Deep navy with stars, never black | Moonlight (`MOONLIGHT`), dim | Blue-grey meadow, ember crowns and lanterns carry the colour | Dark and a little dangerous, but you can always see the path and every player |

- **Sunny-day bias.** Most of the day is clear and sunny with the sun well up: readable land,
  crisp shadows, colour you can judge distance by. Golden hour and dusk are short and come
  before the night. (Until 2026-11-25 the day was biased to a low golden sun under haze;
  that is replaced.)
- **Warm key, cool fill, strong rim.** The sun is the warm key light, the sky ambient is the
  cool fill (kept low by day so shadows keep their shape: `SkyClock.DAY_AMBIENT`), and the
  shared shader adds a soft rim on silhouettes against the sky. At night the fill is mostly a
  flat moonlit blue (`NIGHT_SKY_SHARE`) and the shader adds extra `SHADE` to the side turned
  away from the moon, so figures read as blue-grey shapes, never black holes.
- **The grade.** One whole-frame grade in the tonemap pass Godot already draws (free):
  saturation x0.92, contrast x1.10 (`WorldBuilder.GRADE_*`). It is the "same film stock" that
  makes every scene sit in one key. Change it only on purpose, with before and after shots.
- **No haze by day.** No height haze in hollows and no warm veil toward the sun. The only fog
  is a thin distance fade right at the draw distance (section 7), so the far edge melts into
  the sky instead of popping; it should not be noticed on a clear day. At night a faint blue
  ground mist is allowed where it helps the mood (marsh, the Dimming), capped by quality.
  Today's build (as of #219) still has a light height haze and fog sun scatter; the next world
  lighting PR removes them, with before and after shots.
- **Glow, not lights.** Ember things glow through emission and one cheap bloom pass, not
  through real lights. Real lights are few (section 7).

## 6. "Inspired by, never copied": staying legally safe
We take inspiration from **genres** (grounded survival-and-crafting games, open-world zombie
survival sandboxes) and their
**mood, lighting philosophy, palette philosophy and gameplay feel**. Those are free for anyone.
The *expression* of any particular game is not. Concretely, never:
- **Names**: no place, faction, creature, item, resource, skill, effect or style names from
  any existing game, and no near-misses or puns on them. "Emberlight", "Ashgrove" and "the
  Dimming" are ours.
- **Lore and setting hooks**: no colonial-expedition or "cursed island" premise, no
  17th-century explorer costume look, no corruption faction look.
- **The dark layer of another game**: no purple-black, tendril or "corrupted" look, and no
  blue magic-energy glow as the signature. Our supernatural is warm ember; our darkness is
  cold grey ash.
- **UI**: no HUD or menu layouts, icon sets, fonts, frames, or gold-on-dark-parchment window
  style that look like an existing game (section 9 has ours).
- **Assets or lookalikes**: no traced, recreated or "low-poly version of" any existing
  character, creature, building, weapon, landmark or logo. No photographic or hand-painted
  texture look, no realistic PBR materials (and CLAUDE.md hard rule 3 makes all art
  procedural anyway).
- **References in public**: patch notes, in-game text and PRs describe *our* look in our words;
  they never say "like <game>".
When in doubt, push it further toward ember, cold ash, weathered wood and clean sunlight on old
stone, which no one else owns. The Zombai are never shaped or coloured like another game's
zombies (green skin, exposed brains, hazmat looks): they are the kingdom's dead, grey and
ash-cold, in what they died wearing.

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
  generated once on first use and cached for the session (as `ItemIcons` does). In the world
  shaders, only `SurfaceTex`'s painted detail (2026-11-24, owner direction, the test-camp
  look): 64 px brightness-only images made in code (grass and earth, bark, stone, wood), laid on
  triplanar in world space with nearest filtering, one shared material per kind. The colour
  still comes from the vertices.
  And `Grass`'s blade sheet (2026-11-25): one 64 x 32 alpha-cut brightness image for the grass
  tufts near the camera; the colour comes from the ground under each tuft.
- **The low-res look is maths, not textures.** The texel grain hashes the mesh's own position
  in the fragment shader (`texel_size`, `texel_grain` uniforms on the shared materials). If a
  later step wants painted patterns (bark lines, cloth weave) they are generated the same way
  or as tiny 32 to 64 px images made in code, shown with nearest-neighbour filtering, and
  shared by every instance.

### Draw less
- **Instance everything repeated** with MultiMesh (as trees, rocks, flora, nodes and lamps
  are today), and **chunk it by area** (about 64 m) so the camera culls what it can't see.
  One MultiMesh spanning the whole 512 m world can never be culled.
- **Level of detail by distance.** Near: full mesh. Mid: a simpler mesh with fewer segments
  and no small parts. Far: faded out at the draw distance. Use `visibility_range_begin/end` per layer.
  Small things fade first (flowers 90 m, as today; props about 160 m; trees about 300 m).
- **The far plane is a fade, not a haze.** The camera's far distance matches the thin distance
  fade at the edge of view (section 5), so nothing past it is drawn. Clear days put more on
  screen than hazy ones did, so the chunking and LODs below carry the culling.
- **Lights:** one shadowed sun (shadow distance 120 m or less), every other light unshadowed,
  and at most 8 lit at once near the player. Glow through emission instead of lights.
- **Crowds** (servers of up to about 100, owner 2026-11-25): the client only draws the players,
  Zombai and animals the server tells it about (interest management, `docs/vision.md`). Bodies
  past about 40 m use a cheaper LOD of the sculpted body, and past about 120 m a simple
  silhouette; a horde night at a busy hold must fit the same budget as the spawn shot. qa adds a
  crowd shot (about 30 players and 40 Zombai in view) to the smoke test before the live cap
  passes 24.
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

## 9. UI tone
The HUD is the frame, not the picture. It should feel like a field journal and a worn
leather satchel, our own, never like another game's menus.
- **Quiet by default.** Small, calm type; muted panels (dark warm-grey, about 70 to 85%
  opaque); no big saturated buttons. Colour in the UI is information (an ember accent for
  "ready", `SMOULDER` for danger), never decoration.
- **One accent.** The UI's accent is `EMBER`, used sparingly (a title, a ready button, a
  progress fill). Never rainbow progress bars, never neon text.
- **Text, not shouting.** Toasts and floaters are short and sit near what they describe; no
  thick black outlines on big bold yellow type; no exclamation marks except real milestones.
- **Ours, not borrowed.** Our own layouts, our own procedural icons (`ItemIcons`), Godot's bundled font until we generate our own. See section 6.

## 10. Effects: restraint
Effects mark moments. If everything sparkles, nothing does.
- **Small and short by default.** Gather hits: a few chips or leaves and a puff, gone in about
  half a second. Pickups: one quick motion into the pack.
- **Translucent light, not solid shapes.** Glows, columns and rings are soft and see-through;
  you can always see your character through an effect (the old level-up column was a solid
  gold tube that swallowed the avatar; levels are gone since 2026-11-26, the lesson stays).
- **Ember, not rainbow.** Effects use `EMBER`, `EMBER_CORE` and `SMOULDER`, plus the
  material's own colour (wood chips, stone dust). No rainbow rings, no pure yellow, no
  confetti, no cartoon stars or hearts.
- **Scale with importance.** A gather is a whisper, a craft is a word, a first ember tool or
  a horde night is the loud moment, and even that stays inside the frame: about 2 s,
  readable from across the meadow by its light, not by covering the screen.
- **Cheap.** Pooled, capped by quality, no per-frame allocation (section 7).

## 11. What reads as cheesy, and its status
The owner's "cheesy and silly" came from these. Fixed items stay listed so nobody
reintroduces them.

| Offender | Why it read as cheesy | Status |
|---|---|---|
| Lime-green, glowing grass | Highlighter green over 60% of the screen is the single biggest "toy" signal | **Fixed 2026-11-24**: olive and straw palette, lower sky fill, whole-frame grade |
| Candy-orange lollipop ash trees | One saturated ball on a thin stick, repeated | **Fixed 2026-11-24**: rust and ochre, thicker trunks, two lopsided lobes per crown |
| Pointed wizard hat | A comedy prop on a traveller | **Fixed 2026-11-24**: a travelling hood |
| Bright cyan and primary tunics | Toy colours | **Fixed 2026-11-24**: `Palette.CLOTH` dyes |
| Big bald orange head, black button eyes | About 3.5 heads tall, a doll's face | **Fixed 2026-11-24**: hair or a hood on every head, natural skin, a nose and quiet eyes |
| Blocky mannequin bodies ("less blocky, more low res actual") | Boxes and cylinders, plastic flat colour | **Fixed 2026-11-24**: smooth lofted bodies and the low-res texel grain on everything (section 1) |
| Fat, barrel-shaped bodies ("our dudes look fat and silly") | A 0.64 m wide capsule on short stubby legs | **Fixed 2026-11-24 (character overhaul)**: lean 7-head adults, tapered chest, long legs, layered survival gear. **Superseded 2026-11-26**: the owner chose goofy cartoon folk on purpose (section 3, "Characters"); the colour rules still hold |
| Pixel-noise faces and a hood that swallows the head (owner's screenshot, 2026-11-26) | The texel grain on a small face; a sculpted hood over the brow | **Fixed 2026-11-26**: the cartoon folk on a no-grain material, big readable faces |
| Skull faces | Hollow cheeks and cut eye sockets go black under low light | **Direction set 2026-11-24**: full jaw and cheeks, painted eye slits and brows, real beards (section 3, "Characters"); lands with the sculpted body |
| Saw-tooth clothing edges and sack-shaped coats | Colour picked per triangle; long garments as rounded tubes | **Direction set 2026-11-24**: straight hems at set heights, flat-cut lower edges, layers sculpted proud; lands with the sculpted body |
| Postcard-cyan noon sky | Bright and flat, no mood | **Fixed 2026-11-24**: dusty blue. **Revised 2026-11-25**: a clean, deep sky blue with no haze (owner approved the test-camp look); still never flat cyan |
| Solid gold level-up tube and red crystal sparks | Swallowed the avatar; arcade effect | **Gone 2026-11-26**: levels were removed (design bible direction 5) |
| Teal, green-lit nights | Neither moonlit nor dark | **Improved 2026-11-24**: navy and blue-grey, moon-blue fill. Next: check dark cloth reads on a real GPU (CI renders in software) |
| Bold outlined yellow floaters and banners | Mobile-game shouting | **To do** (client): section 9 |
| Thin black lamp posts with red boxes | Reads as a street lamp, not a wilderness lantern | **To do** (world): timber posts, iron and horn lanterns |
| Uniform flat terrain facets at noon | No sense of ground cover | **Fixed 2026-11-24**: the low-res grain breaks the ground into 40 cm texels, and seeded moss, dry grass and bare earth patches break up the meadow and forest floor (#189) |

## 12. Checklist for any PR that changes what is on screen
1. Before and after screenshots at noon, golden hour and night (the client smoke shots plus
   your own), in the PR and in the project files.
2. Grounded? Proportions, materials and colours would sit in a grounded open-world survival
   game (pillar 1).
3. Palette from `palette.gd`, naturals under about 0.45 saturation, ember only on usable things.
4. Effects translucent, short, ember-coloured; the character visible through them.
5. Nothing named, shaped or laid out after another game (section 6).
6. Inside the render budget (section 7), and the style check passes; if the look changed on
   purpose, the style baseline was rewritten with `--write-baseline` and the PR says so.

