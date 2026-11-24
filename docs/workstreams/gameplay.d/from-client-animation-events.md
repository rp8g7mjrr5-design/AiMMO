Request (from client, 2026-11-23): server events for the new character animations (protocol v8, after #180 lands)

The traveller now has a real skeleton and a full move set (`AvatarAnimator`, PR "Character animation groundwork"). Idle, walk, run, gathering, crafting and the light and heavy swings (`s2c_swing`, v7) need nothing new. Three moves need the server, because they must look the same on every screen:

- [ ] **Jump.** `c2s_jump()` on Net/Play. The server owns the arc: when you're on the ground and not knocked down, `vy = 5.0` m/s with gravity 15 m/s² (about 0.67 s in the air, a 0.8 m apex), applied in `Movement.step` so client prediction replays it. Snapshots already carry `y`, so remote avatars follow the arc with no extra data. Also send `s2c_jumped(peer)` to everyone in view so they play the take-off dip at the right moment. A jump cancels a gather and may cost a little stamina (`Vitals.COSTS`).
- [ ] **Knock-down that stays down.** Today a knock-down moves you to Spawn Meadow at once, so nobody sees you fall. Proposed: you lie where you fell for `KNOCKDOWN_SECONDS` (2.5 s, inputs ignored), then come to in Spawn Meadow and get up there. Send it as a stance change (below): `down` when you fall, `standing` once you are at spawn, which plays the get-up.
- [ ] **Sit and rest.** `c2s_rest(on: bool)`. You can rest only when standing still, not gathering and not in combat. Any movement input, swing or gather ends it. To make it worth doing: while resting, health and stamina regenerate three times as fast.
- [ ] **One stance RPC for all of the above:** `s2c_stance(peer, stance)` with stance `0` standing, `1` resting, `2` down. Send it to everyone in view on every change, and to a player for everyone already in view when they log in or walk into range, so a latecomer sees a resting traveller sitting and a downed one lying.

On the client, these map one to one onto `AvatarAnimator.jump()`, `sit()` / `stand()`, and `knock_down()` / `get_up()`.
