# AiMMO Art Bible: Emberlight, grounded

This is how Ashgrove looks, and how it stays cheap to draw. Every worker whose change shows
anything on screen reads this first (CLAUDE.md, "Owner directions"). Owned by the director;
every change is logged in the design bible's Revision history, like any other change to the
vision. `world` builds the look, `client` owns the HUD, render settings and quality options,
`qa` enforces the budgets and the style check in CI.

## 0. What the owner asked for (owner direction, 2026-11-24)
The owner played the build and said the style "is cheesy and looks silly". They want AiMMO to
feel **heavily inspired by the genre of grounded survival-and-crafting action MMOs** (their
favourite is New World): a real-feeling wilderness, moody painterly light, weathered materials,
the sense that the world is old and a little dangerous. Done in **low poly**, with a style that
is **clearly our own**, and without getting us in trouble (section 6).

So the bar for every visual change is: *would this look at home in a grounded, moody
wilderness MMO, rendered as chunky low-poly?* If it would look at home in a mobile party game
or a toy box, it is wrong for Ashgrove.

### The five pillars
1. **Grounded before cute.** Real proportions, real materials, real weight. Nothing is round
   because round is friendly; things are the shape their job and their age made them.
2. **Mood comes from light.** Atmosphere is built with low sun, haze, long shadows, dusk and
   real night, not with brighter colours. A good screenshot of Ashgrove could be a painting of
   a quiet evening.
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
colours, gradients and one shared shader), never photographic textures. A muted autumn
valley under low golden light and cool blue shadows, with a faint ember glow pulsing through
everything the sleeping thing under the valley touches.

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
realistic MMO cannot look like this, and could not run on this budget.

## 2. Palette
The palette lives in `game/procgen/palette.gd`. New content picks from it or extends it
there, with a comment saying what the colour is for. No other file hard-codes a colour for
world art (qa lints this, see section 8).

**The 60 / 30 / 10 rule.** About 60% of any screen is muted natural colour (grass, bark,
rock, sky), about 30% is warm light (sunlit faces, haze, rust crowns), and at most 10% is ember
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
| `EMBER` | `#F2A541` | **The signature.** Glow on anything you can use: gatherable nodes, interactables, magic, level-ups. Never on plain decoration |
| `EMBER_CORE` | `#FFD27A` | The hot centre of a glow, sparks, the brightest pixel of an ember vein |
| `SMOULDER` | `#B5432A` | Deep ember red: dying embers, danger, the edge of a vein |
| `COLD_ASH` | `#6E7A86` | The Dimming (section 4): drained, blue-grey ash |
| `SOOT` | `#2B2A2E` | The darkest value |
| `SHADE` | `#4A5878` | Shadow tint. Shadows lean blue-violet, never grey or black |
| `HAZE` | `#E8C9A0` | Valley haze by day: warm, golden |
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
The owner's words (2026-11-24): "our dudes look fat and silly". Characters are lean,
grounded adults who live outdoors, rendered as chunky low-poly. `AvatarBuilder` is the
reference; every new character, NPC or gear piece follows these rules.

**Lean, not sticky** (owner, 2026-11-24, later the same day: "they are to sticky"). Lean
means a fit adult with real mass, not a stick figure: a full chest and back about 0.31 m
deep, upper arms about 16 cm across at the shoulder, thighs about 21 cm across, hands you
can read at a glance. Joint positions and the skeleton stay the same. The bulk lives in the
loft rings, so slimmer or sturdier body types are a girth factor on the same rings (the
customization work).

**Organic, not blocky** (owner, 2026-11-24: "less blocky and more low res actual"). Every
body part is a smooth lofted shape (`AvatarBuilder.loft()`: rings of width and depth, smooth
normals) or a squashed ball. No boxes and no bare cylinders on a character; a unit test
enforces it. The torso swells at the chest and narrows at the waist, the calves swell, the
head is an egg with a jaw, and the arms hang slightly away from the body. Upper arm and
forearm, thigh and shin are separate pieces, so the animation work can skin them to a
skeleton and bend elbows and knees.

**Proportions (the numbers live in `AvatarBuilder`'s constants):**
- **About 7 heads tall.** A 1.78 m adult with a 0.25 m head. Never chibi, never a big-headed
  doll, never a barrel. The old wanderer was about 3.5 heads and 0.64 m wide.
- **Shoulders wider than hips, a narrow waist.** The chest is a tapered shape about 0.41 m
  across at the chest and 0.36 m at the waist, and about seven-tenths as deep as it is
  wide. Nothing is a capsule or a ball.
- **Long legs.** The hips sit at about half the height (0.92 m). Thigh, shin and boot are
  separate pieces, so the legs taper and read as legs.
- **Real arms.** The shoulders sit at 1.42 m and the hands hang to mid-thigh (0.63 m of arm).
  The sleeve, a leather bracer and the hand are separate pieces.
- **Small, quiet faces.** A slightly narrow head, a neck, a nose and two shadowed eye
  sockets in the skin's own colour. No black button eyes, no big round heads.

**Silhouette, read from the back first** (the action camera sees the back all game):
- Every head has a hood or hair (with or without a felt cap). No bare skin balls and no
  comedy hats: no pointed wizard hats, party hats or crowns.
- A wool mantle over the shoulders, a framed pack with a bedroll on top, a belt with a pouch
  and a knife, a strap across the chest. Players should read "someone who sleeps outdoors"
  at 20 m.
- The pack stays between the swinging arms (`PACK_WIDTH`), and nothing hangs where an arm
  or leg swings through it.

**Layers and colour:**
- The base is dyed cloth (`Palette.CLOTH`). Over it go gear layers in `Palette.LEATHER`,
  `LEATHER_DARK`, `WOOL`, `TROUSERS` and `BEDROLL`. The cloth colour shows on the chest, the
  skirt and the sleeves. Everything else is worn leather and wool.
- No bright primaries, no pure colours, no glow on characters. Ember on a character is
  reserved for gear that does something, later.
- Gear (Milestone 3) changes the silhouette in this same language: shoulders, gloves,
  helmets and weapons grow out of these layers, about 1.2x real size so they read in hand.

**Cost:** each traveller is drawn as five merged meshes (body and four limbs) on the shared
Emberlight material: 5 draw calls, about 2,300 triangles. New parts go into those merged
meshes, never as extra nodes. Hard limits: 6 draw calls and 3,000 triangles a character.

**Animation** is its own piece of work (the owner asked for it on 2026-11-24): a skinned
skeleton on these segment meshes with idle, walk, run, gathering, crafting, jump, light and
heavy swings, knockdown and getting up, and sitting. It should be weighty and grounded:
weight shifts onto the planted foot, swings wind up before they land, nothing snaps.

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
The day is where the mood lives. `SkyClock` holds the keys; these are the targets.

| Time | Sky | Key light | Ground and shadows | Feel |
|---|---|---|---|---|
| Dawn | Deep blue top, ember-rose horizon | Low, red-orange, weak | Long blue shadows, haze lying in hollows | Cold and quiet, the valley waking |
| Morning, golden hour | Dusty blue, warm haze at the horizon | Low gold (`GOLDEN_LIGHT`) | Long shadows, warm faces, haze glowing toward the sun | The valley's favourite hour; most of the day looks like this |
| Noon | Dusty high-altitude blue, never postcard cyan | Warm white, still a little gold | Olive and rust, real shadow shapes (sky fill kept low) | Short, bright but never washed out or lime |
| Dusk | Rose-violet top, ember horizon | Sinking red-orange | Ground goes dark first, crowns hold the last light | Melancholy; lamps come on |
| Night | Deep navy with stars, never black | Moonlight (`MOONLIGHT`), dim | Blue-grey meadow, ember crowns and lanterns carry the colour | Dark and a little dangerous, but you can always see the path and every player |

- **Golden-hour bias.** The day spends most of its time with the sun low: long warm light,
  long blue shadows. Noon is short and still warm.
- **Warm key, cool fill, strong rim.** The sun is the warm key light, the sky ambient is the
  cool fill (kept low by day so shadows keep their shape: `SkyClock.DAY_AMBIENT`), and the
  shared shader adds a soft rim on silhouettes against the sky. At night the fill is mostly a
  flat moonlit blue (`NIGHT_SKY_SHARE`) and the shader adds extra `SHADE` to the side turned
  away from the moon, so figures read as blue-grey shapes, never black holes.
- **The grade.** One whole-frame grade in the tonemap pass Godot already draws (free):
  saturation x0.92, contrast x1.10 (`WorldBuilder.GRADE_*`). It is the "same film stock" that
  makes every scene sit in one key. Change it only on purpose, with before and after shots.
- **Height haze.** Warm `HAZE` fills the valley floors and lake hollows by day; it goes blue at
  night. Fog distance is also the draw distance (section 7), so the haze is the culling.
- **Glow, not lights.** Ember things glow through emission and one cheap bloom pass, not
  through real lights. Real lights are few (section 7).

## 6. "Inspired by, never copied": staying legally safe
We take inspiration from a **genre** (grounded survival-and-crafting action MMOs) and its
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
When in doubt, push it further toward ember, ash, weathered wood and late-afternoon warmth,
which no one else owns.

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

## 9. UI tone
The HUD is the frame, not the picture. It should feel like a field journal and a worn
leather satchel, our own, never like another game's menus.
- **Quiet by default.** Small, calm type; muted panels (dark warm-grey, about 70 to 85%
  opaque); no big saturated buttons. Colour in the UI is information (an ember accent for
  "ready", `SMOULDER` for danger, a skill's own muted badge colour), never decoration.
- **One accent.** The UI's accent is `EMBER`, used sparingly (a title, a ready button, a
  progress fill). Never rainbow progress bars, never neon text.
- **Text, not shouting.** Toasts and floaters are short and sit near what they describe; no
  thick black outlines on big bold yellow type; no exclamation marks except real milestones.
- **Level-up banners** are proud, not loud: the skill badge, the new level, the unlock in one
  line, on screen for about 3 s.
- **Ours, not borrowed.** Our own layouts, our own procedural icons (`ItemIcons`,
  `SkillIcons`), Godot's bundled font until we generate our own. See section 6.

## 10. Effects: restraint
Effects mark moments. If everything sparkles, nothing does.
- **Small and short by default.** Gather hits: a few chips or leaves and a puff, gone in about
  half a second. Pickups: one quick motion into the pack.
- **Translucent light, not solid shapes.** Glows, columns and rings are soft and see-through;
  you can always see your character through an effect (the level-up column was a solid gold
  tube that swallowed the avatar; it is now a translucent shaft with half the sparks).
- **Ember, not rainbow.** Effects use `EMBER`, `EMBER_CORE` and `SMOULDER`, plus the
  material's own colour (wood chips, stone dust). No rainbow rings, no pure yellow, no
  confetti, no cartoon stars or hearts.
- **Scale with importance.** A gather is a whisper, a craft is a word, a level-up is the one
  loud moment (design bible "Level-ups are moments") and even that stays inside the frame:
  about 2 s, readable from across the meadow by its light, not by covering the screen.
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
| Fat, barrel-shaped bodies ("our dudes look fat and silly") | A 0.64 m wide capsule on short stubby legs | **Fixed 2026-11-24 (character overhaul)**: lean 7-head adults, tapered chest, long legs, layered survival gear (section 3, "Characters") |
| Postcard-cyan noon sky | Bright and flat, no mood | **Fixed 2026-11-24**: dusty blue, hazy horizon |
| Solid gold level-up tube and red crystal sparks | Swallowed the avatar; arcade effect | **Toned down 2026-11-24**: translucent, fewer sparks, dimmer light. Next: rounder ember sparks instead of hexagon shards, a subtler ground ring |
| Teal, green-lit nights | Neither moonlit nor dark | **Improved 2026-11-24**: navy and blue-grey, moon-blue fill. Next: check dark cloth reads on a real GPU (CI renders in software) |
| Bold outlined yellow floaters and banners | Mobile-game shouting | **To do** (client): section 9 |
| Thin black lamp posts with red boxes | Reads as a street lamp, not a wilderness lantern | **To do** (world): timber posts, iron and horn lanterns |
| Uniform flat terrain facets at noon | No sense of ground cover | **Improved 2026-11-24**: the low-res grain breaks the ground into 40 cm texels. Still to do (world): colour patches (moss, dry grass, bare earth) in the ground palette |

## 12. Checklist for any PR that changes what is on screen
1. Before and after screenshots at noon, golden hour and night (the client smoke shots plus
   your own), in the PR and in the project files.
2. Grounded? Proportions, materials and colours would sit in a moody wilderness MMO (pillar 1).
3. Palette from `palette.gd`, naturals under about 0.45 saturation, ember only on usable things.
4. Effects translucent, short, ember-coloured; the character visible through them.
5. Nothing named, shaped or laid out after another game (section 6).
6. Inside the render budget (section 7), and the style check passes; if the look changed on
   purpose, the style baseline was rewritten with `--write-baseline` and the PR says so.

