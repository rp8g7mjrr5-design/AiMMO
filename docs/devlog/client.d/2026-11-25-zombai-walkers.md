The Zombai walkers in the game, end to end (owner ask, 2026-11-25: "we just need the Zombai and they need to work like zombies ... nothing fancy just the basics")

What shipped:
- `ZombaiView` (client/zombai_view.gd): HerdView's smoothing for `s2c_gloam`, plus windup timing
  from the server's `windup_left` (arms reach the top exactly when the grab closes), blows from
  `s2c_gloam_hits` (flinch, heavy = stagger at once), and bodies: a walker put down stays as a
  body for LIE_SECONDS, sinks for SINK_SECONDS, then drops. A late `s2c_gloam` that still lists
  a downed walker never stands it back up.
- `ZombaiBody` (procgen/zombai_body.gd): the walker is the traveller's own body and skeleton,
  drained (art bible: grounded, real proportions; vision: "the Zombai grey and ash-cold, the
  living warm"). Ash-grey flesh from COLD_ASH and ROCK, dark sunken eyes, cloth desaturated and
  darkened, pack and bedroll removed. 4 variants built once, shared by every walker. Poses as
  AvatarClips poses: shamble (hunch, lolled head, one arm half reaching, one dead, hitch in the
  step, on the traveller's planted-feet gait), grab(k) (both arms up by half the windup, lunge
  in the last fifth), stagger, fall (the knock-down without breathing).
- `ZombaiFigures` (client/zombai_figures.gd): one node + skinned mesh per walker in view (one
  draw call each, at most Gloam.MAX_WALKERS); a voice each: a groan every few seconds (more
  often once hunting), a rasp on the windup, a thud as a body lands. `Sfx.groan(variant)`,
  `Sfx.rasp()`.
- client.gd: `gloam_changed` / `gloam_struck` wired; your own connecting blow on a walker now
  smacks (it never did: walker hits come in `s2c_gloam_hits`, not `s2c_swing_hits`); "Zombai
  down." centre screen when yours goes down; the first raised grab within 3 m of you each
  session explains itself ("Its arms are up: step back, or hit it first.").
- Server: walkers now rise on their own by default (`parse_gloam`: unset is on;
  `--gloam=0` / `AIMMO_GLOAM=0` turns them off). So the live Railway world has them as soon as
  this deploys. Player-facing name is "Zombai" (`Gloam.KINDS.walker.label`, the /gloam reply);
  the code keeps "Gloam".
- Tests: `test_client_zombai.gd` (view, body, poses, figures' pose choice, sounds);
  bot behaviour `client_zombai` (the client's view matches the wire, windups, bodies).
  `gameplay_gloam` and `test_gameplay_gloam` updated for the new name and default.
- Checked in the real client under xvfb (opengl3): /gloam, it shambles up, arms up with the
  hint, three haymakers, it goes down and lies there. Shots in the project files under
  `zombai/`. `tests/client_smoke/zombai_shots.gd` is the script (not in CI's run.sh).

Not done / next:
- No dodge key (gameplay has no `c2s_dodge` yet).
- No death moment beyond the existing knock-down to Spawn Meadow.
- Walkers are drawn without a distance fade; they only exist near players anyway.
- Bodies are client-only: two players see the same body only because they both saw the blow.
