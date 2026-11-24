# The Gloam walker, server side, behind a flag (ws/gameplay/gloam-walker)

**Why this item.** The top three backlog items (world config on the wire, stance events, and
hunger's `s2c_needs`) all need a protocol bump, and #197 (character customization, owner
thread) still holds v8; `docs/workstreams.md` allows one bump PR at a time. Placed campfires
need a new `c2s` place action to be anything a player does, which is a bump too. The walker is
the next build-ahead item that is fully buildable and testable on the server today, and it is
the heart of the game's name. So it went first; campfires are next in line the moment a bump
is free (or as server rules plus a bot-only path, if #197 is still open next run).

**Fun it unblocks.** The first time something in the hills wants you: you hear nothing, you
chop, and a grey shape shambles out of the trees toward the noise. By day you can walk away;
at night it is quicker. Its grab is a readable windup (arms up for 0.9 s): step back and it
closes on air, or land a haymaker first and it staggers. Alone it is beatable bare-handed,
which makes the first crafted weapon matter.

## What changed
- New `game/shared/gloam.gd` (`Gloam`): pure rules over plain data, like Wildlife. Walker
  (30 hp, 0.45 m body, 15 per grab); 1.8 m/s by day, 3.4 at night (you walk 6); sight 9 m by
  day, 14 at night, lost at 22 m; noise draws idle walkers within 25 m; grab windup 0.9 s,
  reach 2.0 m at the end of it, 1.2 s recovery; a heavy blow staggers (0.7 s) and breaks a
  windup; keeps 6 m from any fire passed in (none yet). Rising: per player every 45 s by day /
  12 s at night, 26 to 40 m out, never within 40 m of `WorldGen.spawn_point()`, cap 1 per
  player by day and 3 at night plus 1 per other player within 40 m, 24 in the world; crumble
  after 20 s with nobody within 70 m. Walkers are not saved.
- Server: `gloam` state stepped every tick (`_tick_gloam`); grabs go through `hurt()` (so the
  vitals bar, combat timer and fair knock-down all apply). `--gloam` / `AIMMO_GLOAM` (via
  `parse_gloam`, off when unset) turns natural rising on; the start-up log says which.
  Swings check grazers and walkers in one `Weapons.targets_hit` (walkers keyed "w<id>" so the
  spear still stops at the first thing it meets); only grazer ids go into `s2c_swing_hits`, so
  the wire is unchanged. Every swing and every finished gather is a noise.
- Hidden dev command `/gloam` (dev servers only, like `/lure`): raises a walker 7 m in front of
  you bound to you (hunts only you, crumbles when you leave); `/gloam status` says how it is
  or "Your walker N is down."
- Bot flake fix, `gameplay_wildlife`: after a bolt it now only demands a herd-mate follow if
  one was standing calm within `HERD_RADIUS - 2 m` of the target in the send before the bolt;
  otherwise the stalk is counted (`herd_unchecked`) and handed back. That was the "grazer N
  bolted but no herd-mate went with it" flake (herd-mates ambling out past 16 m, already
  running, or down after the hunt bot's kill).

## Tests
- `test_gameplay_gloam.gd`, 17 tests: the numbers hold together (slower than you, tougher
  than a grazer, a windup you can step out of, bare hands reach it); speed by day and night;
  sight; noise range; grab after the windup; stepping back escapes; a heavy blow breaks the
  grab, blows put it down; fire keepaway (stops at the edge, walks out of a fire lit beside
  it); rising only near players, outside the meadow, on dry land, under caps; more at night
  and for a crowd; crumbling; the bound walker; and on the server: off by default, `/gloam`
  then a grab costs exactly 15 and shows on `s2c_vitals`, haymakers put it down in at most 5
  and `s2c_swing_hits` never carries a walker; a swing is a noise; an unanswered walker
  knocks you down only after many grabs and you come to at spawn.
- Bot behaviour `gameplay_gloam.gd` (bot *_3, long runs, after the reconnect, once
  `gameplay_vitals` and `gameplay_first_swing` are done): `/gloam`, wait for one grab of
  exactly 15 on the health bar, haymakers until `/gloam status` says it is down.

## Didn't work / watch
- First fire test failed: a walker inside a fire's ring backed out at its 0.8 m/s idle
  shuffle and was still inside after 6 s. It now backs off at day speed.
- Fists' haymakers can chain-stagger a lone walker (each lands inside its next windup). That
  is fine for one walker (timing is the skill), and packs are what make them deadly. Revisit
  once walkers are drawn and a dodge exists.
- `Gloam.rise_near_players` is a steady trickle, not the vision's night rounds yet.

## Next run
- Placed campfires (rules, save, and `gloam_fires()`), then hunger, all in or after the next
  free bump. If #197 has landed, the world config + stance events + `s2c_gloam` bump.

## Test runs
- Unit tests: 869 pass (with Postgres). Client smoke test passed.
- Bot test (8 bots, 180 s, WebSocket), first run: failed, `gameplay_gloam`'s haymakers all
  missed (walker 30/30 at 1.4 m). The bot's wander turns `bot.yaw` every few seconds even
  while a behaviour holds it still, so the swings went off to the side. The behaviour now
  pins the yaw it had at `/gloam` until the fight ends. Second and third runs passed: one
  walker summoned, one grab of 15, down in 4 haymakers. The wildlife flake fix's second
  form (judge herd-mates from the send before the bolt, and count a herd-mate already
  running as following) gave `herd_bolts=1, herd_unchecked=0` on the last run.
