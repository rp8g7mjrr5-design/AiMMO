## Night on the Compatibility renderer (ws/world/compat-night)

**Picked.** Next on the backlog after the generator and the kingdom dressing: night near black on opengl3 (CI's smoke shots and any player whose GPU has no Vulkan). **What a player will feel:** on an older or Vulkan-less machine, night is a moonlit blue meadow where you can see the pines, the path and your friends, instead of a black screen with lanterns floating in it.

**Root cause.** Not lighting. Godot 4.3's Compatibility renderer treats a spatial shader's `ALBEDO` and `EMISSION` as **sRGB** and linearises them itself (`drivers/gles3/shaders/scene.glsl`, "Convert colors to linear", a cubic approximation in `tonemap_inc.glsl`), and it leaves `source_color` uniforms in sRGB. Forward+ and Mobile take `ALBEDO`/`EMISSION` as linear, and linearise `source_color` uniforms on upload. Every one of our shaders writes linear colours (`Emberlight.paint()` stores vertex colours linear, palette constants are baked with `srgb_to_linear()`), so on Compatibility every colour was linearised twice: a mid tone kept about a fifth of its brightness. By day the bright key hid it (just darker, more saturated); at night everything sits in the tonemapper's toe and went near black.

How I found it: installed `mesa-vulkan-drivers` here, which gives a working **Forward+ on lavapipe** next to opengl3 on llvmpipe, same machine. Then bisected with a scratch scene: grey albedo matched on both renderers, vertex colours and constant emission did not; unshaded swatches (0.02 to 1.0) showed opengl3 putting out exactly `srgb_to_linear` of what Forward+ put out. Reading the 4.3 GLES3 shader source confirmed it.

**Built.**
- `Emberlight.srgb_output()`: true on Compatibility (no `RenderingDevice`, not headless). `RenderingServer.get_current_rendering_method()` doesn't exist in 4.3, and the shader preprocessor's `CURRENT_RENDERER` check broke `#endif` parsing in my test, so the choice is made in GDScript when the shader source is built: `compat_define()` prepends `#define COMPAT_SRGB`. Forward+ and Mobile get byte-identical shaders to before.
- `COMPAT_GLSL`: `compat_decode` (Godot's own cubic) and `compat_encode`, its exact inverse (quadratic first guess, three Newton steps). The usual pow approximation of linear to sRGB left the darks up to 60% off, which is exactly where night lives. A GDScript mirror is unit tested down to linear 0.0005.
- Emberlight (every world surface, terrain, avatars, node props): on Compatibility, `emission_color` is decoded to linear first, then `ALBEDO` and `EMISSION` are encoded once at the end of `fragment()`. Motes and the level-up sparks (linear constants and instance colours, unshaded) encode their `ALBEDO` too.
- `COMPAT_ALBEDO = 0.5`: even with colours right, lit surfaces still came out brighter on Compatibility than on Forward+ (its sky ambient differs; I didn't find exactly where). Scaling only the lit paint brings the spawn shot to Forward+'s brightness: centre luma at night 0.22 vs 0.26, golden hour 0.55 vs 0.54, noon 0.71 vs 0.64.

**Numbers (same night shot, centre luma).** opengl3 before 0.06, after 0.22; Forward+ 0.26. CI smoke night shot luma 0.05 -> 0.19. Before/after/Forward+ triptychs at night, golden hour and noon: project files `world/compat-night/`.

**Style baseline rewritten on purpose** (`tests/client_smoke/style_baseline.json`, as its `_doc` allows for a world PR that changes the look; reason appended there). Night luma 0.05 -> 0.19, noon 0.54 -> 0.67.

**Honest notes / didn't work.**
- Every earlier art pass that was tuned from opengl3 shots (all of mine since this container had no Vulkan) was tuned against colours that were too dark and too saturated. Players on Forward+ always saw the brighter, softer version. From now on the CI shots show what they see.
- Night `neon_share` is now 0.19 on CI (the art bible wants at most 0.10): the ember-ash crowns read saturated orange-red at night, on Forward+ too. It was hidden by the darkening. Follow-up filed.
- Noon on opengl3 is still a touch paler and its sky a touch bluer than Forward+ (sky and fog differ in the GLES3 sky shader, which treats sky `COLOR` as sRGB as well; our sky's colours come from `source_color` uniforms, which happen to come out right). Left alone.
- Not touched: `NodeFx`'s highlight rim and the level-up column and ring. They colour from `source_color` uniforms, which Compatibility already shows about right.
- No bot behaviour: nothing changed on the server or the wire; this is client rendering only. Unit tests cover the maths and the shader sources; the client smoke test covers the real render.

**Tip for next runs:** `apt-get install -y mesa-vulkan-drivers` gives Forward+ here (`--rendering-method forward_plus --rendering-driver vulkan`). Compare against it before trusting an opengl3 shot.

**Next run.** The ember-ash night saturation follow-up is small; then part 2 (chunks) or the material merge before the ruin kit, per the director's order.
