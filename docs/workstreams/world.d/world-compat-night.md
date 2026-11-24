Done: Night on the Compatibility renderer is near black (a bug for players without Vulkan) (ws/world/compat-night)
Godot 4.3 Compatibility linearises ALBEDO/EMISSION itself; Emberlight, Motes and level-up sparks now encode once on it. Night centre luma 0.06 -> 0.22 (Forward+ 0.26). Also closes the same follow-up in `world.d/world-night-lighting-fix.md` (fold as one). The style baseline is re-baselined in this PR.

Follow-ups:
- [ ] Night ember-ash crowns read saturated orange-red (CI night `neon_share` 0.19, art bible max 0.10), on Forward+ as well; it was hidden by the darkening. Tone the night leaf glow or the crown paint down until neon share is under 0.10, and re-baseline.
- [ ] Noon on Compatibility is a touch paler, with a bluer sky, than Forward+ (GLES3 sky and fog differ). Look again if the owner plays on Compatibility.
- [ ] Re-check the earlier opengl3-tuned art passes (grounded art, ground cover, kingdom dressing) on Forward+ via lavapipe (`apt-get install mesa-vulkan-drivers`): they were tuned against colours that were too dark and too saturated.
