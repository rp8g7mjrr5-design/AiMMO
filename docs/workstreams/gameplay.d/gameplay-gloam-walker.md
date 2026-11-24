Done: **Phase 2 build-ahead: the Gloam walker, server side, behind a flag.** (ws/gameplay/gloam-walker)
`game/shared/gloam.gd` (rules and data), stepped by the server every tick; walkers rise near players only with `--gloam` / `AIMMO_GLOAM` (off on the live world), the hidden `/gloam` raises one bound to its caller. Grabs hurt through `Vitals`, swings and gathers are noise, heavy blows break a grab. Not on the wire yet. Also fixes the `gameplay_wildlife` "no herd-mate went with it" flake.

Follow-ups:
- [ ] Walkers on the wire in the next free bump (after #197's v8): `s2c_gloam` like `s2c_wildlife` (PackedFloat32Array [id, x, z, yaw, state] per walker in view, 5 Hz), plus the grab's windup as a state the client can show (the telegraph is the whole fairness of it), and walker ids in `s2c_swing_hits` (today the server keeps them off the wire: `Gloam.target_key` "w<id>"). Ask world for the walker's look (grey, ash-cold, arms-up windup pose; art bible) and client for drawing and the hit feedback.
- [ ] Turn `--gloam` on for the main bot test (qa request filed) so natural rising, noise and crumbling run against 8 bots, not only the bound `/gloam` walker.
- [ ] Fires: `Server.gloam_fires()` returns [] until placed campfires (next build-ahead) and a held torch exist; feed them in and the 6 m keepaway works (unit tested already).
- [ ] Night rounds (`docs/vision.md`, "Nights come in rounds"): waves at night with a lull between them, built on `Gloam.rise_near_players` (today it is a steady trickle up to a cap). Wait until walkers are drawn and players can fight back with a crafted weapon.
- [ ] The chill (`docs/vision.md`): a grab may leave the chill, which drains warmth. Needs warmth (needs work) first.
- [ ] A walker that is put down could drop something small (cloth, a bone charm) once a recipe uses it, so fighting pays into crafting like the hunt does.
